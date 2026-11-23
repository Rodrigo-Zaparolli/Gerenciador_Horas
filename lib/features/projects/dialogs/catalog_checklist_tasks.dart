import 'package:flutter/material.dart';
import 'checklist_stage_dialog.dart';

typedef CatalogChecklistRequest = Future<Map<String, dynamic>> Function(
    String action,
    {String? revision,
    List<Map<String, dynamic>>? changes});

class CatalogChecklistTasks extends StatefulWidget {
  const CatalogChecklistTasks(
      {super.key,
      required this.call,
      required this.allowed,
      required this.sourceIdentity,
      required this.sheet,
      required this.search,
      required this.filter,
      this.onSaved});
  final CatalogChecklistRequest call;
  final bool Function() allowed;
  final String sourceIdentity, sheet, search, filter;
  final VoidCallback? onSaved;
  @override
  State<CatalogChecklistTasks> createState() => _CatalogChecklistTasksState();
}

class _CatalogChecklistTasksState extends State<CatalogChecklistTasks> {
  Map<String, dynamic>? data;
  bool busy = false;
  String? error;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant CatalogChecklistTasks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceIdentity != widget.sourceIdentity) load();
  }

  bool valid(Map<String, dynamic> result) =>
      result['catalogChecklistVersion'] == 1 &&
      result['checklistSheet'] == widget.sheet &&
      result['revision'] is String &&
      result['tasks'] is List;
  Future<void> load() async {
    final current = ++epoch;
    setState(() {
      busy = true;
      error = null;
      data = null;
    });
    try {
      final result = await widget.call('excel-editor-read');
      if (!mounted || current != epoch) return;
      if (!valid(result))
        throw StateError(
            'Atualize a integração local para carregar o checklist do Catalog.');
      setState(() {
        data = result;
        busy = false;
      });
    } catch (e) {
      if (!mounted || current != epoch) return;
      setState(() {
        busy = false;
        error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> get tasks => (data?['tasks'] as List? ?? [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  bool shown(Map<String, dynamic> task) =>
      '${task['label']} ${task['group']}'
          .toLowerCase()
          .contains(widget.search.toLowerCase()) &&
      (widget.filter == 'Todas' ||
          widget.filter == 'Pendentes' && task['value'] != 1 ||
          widget.filter == 'Concluídas' && task['value'] == 1);
  Future<void> edit(String group, List<Map<String, dynamic>> members) async {
    if (busy || !widget.allowed()) return;
    final originalEpoch = epoch, revision = data!['revision'] as String;
    final values = await showDialog<Map<String, double>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ChecklistStageDialog(
              stage: group,
              tasks: members,
              expandableBlocks: true,
              footerNote:
                  'Ao aplicar, você poderá confirmar o salvamento na planilha vinculada ao Catalog.',
              values: {
                for (final task in members)
                  ChecklistStageDialog.fieldKey(task):
                      (task['value'] as num).toDouble()
              },
              canApply: () =>
                  mounted &&
                  originalEpoch == epoch &&
                  widget.allowed() &&
                  !busy,
            ));
    if (values == null ||
        !mounted ||
        !widget.allowed() ||
        originalEpoch != epoch) return;
    final changes = <Map<String, dynamic>>[
      for (final task in members)
        if (task['readOnly'] != true &&
            values[ChecklistStageDialog.fieldKey(task)] != null &&
            values[ChecklistStageDialog.fieldKey(task)] != task['value'])
          {
            'sheet': task['sheet'],
            'cell': task['cell'],
            'before': task['value'],
            'value': values[ChecklistStageDialog.fieldKey(task)]
          },
    ];
    if (changes.isEmpty) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Salvar checklist do Catalog?'),
              content: Text(
                  '${changes.length} ajuste(s) serão salvos exclusivamente na planilha vinculada ao treinamento.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Salvar na planilha'))
              ],
            ));
    if (confirmed != true ||
        !mounted ||
        !widget.allowed() ||
        originalEpoch != epoch) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await widget.call('excel-editor-write',
          revision: revision, changes: changes);
      if (!mounted || !widget.allowed() || originalEpoch != epoch) return;
      if (saved['saved'] != true || !valid(saved))
        throw StateError(
            'O salvamento não foi confirmado. Recarregue e confira antes de tentar novamente.');
      setState(() {
        data = saved;
        busy = false;
      });
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted || originalEpoch != epoch) return;
      setState(() {
        busy = false;
        error = '$e\nConfira a planilha antes de repetir o salvamento.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = tasks.where(shown).toList();
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(
                    data == null
                        ? 'Treinamento Catalog'
                        : 'Treinamento Catalog · ${visible.length} tarefas',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
                tooltip: 'Recarregar tarefas do Catalog',
                onPressed: busy || !widget.allowed() ? null : load,
                icon: const Icon(Icons.refresh, size: 18))
          ]),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!busy && error == null && visible.isEmpty)
            const Text('Nenhuma tarefa para este filtro.'),
          for (final group in visible.map((t) => t['group'].toString()).toSet())
            Card(
                child: ListTile(
                    key: ValueKey('catalog-stage-$group'),
                    leading: const Icon(Icons.school_outlined),
                    title: Text(group),
                    subtitle: Text(
                        '${visible.where((t) => t['group'] == group).length} tarefas · Catalog'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: busy || !widget.allowed()
                        ? null
                        : () => edit(group,
                            tasks.where((t) => t['group'] == group).toList()))),
        ]);
  }
}
