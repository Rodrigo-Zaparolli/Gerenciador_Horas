import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';

void main() {
  test('Internal closing uses only the nine specified roles in Para', () {
    final rows = List.generate(48, (_) => List.filled(7, ''));
    for (final row in [44, 43, 39, 38, 41, 42, 46, 47, 48, 17, 37, 45]) {
      rows[row - 1][6] = 'cell$row@example.com';
    }
    final result = internalRecipientsFromRows(rows);
    expect(result.map((c) => c.email), [44, 43, 39, 38, 41, 42, 46, 47, 48].map((r) => 'cell$r@example.com'));
    expect(result.every((c) => c.destination == 'Para'), true);
    rows[37][6] = 'CELL39@example.com';
    expect(internalRecipientsFromRows(rows), hasLength(8));
    rows[43][6] = '';
    rows[42][6] = 'sem email';
    expect(internalRecipientsFromRows(rows), hasLength(6));
    expect(internalRecipientsFromRows([]), isEmpty);
  });
}
