from types import SimpleNamespace
import unittest
from local_edesk.excel_editor import checklist_tasks

class ChecklistHoursTest(unittest.TestCase):
    def test_native_estimates_are_minutes_and_invalid_values_are_not_zero(self):
        estimates={2:1/24,3:'01:30',4:None,5:'#VALUE!'}
        def cell(row,column):
            return SimpleNamespace(HasFormula=False,Value2={4:'Implantação',5:0,6:'Tarefa',8:estimates[row],10:''}.get(column))
        tasks=checklist_tasks(SimpleNamespace(Name='Checklist',Cells=cell),1,5)
        self.assertEqual([t['estimatedMinutes'] for t in tasks],[60,90,0,None])
        self.assertEqual([t['estimatedValid'] for t in tasks],[True,True,True,False])
        self.assertEqual(tasks[-1]['estimated'],'Não consultado')

if __name__=='__main__':unittest.main()
