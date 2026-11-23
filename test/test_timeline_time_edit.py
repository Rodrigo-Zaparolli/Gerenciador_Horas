from types import SimpleNamespace
import unittest
from local_edesk.excel_editor import validated_changes
from local_edesk.timeline_dates import normalized_changes


class TimelineTimeEditTests(unittest.TestCase):
    def fixture(self):
        fields = [dict(sheet='Timeline',cell=cell,kind='number',value=value,
            readOnly=False,timelineTime=True,timeDuration=duration) for cell,value,duration in
            [('J19',8/24,False),('K19',10/24,True)]]
        cells = {f['cell']:SimpleNamespace(Value2=f['value'],HasFormula=False) for f in fields}
        book = SimpleNamespace(Worksheets=lambda _: SimpleNamespace(Range=lambda address:cells[address]))
        return book,dict(fields=fields,tasks=[]),cells

    def test_time_and_duration_are_editable_inputs_in_day_units(self):
        book,snapshot,cells=self.fixture()
        changes=normalized_changes(book,snapshot,[
            dict(sheet='Timeline',cell='J19',before=8/24,value=9/24),
            dict(sheet='Timeline',cell='K19',before=10/24,value=2.5/24)])
        self.assertEqual(len(changes),2)
        self.assertEqual(cells['J19'].Value2,9/24)
        self.assertEqual(cells['K19'].Value2,2.5/24)

    def test_invalid_start_duration_and_formula_are_rejected(self):
        _,snapshot,_=self.fixture()
        for cell,value in [('J19',1),('J19',-0.1),('K19',367),('K19',0.00000001)]:
            f=next(f for f in snapshot['fields'] if f['cell']==cell)
            with self.subTest(cell=cell,value=value), self.assertRaises(ValueError):
                validated_changes(snapshot,[dict(sheet='Timeline',cell=cell,before=f['value'],value=value)])
        snapshot['fields'][0]['readOnly']=True
        with self.assertRaises(ValueError):
            validated_changes(snapshot,[dict(sheet='Timeline',cell='J19',before=8/24,value=9/24)])


if __name__=='__main__':unittest.main()
