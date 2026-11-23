import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Read only the entry sheet and saved formula results. No macros are executed.
List<List<String>> readEmailEntryRows(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  if (archive.files.fold<int>(0, (sum, f) => sum + f.size) > 128 * 1024 * 1024) {
    throw const FormatException('A planilha descompactada excede o limite de leitura.');
  }
  XmlDocument? document(String name) {
    final file = archive.findFile(name);
    return file == null ? null : XmlDocument.parse(utf8.decode(file.content as List<int>));
  }
  final workbook = document('xl/workbook.xml');
  final relationships = document('xl/_rels/workbook.xml.rels');
  if (workbook == null || relationships == null) throw const FormatException('Arquivo Excel inválido.');
  final sheets = workbook.findAllElements('sheet').where((s) =>
      s.getAttribute('name')?.toLowerCase().replaceAll('ç', 'c').replaceAll('õ', 'o')
          .replaceAll(RegExp(r'[^a-z]'), '') == 'informacoesdeentrada').toList();
  if (sheets.length != 1) throw const FormatException('Não foi encontrada uma única aba Informações de entrada.');
  final id = sheets.single.attributes.where((a) => a.name.local == 'id').first.value;
  final links = relationships.findAllElements('Relationship').where((r) => r.getAttribute('Id') == id).toList();
  if (links.length != 1 || links.single.getAttribute('TargetMode') == 'External') {
    throw const FormatException('Referência inválida da aba Informações de entrada.');
  }
  final target = Uri(path: 'xl/workbook.xml').resolve(links.single.getAttribute('Target') ?? '').path.replaceFirst(RegExp(r'^/'), '');
  final sheet = document(target);
  if (sheet == null) throw const FormatException('Não foi possível ler a aba Informações de entrada.');
  final shared = document('xl/sharedStrings.xml')?.findAllElements('si')
      .map((s) => s.findAllElements('t').map((t) => t.innerText).join()).toList() ?? <String>[];
  final styles = document('xl/styles.xml');
  final formats = {for (final f in styles?.findAllElements('numFmt') ?? <XmlElement>[])
    int.tryParse(f.getAttribute('numFmtId') ?? ''): f.getAttribute('formatCode') ?? ''};
  final cellStyles = styles?.findAllElements('cellXfs').firstOrNull?.findElements('xf').toList() ?? <XmlElement>[];
  bool dateStyle(int index) {
    if (index < 0 || index >= cellStyles.length) return false;
    final id = int.tryParse(cellStyles[index].getAttribute('numFmtId') ?? '') ?? 0;
    if (id >= 14 && id <= 22) return true;
    final format = (formats[id] ?? '').toLowerCase()
        .replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]|\\.'), '');
    return format.contains('d') && (format.contains('m') || format.contains('y'));
  }
  final date1904 = workbook.findAllElements('workbookPr').firstOrNull?.getAttribute('date1904');
  final rows = <List<String>>[];
  for (final cell in sheet.findAllElements('c')) {
    final reference = RegExp(r'^([A-Z]+)([0-9]+)$').firstMatch(cell.getAttribute('r') ?? '');
    if (reference == null) continue;
    final row = int.parse(reference[2]!) - 1;
    var column = 0;
    for (final code in reference[1]!.codeUnits) { column = column * 26 + code - 64; }
    if (row < 0 || row >= 1000 || column < 1 || column > 64) continue;
    while (rows.length <= row) { rows.add([]); }
    while (rows[row].length < column) { rows[row].add(''); }
    final type = cell.getAttribute('t');
    var value = cell.findElements('v').firstOrNull?.innerText ?? '';
    if (type == 'inlineStr') {
      value = cell.findAllElements('t').map((t) => t.innerText).join();
    } else if (type == 's') {
      final index = int.tryParse(value);
      value = index != null && index >= 0 && index < shared.length ? shared[index] : '';
    } else if (type == 'e') {
      value = '';
    } else if ((type == null || type == 'n') && dateStyle(int.tryParse(cell.getAttribute('s') ?? '') ?? 0)) {
      final serial = double.tryParse(value);
      if (serial != null && serial.isFinite && serial >= 0 && serial < 1000000) {
        final base = date1904 == '1' || date1904 == 'true' ? DateTime.utc(1904, 1, 1)
            : serial < 60 ? DateTime.utc(1899, 12, 31) : DateTime.utc(1899, 12, 30);
        final date = base.add(Duration(days: serial.floor()));
        value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }
    } else if (type == 'd') {
      final date = DateTime.tryParse(value);
      if (date != null) value = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
    rows[row][column - 1] = value;
  }
  return rows;
}
