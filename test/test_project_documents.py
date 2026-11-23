import unittest
from unittest.mock import patch
from local_edesk import project_documents, activity_report, local_files

class DocumentBoundaries(unittest.TestCase):
    def test_save_rejects_unmapped_columns_before_opening(self):
        with patch('local_edesk.excel_editor.edit') as edit:
            for cell in ['C0', 'H0', 'A19']:
                with self.assertRaises(ValueError):
                    project_documents.execute('ignored.xlsm', {'operation':'timeline-save',
                        'changes':[{'sheet':'Implantação - Linha do Tempo','cell':cell,'value':1}]})
            edit.assert_not_called()

    def test_report_identity_comes_from_verified_claims(self):
        data=dict(date='2026-11-13',system='Sistema',participants='Cliente',company='Empresa',
                  signatureParticipants='Cliente',signatureCompany='Empresa',activities=['Atividade'],consultant='forged')
        with patch.object(activity_report,'generate',return_value={'pdfBase64':'ok'}) as generate:
            activity_report.execute({'projectId':'123','documentData':data},{'sub':'owner','name':'Consultor real'})
            self.assertEqual(generate.call_args.args[0]['consultant'],'Consultor real')
            self.assertEqual(data['consultant'],'forged')

    def test_report_validation_rejects_bad_date_and_empty_items(self):
        data=dict(date='not-a-date',system='',participants='',company='',signatureParticipants='',signatureCompany='',activities=['ok'])
        with self.assertRaises(ValueError):activity_report.execute({'projectId':'123','documentData':data},{'name':'Consultor'})
        data.update(date='2026-11-13',activities=[''])
        with self.assertRaises(ValueError):activity_report.execute({'projectId':'123','documentData':data},{'name':'Consultor'})

    def test_native_route_requires_matching_verified_user(self):
        with self.assertRaises(PermissionError):
            local_files.execute('owner',{'action':'project-document','operation':'report'},verified_user={'sub':'other'})

if __name__=='__main__':unittest.main()
