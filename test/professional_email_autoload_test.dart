import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  test('Fills pending draft fields without replacing written content', () {
    final result = fillMissingEmailFields('Minha observação. Sistema: [PREENCHER: Nome do sistema]. Recebimento: [PREENCHER: Data de recebimento]. Produtos: [PREENCHER: Produtos adquiridos]. Telefone escrito: 1234.', {'sistema':'Sistema atualizado','data_recebimento':'01/11/2026'});
    expect(result,contains('Sistema atualizado'));
    expect(result,contains('01/11/2026'));
    expect(result,contains('Minha observação.'));
    expect(result,contains('Telefone escrito: 1234.'));
    expect(result,contains('[PREENCHER: Produtos adquiridos]'));
    expect(fillMissingEmailFields('[PREENCHER: Nome do sistema C27]', {'sistema':'Nome correto'}), 'Nome correto');
  });
  for (final service in ['Promob Professional','Enterprise']) {
    testWidgets('Internal $service fills an edited draft when loading linked sheet', (tester) async {
      tester.view.physicalSize=const Size(1440,1000); tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final book=excel.Excel.createExcel(); final sheet=book['Informações de entrada'];
      for(final c in {'C27':'Sistema atualizado','C23':'01/11/2026','C24':'19/11/2026'}.entries) {
        sheet.cell(excel.CellIndex.indexByString(c.key)).value=excel.TextCellValue(c.value);
      }
      final kind=service=='Enterprise'?ProjectEmailKind.internal:ProjectEmailKind.professionalInternal;
      final store=MemoryEmailStore();
      store.drafts['owner-a/2262790/${kind.name}']={'contacts':[],'fields':{},'body':'Minha observação. Sistema: [PREENCHER: Nome do sistema]. Recebimento: [PREENCHER: Data de recebimento].'};
      var reads=0;
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(project:ProjectModel.fromJson({'id':'2262790','client':'Cliente','serviceType':service,'excelLink':'linked'}),store:store,workbookLoader:()async {reads++; return Uint8List.fromList(book.encode()!);} ))));
      await tester.pumpAndSettle();
      final chip=find.widgetWithText(ChoiceChip,ProjectEmailKind.internal.label);
      await tester.ensureVisible(chip); await tester.tap(chip); await tester.pumpAndSettle();
      final body=tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
      expect(reads,2); expect(body,contains('Minha observação.')); expect(body,contains('Sistema atualizado')); expect(body,contains('01/11/2026'));
      expect(find.text('Importar dados da planilha?'),findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  testWidgets('Professional internal reads linked workbook on selection without import clicks', (tester) async {
    tester.view.physicalSize = const Size(1440,1000);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final book=excel.Excel.createExcel();
    final sheet=book['Informações de entrada'];
    for (final cell in {'C27':'Maker Produção','C23':'03/09/2026','C24':'05/12/2026',
      'F24':'Cliente da planilha Ltda','F18':'Maria','G18':'maria@example.com',
      'H18':'54 99999-1234','F26':'54 3333-1234'}.entries) {
      sheet.cell(excel.CellIndex.indexByString(cell.key)).value=excel.TextCellValue(cell.value);
    }
    var reads=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(
      project:ProjectModel.fromJson({'id':'2263850','client':'Cliente','serviceType':'Promob Professional','excelLink':'linked-book'}),
      store:MemoryEmailStore(),workbookLoader:()async { reads++; return Uint8List.fromList(book.encode()!); }))));
    await tester.pumpAndSettle();
    final chip=find.widgetWithText(ChoiceChip,ProjectEmailKind.internal.label);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(reads,2);
    expect(find.text('Importar dados da planilha?'),findsNothing);
    final values=tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
    expect(values,contains('Maker Produção'));
    expect(values,contains('03/09/2026'));
    expect(values,contains('05/12/2026'));
    expect(values,contains('Cliente da planilha Ltda'));
    expect(values,contains('Maria'));
    expect(values,contains('maria@example.com'));
    expect(values,contains('54 99999-1234'));
    expect(tester.takeException(),isNull);
  });
}
