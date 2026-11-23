"""Package identity and preflight checks; never start installed services."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from integration_release import release, package_name, destination


class IntegrationReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def metadata(self, **changes):
        data = {'schemaVersion': 1, 'version': '81', 'status': 'candidate'}
        data.update(changes)
        (self.root / 'integration-release.json').write_text(json.dumps(data), encoding='utf-8')
        return data

    def ps(self, code):
        helper = str(ROOT / 'scripts/integration_release.ps1').replace("'", "''")
        result = subprocess.run(['powershell', '-NoProfile', '-Command',
            "$ErrorActionPreference='Stop'; . '" + helper + "'; " + code],
            capture_output=True, text=True, timeout=30)
        return result

    def test_future_versions_and_output_names_match_powershell(self):
        for version in ['81', '105']:
            with self.subTest(version=version):
                self.metadata(version=version)
                self.assertEqual(release(self.root)['version'], version)
                names = [package_name(k, self.root) for k in ['complete', 'update', 'opener']]
                root = str(self.root).replace("'", "''")
                result = self.ps("$r=Get-IntegrationRelease -Root '" + root + "'; @('complete','update','opener') | ForEach-Object { Get-IntegrationPackageName -Release $r -Kind $_ }")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), names)

    def test_invalid_metadata_is_rejected_by_both_runtimes(self):
        for change in [{'version': 81}, {'version': '../81'}, {'version': '081'},
                       {'version': '0'}, {'version': '81?x'}, {'status': 'unknown'},
                       {'schemaVersion': True}]:
            with self.subTest(change=change):
                self.metadata(**change)
                with self.assertRaises(ValueError): release(self.root)
                result = self.ps("Get-IntegrationRelease -Root '" + str(self.root).replace("'", "''") + "'")
                self.assertNotEqual(result.returncode, 0)

    def test_existing_package_is_never_reused_or_overwritten(self):
        self.metadata()
        target = destination('complete', self.root / 'out', self.root)
        target.write_bytes(b'preserve this existing package')
        with self.assertRaises(FileExistsError): destination('complete', self.root / 'out', self.root)
        self.assertEqual(target.read_bytes(), b'preserve this existing package')

    def test_code_update_includes_shared_runtime_modules(self):
        import package_edesk_update
        files = package_edesk_update.FILES
        self.assertEqual(len(files), len(set(files)))
        for name in ['integration-release.json', 'scripts/integration_release.ps1',
                     'edesk_bot/send_progress.py', 'scripts/stop_local_files.ps1',
                     'local_edesk/authentication.py', 'local_edesk/central.py',
                     'local_edesk/server.py', 'local_edesk/zendesk_routes.py',
                     'local_edesk/zendesk_workflow.py']:
            self.assertIn(name, files)

    def test_missing_packages_abort_release_before_build_or_manifest_changes(self):
        manifest = ROOT / 'build/web/web-release.json'
        before = manifest.read_bytes() if manifest.exists() else None
        result = subprocess.run(['powershell', '-NoProfile', '-File',
            str(ROOT / 'scripts/build_web_release.ps1'), '-PackageDirectory',
            str(self.root), '-FlutterPath', 'SHOULD_NOT_RUN.invalid'],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Pacote ausente', result.stderr)
        self.assertEqual(manifest.read_bytes() if manifest.exists() else None, before)

    def test_package_preflight_rejects_mislabeled_or_incomplete_archives(self):
        metadata = self.metadata()
        path = self.root / package_name('complete', self.root)
        required = ['local_edesk/zendesk_routes.py', 'local_edesk/zendesk_workflow.py',
                    'edesk_bot/edesk_adv.py', 'edesk_bot/edesk_ns_interno.py',
                    'scripts/start_full_integration.ps1', 'scripts/integration_release.ps1']
        for version, modules, expected in [('74', required, False), ('81', [], False), ('81', required, True)]:
            with self.subTest(version=version, modules=bool(modules)):
                with ZipFile(path, 'w') as archive:
                    archive.writestr('integration-release.json', json.dumps({**metadata, 'version': version}))
                    for name in modules: archive.writestr(name, '# fixture only')
                result = self.ps("$r=Get-IntegrationRelease -Root '" + str(self.root).replace("'", "''") + "'; Test-IntegrationPackage -Path '" + str(path).replace("'", "''") + "' -Release $r -Kind complete")
                self.assertEqual(result.returncode == 0, expected, result.stderr)


if __name__ == '__main__': unittest.main()
