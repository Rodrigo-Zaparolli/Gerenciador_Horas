import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  test('Accepts xlsx and xlsm attachments and uses the selected filename', () {
    final macro=EmailAttachment('Definições de Acabamentos.xlsm',Uint8List.fromList([1,2,3]));
    final ordinary=EmailAttachment('projeto.xlsx',Uint8List.fromList([4]));
    expect(finishesSpreadsheet([ordinary,macro]),same(macro));
    expect(finishesSpreadsheet([ordinary]),same(ordinary));
    expect(finishesSpreadsheet([EmailAttachment('arquivo.xlsm.exe',Uint8List.fromList([1]))]),isNull);
    expect(finishesSpreadsheet([]),isNull);
    final text=finishesAttachmentText(defaultEmailBody(ProjectEmailKind.finishes),macro);
    expect(text,contains('segue anexo Definições de Acabamentos.xlsm.'));
    expect(text,isNot(contains('segue anexo Planilha Definições de Acabamentos.xlsx.')));
  });
  test('Consultant phone and existing signature are corrected without touching prose', () {
    final consultant={'consultor':'Rodrigo Zaparolli','email_consultor':'rodrigo.zaparolli@cyncly.com',
      'telefone_consultor':emailConsultantPhone('rodrigo.zaparolli@cyncly.com','')};
    expect(consultant['telefone_consultor'],'5430225800');
    expect(emailConsultantPhone('outro@example.com','1234'),'1234');
    final body=updateEmailSender('Fulvio participou do projeto.\n\nAtt,\nFulvio\nfulvio@example.com\n[PREENCHER: Telefone do consultor]',
      {'consultor':'Fulvio','email_consultor':'fulvio@example.com'},consultant,includePhone:true);
    expect(body,startsWith('Fulvio participou do projeto.'));
    expect(body,contains('Att,\nRodrigo Zaparolli\nrodrigo.zaparolli@cyncly.com\n5430225800'));
    expect(body,isNot(contains('fulvio@example.com')));
  });
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  test('Finishes email follows supplied body and keeps deadline visible', () {
    final fields={'saudacao':'Bom dia','proprietario':'Ana','responsavel_tecnico':'Bruno','nome_resumido_sistema':'Cliente','consultor':'Consultor','email_consultor':'consultor@example.com','telefone_consultor':'5430225800'};
    final body=renderEmailTemplate(defaultEmailBody(ProjectEmailKind.finishes),fields,markMissing:true);
    expect(body,startsWith('Bom dia, Ana e Bruno.'));
    expect(body,contains('produto Promob Cliente'));
    expect(body,contains('Planilha Definições de Acabamentos.xlsx'));
    expect(body,contains('[PREENCHER: Prazo de retorno da planilha de acabamentos]'));
    expect(cleanRemovedEmailFields(body,ProjectEmailKind.finishes,consultantPhone:'5430225800'),contains('5430225800'));
    fields.remove('responsavel_tecnico');
    expect(renderEmailTemplate(defaultEmailBody(ProjectEmailKind.finishes),fields,markMissing:true),startsWith('Bom dia, Ana.'));
  });
  testWidgets('Loads names and short system name; deadline updates body and draft', (tester) async {
    tester.view.physicalSize=const Size(1440,1100);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final book=excel.Excel.createExcel();final sheet=book['Informações de entrada'];
    for(final c in {
      'B27':'Nome do sistema','C27':'Sistema completo','B28':'Nome resumido do sistema','C28':'Nome curto',
      'E16':'CLIENTE','E18':'Proprietário','F18':'Ana','G18':'ana@example.com','H18':'123456',
      'E19':'Responsável Técnico','F19':'Bruno','G19':'bruno@example.com',
      'E35':'CYNCLY','E36':'Consultor de Implantação','F36':'Rodrigo Zaparolli','G36':'rodrigo.zaparolli@cyncly.com',
      'E37':'Executivo de Vendas','F37':'Fulvio Luz Stumpf','G37':'fulvio@example.com','H37':'111111'
    }.entries) {sheet.cell(excel.CellIndex.indexByString(c.key)).value=excel.TextCellValue(c.value);}
    final store=MemoryEmailStore(); var reads=0;
    store.drafts['owner-a/123/finishes']={
      'contacts':[],
      'fields':{'consultor':'Fulvio Luz Stumpf','email_consultor':'fulvio@example.com','telefone_consultor':'111111'},
      'body':'Observação preservada.\n${defaultEmailBody(ProjectEmailKind.finishes).replaceAll('{consultor}', 'Fulvio Luz Stumpf').replaceAll('{email_consultor}', 'fulvio@example.com').replaceAll('{telefone_consultor}', '111111')}',
    };
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(project:ProjectModel.fromJson({'id':'123','client':'Cliente','serviceType':'Enterprise','excelLink':'linked'}),store:store,workbookLoader:() async {reads++;return Uint8List.fromList(book.encode()!);},
      attachmentPicker:()async=>[EmailAttachment('Definições de Acabamentos.xlsm',Uint8List.fromList([1,2,3]))] ))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip,'Planilha de Acabamentos'));await tester.pumpAndSettle();
    expect(reads,2);
    String body()=>tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
    expect(body(),contains('Ana e Bruno.'));expect(body(),contains('Promob Nome curto'));
    final recipients=tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
    expect(recipients.map((c)=>c.email).toSet(),{'ana@example.com','bruno@example.com'});
    expect(recipients.every((c)=>c.destination=='Para'),isTrue);
    final deadline=find.text('Definir prazo de retorno');await tester.ensureVisible(deadline);await tester.tap(deadline);await tester.pumpAndSettle();
    tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).onDateChanged(DateTime(2026,11,25));
    await tester.pump();await tester.tap(find.text('OK'));await tester.pumpAndSettle();
    expect(body(),contains('Definições de acabamentos até o dia 25/11/2026.'));
    expect(body(),contains('5430225800'));
    expect(body(),isNot(contains('54993879340')));
    expect(body(),contains('Rodrigo Zaparolli'));
    expect(body(),contains('Observação preservada.'));
    expect(body(),isNot(contains('Fulvio Luz Stumpf')));
    await tester.tap(find.text('Salvar neste projeto'));await tester.pumpAndSettle();
    expect(store.drafts['owner-a/123/finishes']!['fields']['prazo_acabamentos'],'25/11/2026');
    await tester.tap(find.text('Gerar e-mail para Outlook'));await tester.pumpAndSettle();
    expect(find.textContaining('Anexe a planilha de acabamentos (.xlsx ou .xlsm)'),findsWidgets);
    expect(find.byType(AlertDialog),findsOneWidget);
    await tester.tap(find.text('Corrigir dados'));await tester.pumpAndSettle();
    final attach=find.text('Selecionar Anexo');await tester.ensureVisible(attach);await tester.tap(attach);await tester.pumpAndSettle();
    expect(body(),contains('segue anexo Definições de Acabamentos.xlsm.'));
    expect(find.text('Definições de Acabamentos.xlsm'),findsOneWidget);
    await tester.tap(find.text('Gerar e-mail para Outlook'));await tester.pumpAndSettle();
    expect(find.text('Gerar rascunho para Outlook?'),findsOneWidget);
    expect(find.textContaining('1 anexos'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
