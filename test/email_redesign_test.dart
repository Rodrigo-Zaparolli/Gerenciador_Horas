import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';
import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  for (final destination in ['Para','Cc']) {
    testWidgets('selects all available emails for $destination in a single batch, including directory', (tester) async {
      final contacts=[EmailContact(name:'Ana',email:'ana@example.com'),
        EmailContact(name:'Outro destino',email:'other@example.com',destination:destination=='Para'?'Cc':'Para')];
      var notifications=0;
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:StatefulBuilder(builder:(context,refresh)=>
        EmailRecipientFields(contacts:contacts,companyContacts:[
          EmailContact(name:'Ana repetida',email:'ana@example.com'),EmailContact(name:'Bruno',email:'bruno@example.com')],
          onChanged:(){notifications++;refresh((){});})))));
      await tester.tap(find.byTooltip('Adicionar em $destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selecionar e-mails…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selecionar todos'));
      await tester.pumpAndSettle();
      expect(notifications,0);
      await tester.tap(find.text('Adicionar (2)'));
      await tester.pumpAndSettle();
      expect(notifications,1);
      expect(contacts.where((c)=>c.destination==destination).map((c)=>c.email).toSet(),
        {'ana@example.com','bruno@example.com'});
      expect(contacts.where((c)=>c.email=='other@example.com').single.destination,destination=='Para'?'Cc':'Para');
    });
  }
  testWidgets('three models, single load action and missing values highlighted directly in preview', (tester) async {
    tester.view.physicalSize=const Size(1440,1000); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final book=excel.Excel.createExcel();
    final sheet=book['Informações de entrada'];
    sheet.cell(excel.CellIndex.indexByString('C27')).value=excel.TextCellValue('Maker Cliente');
    var reads=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(
      project:ProjectModel.fromJson({'id':'123','client':'Cliente','serviceType':'Professional','excelLink':'book'}),
      store:MemoryEmailStore(),workbookLoader:()async{reads++;return Uint8List.fromList(book.encode()!);} ))));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip),findsNWidgets(4));
    for(final label in ['Contato Inicial','Encerramento Interno','Encerramento Externo']) {
      expect(find.widgetWithText(ChoiceChip,label),findsOneWidget);
    }
    expect(find.text('Dados e destinatários'),findsNothing);
    expect(find.text('Carregar dados no modelo'),findsNothing);
    expect(find.text('Atualizar da planilha do projeto'),findsNothing);
    final load=find.text('Carregar dados da planilha');
    await tester.ensureVisible(load);await tester.tap(load);await tester.pumpAndSettle();
    expect(reads,2);
    expect(find.text('Importar dados da planilha?'),findsNothing);
    final internal=find.widgetWithText(ChoiceChip,'Encerramento Interno');
    await tester.ensureVisible(internal);await tester.tap(internal);await tester.pumpAndSettle();
    final body=tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
    expect(body,contains('Maker Cliente'));
    expect(body,contains('[PREENCHER: Data de recebimento]'));
    expect(body,contains('[PREENCHER: Resumo da implantação]'));
    final editable=find.byKey(const ValueKey('email-inline-body-0'));
    final spans=tester.widget<TextField>(editable).controller!.buildTextSpan(context:tester.element(editable),withComposing:false);
    expect(spans.children!.whereType<TextSpan>().any((s)=>s.style?.backgroundColor==const Color(0xFFFFE4AA)),isTrue);
    final heading=find.text('Prévia do e-mail');final attach=find.text('Selecionar Anexo');
    await tester.ensureVisible(heading);await tester.pumpAndSettle();
    expect(tester.getCenter(attach).dx,greaterThan(tester.getCenter(heading).dx));
    expect(tester.getCenter(attach).dy,closeTo(tester.getCenter(heading).dy,12));
    expect(tester.takeException(),isNull);
  });
  test('missing markers preserve known values and unknown fields remain identifiable', () {
    expect(renderEmailTemplate('{cliente} / {data_finalizacao}',{'cliente':'Cliente'},markMissing:true),
      'Cliente / [PREENCHER: Data de finalização]');
  });
  testWidgets('loading a workbook asks before replacing manual text and allows preserving it on mobile', (tester) async {
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final store=MemoryEmailStore();
    store.drafts['owner-a/123/initial']={'body':'Texto escrito pelo usuário'};
    final book=excel.Excel.createExcel();
    book['Informações de entrada'].appendRow([excel.TextCellValue('Nome do sistema'),excel.TextCellValue('Sistema Excel')]);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(
      project:ProjectModel.fromJson({'id':'123','client':'Cliente','serviceType':'Enterprise'}),
      store:store,workbookLoader:()async=>Uint8List.fromList(book.encode()!)))));
    await tester.pumpAndSettle();
    final load=find.text('Carregar dados da planilha');
    await tester.ensureVisible(load);await tester.tap(load);
    await tester.pump();await tester.pump(const Duration(milliseconds:400));
    expect(find.text('Importar dados da planilha?'),findsOneWidget);
    final checkbox=find.byType(Checkbox);
    await tester.ensureVisible(checkbox);await tester.tap(checkbox);await tester.pump();
    await tester.tap(find.text('Importar'));await tester.pumpAndSettle();
    expect(find.text('Importar dados da planilha?'),findsNothing);
    expect(tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body,'Texto escrito pelo usuário');
    expect(tester.takeException(),isNull);
  });
}
