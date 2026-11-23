import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_workbook.dart';

void main() {
  test('reads cached formulas and dates while ignoring unrelated sheets and empty string cells', () {
    final serial=DateTime.utc(2026,9,3).difference(DateTime.utc(1899,12,30)).inDays;
    final files={
      'xl/workbook.xml': '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Informações de entrada" sheetId="1" r:id="rId1"/><sheet name="Outra guia" sheetId="2" r:id="rId2"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>',
      'xl/styles.xml':'<styleSheet><numFmts><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts><cellXfs><xf numFmtId="0"/><xf numFmtId="164"/></cellXfs></styleSheet>',
      'xl/worksheets/sheet1.xml': '<worksheet><sheetData><row r="17"><c r="H18" t="str"><f>IF(A1,1,2)</f></c></row><row r="22"><c r="C23" s="1"><v>$serial</v></c></row><row r="26"><c r="C27" t="str"><f>CONCAT(A1,B1)</f><v>Promob Maker Cliente</v></c><c r="F26" t="inlineStr"><is><t>54 3333-1234</t></is></c></row></sheetData></worksheet>',
      'xl/worksheets/sheet2.xml':'unrelated content must not be parsed',
    };
    final archive=Archive();
    for(final file in files.entries) {
      final bytes=utf8.encode(file.value);
      archive.addFile(ArchiveFile(file.key,bytes.length,bytes));
    }
    final parsed=readEmailWorkbook(ZipEncoder().encode(archive)!,professionalInternal:true);
    expect(parsed.fields['sistema'],'Promob Maker Cliente');
    expect(parsed.fields['data_recebimento'],'03/09/2026');
    expect(parsed.fields['telefone_cliente'],'');
  });
}
