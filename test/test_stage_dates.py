import unittest
from pathlib import Path
from types import SimpleNamespace
from tempfile import TemporaryDirectory
from zipfile import ZipFile
from xml.etree import ElementTree as ET
from local_edesk.stage_dates import adjusted_formula, original_formula, timeline_period_fields, with_mirrors, validate_summary_periods
from local_edesk.excel_editor import preserve_package, value, validated_changes


class StageDateTests(unittest.TestCase):
    def test_dependent_phase_must_not_end_before_its_recalculated_start(self):
        validate_summary_periods({'rows':[{'label':'Post','start':'2026-11-15','end':'2026-12-20'}]})
        with self.assertRaises(ValueError):
            validate_summary_periods({'rows':[{'label':'Post','start':'2026-12-21','end':'2026-12-20'}]})
    def test_adjusted_date_keeps_original_formula_and_repeated_edits_do_not_nest(self):
        source = '=MINIFS(DetalhesProjeto[Data],DetalhesProjeto[Etapa],F3)'
        first = adjusted_formula(source, '2026-11-13')
        second = adjusted_formula(first, '2026-11-20')
        self.assertEqual(original_formula(second), source)
        self.assertEqual(second.count('IF(TRUE'), 1)
        with self.assertRaises(ValueError): adjusted_formula(source, '2026-02-30')

    def book(self):
        labels = ['Contato Inicial', 'Escopo', 'Desenvolvimento', 'Implantação', 'Pós-Implantação']
        def sheet(name):
            def cell(r, c):
                v = 'Status Projeto' if (r,c) == (1,6) and name != 'Dados' or (r,c)==(5,33) and name=='Dados' else None
                if name != 'Dados' and r == 2 and 6 <= c <= 9: v=['Trabalhos','%','Inicio','Fim'][c-6]
                if name != 'Dados' and 3 <= r <= 7 and c == 6: v=labels[r-3]
                if name == 'Dados' and 7 <= r <= 11 and c == 33: v=labels[r-7]
                calculated = name != 'Dados' and c in [8,9] and r >= 3 or name == 'Dados' and c in [35,36] and r >= 7
                if calculated: v=46300
                formula = "='Checklist-Processo'!E15" if (r,c)==(1,7) else '=1+1' if calculated else ''
                return SimpleNamespace(Value2=v, HasFormula=calculated, Formula=formula, HasArray=False)
            def address(a):
                import re
                col, row=re.fullmatch(r'([A-Z]+)(\d+)', a).groups(); number=0
                for char in col: number=number*26+ord(char)-64
                return cell(int(row),number)
            return SimpleNamespace(Name=name,Cells=cell,Range=address)
        return SimpleNamespace(Worksheets=sheet)

    def test_timeline_summary_maps_ten_fields_and_exact_mirrors(self):
        fields=timeline_period_fields(self.book(),'Checklist-Processo',value)
        self.assertEqual(len(fields),10)
        self.assertEqual([f['cell'] for f in fields[:2]],['H3','I3'])
        self.assertEqual(fields[6]['dateMirrors'][0]['cell'],'AI10')
        self.assertTrue(fields[6]['managedDateFormula'])
        self.assertEqual(timeline_period_fields(self.book(),'Wrong checklist',value),[])

    def test_validation_adds_only_the_known_mirror_and_rejects_reversed_interval(self):
        fields=timeline_period_fields(self.book(),'Checklist-Processo',value)
        field=fields[0]
        changes=[{'sheet':field['sheet'],'cell':field['cell'],'before':field['value'],'value':'2026-01-01'}]
        result=validated_changes({'fields':fields,'tasks':[]},changes)
        self.assertEqual(len(result),2)
        self.assertEqual(result[1][0]['cell'],'AI7')
        changes[0]['value']='2027-01-01'
        with self.assertRaises(ValueError): validated_changes({'fields':fields,'tasks':[]},changes)
        with self.assertRaises(ValueError): with_mirrors([(field,'2026-01-01'),(field['dateMirrors'][0],'2026-01-02')])

    def test_package_changes_only_the_managed_date_formula_and_keeps_vba_styles_and_other_formulas(self):
        with TemporaryDirectory() as folder:
            source=Path(folder)/'source.xlsm';target=Path(folder)/'target.xlsm'
            workbook='<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Timeline" sheetId="1" r:id="rId1"/></sheets></workbook>'
            rels='<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'
            xml='<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="3"><c r="H3" s="4"><f ca="1">SUM(A1:A2)</f><v>46300</v></c><c r="I3"><f>1+1</f><v>2</v></c></row></sheetData></worksheet>'
            for path in [source,target]:
                with ZipFile(path,'w') as z:
                    z.writestr('xl/workbook.xml',workbook);z.writestr('xl/_rels/workbook.xml.rels',rels)
                    z.writestr('xl/worksheets/sheet1.xml',xml)
                    z.writestr('xl/vbaProject.bin',b'macros' if path==source else b'recompiled')
            preserve_package(source,target,[({'sheet':'Timeline','cell':'H3','kind':'date','managedDateFormula':True},'2026-11-13')])
            with ZipFile(target) as z:
                ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
                root=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
                cell=root.find('.//s:c[@r="H3"]',ns)
                self.assertEqual(cell.attrib['s'],'4')
                self.assertEqual(cell.find('s:f',ns).attrib,{'ca':'1'})
                self.assertEqual(original_formula('='+cell.find('s:f',ns).text),'=SUM(A1:A2)')
                self.assertEqual(root.find('.//s:c[@r="I3"]/s:f',ns).text,'1+1')
                self.assertEqual(z.read('xl/vbaProject.bin'),b'macros')


if __name__=='__main__': unittest.main()
