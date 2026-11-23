import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:flutter/material.dart';
import '../../core/theme/cores_app.dart';
import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';
import 'task_hours_filter.dart';
import 'task_period_summary.dart';
import 'task_logs_table.dart';

class TaskWorkspacePanel extends StatelessWidget {
  const TaskWorkspacePanel(
      {super.key,
      required this.logs,
      required this.summary,
      required this.workLabel,
      required this.periodLabel,
      required this.filter,
      required this.onBilling,
      required this.selected,
      required this.onSelect,
      required this.onSelectAll,
      required this.onAction,
      required this.onSend,
      required this.onRegisterHours,
      required this.onRetry,
      this.onToggleHistory,
      this.onViewMonth,
      this.sending = false,
      this.loading = false,
      this.hasError = false,
      this.showPending = false});
  final List<TimeLog> logs;
  final TaskPeriodSummary summary;
  final String? workLabel;
  final String periodLabel;
  final TaskHoursFilter filter;
  final ValueChanged<TaskHoursFilter> onBilling;
  final Set<String> selected;
  final void Function(TimeLog, bool) onSelect;
  final ValueChanged<bool> onSelectAll;
  final void Function(TimeLog, TaskLogAction) onAction;
  final ValueChanged<List<TimeLog>> onSend;
  final VoidCallback onRegisterHours, onRetry;
  final VoidCallback? onToggleHistory, onViewMonth;
  final bool sending, loading, hasError, showPending;
  @override
  Widget build(BuildContext context) {
    final sendable = logs.where((log) => log.isRegistered).toList();
    final selection =
        sendable.where((log) => selected.contains(taskLogKey(log))).toList();
    final hasSelection = logs.any((log) => selected.contains(taskLogKey(log)));
    return Container(
        clipBehavior: Clip.antiAlias,
        decoration: AppVisuals.panel(radius: 14),
        child: LayoutBuilder(
            builder: (context, c) => Column(children: [
                  ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: c.maxHeight * .38),
                      child: SingleChildScrollView(
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: LayoutBuilder(builder: (context, width) {
                                final title = Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                          workLabel == null
                                              ? 'Apontamentos do período'
                                              : 'Apontamentos do projeto',
                                          style: TextStyle(
                                              color: CoresApp.textoPrincipal,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 3),
                                      Text(
                                          workLabel == null
                                              ? periodLabel
                                              : '$workLabel · Todos os trabalhos · $periodLabel',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 10))
                                    ]);
                                final actions = Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (onToggleHistory != null)
                                        TextButton.icon(
                                            onPressed: onToggleHistory,
                                            icon: const Icon(
                                                Icons.view_sidebar_outlined,
                                                size: 15),
                                            label: const Text('Histórico',
                                                style:
                                                    TextStyle(fontSize: 11))),
                                      TextButton.icon(
                                          onPressed: onRegisterHours,
                                          icon: const Icon(Icons.add, size: 15),
                                          label: const Text('Registrar',
                                              style: TextStyle(fontSize: 11))),
                                      OutlinedButton.icon(
                                          onPressed: sending ||
                                                  loading ||
                                                  hasError ||
                                                  sendable.isEmpty ||
                                                  (hasSelection &&
                                                      selection.isEmpty)
                                              ? null
                                              : () => onSend(hasSelection
                                                  ? selection
                                                  : sendable),
                                          style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 32),
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 7),
                                              textStyle: const TextStyle(
                                                  fontSize: 11)),
                                          icon: sending
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2))
                                              : const Icon(
                                                  Icons.cloud_upload_outlined,
                                                  size: 15),
                                          label: Text(hasSelection ? 'Enviar seleção (${selection.length})' : 'Conferir e enviar')),
                                    ]);
                                if (width.maxWidth >= 800)
                                  return Row(children: [
                                    Expanded(child: title),
                                    const SizedBox(width: 8),
                                    actions
                                  ]);
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      title,
                                      const SizedBox(height: 4),
                                      actions
                                    ]);
                              })))),
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  if (hasError)
                    Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('A leitura do período não foi concluída.',
                              style: TextStyle(fontSize: 11)),
                          TextButton(
                              onPressed: onRetry,
                              child: const Text('Tentar novamente'))
                        ]),
                  Divider(height: 1, color: CoresApp.borda),
                  Expanded(
                      child: logs.isEmpty && !loading && !hasError
                          ? Center(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                            'Nenhum apontamento neste filtro.'),
                                        const SizedBox(height: 6),
                                        const Text(
                                            'Confira o projeto, o período e a cobrança.',
                                            style: TextStyle(fontSize: 12)),
                                        if (onViewMonth != null)
                                          TextButton(
                                              onPressed: onViewMonth,
                                              child: const Text(
                                                  'Ver mês completo'))
                                      ])))
                          : TaskLogsTable(
                              logs: logs,
                              selected: selected,
                              busy: sending,
                              onSelect: onSelect,
                              onSelectAll: onSelectAll,
                              onAction: onAction)),
                  if(logs.isEmpty || showPending) Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              '${logs.length} apontamentos · ${summary.hours(logs.fold<int>(0, (sum, log) => sum + WorkDuration.minutes(log)))} exibidas${showPending ? ' · inclui pendentes de registro' : ''}',
                              style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 10)))),
                ])));
  }
}
