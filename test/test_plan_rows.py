import unittest
from local_edesk.plan_rows import split


class PlanRowValidationTests(unittest.TestCase):
    def test_remove_guidance_can_be_combined_with_text_and_rows(self):
        removal = {'operation': 'remove-plan-guidance', 'names': ['Seta 1', 'Seta 2']}
        self.assertEqual(split([removal], 205), ([], [removal]))
        for names in [[], ['x', 'x'], [None], 'x']:
            with self.assertRaises(ValueError):
                split([{'operation': 'remove-plan-guidance', 'names': names}], 205)

    def test_rows_use_current_coordinates_and_keep_edits_separate(self):
        first = {'operation': 'insert-plan-rows', 'row': 111, 'count': 2}
        second = {'operation': 'insert-plan-rows', 'row': 112, 'count': 1}
        edit = {'sheet': 'Plano de Projeto', 'cell': 'B111', 'before': '', 'value': 'Acordo'}
        edits, ops = split([first, edit, second], 205)
        self.assertEqual(edits, [edit])
        self.assertEqual(ops, [first, second])

    def test_invalid_rows_counts_and_unknown_operations_are_rejected(self):
        for bad in [
            {'operation': 'insert-plan-rows', 'row': 0, 'count': 1},
            {'operation': 'insert-plan-rows', 'row': 207, 'count': 1},
            {'operation': 'insert-plan-rows', 'row': True, 'count': 1},
            {'operation': 'insert-plan-rows', 'row': 110, 'count': 21},
            {'operation': 'insert-plan-rows', 'row': 110, 'count': 0},
            {'operation': 'delete-plan-rows', 'row': 110, 'count': 1},
        ]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                split([bad], 205)
        with self.assertRaises(ValueError):
            split([{'operation':'insert-plan-rows','row':1,'count':20}]*6,205)
        with self.assertRaises(ValueError):
            split([{'operation':'insert-plan-rows','row':1,'count':20}],490)


if __name__ == '__main__':
    unittest.main()
