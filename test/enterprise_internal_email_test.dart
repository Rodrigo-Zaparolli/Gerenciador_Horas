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

const cells = {
  'C27':'Enterprise Cliente','C23':'03/09/2026','C24':'05/12/2026',
  'C39':'https://example.com/materiais','C40':'Liberado no Portal',
  'C29':'12345','C35':'dim-test','C36':'orc-test','C37':'mar-test',
  'F24':'11.222.333/0001-44','F23':'Cliente Ltda','F26':'Cliente Fantasia',
  'F18':'Maria','G18':'maria@example.com','H18':'54 3333-1234',
  'F19':'Bruno','G19':'bruno@example.com',
  'F37':'Consultor Teste','G37':'consultor@example.com',
  'F38':'Vendas Teste','F39':'Relacionamento Teste','G39':'er@example.com',
  'F41':'Regional','F42':'Coordenador Regional','F43':'Gestor Implantação',
  'F44':'Coordenadora Implantação','F45':'Líder Projetos','F46':'Gestora Serviços',
  'F47':'Suporte','F48':'Líder Serviços',
};

List<List<String>> rows() {
  final result=List.generate(48,(_)=>List.filled(8,''));
  for(final entry in cells.entries) {
    final index=excel.CellIndex.indexByString(entry.key);
    result[index.rowIndex][index.columnIndex]=entry.value;
  }
  return result;
}

void main() {
  setUp(()=>LocalUserState.memory={});tearDown(()=>LocalUserState.memory=null);
  test('Enterprise uses its own cells for company, passwords, team and consultant signature', () {
    final parsed=parseEmailWorkbookRows(rows(),enterpriseInternal:true);
    final f=parsed.fields;
    expect(f['razao_social'],'Cliente Ltda');expect(f['cnpj'],'11.222.333/0001-44');
    expect(f['er'],'Relacionamento Teste');expect(f['executivo_vendas'],'Vendas Teste');
    expect(f['consultor'],'Consultor Teste');expect(f['email_consultor'],'consultor@example.com');
    expect(f['senha_dimensoes'],'dim-test');expect(f['senha_orcamentos'],'orc-test');expect(f['senha_margens'],'mar-test');
    expect(f['materiais'],'https://example.com/materiais');expect(f['liberacao'],'Liberado no Portal');
    expect(f['email_tecnico'],'bruno@example.com');expect(f['lider_projetos_servicos'],'Líder Serviços');
    final body=renderEmailTemplate(defaultEmailBody(ProjectEmailKind.internal,enterprise:true),
      {...f,'saudacao':'Boa tarde','solicitacao':'123'},markMissing:true);
    for(final entry in cells.entries.where((entry)=>entry.key!='G39')) {
      expect(body,contains(entry.value));
    }
    expect(parsed.contacts.any((c)=>c.email=='er@example.com'),true);
    expect(body,startsWith('Boa tarde a todos!'));
    expect(body,contains('[PREENCHER: Produtos adquiridos]'));
    expect(body,contains('[PREENCHER: Título completo da solicitação no E-Desk]'));
    expect(body,contains('[PREENCHER: Resumo da implantação]'));
    expect(parsed.contacts.every((c)=>c.destination=='Não incluir'),true);
  });
  test('missing team members remain visible and models cannot be combined', () {
    final parsed=parseEmailWorkbookRows(List.generate(48,(_)=>List.filled(8,'')),enterpriseInternal:true);
    final body=renderEmailTemplate(defaultEmailBody(ProjectEmailKind.internal,enterprise:true),parsed.fields,markMissing:true);
    expect(body,contains('Coordenador Suporte: [PREENCHER: Coordenador Suporte]'));
    expect(body,contains('Gestora Serviços: [PREENCHER: Gestora Serviços]'));
    expect(()=>parseEmailWorkbookRows(rows(),professionalInternal:true,enterpriseInternal:true),throwsFormatException);
  });
  testWidgets('Enterprise internal loads its model and saved cells directly into preview', (tester) async {
    tester.view.physicalSize=const Size(1440,1000);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final book=excel.Excel.createExcel();
    for(final entry in cells.entries) {
      book['Informações de entrada'].cell(excel.CellIndex.indexByString(entry.key)).value=excel.TextCellValue(entry.value);
    }
    final store=MemoryEmailStore();
    store.templates['owner-a/internal']={'body':defaultEmailBody(ProjectEmailKind.internal)};
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ProjectEmailModal(
      project:ProjectModel.fromJson({'id':'123','client':'Cliente','serviceType':'Promob Enterprise'}),
      store:store,workbookLoader:()async=>Uint8List.fromList(book.encode()!)))));
    await tester.pumpAndSettle();
    final internal=find.widgetWithText(ChoiceChip,'Encerramento Interno');
    await tester.ensureVisible(internal);await tester.tap(internal);await tester.pumpAndSettle();
    final load=find.text('Carregar dados da planilha');
    await tester.ensureVisible(load);await tester.tap(load);await tester.pumpAndSettle();
    final body=tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
    expect(body,contains('Razão Social: Cliente Ltda'));
    expect(body,contains('CNPJ: 11.222.333/0001-44'));
    expect(body,contains('Executivo de Vendas: Vendas Teste'));
    expect(body,contains('Exec. de Relacionamento: Relacionamento Teste'));
    final selected = tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
    final expected = parseEmailWorkbookRows(rows(), enterpriseInternal:true).internalRecipients;
    expect(selected, isNotEmpty);
    expect(selected.map((c)=>c.email).toSet(), expected.map((c)=>c.email).toSet());
    expect(selected.every((c)=>c.destination=='Para'),true);
    expect(tester.takeException(),isNull);
  });
}
