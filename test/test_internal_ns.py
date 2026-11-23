import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import io
from contextlib import redirect_stdout

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'edesk_bot'))
from edesk_ns_interno import validate_request, create_request, NsLedger, fingerprint

DATA = {'operationId': 'a'*32, 'subject': 'NS para uso interno',
        'description': 'Solicito NS Plugin Router para uso interno.', 'confirmed': True}
BASE = 'https://promob.e-desk.com.br/Portal/'


class InternalNsTest(unittest.TestCase):
    def test_documentation_fields_are_reviewed_and_attachments_block_before_save(self):
        data = {**DATA, 'kind': 'plugin-documentation', 'group': 'Documentação',
                'service': 'Documentação de Suporte', 'process': 'Documentação Plugin',
                'classification': '', 'urgency': 'Normal'}
        validate_request(data)
        self.assertNotEqual(fingerprint(data), fingerprint(DATA))
        for key in ('group', 'service', 'process', 'urgency'):
            with self.assertRaises(ValueError): validate_request({**data, key: ''})
        with self.assertRaisesRegex(ValueError, 'anexos'):
            validate_request({**data, 'attach': True})

    def test_documentation_creates_once_with_reviewed_metadata(self):
        from playwright.sync_api import sync_playwright
        data = {**DATA, 'kind': 'plugin-documentation', 'group': 'Documentação',
                'service': 'Documentação de Suporte', 'process': 'Documentação Plugins',
                'classification': '', 'urgency': 'Alta', 'subject': 'Documentação Plugin Router',
                'description': 'Favor documentar o plugin. Extensão: nc'}
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,
                EDESK_JOURNAL_PATH=str(Path(directory)/'history.sqlite3'),
                PLAYWRIGHT_BROWSERS_PATH=str(ROOT/'python/ms-playwright')):
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True)
                try:
                    page = browser.new_page(); saved=[]; self.fixture(page, saved)
                    page.goto(BASE+'SolicitacaoRapida.aspx')
                    page.evaluate('''() => {
                      for(const [id,value] of [['group','Documentação'],['service','Documentação de Suporte'],['process','Documentação Plugins']]){
                        document.getElementById(id).add(new Option(value,value));
                      }
                      const row=document.createElement('tr');row.innerHTML='<td>Urgência</td><td><select id="urgency"><option>Normal</option><option>Alta</option></select></td>';
                      document.querySelector('table').append(row);
                    }''')
                    result=create_request(page, data, NsLedger('owner'))
                    self.assertEqual(result['requestId'], '2267999')
                    self.assertIn('documentação', result['message'])
                    self.assertEqual(len(saved), 1)
                    self.assertEqual(saved[0]['process'], data['process'])
                    self.assertEqual(saved[0]['group'], data['group'])
                    self.assertEqual(saved[0]['service'], data['service'])
                finally:
                    browser.close()

    def test_startup_opens_official_url_then_creates_one_request_in_fixture(self):
        from edesk_ns_interno import main
        from playwright.sync_api import BrowserType
        original_launch = BrowserType.launch_persistent_context
        saved = []
        def launch_fixture(browser_type, *args, **kwargs):
            context = original_launch(browser_type, *args, **kwargs)
            page = context.pages[0] if context.pages else context.new_page()
            self.fixture(page, saved)
            return context
        data={**DATA,'url':'https://promob.e-desk.com.br/','enviar':True,
              'edeskCredenciais':{'email':'consultor@example.test','senha':'test-only'}}
        browser_root=ROOT/'python/ms-playwright'
        if not browser_root.exists(): browser_root=ROOT.parents[1]/'python/ms-playwright'
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,
                EDESK_JOURNAL_PATH=str(Path(directory)/'journal.sqlite3'),
                EDESK_AUTH_UID='fixture-owner', PLAYWRIGHT_BROWSERS_PATH=str(browser_root)), \
             patch('config.PROFILE_DIR',Path(directory)/'profile'), patch('config.HEADLESS',True), \
             patch('config.restore_session_cookies'), patch('config.save_session_cookies'), \
             patch('edesk_comentario.carregar_request',return_value=data), \
             patch('edesk_comentario.aguardar_login',side_effect=lambda page,**_:page.goto(BASE+'Solicitacao.aspx?GUID=fixture-session')), \
             patch.object(BrowserType,'launch_persistent_context',launch_fixture), redirect_stdout(io.StringIO()) as output:
            main()
        self.assertEqual(len(saved),1)
        self.assertEqual(json.loads(output.getvalue())['requestId'],'2267999')
    def test_validation_requires_review_and_a_stable_operation_identity(self):
        validate_request(DATA)
        for changes in [{'confirmed': False}, {'operationId': 'invalid'}, {'subject': ''}, {'description': ''}]:
            with self.assertRaises(ValueError): validate_request({**DATA, **changes})

    def test_ledger_survives_restart_and_is_scoped_to_account_and_content(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,
                EDESK_JOURNAL_PATH=str(Path(directory)/'history.sqlite3')):
            ledger = NsLedger('owner')
            digest = fingerprint(DATA)
            self.assertTrue(ledger.claim(DATA['operationId'], digest))
            self.assertFalse(NsLedger('owner').claim(DATA['operationId'], digest))
            with self.assertRaisesRegex(RuntimeError, 'já chegou'): NsLedger('owner').lookup(DATA['operationId'], digest)
            ledger.confirm(DATA['operationId'], digest, '2267999')
            self.assertEqual(NsLedger('owner').lookup(DATA['operationId'], digest), '2267999')
            self.assertIsNone(NsLedger('other').lookup(DATA['operationId'], digest))
            with self.assertRaisesRegex(ValueError, 'mudou'): ledger.lookup(DATA['operationId'], 'different')

    def fixture(self, page, saved, *, receipt=True, stale=False):
        def route_handler(route):
            if route.request.method == 'POST':
                saved.append(json.loads(route.request.post_data))
                route.fulfill(content_type='application/json', body='{}')
            elif 'SolicitacaoRapida.aspx' in route.request.url:
                redirect = "location.href='Solicitacao.aspx';" if receipt else "document.querySelector('#done').textContent='Processado';"
                note = '<div class="alert-success">Solicitação: 2267000</div>' if stale else ''
                route.fulfill(content_type='text/html; charset=utf-8', body='''<table>
                  <tr><td>Grupo de Serviço</td><td><select id="group"><option></option><option>Sales OPS</option></select></td></tr>
                  <tr><td>Serviço</td><td><select id="service"><option></option><option>Serviços Internos</option></select></td></tr>
                  <tr><td>Processo</td><td><select id="process"><option></option><option>Uso Interno - Novo NS</option></select></td></tr>
                  <tr><td>Classificação</td><td><input id="classification"></td></tr>
                  <tr><td>Assunto</td><td><input id="subject"></td></tr>
                  <tr><td>Detalhamento</td><td><textarea id="description"></textarea></td></tr></table>
                  <label><input type="checkbox">Quero anexar um arquivo ao gravar esta solicitação.</label>
                  <span id="done"></span>'''+note+'''<button onclick="save()">Salvar</button><script>
                  async function save(){await fetch(location.href,{method:'POST',body:JSON.stringify({
                    group:group.value,service:service.value,process:process.value,subject:subject.value,
                    description:description.value,classification:classification.value})});'''+redirect+'''}</script>''')
            else:
                route.fulfill(content_type='text/html; charset=utf-8', body='<h1>Solicitação: 2267999</h1>')
        page.route('**/*', route_handler)

    def test_creates_once_with_the_video_fields_and_confirms_real_number(self):
        from playwright.sync_api import sync_playwright
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,
                EDESK_JOURNAL_PATH=str(Path(directory)/'history.sqlite3'), PLAYWRIGHT_BROWSERS_PATH=str(ROOT/'python/ms-playwright')):
            with sync_playwright() as p:
                browser = p.chromium.launch(headless=True, executable_path=p.chromium.executable_path)
                try:
                    page = browser.new_page(); saved=[]; self.fixture(page,saved)
                    page.goto(BASE+'SolicitacaoRapida.aspx')
                    result = create_request(page, DATA, NsLedger('owner'), confirmation_timeout=3)
                    self.assertEqual(result['requestId'], '2267999')
                    self.assertEqual(saved, [{'group': 'Sales OPS', 'service': 'Serviços Internos',
                        'process': 'Uso Interno - Novo NS', 'subject': DATA['subject'],
                        'description': DATA['description'], 'classification': ''}])
                    self.assertTrue(create_request(page, DATA, NsLedger('owner'))['alreadyExists'])
                    self.assertEqual(len(saved), 1)
                finally: browser.close()

    def test_missing_receipt_or_old_notice_never_confirms_or_repeats_save(self):
        from playwright.sync_api import sync_playwright
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ,
                EDESK_JOURNAL_PATH=str(Path(directory)/'history.sqlite3'), PLAYWRIGHT_BROWSERS_PATH=str(ROOT/'python/ms-playwright')):
            with sync_playwright() as p:
                browser=p.chromium.launch(headless=True,executable_path=p.chromium.executable_path)
                try:
                    page=browser.new_page(); saved=[]; self.fixture(page,saved,receipt=False,stale=True)
                    page.goto(BASE+'SolicitacaoRapida.aspx')
                    with self.assertRaisesRegex(RuntimeError, 'não foi confirmado'):
                        create_request(page, DATA, NsLedger('owner'), confirmation_timeout=.5)
                    with self.assertRaisesRegex(RuntimeError, 'já chegou'):
                        create_request(page, DATA, NsLedger('owner'), confirmation_timeout=.5)
                    self.assertEqual(len(saved), 1)
                finally: browser.close()
