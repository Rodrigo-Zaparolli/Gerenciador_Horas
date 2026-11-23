import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

Map<String, Map<String, dynamic>> shiftPlanEdits(
    Map<String, Map<String, dynamic>> pending, int at, int count) {
  final shifted = <String, Map<String, dynamic>>{};
  for (final entry in pending.entries) {
    final item = Map<String, dynamic>.from(entry.value);
    final match = RegExp(r'^([A-L])([1-9][0-9]*)$').firstMatch('${item['cell']}');
    if (item['operation'] == null && match != null && int.parse(match[2]!) >= at) {
      item['cell'] = '${match[1]}${int.parse(match[2]!) + count}';
      shifted['${item['sheet']}!${item['cell']}'] = item;
    } else { shifted[entry.key] = item; }
  }
  return shifted;
}

/// Excel renders the background. Validated text fields receive editing targets;
/// structural changes, formula preservation, saving and printing remain native.
class PlanSheetEditor extends StatefulWidget {
  const PlanSheetEditor(
      {super.key,
      required this.data,
      required this.pending,
      required this.enabled,
      required this.onChanged,
      this.onInsertRows,
      this.onRemoveGuidance});
  final Map<String, dynamic> data;
  final Map<String, Map<String, dynamic>> pending;
  final bool enabled;
  final void Function(Map<String, dynamic>, String) onChanged;
  final Future<void> Function(int row, int count, bool below)? onInsertRows;
  final Future<void> Function(List<String> names)? onRemoveGuidance;
  @override
  State<PlanSheetEditor> createState() => _PlanSheetEditorState();
}

