import asyncio
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'edesk_bot'))
from phase_confirmation import mismatched_phases, close_new_duplicate_requests, fill_empty_original_dates, validate_phase_targets, phase_key
import send_progress

class PhaseConfirmationTest(unittest.TestCase):
    def test_phase_targets_must_all_exist_once_before_filling(self):
        validate_phase_targets(['Implantacao'], ['Implantacao', 'Outra fase'], phase_key)
        for names in [[], ['Outra fase'], ['Implantacao', 'Implantacao']]:
            with self.assertRaisesRegex(ValueError, 'forma unica'):
                validate_phase_targets(['Implantacao'], names, phase_key)
    def test_original_dates_only_fill_empty_fields_in_the_same_phase(self):
        async def run():
            from playwright.async_api import async_playwright
            root = Path(__file__).resolve().parents[1]
            with patch.dict(os.environ, PLAYWRIGHT_BROWSERS_PATH=str(root / 'python/ms-playwright')):
                async with async_playwright() as driver:
                    browser = await driver.chromium.launch(headless=True, executable_path=driver.chromium.executable_path)
                    try:
                        page = await browser.new_page()
                        for initial, final in [('', ''), ('01/09/2026', ''), ('', '30/09/2026'), ('01/09/2026', '30/09/2026')]:
                            await page.set_content('''<table><tr><td>Data Inicial</td><td>Data Final</td><td>Dt. Ini. Ajustada</td><td>Dt. Fin. Ajustada</td></tr>
                              <tr><td><input id="originalStart"></td><td><input id="originalEnd"></td>
                              <td><input id="txtGFasDtIniAj"></td><td><input id="txtGFasDtTerAju"></td></tr></table>
                              <input id="unrelated" value="preserved">''')
                            await page.locator('#originalStart').fill(initial)
                            await page.locator('#originalEnd').fill(final)
                            await fill_empty_original_dates(page.locator('#txtGFasDtIniAj'), '04/11/2026', '30/11/2026')
                            self.assertEqual(await page.locator('#originalStart').input_value(), initial or '04/11/2026')
                            self.assertEqual(await page.locator('#originalEnd').input_value(), final or '30/11/2026')
                            self.assertEqual(await page.locator('#unrelated').input_value(), 'preserved')
                    finally:
                        await browser.close()
        asyncio.run(run())

    def test_only_reloaded_matching_dates_are_confirmed(self):
        expected = [{'nome': 'Implantação', 'dataInicial': '01/10/2026', 'dataFinal': '14/10/2026'}]
        self.assertEqual(mismatched_phases(expected, expected), [])
        self.assertTrue(mismatched_phases(expected, [{**expected[0], 'dataFinal': '10/10/2026'}]))
        self.assertTrue(mismatched_phases(expected, []))
        self.assertTrue(mismatched_phases(expected, expected + expected))

    def test_only_new_duplicate_tabs_are_closed(self):
        class Page:
            url = 'https://promob.e-desk.com.br/Portal/Solicitacao.aspx?id=abc'
            closed = False
            def is_closed(self): return self.closed
            async def close(self): self.closed = True
        selected, duplicate, original = Page(), Page(), Page()
        class Context: pages = [selected, duplicate, original]
        asyncio.run(close_new_duplicate_requests(Context(), selected, [original]))
        self.assertTrue(duplicate.closed)
        self.assertFalse(selected.closed)
        self.assertFalse(original.closed)

    def test_confirmed_progress_survives_stage_changes_and_deduplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'progress.json'
            with patch.dict(os.environ, EDESK_PROGRESS_FILE=str(target), EDESK_PROGRESS_TOTAL='3'):
                send_progress._completed.clear()
                send_progress.completed('first')
                send_progress.completed('first')
                send_progress.stage('preparing')
                data = json.loads(target.read_text())
                self.assertEqual(data['completed'], 1)
                self.assertEqual(data['total'], 3)
                self.assertEqual(data['stage'], 'preparing')
                send_progress._completed.clear()

if __name__ == '__main__': unittest.main()
