import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';

void main() {
  test('accepts the descriptive placeholders supplied for the internal template', () {
    final rendered = renderEmailTemplate(
      '{Nome do sistema C27}\n{Início do projeto pela Consultoria C23}\n'
      '{Encerramento do projeto C24}\n{Razão Social F24}\n'
      '{Proprietário F18}\n{email_cliente G18}\n{telefone_cliente H18}',
      {'sistema':'Maker','data_recebimento':'03/09/2026','data_finalizacao':'04/12/2026',
       'razao_social':'Cliente Ltda','proprietario':'Maria','email_cliente':'maria@example.com'},
      markMissing:true);
    expect(rendered, 'Maker\n03/09/2026\n04/12/2026\nCliente Ltda\nMaria\nmaria@example.com\n[PREENCHER: Telefone do cliente]');
  });
  test('Professional reads revised cells and never falls back to old phone cells', () {
    final rows = List.generate(27, (_) => List.filled(8, ''));
    rows[26][2] = 'Promob Maker Cliente';
    rows[22][2] = '03/09/2026';
    rows[23][2] = '04/12/2026';
    rows[23][5] = 'Cliente Ltda';
    rows[17][5] = 'Maria';
    rows[17][6] = 'maria@example.com';
    rows[17][7] = '54 99999-1111';
    rows[16][7] = 'old H17';
    rows[25][5] = 'old F26';
    final fields = parseEmailWorkbookRows(rows, professionalInternal: true).fields;
    expect(fields['sistema'], 'Promob Maker Cliente');
    expect(fields['data_recebimento'], '03/09/2026');
    expect(fields['data_finalizacao'], '04/12/2026');
    expect(fields['razao_social'], 'Cliente Ltda');
    expect(fields['proprietario'], 'Maria');
    expect(fields['email_cliente'], 'maria@example.com');
    expect(fields['telefone_cliente'], '54 99999-1111');
    rows[17][7] = '';
    expect(parseEmailWorkbookRows(rows, professionalInternal: true).fields['telefone_cliente'], '');
  });

  test('new template preserves products and updates comments without duplication', () {
    final body = renderEmailTemplate(defaultEmailBody(ProjectEmailKind.professionalInternal), {
      'saudacao': 'Boa tarde', 'resumo': 'Processo tranquilo.',
      'sistema': 'Maker', 'solicitacao': '2263892',
      'titulo_solicitacao': 'Professional Cliente',
    });
    expect(body, startsWith('Boa tarde a todos,'));
    expect(body, contains('Solicitação: 2263892 - Professional Cliente'));
    final updated = emailBodyWithSummary(body, 'Novo resumo.', previousSummary: 'Processo tranquilo.');
    expect(updated, contains('Comentários:\nNovo resumo.'));
    expect(updated, isNot(contains('Processo tranquilo.')));
    expect(emailBodyWithProductsImage(updated), contains(productsImageMarker));
    expect(defaultEmailBody(ProjectEmailKind.internal), isNot(contains('{titulo_solicitacao}')));
  });
}
