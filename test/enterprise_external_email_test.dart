import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';
import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  setUp(()=>LocalUserState.memory={});tearDown(()=>LocalUserState.memory=null);
  test('Enterprise external uses the same wording as Professional with its own ER cells', () {
    expect(defaultEmailBody(ProjectEmailKind.finalization,enterprise:true),
        defaultEmailBody(ProjectEmailKind.finalization,professional:true));
    final rows=List.generate(48,(_)=>List.filled(8,''));
    rows[17][5]='Maria';rows[23][2]='05/12/2026';
    rows[37][5]='Vendas';rows[37][6]='vendas@example.com';
    rows[38][5]='ER Enterprise';rows[38][6]='er@example.com';
    final fields=parseEmailWorkbookRows(rows,enterpriseInternal:true).fields;
    final body=renderEmailTemplate(defaultEmailBody(ProjectEmailKind.finalization,enterprise:true),
        {...fields,'saudacao':'Boa tarde'},markMissing:true);
    expect(body,startsWith('Boa tarde Maria,'));
    expect(body,contains('no dia 05/12/2026'));
    expect(body,contains('o seu nome é ER Enterprise'));
    expect(body,contains('e-mail er@example.com'));
    expect(body,isNot(contains('vendas@example.com')));
    expect(body,isNot(contains('Senhas:')));
  });
  testWidgets('Enterprise external loads its dates and ER without selecting recipients', (tester) async {
    tester.view.physicalSize=const Size(1440,1000);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final book=excel.Excel.createExcel();
    for(final cell in {'F18':'Maria','C24':'05/12/2026','F38':'Vendas','G38':'vendas@example.com',
      'F39':'ER Enterprise','G39':'er@example.com'}.entries) {
      book['Informações de entrada'].cell(excel.CellIndex.indexByString(cell.key)).value=excel.TextCellValue(cell.value);
    }
    final store=MemoryEmailStore();
    store.templates['owner-a/finalization']={'body':defaultEmailBody(ProjectEmailKind.finalization)};
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(
      project:ProjectModel.fromJson({'id':'123','client':'Cliente','serviceType':'Promob Enterprise'}),
      store:store,workbookLoader:()async=>Uint8List.fromList(book.encode()!)))));
    await tester.pumpAndSettle();
    final external=find.widgetWithText(ChoiceChip,'Encerramento Externo');
    await tester.ensureVisible(external);await tester.tap(external);await tester.pumpAndSettle();
    final load=find.text('Carregar dados da planilha');
    await tester.ensureVisible(load);await tester.tap(load);await tester.pumpAndSettle();
    final body=tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
    expect(body,contains('Maria,'));expect(body,contains('ER Enterprise'));expect(body,contains('05/12/2026'));
    expect(body,isNot(contains('vendas@example.com')));
    final recipients=tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
    expect(recipients.map((c)=>c.email).toSet(),{'er@example.com','vendas@example.com'});
    expect(recipients.every((c)=>c.destination=='Cc'),true);
    expect(tester.takeException(),isNull);
  });
}
