from types import SimpleNamespace
import unittest
from unittest.mock import patch
from local_edesk.project_documents import plan_original_formula, plan_text_formula, plan_snapshot


class PlanTextTests(unittest.TestCase):
    def test_quote_escaping_long_text_and_repeated_edits_retain_original_formula(self):
        original = '="O cliente "&Entrada!F23&" homologa e aceita o projeto"'
        text = 'Conclusão "parcial";\n' * 40
        formula = plan_text_formula(original, text)
        self.assertEqual(plan_original_formula(formula), original)
        self.assertIn('""parcial""', formula)
        self.assertEqual(plan_original_formula(plan_text_formula(formula, 'Concluído')), original)
        self.assertEqual(plan_original_formula(plan_text_formula(formula, '')), original)
        with self.assertRaises(ValueError):
            plan_text_formula(original, 'x' * 10000)

    def test_only_conclusion_text_formulas_become_editable_and_blank_agreements_stay_editable(self):
        values = [[None]*12 for _ in range(205)]
        formulas = [[None]*12 for _ in range(205)]
        values[145][1] = 'O cliente Cliente homologa e aceita o projeto'
        formulas[145][1] = '="O cliente "&Entrada!F23&" homologa e aceita o projeto"'
        values[88][3] = 'Sistema do cliente'
        formulas[88][3] = '=Entrada!C27'
        values[111][0] = '5.1.3'
        def cell(address):
            return SimpleNamespace(Value2=values if address == 'A1:L205' else None,
                Formula=formulas, HasArray=False)
        sheet = SimpleNamespace(Name='Plano de Projeto', Range=cell)
        with patch('local_edesk.project_documents.plan_sheet', return_value=sheet):
            result = plan_snapshot(None, sheet.Name)
        fields = {f['cell']: f for f in result['fields']}
        self.assertTrue(fields['B146']['managedPlanTextFormula'])
        self.assertNotIn('D89', fields)
        self.assertEqual(fields['B112']['value'], '')


if __name__ == '__main__':
    unittest.main()
