import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  setUp(()=>LocalUserState.memory={});
  tearDown(()=>LocalUserState.memory=null);
  for(final mode in ['new','legacy','manual']) {
    testWidgets('recipients require explicit selection on load and import: $mode', (tester) async {
      tester.view.physicalSize=const Size(1440,1000);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final store=MemoryEmailStore();
      if(mode!='new') store.drafts['owner-a/123/initial']={
        'recipientsConfigured':true,'recipientSelectionManual':mode=='manual',
        'contacts':[{'name':'Ana','email':'ana@example.com','group':'Cyncly','destination':'Para'}]};
      final book=excel.Excel.createExcel();
      book['Informações de entrada'].appendRow([excel.TextCellValue('CYNCLY')]);
      book['Informações de entrada'].appendRow([
        excel.TextCellValue('Consultor de Implantação'),excel.TextCellValue('Ana'),excel.TextCellValue('ana@example.com')]);
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(
        project:ProjectModel.fromJson({'id':'123','client':'Cliente','serviceType':'Enterprise'}),
        store:store,workbookLoader:()async=>Uint8List.fromList(book.encode()!)))));
      await tester.pumpAndSettle();
      List<String> selected()=>tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields))
          .contacts.where((c)=>['Para','Cc'].contains(c.destination)).map((c)=>c.email).toList();
      expect(selected(),mode=='manual'?['ana@example.com']:isEmpty);
      final load=find.text('Carregar dados da planilha');
      await tester.ensureVisible(load);await tester.tap(load);await tester.pumpAndSettle();
      expect(selected(),mode=='manual'?['ana@example.com']:isEmpty);
      if(mode!='manual') {
        final add=find.byTooltip('Adicionar em Para');
        await tester.ensureVisible(add);await tester.tap(add);await tester.pumpAndSettle();
        await tester.tap(find.text('Adicionar todos'));await tester.pumpAndSettle();
        expect(selected(),['ana@example.com']);
      }
      await tester.tap(find.text('Salvar neste projeto'));await tester.pumpAndSettle();
      expect(store.drafts['owner-a/123/initial']!['recipientSelectionManual'],true);
      expect(tester.takeException(),isNull);
    });
  }
}
