import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  setUp(()=>LocalUserState.memory={});
  tearDown(()=>LocalUserState.memory=null);
  testWidgets('External email restores draft, verifies sheet, accepts typed recipients and two PDFs', (tester) async {
    tester.view.physicalSize=const Size(1440,1100);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final book=excel.Excel.createExcel();final sheet=book['Informações de entrada'];
    for(final c in {
      'B27':'Nome do sistema','C27':'Sistema do cliente','B28':'Nome resumido do sistema','C28':'Cliente',
      'E16':'CLIENTE','E17':'Proprietário','F17':'Cliente','G17':'planejanmoveis@gmail.com',
      'E35':'CYNCLY','E36':'Consultor de Implantação','F36':'Rodrigo Zaparolli','G36':'rodrigo.zaparolli@cyncly.com',
      'E45':'Líder do Projeto','F45':'Mila','G45':'mila.crespin@cyncly.com',
    }.entries) {sheet.cell(excel.CellIndex.indexByString(c.key)).value=excel.TextCellValue(c.value);}
    final bytes=Uint8List.fromList(book.encode()!);
    final store=MemoryEmailStore();
    store.drafts['owner-a/2262790/finalization']={
      'fields':{},'body':'Boa tarde!\nProjeto finalizado. Observação preservada.\n\nAtt,\nRodrigo Zaparolli\nConsultor de Implantação\nrodrigo.zaparolli@cyncly.com',
      'recipientSelectionManual':true,'contacts':[
        EmailContact(email:'planejanmoveis@gmail.com',destination:'Para').toJson(),
        EmailContact(email:'mila.crespin@cyncly.com',destination:'Cc').toJson(),
      ],
    };
    var reads=0;
    Widget modal()=>MaterialApp(home:Scaffold(body:ProjectEmailModal(project:ProjectModel.fromJson({'id':'2262790','client':'W. M. MOVEIS PLANEJADOS LTDA','serviceType':'Enterprise','excelLink':'linked-sheet'}),
      store:store,workbookLoader:()async {reads++;return bytes;},attachmentPicker:()async=>[
        EmailAttachment('Plano Projeto - Planejan-Manifesto.pdf',Uint8List.fromList([1,2])),
        EmailAttachment('Engenharia.pdf',Uint8List.fromList([3,4])),
      ])));
    Future<void> external() async {
      final chip=find.widgetWithText(ChoiceChip,'Encerramento Externo');
      await tester.ensureVisible(chip);await tester.tap(chip);await tester.pumpAndSettle();
    }
    List<EmailContact> contacts()=>tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
    await tester.pumpWidget(modal());await tester.pumpAndSettle();await external();
    expect(reads,2);
    final allowed=tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).allowedEmails!;
    expect(allowed,containsAll(['planejanmoveis@gmail.com','mila.crespin@cyncly.com','rodrigo.zaparolli@cyncly.com']));
    expect(contacts().singleWhere((c)=>c.email=='planejanmoveis@gmail.com').destination,'Para');
    expect(contacts().singleWhere((c)=>c.email=='mila.crespin@cyncly.com').destination,'Cc');
    for(final chip in tester.widgetList<InputChip>(find.byType(InputChip)).toList()){chip.onDeleted?.call();}
    await tester.pumpAndSettle();
    final to=find.byKey(const ValueKey('recipient-input-Para'));
    final cc=find.byKey(const ValueKey('recipient-input-Cc'));
    await tester.enterText(to,'fora-da-planilha@example.com');
    await tester.tap(find.text('Gerar e-mail para Outlook'));await tester.pumpAndSettle();
    expect(find.textContaining('Não encontrado na planilha: fora-da-planilha@example.com'),findsOneWidget);
    expect(find.text('Gerar rascunho para Outlook?'),findsNothing);
    await tester.tap(find.text('Corrigir dados'));await tester.pumpAndSettle();
    await tester.enterText(to,' PLANEJANMOVEIS@gmail.com ');await tester.enterText(cc,'mila.crespin@cyncly.com');
    final attach=find.text('Selecionar Anexo');await tester.ensureVisible(attach);await tester.tap(attach);await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar e-mail para Outlook'));await tester.pumpAndSettle();
    expect(find.text('Gerar rascunho para Outlook?'),findsOneWidget);
    expect(find.textContaining('2 anexos'),findsOneWidget);
    await tester.tap(find.text('Revisar'));await tester.pumpAndSettle();
    // An intentional change must survive saving/reopening; defaults must not undo it.
    final mila=contacts().singleWhere((c)=>c.email.toLowerCase()=='mila.crespin@cyncly.com');
    final chip=find.ancestor(of:find.textContaining('mila.crespin@cyncly.com'),matching:find.byType(InputChip));
    tester.widget<InputChip>(chip).onDeleted!();await tester.pumpAndSettle();
    await tester.enterText(to,'mila.crespin@cyncly.com');
    tester.widget<TextField>(to).onSubmitted!('mila.crespin@cyncly.com');await tester.pumpAndSettle();
    expect(mila.destination,'Para');
    await tester.tap(find.text('Salvar neste projeto'));await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
    await tester.pumpWidget(modal());await tester.pumpAndSettle();await external();
    expect(contacts().singleWhere((c)=>c.email.toLowerCase()=='mila.crespin@cyncly.com').destination,'Para');
    expect(contacts().singleWhere((c)=>c.email.toLowerCase()=='planejanmoveis@gmail.com').destination,'Para');
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
