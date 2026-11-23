import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';

void main() {
  for (final technical in ['', 'Bruno']) {
    test('Professional external greeting and ER come from exact cells: technical=$technical', () {
      final rows=List.generate(38,(_)=>List.filled(8,''));
      rows[17][5]='Maria'; rows[17][6]='maria@example.com';
      rows[18][5]=technical;
      rows[23][2]='05/12/2026';
      rows[37][5]='Ana Relacionamento'; rows[37][6]='ana@example.com';
      final parsed=parseEmailWorkbookRows(rows,professionalInternal:true);
      expect(parsed.fields['responsavel_tecnico'],technical);
      expect(parsed.fields['er'],'Ana Relacionamento');
      expect(parsed.fields['email_er'],'ana@example.com');
      expect(parsed.contacts.map((c)=>c.email).toSet(),{'maria@example.com','ana@example.com'});
      expect(parsed.contacts.every((c)=>c.destination=='Não incluir'),true);
      final body=renderEmailTemplate(defaultEmailBody(ProjectEmailKind.finalization,professional:true),
          {...parsed.fields,'saudacao':'Boa tarde'},markMissing:true);
      expect(body,startsWith(technical.isEmpty?'Boa tarde Maria,':'Boa tarde Maria, Bruno,'));
      expect(body,contains('reunião realizada no dia 05/12/2026'));
      expect(body,contains('o seu nome é Ana Relacionamento'));
      expect(body,contains('e-mail ana@example.com'));
      expect(body,isNot(contains('[PREENCHER: Responsável técnico]')));
      expect(body,isNot(contains(', ,')));
    });
  }
  test('supplied descriptive template resolves square brackets and optional technical name', () {
    const source='{saudacao} {Proprietário F18}, {Responsável Técnico F19 só se tiver cadastrado na planilha},\n'
      '[Encerramento do Projeto C24] / [Exec. de Relacionamento F38] / [E-mail do ER G38]';
    final result=renderEmailTemplate(source,{'saudacao':'Bom dia','proprietario':'Maria',
      'data_finalizacao':'05/12/2026','er':'Ana','email_er':'ana@example.com'},markMissing:true);
    expect(result,'Bom dia Maria,\n05/12/2026 / Ana / ana@example.com');
  });
  test('missing ER stays highlighted while optional technical name is omitted', () {
    final body=renderEmailTemplate(defaultEmailBody(ProjectEmailKind.finalization,professional:true),
      {'saudacao':'Bom dia','proprietario':'Maria'},markMissing:true);
    expect(body,contains('[PREENCHER: Executivo de Relacionamento]'));
    expect(body,contains('[PREENCHER: E-mail do ER]'));
    expect(body,isNot(contains('responsavel_tecnico_opcional')));
  });
}
