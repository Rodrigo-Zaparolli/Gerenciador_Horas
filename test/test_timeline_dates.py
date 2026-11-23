from datetime import datetime
from types import SimpleNamespace
import unittest
from local_edesk.timeline_dates import normalized_changes, BASE


class TimelineDatesTest(unittest.TestCase):
    def fixture(self):
        serial = (datetime(2026, 11, 16)-BASE).days
        cells = {'C19': SimpleNamespace(Value2=serial, HasFormula=True),
                 'C20': SimpleNamespace(Value2=serial+1, HasFormula=True),
                 'H19': SimpleNamespace(Value2=1, HasFormula=False)}
        sheet = SimpleNamespace(Range=lambda key: cells[key])
        def calculate(): cells['C20'].Value2=cells['C19'].Value2+cells['H19'].Value2
        book = SimpleNamespace(Worksheets=lambda _: sheet, Application=SimpleNamespace(CalculateFull=calculate))
        date = dict(sheet='Timeline',cell='C20',value='2026-11-17',kind='date',readOnly=True,
            timelineDateEditable=True,dateDriver=dict(sheet='Timeline',cell='H19',previousDate='C19'))
        days = dict(sheet='Timeline',cell='H19',value=1,kind='number',readOnly=False,timelineDays=True)
        return book, {'fields':[date,days],'tasks':[]}, cells

    def test_date_edit_becomes_days_and_retains_calculated_cell(self):
        book, snapshot, cells = self.fixture()
        changes=normalized_changes(book,snapshot,[dict(sheet='Timeline',cell='C20',before='2026-11-17',value='2026-11-18')])
        self.assertEqual([(f['cell'],v) for f,v in changes],[('H19',2)])
        self.assertTrue(cells['C20'].HasFormula)
        self.assertEqual(changes[0][0]['value'],1)

    def test_stale_invalid_and_reversed_dates_are_rejected(self):
        for before, new in [('old','2026-11-18'),('2026-11-17','invalid'),('2026-11-17','2026-11-15')]:
            book,snapshot,_=self.fixture()
            with self.assertRaises(ValueError):
                normalized_changes(book,snapshot,[dict(sheet='Timeline',cell='C20',before=before,value=new)])

    def test_conflicting_date_and_driver_are_rejected(self):
        book,snapshot,_=self.fixture()
        with self.assertRaisesRegex(ValueError,'mesma transição'):
            normalized_changes(book,snapshot,[dict(sheet='Timeline',cell='H19',before=1,value=3),
                dict(sheet='Timeline',cell='C20',before='2026-11-17',value='2026-11-18')])

    def test_unmapped_cells_are_not_accepted(self):
        book,snapshot,_=self.fixture()
        with self.assertRaises(ValueError):
            normalized_changes(book,snapshot,[dict(sheet='Timeline',cell='D20',before='',value='text')])

if __name__=='__main__':unittest.main()
