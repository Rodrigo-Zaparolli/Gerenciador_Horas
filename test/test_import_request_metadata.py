import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'edesk_bot'))
from edesk_conferencia import import_work_rows, read_request_metadata


class RequestMetadataImportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from playwright.sync_api import sync_playwright
        os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
        cls.driver = sync_playwright().start()
        cls.browser = cls.driver.chromium.launch(headless=True,
            executable_path=cls.driver.chromium.executable_path)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.driver.stop()

    def setUp(self):
        self.page = self.browser.new_page()

    def tearDown(self):
        self.page.close()

    def fixture(self):
        self.page.set_content('''
        <div>Solicitação: 2266963 - Promob Studio Start PROMAD - Implantação Plugin</div>
        <div>Solicitante: PROMAD COMERCIO LTDA / ALEXANDRE PAULO DO CARMO</div>
        <div class="rtsLevel1">
          <a class="rtsLink" href="#" onclick="requestPanel.hidden=false;works.hidden=true">Solicitação</a>
          <a class="rtsLink" href="#" onclick="requestPanel.hidden=true;works.hidden=false">Trabalhos (3)</a>
        </div>
        <div id="requestPanel" hidden><table>
          <tr><td>Responsável</td><td>Flavia Martinelli</td></tr>
          <tr><td>Executivo responsável</td><td>Pedro Santos</td></tr>
        </table></div>
        <div id="works"><table id="cph1_gvwTra">
          <tr><th>ID</th><th>Tipo de Trabalho</th><th>Atendente</th><th>Tp. Estimado</th><th>Fase</th></tr>
          <tr><td><a onclick="/* btnSelTra */">3</a></td><td>Implantação Plugin (OH)</td><td>Rodrigo Zaparolli</td><td>07:30</td><td>PROMOB - Implantação Plugin Desenvolvimento</td></tr>
        </table></div>
        <button onclick="window.saved=true">Salvar</button>
        ''')

    def test_reads_request_company_and_responsible_not_work_attendant(self):
        self.fixture()
        rows = import_work_rows(self.page, '2266963')
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['idTrabalho'], '3')
        self.assertEqual(rows[0]['values']['phase'], 'PROMOB - Implantação Plugin Desenvolvimento')
        self.assertEqual(rows[0]['values']['requestClient'], 'PROMAD COMERCIO LTDA')
        self.assertEqual(rows[0]['values']['requestLeader'], 'Flavia Martinelli')
        self.assertEqual(rows[0]['values']['client'], 'PROMAD COMERCIO LTDA')
        self.assertEqual(rows[0]['values']['leader'], 'Flavia Martinelli')
        self.assertTrue(self.page.locator('#cph1_gvwTra').is_visible())
        self.assertIsNone(self.page.evaluate('window.saved'))

    def test_wrong_request_is_rejected(self):
        self.fixture()
        for include_metadata in [True, False]:
            with self.assertRaisesRegex(RuntimeError, 'outra solicitacao'):
                import_work_rows(self.page, '9999999', include_metadata=include_metadata)

    def test_real_id_is_distinct_from_clickable_order(self):
        self.fixture()
        self.page.evaluate('''() => {
          const table=document.querySelector('#cph1_gvwTra');
          table.rows[0].cells[0].textContent='';
          table.rows[0].insertCell(1).textContent='Ordem';
          const order=table.rows[1].insertCell(1);
          order.textContent='1'; order.setAttribute('onclick','/* btnSelTra */');
        }''')
        rows=import_work_rows(self.page, '2266963', include_metadata=False)
        self.assertEqual(rows[0]['idTrabalho'], '3')

    def test_order_alone_is_not_a_real_work_id(self):
        self.fixture()
        self.page.evaluate("document.querySelector('#cph1_gvwTra').rows[0].cells[0].textContent='Ordem'")
        with self.assertRaisesRegex(RuntimeError, 'ID real'):
            import_work_rows(self.page, '2266963', include_metadata=False)

    def test_missing_responsible_never_uses_executive_or_attendant(self):
        self.page.set_content('''<div>Solicitação: 2266963 - Projeto</div>
          <div>Solicitante: PROMAD COMERCIO LTDA / ALEXANDRE</div>
          <table><tr><td>Responsável</td><td></td></tr>
          <tr><td>Executivo responsável</td><td>Pedro Santos</td></tr>
          <tr><td>Atendente</td><td>Rodrigo Zaparolli</td></tr></table>''')
        data = read_request_metadata(self.page, '2266963')
        self.assertEqual(data['requestClient'], 'PROMAD COMERCIO LTDA')
        self.assertNotIn('requestLeader', data)

    def test_labelled_control_uses_its_value(self):
        self.page.set_content('''<div>Solicitação: 2266963 - Projeto</div>
          <div>Solicitante: PROMAD COMERCIO LTDA / ALEXANDRE</div>
          <label for="responsible">Responsável:</label><input id="responsible" value="Flavia Martinelli">
          <span>Executivo responsável</span><span>Pedro Santos</span>''')
        self.assertEqual(read_request_metadata(self.page, '2266963')['requestLeader'], 'Flavia Martinelli')


if __name__ == '__main__':
    unittest.main()
