from types import SimpleNamespace
import unittest
from local_edesk.project_documents import plan_view_region, remove_plan_guidance


class PlanViewRegionTests(unittest.TestCase):
    def sheet(self, shapes):
        return SimpleNamespace(Shapes=shapes, Range=lambda address: SimpleNamespace(Left=0, Width=600, Address=address))

    def shape(self, column=25, row=120, visible=True, text='Ajustar'):
        return SimpleNamespace(Visible=visible, Name='Seta', BottomRightCell=SimpleNamespace(Column=column, Row=row),
            Left=590, Width=300, TextFrame2=SimpleNamespace(TextRange=SimpleNamespace(Text=text)))

    def test_visible_arrows_to_Y_extend_editor_to_Z_without_changing_document_area(self):
        region, notes = plan_view_region(self.sheet([self.shape()]))
        self.assertEqual(region.Address, 'A1:Z205')
        self.assertEqual(notes, [{'name': 'Seta', 'text': 'Ajustar'}])

    def test_hidden_shapes_do_not_inflate_editor_and_ordinary_document_stays_same(self):
        region, notes = plan_view_region(self.sheet([self.shape(column=500, visible=False)]))
        self.assertEqual(region.Address, 'A1:L205')
        self.assertFalse(notes)

    def test_unbounded_shapes_are_reported_instead_of_silently_cropped(self):
        with self.assertRaises(ValueError):
            plan_view_region(self.sheet([self.shape(column=100)]))

    def test_remove_guidance_preserves_shapes_and_excludes_them_from_mirror(self):
        arrow = self.shape()
        logo = self.shape(column=4, text='Logo')
        logo.Name, logo.Left, logo.Width = 'Logo', 0, 100
        sheet = self.sheet([arrow, logo])
        remove_plan_guidance(sheet, ['Seta'])
        self.assertFalse(arrow.Visible)
        self.assertTrue(logo.Visible)
        self.assertEqual(len(sheet.Shapes), 2)
        region, notes = plan_view_region(sheet)
        self.assertFalse(notes)
        self.assertEqual(region.Address, 'A1:L205')
        with self.assertRaises(ValueError):
            remove_plan_guidance(sheet, ['Logo'])


if __name__ == '__main__':
    unittest.main()
