import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';

void main() {
  test('Leader is resolved by exact role in shifted layouts, never services manager', () {
    final rows = List.generate(48, (_) => List.filled(7, ''));
    rows[43][4] = 'Líder de Projetos';
    rows[43][5] = 'Líder correta';
    rows[43][6] = 'lider@example.com';
    rows[44][4] = 'Gestora Serviços';
    rows[44][6] = 'gestora@example.com';
    rows[47][4] = 'Líder de Projetos (serviços)';
    rows[47][6] = 'servicos@example.com';
    final recipients = externalRecipientsFromRows(rows);
    expect(recipients.map((c) => c.email), ['lider@example.com']);
    expect(recipients.single.name, 'Líder correta');
    rows[43][4] = '';
    rows[43][6] = '';
    expect(externalRecipientsFromRows(rows), isEmpty);
  });

  test('Ambiguous project leader role does not choose an arbitrary contact', () {
    final rows = List.generate(48, (_) => List.filled(7, ''));
    for (final row in [43, 45]) {
      rows[row - 1][4] = 'Líder de Projetos';
      rows[row - 1][6] = 'pessoa$row@example.com';
    }
    expect(externalRecipientsFromRows(rows), isEmpty);
  });
  test('External recipients use exactly the specified cells and deduplicate', () {
    final rows = List.generate(48, (_) => List.filled(8, ''));
    void address(int row, String email) => rows[row - 1][6] = email;
    address(17, 'owner@example.com');
    address(18, 'tech@example.com');
    address(19, 'participant@example.com');
    address(20, '');
    address(38, 'SALES@example.com');
    address(39, 'sales@example.com');
    address(45, 'leader@example.com');
    address(37, 'consultant@example.com');
    final contacts = externalRecipientsFromRows(rows);
    expect(contacts.where((c) => c.destination == 'Para').map((c) => c.email),
        ['owner@example.com', 'tech@example.com', 'participant@example.com']);
    expect(contacts.where((c) => c.destination == 'Cc').map((c) => c.email),
        ['sales@example.com', 'leader@example.com']);
    address(39, 'OWNER@example.com');
    expect(externalRecipientsFromRows(rows).where((c) => c.email.toLowerCase() == 'owner@example.com'), hasLength(1));
  });

  test('Missing and invalid optional addresses are omitted', () {
    expect(externalRecipientsFromRows([]), isEmpty);
    final rows = List.generate(45, (_) => List.filled(7, ''));
    rows[16][6] = 'owner@example.com';
    rows[17][6] = 'sem email';
    expect(externalRecipientsFromRows(rows).map((c) => c.email), ['owner@example.com']);
  });
}
