import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_status_cache.dart';

void main() {
  test('separate Catalog settings do not invalidate the main workbook status', () {
    final saved = withSavedSpreadsheetStatus({'revision': 'one'},
      {'entry': 'Entrada', 'checklist': 'Enterprise'}, {'total': .5});
    expect(savedSpreadsheetStatus(saved, {'entry': 'Entrada', 'checklist': 'Enterprise',
      'catalogEnabled': 'true', 'catalogReference': 'other.xlsm', 'catalogChecklistSheet': 'Checklist-Catalog'})!['total'], .5);
    expect(savedSpreadsheetStatus(saved, {'entry': 'Entrada', 'checklist': 'Other',
      'catalogEnabled': 'true'}), isNull);
  });
  test('status belongs to the saved revision and selected guides', () {
    final saved = withSavedSpreadsheetStatus(
        {'revision': 'one'}, {'checklist': 'Professional'}, {'total': .5});
    expect(
        savedSpreadsheetStatus(saved, {'checklist': 'Professional'})!['total'],
        .5);
    expect(
        savedSpreadsheetStatus(
            {...saved, 'revision': 'two'}, {'checklist': 'Professional'}),
        isNull);
    expect(savedSpreadsheetStatus(saved, {'checklist': 'Enterprise'}), isNull);
  });
}
