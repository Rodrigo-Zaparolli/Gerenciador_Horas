import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../domain/models/work_duration.dart';
import 'checklist_hours.dart';
import '../../../data/services/native_local_files_service.dart';
import 'spreadsheet_sheet_settings.dart';

Future<Map<String, dynamic>> loadProjectChecklistHours({required String projectId,
  required String reference, required String previousReference, required String serviceType}) async {
  final owner = FirebaseAuth.instance.currentUser?.uid;
  if(owner == null) throw StateError('Entre novamente no sistema.');
  if(reference.isEmpty) throw StateError('Vincule uma planilha a este trabalho.');
  if(reference != previousReference.trim()) throw StateError('Salve o novo vínculo da planilha e reabra o trabalho antes de importar as horas.');
  final sheets = await FirebaseSpreadsheetSheetSettingsStore().load(owner, projectId, reference);
  if(FirebaseAuth.instance.currentUser?.uid != owner) throw StateError('A conta mudou.');
  return NativeLocalFiles.call('excel-editor-read', reference: reference, projectId: projectId,
    projectField: 'excelLink', serviceType: serviceType, sheetNames: sheets.isEmpty ? null : sheets);
}

class ChecklistHoursButton extends StatefulWidget {
  const ChecklistHoursButton(
      {super.key,
      required this.stages,
      required this.sourceToken,
      required this.load,
      required this.apply,
      this.enabled = true,
      this.uidProvider});
  final List<ChecklistHoursStage> Function() stages;
  final String Function() sourceToken;
  final Future<Map<String, dynamic>> Function() load;
  final void Function(Map<int, int>) apply;
  final bool enabled;
  final String? Function()? uidProvider;
  @override
  State<ChecklistHoursButton> createState() => _ChecklistHoursButtonState();
}

class _ChecklistHoursButtonState extends State<ChecklistHoursButton> {
  bool busy = false;
  bool reading = false;
  Timer? reviewGuard;
  BuildContext? reviewContext;
  String? reviewOwner;
  @override
  void dispose() {
    reviewGuard?.cancel();
    super.dispose();
  }

  Widget guardedReview(BuildContext context, Widget dialog) {
    reviewContext = context;
    return uid == reviewOwner ? dialog : const SizedBox.shrink();
  }

  String? get uid => widget.uidProvider != null
      ? widget.uidProvider!()
      : FirebaseAuth.instance.currentUser?.uid;
  String fingerprint() => jsonEncode([
        widget.sourceToken(),
        for (final s in widget.stages()) [s.name, s.hours]
      ]);
  Future<void> run() async {
    if (busy || !widget.enabled) return;
    final owner = uid;
    if (owner == null) return;
    final before = fingerprint();
    final stages = widget.stages();
    bool current() => mounted && widget.enabled && uid == owner && fingerprint() == before;
    setState(() { busy = true; reading = true; });
    try {
      final data = await widget.load();
      if (!mounted || !widget.enabled) return;
      setState(() => reading = false);
      if (!current()) {
        throw StateError(
            'A conta, a planilha ou as etapas mudaram. Consulte novamente antes de aplicar.');
      }
      final comparison = ChecklistHoursComparison.build(data, stages);
      final selected = {
        for (final row in comparison.rows)
          if (row.selectable && row.minutes! > 0) row.index
      };
      reviewOwner = owner;
      reviewGuard = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (uid != owner) {
          final context = reviewContext;
          if (context != null && context.mounted) Navigator.pop(context);
          timer.cancel();
        }
      });
      final approved = await showDialog<Set<int>>(
          context: context,
          builder: (context) => StatefulBuilder(
              builder: (context, refresh) => guardedReview(
                  context,
                  AlertDialog(
                      title: const Text('Atualizar horas pelo checklist'),
                      content: SizedBox(
                          width: 780,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Planilha: ${data['filename'] ?? ''}'),
                                const SizedBox(height: 8),
                                const Text(
                                    'Horas da planilha salva. Selecione as etapas. As horas apontadas permanecem iguais. Após aplicar, use Salvar alterações no trabalho.'),
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                        columnSpacing: 18,
                                        columns: const [
                                          DataColumn(label: Text('Aplicar')),
                                          DataColumn(label: Text('Etapa')),
                                          DataColumn(label: Text('Atual')),
                                          DataColumn(label: Text('Checklist')),
                                          DataColumn(label: Text('Conferência'))
                                        ],
                                        rows: [
                                          for (final row in comparison.rows)
                                            DataRow(cells: [
                                              DataCell(Checkbox(
                                                  value: selected
                                                      .contains(row.index),
                                                  onChanged: row.selectable
                                                      ? (v) => refresh(() =>
                                                          v == true
                                                              ? selected.add(
                                                                  row.index)
                                                              : selected.remove(
                                                                  row.index))
                                                      : null)),
                                              DataCell(Text(row.stage.name)),
                                              DataCell(Text(row.stage.hours)),
                                              DataCell(Text(row.minutes == null
                                                  ? 'Não consultado'
                                                  : WorkDuration.format(
                                                      row.minutes!))),
                                              DataCell(Text(row.warning ??
                                                  (row.selectable
                                                      ? '${row.count} tarefas'
                                                      : 'Sem alteração'))),
                                            ])
                                        ])),
                                if (comparison.unmatched.isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                          'Etapas do checklist sem vínculo no trabalho: ${comparison.unmatched.join(', ')}.')),
                              ]))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar')),
                        FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    context, Set<int>.from(selected)),
                            child: const Text('Aplicar nas etapas'))
                      ]))));
      if (approved == null) return;
      if (!mounted || !widget.enabled) return;
      if (!current()) {
        throw StateError(
            'Os dados mudaram durante a conferência. Nenhuma hora foi aplicada.');
      }
      widget.apply({
        for (final row in comparison.rows)
          if (approved.contains(row.index) && row.selectable)
            row.index: row.minutes!
      });
    } catch (error) {
      if (mounted && widget.enabled && uid == owner) {
        setState(() => reading = false);
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Não foi possível atualizar as horas'),
                    content: SelectableText('$error'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Entendi'))
                    ]));
      }
    } finally {
      reviewGuard?.cancel();
      reviewContext = null;
      reviewOwner = null;
      if (mounted) setState(() { busy = false; reading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: busy || !widget.enabled ? null : run,
      icon: reading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.calculate_outlined, size: 18),
      label:
          Text(reading ? 'Lendo checklist...' : 'Atualizar horas pelo checklist'));
}
