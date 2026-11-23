import base64
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from flask import Flask
from local_edesk import zendesk_workflow as workflow
from local_edesk.zendesk_routes import register


def meta():
    return {'agent': {'id': 7, 'name': 'Consultor'}, 'forms': [{'id': 10, 'fieldIds': [30,31]}],
            'brands': [{'id': 20}], 'groups': [{'id': 21}], 'customStatuses': [{'id': 22, 'category': 'hold'}],
            'fields': [{'id':30,'name':'Produto','type':'tagger','required':True,'options':[{'value':'plugin'}]},
                       {'id':31,'name':'Data','type':'date','required':False,'options':[]}]}


class ZendeskWorkflowTests(unittest.TestCase):
    def test_sla_inputs_reject_incomplete_boolean_and_unknown_units(self):
        for values in [[1,2], [True,1,1,1,1], [0,1,1,1,1]]:
            with self.assertRaises(ValueError):
                workflow.priority_input({'unit':'production','product':'Builder','answers':values})
        self.assertEqual(workflow.priority_input({'unit':'production','product':'Builder','answers':[3,1,3,3,3]})['answers'],[3,1,3,3,3])

    def test_ticket_uses_actual_fields_and_custom_status_ids(self):
        data={'subject':'Teste','description':'Descrição','formId':10,'type':'problem','status':22,'fields':{'30':'plugin'},'brandId':20}
        result=workflow.validated_ticket(data,meta())
        self.assertEqual(result['requester_id'],7)
        self.assertEqual(result['status'],'hold')
        self.assertEqual(result['custom_status_id'],22)
        for bad in [{'formId':99},{'fields':{'30':'inventado'}},{'fields':{'300':'plugin'}},{'fields':{}},{'fields':{'30':'plugin','31':'2026-02-30'}}]:
            with self.subTest(bad=bad),self.assertRaises(ValueError):
                workflow.validated_ticket({**data,**bad},meta())

    def test_description_is_escaped_and_official_image_is_inline(self):
        value=workflow.compose('<script>alert(1)</script>\nTeste',{'priority':'P3','points':24},'https://example.test/a.png')
        self.assertNotIn('<script>',value)
        self.assertIn('&lt;script&gt;',value)
        self.assertIn('Prioridade da solicitação:',value)
        self.assertIn('<img src="https://example.test/a.png"',value)

    def test_attachments_reject_paths_and_invalid_bytes(self):
        for value in [{'name':'../secret','base64':'eA=='},{'name':'x','base64':'??'}]:
            with self.assertRaises(ValueError):workflow.attachments({'attachments':[value]})

    def prepared(self,root):
        draft='a'*32;folder=root/'drafts'/draft;folder.mkdir(parents=True)
        image=b'\x89PNG\r\n\x1a\nfixture';(folder/'priorizacao.png').write_bytes(image)
        sla={'unit':'production','product':'Builder','answers':[3,1,3,3,3]}
        capture={**sla,'draftId':draft,'priority':'P3','points':24,'imageSha256':hashlib.sha256(image).hexdigest()}
        workflow.write_json(folder/'capture.json',capture)
        return {'draftId':draft,'sla':sla,'confirmed':True,'agentId':7,'subject':'Teste','description':'Texto','formId':10,'type':'problem','status':'hold','fields':{'30':'plugin'}},folder

    def test_capture_tampering_and_changed_answers_are_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);data,folder=self.prepared(root)
            data['sla']['answers'][0]=5
            with self.assertRaises(ValueError):workflow.load_capture(root,data)
            data['sla']['answers'][0]=3;(folder/'priorizacao.png').write_bytes(b'changed')
            with self.assertRaises(ValueError):workflow.load_capture(root,data)

    def test_create_verifies_receipt_and_does_not_send_twice(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);data,folder=self.prepared(root);calls=[];marker=None
            def api(context,path,**kwargs):
                nonlocal marker
                calls.append((path,kwargs.get('method')))
                if 'uploads' in path:return {'upload':{'token':'t','attachment':{'content_url':'https://example.test/image.png'}}}
                if kwargs.get('method')=='POST':
                    marker=kwargs['payload']['ticket']['external_id']
                    self.assertFalse(kwargs['payload']['ticket']['comment']['public'])
                    return {'ticket':{'id':456}}
                return {'ticket':{'id':456,'external_id':marker}}
            with patch.object(workflow,'current_agent',return_value={'id':7,'authenticity_token':'secret'}),patch.object(workflow,'metadata',return_value=meta()),patch.object(workflow,'api',side_effect=api):
                result=workflow.create_ticket(None,root,data)
                self.assertEqual(result['ticketId'],456)
                before=len(calls)
                self.assertEqual(workflow.create_ticket(None,root,data),result)
                self.assertEqual(len(calls),before)
            self.assertEqual(json.loads((folder/'receipt.json').read_text())['state'],'confirmed')

    def test_ambiguous_post_blocks_retries(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);data,folder=self.prepared(root)
            def api(context,path,**kwargs):
                if 'uploads' in path:return {'upload':{'token':'t','attachment':{'content_url':'https://example.test/image.png'}}}
                raise TimeoutError()
            with patch.object(workflow,'current_agent',return_value={'id':7,'authenticity_token':'secret'}),patch.object(workflow,'metadata',return_value=meta()),patch.object(workflow,'api',side_effect=api):
                with self.assertRaises(ValueError):workflow.create_ticket(None,root,data)
                with self.assertRaises(ValueError):workflow.create_ticket(None,root,data)
            self.assertEqual(json.loads((folder/'receipt.json').read_text())['state'],'uncertain')

    def test_definitive_rejection_keeps_draft_available_for_corrected_fields(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);data,folder=self.prepared(root);posts=[]
            def api(context,path,**kwargs):
                if 'uploads' in path:
                    self.assertEqual(kwargs['content_type'],'image/png')
                    return {'upload':{'token':'t','attachment':{'content_url':'https://example.test/image.png'}}}
                posts.append(path)
                raise workflow.ZendeskRejected('Campo obrigatório')
            with patch.object(workflow,'current_agent',return_value={'id':7,'authenticity_token':'secret'}),patch.object(workflow,'metadata',return_value=meta()),patch.object(workflow,'api',side_effect=api):
                for _ in range(2):
                    with self.assertRaises(workflow.ZendeskRejected):workflow.create_ticket(None,root,data)
            self.assertEqual(len(posts),2)
            self.assertEqual(json.loads((folder/'receipt.json').read_text())['state'],'rejected')

    def test_foreign_agent_and_unconfirmed_send_blocked(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);data,_=self.prepared(root)
            with self.assertRaises(ValueError):workflow.create_ticket(None,root,{**data,'confirmed':False})
            with patch.object(workflow,'current_agent',return_value={'id':8}):
                with self.assertRaises(ValueError):workflow.create_ticket(None,root,data)

    def test_route_requires_local_authenticated_origin_and_serializes_worker(self):
        app=Flask(__name__);register(app,lambda **kwargs:({'sub':'owner'},None),True,Path.cwd())
        client=app.test_client()
        response=client.post('/api/zendesk/capture',json={},environ_base={'REMOTE_ADDR':'10.1.1.2'})
        self.assertEqual(response.status_code,403)
        with patch('local_edesk.zendesk_routes.subprocess.run') as run:
            run.return_value.returncode=0;run.return_value.stdout=json.dumps({'ok':True,'priority':'P3'})
            response=client.post('/api/zendesk/capture',json={'unit':'production'})
            self.assertEqual(response.status_code,200)
            self.assertEqual(json.loads(run.call_args.kwargs['input'])['owner'],'owner')
        self.assertEqual(client.post('/api/zendesk/unknown',json={}).status_code,400)


if __name__=='__main__':unittest.main()
