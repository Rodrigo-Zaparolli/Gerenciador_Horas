import unittest
from xml.etree import ElementTree as ET
from local_edesk.implantation_update import PROJECT_TYPES, row_xml, workbook_xml
from local_edesk.excel_editor import validated_changes


class ImplantationUpdateTest(unittest.TestCase):
    def test_project_type_list_and_server_validation(self):
        self.assertEqual(len(PROJECT_TYPES), 8)
        self.assertIn('ENTERPRISE PRODUÇÃO COMPLETA', PROJECT_TYPES)
        field = dict(sheet='Entrada', cell='C3', value='PROFESSIONAL', kind='text', choices=PROJECT_TYPES)
        snapshot = {'fields': [field], 'tasks': []}
        self.assertEqual(validated_changes(snapshot, [dict(sheet='Entrada', cell='C3', before='PROFESSIONAL', value='REVITALIZAÇÃO')])[0][1], 'REVITALIZAÇÃO')
        with self.assertRaises(ValueError):
            validated_changes(snapshot, [dict(sheet='Entrada', cell='C3', before='PROFESSIONAL', value='arbitrário')])

    def test_visibility_patch_preserves_cells_and_order_and_unrelated_flags(self):
        raw = '<worksheet><sheetData><row r="1" hidden="1"><c r="A1"><f>1+1</f><v>2</v></c></row><row r="4"><c r="A4"><v>3</v></c></row></sheetData></worksheet>'
        patched = row_xml(raw, {1: False, 2: True, 4: True})
        tree = ET.fromstring(patched)
        rows = tree.findall('./sheetData/row')
        self.assertEqual([r.get('r') for r in rows], ['1', '2', '4'])
        self.assertIsNone(rows[0].get('hidden'))
        self.assertEqual(rows[1].get('hidden'), '1')
        self.assertEqual(rows[0].find('c/f').text, '1+1')
        self.assertIn('<c r="A4"><v>3</v></c>', patched)

    def test_sheet_states_retain_ids_and_names_and_activate_entry(self):
        raw = '<workbook><bookViews><workbookView activeTab="1"/></bookViews><sheets><sheet name="Entrada" sheetId="1"/><sheet name="Plano de Projeto" sheetId="2" state="hidden"/><sheet name="Outra" sheetId="3" state="veryHidden"/></sheets></workbook>'
        patched = workbook_xml(raw, {'entry': 'Entrada', 'sheets': {'Plano de Projeto': True}})
        root = ET.fromstring(patched)
        self.assertEqual(root.find('bookViews/workbookView').get('activeTab'), '0')
        sheets = root.findall('sheets/sheet')
        self.assertIsNone(sheets[1].get('state'))
        self.assertEqual(sheets[2].get('state'), 'veryHidden')
        self.assertEqual(sheets[1].get('sheetId'), '2')

if __name__ == '__main__':
    unittest.main()
