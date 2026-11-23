import 'dart:convert';
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
import 'products_image_field_test.dart' show png;

Uint8List completeWorkbook() {
  final book=excel.Excel.createExcel();final sheet=book['Informações de entrada'];
  for(final c in {
    'B23':'Início do projeto pela Consultoria','C23':'01/11/2026','B24':'Encerramento do projeto','C24':'19/11/2026',
    'B27':'Nome do sistema','C27':'Promob Cliente','B28':'Nome resumido do sistema','C28':'Cliente','C29':'1234',
    'C35':'senha-dimensoes','C36':'senha-orcamentos','C37':'senha-margens',
    'C39':'https://example.com/materiais','C40':'Sistema liberado',
    'E16':'CLIENTE','E17':'Proprietário','F17':'Ana','G17':'ana@example.com','H17':'1111',
    'E18':'Responsável Técnico','F18':'Bruno','G18':'bruno@example.com','H18':'2222',
    'E19':'Participante adicional 01','F19':'Participante Um','G19':'p1@example.com',
    'E20':'Participante adicional 02','F20':'Participante Dois','G20':'p2@example.com',
    'E23':'Razão Social','F23':'Cliente LTDA','E24':'CNPJ','F24':'11.222.333/0001-44',
    'E26':'Nome Fantasia','F26':'Cliente',
    'E35':'CYNCLY','E36':'Consultor de Implantação','F36':'Rodrigo Zaparolli','G36':'rodrigo.zaparolli@cyncly.com',
    'E37':'Executivo de Vendas','F37':'Executivo','G37':'executivo@example.com',
    'E38':'Exec. de Relacionamento','F38':'Executivo','G38':'executivo@example.com',
    'E41':'Gestor Regional','F41':'Regional','G41':'regional@example.com',
    'E42':'Coordenador Regional','F42':'Coord Regional','G42':'coordregional@example.com',
    'E43':'Gestor de Implantação','F43':'Gestor','G43':'gestor@example.com',
    'E44':'Coordenadora Implantação','F44':'Coordenadora','G44':'coordenadora@example.com',
    'E45':'Líder de Projetos','F45':'Líder','G45':'lider@example.com',
    'E46':'Gestora Serviços','F46':'Serviços','G46':'servicos@example.com',
    'E47':'Coordenador Suporte','F47':'Suporte','G47':'suporte@example.com',
    'E48':'Líder de Projetos (serviços)','F48':'Líder Serviços','G48':'liderservicos@example.com',
  }.entries){sheet.cell(excel.CellIndex.indexByString(c.key)).value=excel.TextCellValue(c.value);}
  return Uint8List.fromList(book.encode()!);
}

void main(){
  setUp(()=>LocalUserState.memory={});tearDown(()=>LocalUserState.memory=null);
  for(final enterprise in [false,true]) {
    for(final mode in [ProjectEmailKind.initial,ProjectEmailKind.internal,ProjectEmailKind.finalization,ProjectEmailKind.finishes]) {
      testWidgets('Complete generation ${mode.name}, enterprise=$enterprise', (tester) async {
        tester.view.physicalSize=const Size(1440,1100);tester.view.devicePixelRatio=1;
        addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
        final store=MemoryEmailStore();
        final kind=mode==ProjectEmailKind.internal && !enterprise ? ProjectEmailKind.professionalInternal : mode;
        // Only manually supplied project commentary, title, deadline and print;
        // names, dates, signature and recipients must come from the workbook.
        store.drafts['owner-a/123/${kind.name}']={'contacts':[],
          'fields':{'resumo':'Implantação concluída.','titulo_solicitacao':'Implantação Cliente','prazo_acabamentos':'25/11/2026'},
          'productsImage':base64Encode(png)};
        final bytes=completeWorkbook();
        await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(
          project:ProjectModel.fromJson({'id':'123','client':'Cliente LTDA','serviceType':enterprise?'Enterprise':'Professional','excelLink':'workbook'}),
          store:store,workbookLoader:()async=>bytes,
          attachmentPicker:()async=>[EmailAttachment(mode==ProjectEmailKind.finishes?'Definições de Acabamentos.xlsm':'Plano e Engenharia.pdf',Uint8List.fromList([1,2,3]))],
        ))));await tester.pumpAndSettle();
        if(mode!=ProjectEmailKind.initial){final chip=find.widgetWithText(ChoiceChip,mode.label);await tester.ensureVisible(chip);await tester.tap(chip);await tester.pumpAndSettle();}
        final recipients=tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
        final selected=recipients.where((c)=>['Para','Cc'].contains(c.destination)).toList();
        if(mode==ProjectEmailKind.initial) {
          expect(selected,isEmpty);
          await tester.enterText(find.byKey(const ValueKey('recipient-input-Para')),'ana@example.com');
        } else if(mode==ProjectEmailKind.internal) {
          expect(selected.map((c)=>c.email).toSet(),{'coordenadora@example.com','gestor@example.com','executivo@example.com','regional@example.com','coordregional@example.com','servicos@example.com','suporte@example.com','liderservicos@example.com'});
          expect(selected.every((c)=>c.destination=='Para'),isTrue);
        } else if(mode==ProjectEmailKind.finalization) {
          expect(selected.where((c)=>c.destination=='Para').map((c)=>c.email).toSet(),{'ana@example.com','bruno@example.com','p1@example.com','p2@example.com'});
          expect(selected.where((c)=>c.destination=='Cc').map((c)=>c.email).toSet(),{'executivo@example.com','lider@example.com'});
        } else {
          expect(selected.map((c)=>c.email).toSet(),{'ana@example.com','bruno@example.com'});
          expect(selected.every((c)=>c.destination=='Para'),isTrue);
        }
        final body=tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
        expect(body,isNot(contains('[PREENCHER:')));
        expect(body,contains('Rodrigo Zaparolli'));expect(body,isNot(contains('54993879340')));
        final attach=find.text('Selecionar Anexo');await tester.ensureVisible(attach);await tester.tap(attach);await tester.pumpAndSettle();
        await tester.tap(find.text('Gerar e-mail para Outlook'));await tester.pumpAndSettle();
        expect(find.text('Gerar rascunho para Outlook?'),findsOneWidget);
        expect(find.textContaining('1 anexos'),findsOneWidget);
        expect(tester.takeException(),isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