class _PlanSheetEditorState extends State<PlanSheetEditor> {
  final horizontal = ScrollController();
  final vertical = ScrollController();
  String? selected;
  int? selectedRow;
  bool restoreBrowserMenu = false;
  @override
  void initState() {
    super.initState();
    if (kIsWeb && BrowserContextMenu.enabled) {
      restoreBrowserMenu = true;
      BrowserContextMenu.disableContextMenu();
    }
  }
  Future<void> rowMenu(Offset position, Map row) async {
    if (!widget.enabled || widget.data['planRowsVersion'] != 1 || widget.onInsertRows == null) return;
    final number = row['row'] as int;
    setState(() => selectedRow = number);
    FocusScope.of(context).unfocus();
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<bool>(context:context,
      position: RelativeRect.fromRect(Rect.fromLTWH(position.dx,position.dy,0,0),Offset.zero & overlay.size),
      items:[PopupMenuItem(enabled:false,child:Text('Linha $number')),
        const PopupMenuItem(value:false,child:Text('Inserir linha acima')),
        const PopupMenuItem(value:true,child:Text('Inserir linha abaixo'))]);
    if (choice != null && mounted && widget.enabled) await widget.onInsertRows!(number,1,choice);
  }
  double? zoom;
  String? imageSource;
  Uint8List? imageBytes;
  Future<void> insertRows() async {
    final row = selectedRow ?? int.tryParse(selected?.replaceAll(RegExp(r'[^0-9]'), '') ?? '');
    if (row == null || widget.onInsertRows == null) return;
    var quantity = '1';
    var below = true;
    String? error;
    final choice = await showDialog<(int, bool)>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: const Text('Inserir linhas'),
        content: SizedBox(width: 340, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<bool>(initialValue: below, decoration: InputDecoration(labelText: 'Posição na linha $row'),
            items: const [DropdownMenuItem(value: false, child: Text('Acima')), DropdownMenuItem(value: true, child: Text('Abaixo'))],
            onChanged: (value) => below = value ?? true),
          const SizedBox(height: 12),
          TextFormField(initialValue: quantity, onChanged: (value) => quantity = value, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Quantidade de linhas', helperText: 'De 1 a 20', errorText: error)),
          const SizedBox(height: 12),
          const Text('A inclusão será exibida na prévia. Use Salvar na planilha para gravar.'),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            final count = int.tryParse(quantity);
            if (count == null || count < 1 || count > 20) { refresh(() => error = 'Informe de 1 a 20 linhas.'); return; }
            Navigator.pop(context, (count, below));
          }, child: const Text('Inserir na prévia'))],
      )));
    if (choice != null && mounted && widget.enabled) await widget.onInsertRows!(row, choice.$1, choice.$2);
  }
  @override
  void dispose() {
    if (restoreBrowserMenu) BrowserContextMenu.enableContextMenu();
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  Color excelColor(dynamic value, Color fallback) {
    if (value is! num || value < 0) return fallback;
    final n = value.toInt();
    return Color.fromARGB(255, n & 255, (n >> 8) & 255, (n >> 16) & 255);
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.data['mirror'];
    if (raw is! Map || raw['imageBase64'] is! String) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Atualize a integração local e recarregue para editar na disposição original do Excel. A visualização do PDF continua disponível.')));
    }
    final mirror = Map<String, dynamic>.from(raw);
    final width = (mirror['width'] as num).toDouble();
    final height = (mirror['height'] as num).toDouble();
    final source = mirror['imageBase64'] as String;
    if (imageSource != source) {
      selected = null;
      selectedRow = null;
      imageSource = source;
      imageBytes = base64Decode(source);
    }
    final image = imageBytes!;
    final fields = {
      for (final f in (widget.data['fields'] as List).cast<Map>())
        if (f['readOnly'] != true)
          f['cell'] as String: Map<String, dynamic>.from(f)
    };
    final cells = (mirror['cells'] as List).cast<Map>();
    final rowGeometry = (mirror['rows'] as List?)?.cast<Map>() ?? [
      for (final cell in cells) {'row':int.parse('${cell['cell']}'.replaceAll(RegExp(r'[^0-9]'),'')), 'top':cell['top'], 'height':cell['height']}
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final fit =
          math.min(1.0, math.max(.2, (constraints.maxWidth - 36) / width));
      final scale = zoom ?? fit;
    Map? rowAt(double y) {
      for (final row in rowGeometry) {
        if (y >= (row['top'] as num)*height*scale && y < ((row['top'] as num)+(row['height'] as num))*height*scale) return row;
      }
      return null;
    }

      return Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Clique para editar. Botão direito na linha para inserir acima ou abaixo.'),
                  if ((mirror['adjustmentNotes'] as List? ?? []).isNotEmpty)
                    PopupMenuButton<List<String>>(
                      tooltip: widget.data['planGuidanceVersion'] == 1 ? 'Retirar as setas de orientação do plano' : 'Atualize a integração local para remover as orientações',
                      enabled: widget.enabled && widget.data['planGuidanceVersion'] == 1 && widget.onRemoveGuidance != null,
                      onSelected: (names) => widget.onRemoveGuidance!(names),
                      itemBuilder: (_) => [
                        for (final note in (mirror['adjustmentNotes'] as List).cast<Map>())
                          PopupMenuItem(value: ['${note['name']}'], child: Text('${note['text']}', maxLines: 3, overflow: TextOverflow.ellipsis)),
                        PopupMenuItem(value: [for (final note in (mirror['adjustmentNotes'] as List).cast<Map>()) '${note['name']}'], child: const Text('Remover todas as orientações')),
                      ],
                      child: const Padding(padding:EdgeInsets.all(8),child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.remove_circle_outline,size:18),SizedBox(width:6),Text('Remover setas')]))),
                  if ((mirror['adjustmentNotes'] as List? ?? []).isNotEmpty)
                    Tooltip(
                      message: 'As setas de orientação ficam ao lado do documento, como no Excel. A impressão mantém a área configurada na planilha.',
                      child: Text('${(mirror['adjustmentNotes'] as List).length} ${(mirror['adjustmentNotes'] as List).length == 1 ? 'indicação' : 'indicações'} de ajuste', style: Theme.of(context).textTheme.bodySmall)),
                  if (selectedRow != null) Text('Linha $selectedRow'),
                  Tooltip(
                    message: widget.data['planRowsVersion'] != 1 ? 'Atualize a integração para inserir linhas no plano' : selectedRow == null && selected == null ? 'Selecione uma linha no plano' : 'Inserir acima ou abaixo da linha destacada',
                    child: OutlinedButton.icon(
                      onPressed: widget.enabled && widget.data['planRowsVersion'] == 1 && widget.onInsertRows != null && (selectedRow != null || selected != null) ? insertRows : null,
                      icon: const Icon(Icons.table_rows_outlined, size: 18), label: const Text('Inserir linhas'))),
                  IconButton(
                      tooltip: 'Diminuir zoom',
                      onPressed: () =>
                          setState(() => zoom = math.max(.2, scale - .1)),
                      icon: const Icon(Icons.remove)),
                  Text('${(scale * 100).round()}%'),
                  IconButton(
                      tooltip: 'Aumentar zoom',
                      onPressed: () =>
                          setState(() => zoom = math.min(2, scale + .1)),
                      icon: const Icon(Icons.add)),
                  TextButton(
                      onPressed: () => setState(() => zoom = null),
                      child: const Text('Ajustar à largura')),
                ])),
        Expanded(
            child: Scrollbar(
                controller: horizontal,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                    controller: horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                        width:
                            math.max(constraints.maxWidth, width * scale + 32),
                        child: Scrollbar(
                            controller: vertical,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                                controller: vertical,
                                child: Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: SizedBox(
                                            width: width * scale,
                                            height: height * scale,
                                            child: Listener(
                                              onPointerDown: (event) {
                                                final row = rowAt(event.localPosition.dy);
                                                if (row == null) return;
                                                if (event.buttons == kSecondaryMouseButton) { rowMenu(event.position,row); }
                                                else if (widget.enabled) { setState(()=>selectedRow=row['row'] as int); }
                                              },
                                              child: Stack(children: [
                                              Positioned.fill(
                                                  child: Image.memory(image,
                                                      fit: BoxFit.fill,
                                                      gaplessPlayback: true)),
                                              for (final row in rowGeometry)
                                                if (row['row'] == selectedRow) Positioned(left:0,right:0,top:(row['top'] as num)*height*scale,height:(row['height'] as num)*height*scale,
                                                  child:IgnorePointer(child:Container(key:ValueKey('selected-plan-row-$selectedRow'),decoration:BoxDecoration(color:Colors.cyan.withValues(alpha:.12),border:Border.all(color:Colors.cyan,width:1.5))))),
                                              for (final cell in cells)
                                                if (fields[cell['cell']] !=
                                                    null)
                                                  Positioned(
                                                      left: (cell['left']
                                                              as num) *
                                                          width *
                                                          scale,
                                                      top:
                                                          (cell['top'] as num) *
                                                              height *
                                                              scale,
                                                      width: (cell['width']
                                                              as num) *
                                                          width *
                                                          scale,
                                                      height: (cell['height']
                                                              as num) *
                                                          height *
                                                          scale,
                                                      child: Builder(
                                                          builder: (context) {
                                                        final field = fields[
                                                            cell['cell']]!;
                                                        final key =
                                                            '${field['sheet']}!${field['cell']}';
                                                        final change =
                                                            widget.pending[key];
                                                        final value = (change?[
                                                                    'value'] ??
                                                                field[
                                                                    'value'] ??
                                                                '')
                                                            .toString();
                                                        final fontSize =
                                                            (cell['fontSize']
                                                                            as num? ??
                                                                        11)
                                                                    .toDouble() *
                                                                scale *
                                                                1.3333;
                                                        final style = TextStyle(
                                                            fontSize: fontSize,
                                                            height: 1.1,
                                                            color: excelColor(
                                                                cell[
                                                                    'fontColor'],
                                                                Colors.black),
                                                            fontFamily:
                                                                cell['fontName']
                                                                    as String?,
                                                            fontWeight:
                                                                cell['bold'] ==
                                                                        true
                                                                    ? FontWeight
                                                                        .bold
                                                                    : FontWeight
                                                                        .normal,
                                                            fontStyle:
                                                                cell['italic'] ==
                                                                        true
                                                                    ? FontStyle
                                                                        .italic
                                                                    : FontStyle
                                                                        .normal);
                                                        final alignment = cell[
                                                                    'alignment'] ==
                                                                -4108
                                                            ? TextAlign.center
                                                            : cell['alignment'] ==
                                                                    -4152
                                                                ? TextAlign
                                                                    .right
                                                                : TextAlign
                                                                    .left;
                                                        if (selected ==
                                                                cell['cell'] &&
                                                            widget.enabled) {
                                                          return TextFormField(
                                                              key: ValueKey(
                                                                  '${widget.data['revision']}-$key'),
                                                              initialValue:
                                                                  value,
                                                              contextMenuBuilder: (_, __) => const SizedBox.shrink(),
                                                              autofocus: true,
                                                              maxLines: null,
                                                              expands: true,
                                                              textAlign:
                                                                  alignment,
                                                              textAlignVertical:
                                                                  TextAlignVertical
                                                                      .top,
                                                              style: style,
                                                              decoration: InputDecoration(
                                                                  isDense: true,
                                                                  contentPadding:
                                                                      const EdgeInsets
                                                                          .all(
                                                                          2),
                                                                  filled: true,
                                                                  fillColor: excelColor(
                                                                      cell[
                                                                          'fillColor'],
                                                                      Colors
                                                                          .white),
                                                                  border: const OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius
                                                                              .zero)),
                                                              onChanged: (value) =>
                                                                  widget.onChanged(
                                                                      field,
                                                                      value));
                                                        }
                                                        return Semantics(
                                                            label:
                                                                'Editar célula ${field['cell']}: $value',
                                                            button: true,
                                                            child: GestureDetector(
                                                                behavior:
                                                                    HitTestBehavior
                                                                        .opaque,
                                                                onTap: widget
                                                                        .enabled
                                                                    ? () => setState(() =>
                                                                        selected =
                                                                            cell['cell']
                                                                                as String)
                                                                    : null,
                                                                child: change ==
                                                                        null
                                                                    ? const SizedBox
                                                                        .expand()
                                                                    : Container(
                                                                        color: excelColor(
                                                                            cell['fillColor'],
                                                                            Colors.white),
                                                                        padding: const EdgeInsets.all(2),
                                                                        child: Text(value, style: style, textAlign: alignment))));
                                                      })),
                                            ]))))))))))),
      ]);
    });
  }
}
