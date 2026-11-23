import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'spreadsheet_phase_dates.dart';

DateTime? checklistDate(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final date = DateTime.tryParse(value);
  return date != null && phaseDay(date) == value ? date : null;
}

/// Only unique named stages with a complete, valid saved period can be applied.
Map<int, List<DateTime>> checklistPeriods(Map<String, dynamic> data, List<String> names) {
  final preview = data['statusPreview'];
  final rows = preview is Map ? preview['rows'] : null;
  if (rows is! List) throw StateError('As datas do Status Projeto não foram consultadas.');
  final result = <int, List<DateTime>>{};
  for (var i = 0; i < names.length; i++) {
    final key = spreadsheetStageKey(names[i]);
    if (key.isEmpty || names.where((n) => spreadsheetStageKey(n) == key).length != 1) continue;
    final matches = rows.whereType<Map>().where((r) => spreadsheetStageKey('${r['label'] ?? ''}') == key).toList();
    if (matches.length != 1) continue;
    final start = checklistDate(matches.single['start']);
    final end = checklistDate(matches.single['end']);
    if (start != null && end != null && !end.isBefore(start)) result[i] = [start, end];
  }
  return result;
}

class ChecklistDatesButton extends StatefulWidget {
  const ChecklistDatesButton({super.key, required this.enabled, required this.sourceToken,
    required this.stages, required this.load, required this.apply});
  final bool enabled;
  final String Function() sourceToken;
  final List<String> Function() stages;
  final Future<Map<String, dynamic>> Function() load;
  final void Function(Map<int, List<DateTime>>) apply;
  @override
  State<ChecklistDatesButton> createState() => _ChecklistDatesButtonState();
}

class _ChecklistDatesButtonState extends State<ChecklistDatesButton> {
  bool busy = false;
  String fingerprint() => jsonEncode([widget.sourceToken(), widget.stages()]);
  Future<void> run() async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (busy || !widget.enabled || owner == null) return;
    final before = fingerprint();
    final names = widget.stages();
    bool current() => mounted && widget.enabled && FirebaseAuth.instance.currentUser?.uid == owner && before == fingerprint();
    setState(() => busy = true);
    try {
      final data = await widget.load();
      if (!current()) return;
      final periods = checklistPeriods(data, names);
      final selected = periods.keys.toSet();
      final confirmed = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Atualizar datas pelo checklist'),
          content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Confira Início e Fim da planilha salva. Após aplicar, use Salvar alterações no trabalho. Esta ação não envia fases ao E-Desk.'),
            for (var i = 0; i < names.length; i++) CheckboxListTile(
              title: Text(names[i]),
              subtitle: Text(periods.containsKey(i) ? '${phaseDay(periods[i]![0])} → ${phaseDay(periods[i]![1])}' : 'Sem período válido e único no Status Projeto; datas atuais preservadas.'),
              value: selected.contains(i),
              onChanged: periods.containsKey(i) ? (value) => refresh(() { if (value == true) { selected.add(i); } else { selected.remove(i); } }) : null,
            ),
          ]))),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true), child: const Text('Aplicar datas'))],
        )));
      if (confirmed == true && current()) widget.apply({for (final i in selected) i: periods[i]!});
    } catch (error) {
      if (current()) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível carregar as datas: $error')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Carregar Início e Fim das etapas a partir do checklist',
    child: OutlinedButton.icon(
    onPressed: busy || !widget.enabled ? null : run,
    icon: const Icon(Icons.date_range_outlined, size: 18),
    label: Text(busy ? 'Lendo...' : 'Datas do checklist')));
}
