import unittest
import tempfile
from pathlib import Path
from contextlib import contextmanager
from unittest.mock import patch
from local_edesk import excel_editor as editor


class WorkbookReadCacheTests(unittest.TestCase):
    def setUp(self):
        editor._read_cache.clear()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(editor._read_cache.clear)
        self.path = Path(self.directory.name) / 'test.xlsm'
        self.path.write_bytes(b'first workbook')
        self.body = {'action': 'excel-editor-read', 'serviceType': 'Enterprise'}

    @contextmanager
    def excel(self, *args, **kwargs):
        yield (None, object())

    def test_repeated_reads_skip_excel_but_file_changes_and_sheet_changes_do_not(self):
        with patch.object(editor, 'workbook', side_effect=self.excel) as opened, patch.object(
                editor, 'snapshot', return_value={'fields': [], 'tasks': [], 'statusPreview': {'rows': []}}):
            first = editor.edit(self.path, self.body)
            first['fields'].append({'value': 'caller draft must not leak'})
            second = editor.edit(self.path, self.body)
            self.assertEqual(second['fields'], [])
            self.assertEqual(opened.call_count, 1)
            self.path.write_bytes(b'changed workbook')
            changed = editor.edit(self.path, self.body)
            self.assertNotEqual(first['revision'], changed['revision'])
            self.assertEqual(opened.call_count, 2)
            editor.edit(self.path, {**self.body, 'sheetNames': {'checklist': 'Other'}})
            self.assertEqual(opened.call_count, 3)

    def test_expiry_and_capacity_bound(self):
        key = editor.read_cache_key(self.path, self.body, 'digest')
        with patch.object(editor.time, 'monotonic', return_value=0):
            editor.remember_read(key, {'fields': []})
        with patch.object(editor.time, 'monotonic', return_value=31):
            self.assertIsNone(editor.cached_read(key))
        for i in range(12):
            editor.remember_read((str(i), 'digest', '{}', 'date'), {'fields': []})
        self.assertEqual(len(editor._read_cache), 8)

    def test_failed_or_changed_reads_never_populate_cache(self):
        with patch.object(editor, 'workbook', side_effect=self.excel), patch.object(
                editor, 'snapshot', side_effect=ValueError('Excel failed')):
            with self.assertRaises(ValueError):
                editor.edit(self.path, self.body)
        self.assertFalse(editor._read_cache)
        with patch.object(editor, 'workbook', side_effect=self.excel), patch.object(
                editor, 'snapshot', return_value={'fields': []}), patch.object(
                editor, 'revision', side_effect=['first', 'changed']):
            with self.assertRaises(ValueError):
                editor.edit(self.path, self.body)
        self.assertFalse(editor._read_cache)


if __name__ == '__main__':
    unittest.main()
