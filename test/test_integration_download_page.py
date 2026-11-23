"""Download page with intercepted metadata and a fake local bridge only."""
import json
import os
from pathlib import Path
import unittest
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


class IntegrationDownloadPageTest(unittest.TestCase):
    def setUp(self):
        os.environ['PLAYWRIGHT_BROWSERS_PATH'] = str(ROOT / 'python/ms-playwright')
        self.driver = sync_playwright().start()
        self.browser = self.driver.chromium.launch(headless=True)
        self.addCleanup(self.driver.stop)
        self.addCleanup(self.browser.close)

    def page(self, metadata, health=None):
        page = self.browser.new_page()
        self.addCleanup(page.close)
        def respond(route):
            if route.request.url.endswith('/integracao-completa.html'):
                route.fulfill(content_type='text/html; charset=utf-8', body=(ROOT / 'web/integracao-completa.html').read_text(encoding='utf-8'))
            elif route.request.url.endswith('/web-release.json'):
                route.fulfill(content_type='application/json', body=json.dumps({'integration': metadata}))
            elif route.request.url.endswith('/native_local_files_v2.js'):
                result = {'status': 200, 'data': health or {}}
                route.fulfill(content_type='application/javascript', body='window.nativeLocalFilesRequest=async()=>'+json.dumps(json.dumps(result))+';')
            else: route.fulfill(status=204, body='')
        page.route('**/*', respond)
        page.goto('http://packaging.example.test/integracao-completa.html')
        page.wait_for_function("!document.getElementById('available-version').textContent.includes('Consultando')")
        return page

    def test_current_and_future_links_follow_metadata_and_old_health_stays_connected(self):
        for version in ['80', '81', '105']:
            with self.subTest(version=version):
                metadata = {'version': version,
                    'updateUrl': f'/downloads/atualizacao-integracao-completa-{version}.zip',
                    'completeUrl': f'/downloads/integracao-edesk-completa-windows-v{version}.zip'}
                page = self.page(metadata, {'service': 'gerenciador-horas-edesk', 'mode': 'local', 'integrationPackageVersion': 'beta-pilot-66'})
                self.assertEqual(page.locator('#download-update').get_attribute('href'), metadata['updateUrl'])
                self.assertIsNone(page.locator('#download-update').get_attribute('aria-disabled'))
                self.assertIn('v'+version, page.locator('#available-version').inner_text())
                page.locator('#check').click()
                page.wait_for_function("document.getElementById('status').textContent.includes('conectada')")
                self.assertIn('atualiza', page.locator('#status').inner_text())

    def test_foreign_mislabeled_and_invalid_download_metadata_remains_disabled(self):
        for metadata in [None, {'version': True}, {'version': '081'},
                {'version': '81', 'updateUrl': 'https://other.example/a.zip', 'completeUrl': '/downloads/integracao-edesk-completa-windows-v81.zip'},
                {'version': '81', 'updateUrl': '/downloads/atualizacao-integracao-completa-74.zip', 'completeUrl': '/downloads/integracao-edesk-completa-windows-v81.zip'}]:
            with self.subTest(metadata=metadata):
                page = self.page(metadata)
                self.assertEqual(page.locator('#download-update').get_attribute('aria-disabled'), 'true')
                self.assertEqual(page.locator('#download-update').get_attribute('href'), '#')
                self.assertIn('Recarregue', page.locator('#available-version').inner_text())


if __name__ == '__main__': unittest.main()
