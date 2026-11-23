import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';

List<List<String>> layout() {
  final rows=List.generate(50,(_)=>List.filled(8,''));
  void put(int r,int c,String value)=>rows[r-1][c-1]=value;
  for(final entry in {
    (16,5):'CLIENTE',(17,5):'Proprietário',(17,6):'Proprietário correto',(17,7):'dono@example.com',(17,8):'1111',
    (18,5):'Responsável Técnico',(18,6):'Técnico correto',(18,7):'tecnico@example.com',(18,8):'2222',
    (19,5):'Participante adicional 01',(19,6):'Participante',(19,7):'participante@example.com',
    (22,2):'Início do projeto pela Consultoria',(22,3):'01/11/2026',
    (23,2):'Encerramento do projeto',(23,3):'19/11/2026',
    (23,5):'Razão Social',(23,6):'Empresa correta LTDA',(24,5):'CNPJ',(24,6):'11.222.333/0001-44',
    (25,5):'Nome Fantasia',(25,6):'Nome fantasia correto',(26,5):'Telefone 01',(26,6):'3333',
    (26,2):'Nome do sistema',(26,3):'Sistema completo',(27,2):'Nome resumido do sistema',(27,3):'Nome curto',
    (35,5):'CYNCLY',(36,5):'Consultor de Implantação',(36,6):'Rodrigo Zaparolli',(36,7):'rodrigo.zaparolli@cyncly.com',
    (37,5):'Executivo de Vendas',(37,6):'Fulvio',(37,7):'vendas@example.com',
    (40,5):'Exec. de Relacionamento',(40,6):'ER correto',(40,7):'er@example.com',
  }.entries){put(entry.key.$1,entry.key.$2,entry.value);}
  return rows;
}

void main(){
  for(final enterprise in [false,true]) {
    test('Reads actual field labels across layout variants: enterprise=$enterprise',(){
      final f=parseEmailWorkbookRows(layout(),professionalInternal:!enterprise,enterpriseInternal:enterprise).fields;
      expect(f['sistema'],'Sistema completo');expect(f['nome_resumido_sistema'],'Nome curto');
      expect(f['data_recebimento'],'01/11/2026');expect(f['data_finalizacao'],'19/11/2026');
      expect(f['proprietario'],'Proprietário correto');expect(f['email_cliente'],'dono@example.com');expect(f['telefone_cliente'],'1111');
      expect(f['responsavel_tecnico'],'Técnico correto');expect(f['email_tecnico'],'tecnico@example.com');
      expect(f['razao_social'],'Empresa correta LTDA');expect(f['er'],'ER correto');expect(f['email_er'],'er@example.com');
      expect(f['consultor'],'Rodrigo Zaparolli');expect(f['email_consultor'],'rodrigo.zaparolli@cyncly.com');
      if(enterprise){expect(f['nome_fantasia'],'Nome fantasia correto');expect(f['cnpj'],'11.222.333/0001-44');}
    });
  }
  test('Missing owner email never borrows technical contact email',(){
    final rows=layout();rows[16][6]='';
    for(final enterprise in [false,true]) {
      final f=parseEmailWorkbookRows(rows,professionalInternal:!enterprise,enterpriseInternal:enterprise).fields;
      expect(f['email_cliente'],'');expect(f['email_tecnico'],'tecnico@example.com');
    }
  });
  test('Editing the summary in the body does not restore an old saved summary',(){
    const body='Texto preservado\nResumo da implantação:\nResumo novo digitado\n\nAtt,\nRodrigo';
    expect(emailBodyWithSummary(body,'Resumo antigo'),body);
    expect(emailBodyWithSummary(body,'Resumo antigo',previousSummary:'Resumo antigo'),body);
    expect(emailBodyWithSummary(body,'Resumo atualizado',previousSummary:'Resumo novo digitado'),contains('Resumo atualizado'));
    expect(emailBodyWithSummary(body,'Resumo atualizado',previousSummary:'Resumo novo digitado'),isNot(contains('Resumo novo digitado')));
  });
}
