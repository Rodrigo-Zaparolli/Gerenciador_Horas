import os
import unittest
from unittest.mock import patch

os.environ['EDESK_LOCAL_MODE'] = 'true'
from local_edesk.sharepoint_browser import valid_link
from cloud_run import main


class SharePointBrowserTest(unittest.TestCase):
    def test_breadcrumb_uses_full_title_and_rejects_truncation(self):
        from playwright.sync_api import sync_playwright
        from local_edesk.sharepoint_browser import folder_name
        from pathlib import Path
        with patch.dict(os.environ, {'PLAYWRIGHT_BROWSERS_PATH': str(Path(__file__).resolve().parents[1] / 'python/ms-playwright')}):
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(headless=True, executable_path=playwright.chromium.executable_path)
                try:
                    page = browser.new_page()
                    page.set_content('<div class="ms-Breadcrumb-list"><li class="ms-Breadcrumb-listItem"><button class="ms-Breadcrumb-itemLink" title="Enterprise - Client folder">Enterprise...</button></li></div>')
                    self.assertEqual(folder_name(page), 'Enterprise - Client folder')
                    page.set_content('<div class="ms-Breadcrumb-list"><li class="ms-Breadcrumb-listItem"><button class="ms-Breadcrumb-itemLink">Enterprise...</button></li></div>')
                    self.assertIsNone(folder_name(page))
                    page.set_content('<h1>Sign in</h1><title>SharePoint</title>')
                    self.assertIsNone(folder_name(page))
                finally:
                    browser.close()

    def test_only_sharepoint_https_links(self):
        self.assertTrue(valid_link('https://cyncly.sharepoint.com/:f:/s/Client/token'))
        for link in [None, '', 'http://cyncly.sharepoint.com/a',
                     'https://cyncly.sharepoint.com.evil.test/a',
                     'https://user@cyncly.sharepoint.com/a',
                     'https://cyncly.sharepoint.com:444/a', 'file:///C:/private']:
            self.assertFalse(valid_link(link), link)

    def test_requires_authentication(self):
        with main.app.test_client() as client:
            response = client.post('/api/sharepoint/names', json={'links': []},
                headers={'Origin': 'https://gerenciador-horas.web.app'})
            self.assertEqual(response.status_code, 401)

    def test_invalid_links_never_launch_browser(self):
        with patch.object(main, '_authenticated_user', return_value=({'sub': 'owner'}, None)), \
             patch.object(main.subprocess, 'run') as run, main.app.test_client() as client:
            response = client.post('/api/sharepoint/names', json={'links': ['https://example.com']},
                headers={'Origin': 'https://gerenciador-horas.web.app'})
            self.assertEqual(response.status_code, 400)
            run.assert_not_called()

    def test_owner_is_taken_from_verified_token(self):
        import json
        from types import SimpleNamespace
        link = 'https://cyncly.sharepoint.com/:f:/s/Client/token'
        with patch.object(main, '_authenticated_user', return_value=({'sub': 'verified-owner'}, None)), \
             patch.object(main.subprocess, 'run', return_value=SimpleNamespace(returncode=0,
                stdout=json.dumps({'names': {link: 'Client folder'}, 'errors': []}))) as run, \
             main.app.test_client() as client:
            response = client.post('/api/sharepoint/names', json={'owner': 'wrong-owner', 'links': [link]},
                headers={'Origin': 'https://gerenciador-horas.web.app'})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(json.loads(run.call_args.kwargs['input'])['owner'], 'verified-owner')


if __name__ == '__main__':
    unittest.main()
