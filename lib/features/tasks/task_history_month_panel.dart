import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';
import 'task_history_month.dart';
import 'task_hours_filter.dart';

class TaskHistoryMonthPanel extends StatefulWidget {
  final TaskHistoryMonth data;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<TimeLog> onEdit;
  final TaskHistoryMonth? summaryData;
  final TaskHoursFilter hoursFilter;
  final ValueChanged<TaskHoursFilter>? onHoursFilterChanged;
  const TaskHistoryMonthPanel(
      {super.key,
      required this.data,
      required this.onSelectDay,
      required this.onEdit,
      this.summaryData,
      this.hoursFilter = TaskHoursFilter.all,
      this.onHoursFilterChanged});
  @override
  State<TaskHistoryMonthPanel> createState() => _TaskHistoryMonthPanelState();
}

class _TaskHistoryMonthPanelState extends State<TaskHistoryMonthPanel> {
  final Map<int, bool> _expanded = {};
  @override
  void didUpdateWidget(covariant TaskHistoryMonthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.year != widget.data.year ||
        oldWidget.data.month != widget.data.month ||
        oldWidget.hoursFilter != widget.hoursFilter) {
      _expanded.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final totals = widget.summaryData ?? data;
    final weeks = data.weeks;
    final today = DateTime.now();
    final current = data.year == today.year && data.month == today.month
        ? weeks.indexWhere(
            (week) => today.day >= week.start.day && today.day <= week.end.day)
        : 0;
    final withLogs = weeks.indexWhere((week) => week.logs.isNotEmpty);
    final initial = current >= 0 && weeks[current].logs.isNotEmpty
        ? current
        : withLogs < 0
            ? 0
            : withLogs;
    return Container(
      decoration: AppVisuals.panel(radius: 14),
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Text('${taskHistoryMonths[data.month - 1]} de ${data.year}',
            style: TextStyle(
                color: AppPalette.text,
                fontWeight: FontWeight.w800,
                fontSize: 19)),
        const SizedBox(height: 4),
        Text(
            '${data.dayCount} dias • ${weeks.length} grupos semanais • somente o mês selecionado',
            style: TextStyle(color: AppPalette.secondary, fontSize: 12)),
        const SizedBox(height: 14),
        LayoutBuilder(
            builder: (context, constraints) =>
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _summary('Total do mês', totals.minutes, constraints.maxWidth,
                      TaskHoursFilter.all),
                  _summary('Horas cobradas', totals.chargedMinutes,
                      constraints.maxWidth, TaskHoursFilter.charged),
                  _summary(
                      'Não cobradas',
                      totals.minutes - totals.chargedMinutes,
                      constraints.maxWidth,
                      TaskHoursFilter.nonCharged),
                ])),
        const SizedBox(height: 14),
        for (var i = 0; i < weeks.length; i++) _week(weeks[i], i, initial),
        const Divider(),
        Row(children: [
          Expanded(
              child: Text(
                  widget.hoursFilter == TaskHoursFilter.all
                      ? 'Total do mês'
                      : 'Total exibido',
                  style: TextStyle(
                      color: AppPalette.text, fontWeight: FontWeight.w800))),
          Text(WorkDuration.format(data.minutes),
              style: TextStyle(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 18))
        ]),
      ]),
    );
  }

  Widget _summary(
      String label, int minutes, double width, TaskHoursFilter filter) {
    final selected =
        filter != TaskHoursFilter.all && widget.hoursFilter == filter;
    final callback = widget.onHoursFilterChanged;
    return Semantics(
      button: callback != null,
      selected: selected,
      child: SizedBox(
        width: width < 500 ? width : (width - 16) / 3,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: callback == null ? null : () => callback(filter),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color:
                          selected ? AppPalette.primary : AppPalette.border)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: AppPalette.secondary, fontSize: 12)),
                    Text(WorkDuration.format(minutes),
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 23,
                            fontWeight: FontWeight.w800)),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _week(TaskHistoryWeek week, int index, int initial) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey(
                  '${widget.data.year}-${widget.data.month}-${widget.hoursFilter.name}-$index'),
              initiallyExpanded: index == initial,
              onExpansionChanged: (value) =>
                  setState(() => _expanded[index] = value),
              collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppPalette.border)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppPalette.border)),
              collapsedBackgroundColor:
                  AppPalette.primary.withValues(alpha: .05),
              backgroundColor: AppPalette.primary.withValues(alpha: .03),
              iconColor: AppPalette.text,
              collapsedIconColor: AppPalette.text,
              title: Text(week.label,
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              subtitle: Text(
                  '${week.logs.length} ${week.logs.length == 1 ? 'apontamento' : 'apontamentos'}'
                  '${week.start.day == 1 ? ' • Início do mês' : week.end.day == widget.data.dayCount ? ' • Fim do mês' : ''}',
                  style: TextStyle(color: AppPalette.secondary, fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(WorkDuration.format(week.minutes),
                    style: TextStyle(
                        color: AppPalette.text, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                Icon(
                    (_expanded[index] ?? index == initial)
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppPalette.secondary),
              ]),
              children: [for (final day in week.days) _day(day, week.logs)],
            )),
      );

  Widget _day(DateTime day, List<TimeLog> weekLogs) {
    final logs = weekLogs.where((log) => log.date.day == day.day).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    const names = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];
    final minutes = logs.fold(0, (sum, log) => sum + WorkDuration.minutes(log));
    return Container(
      key: ValueKey('history-day-${day.year}-${day.month}-${day.day}'),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppPalette.border)),
          color: day.weekday >= DateTime.saturday
              ? AppPalette.primary.withValues(alpha: .04)
              : null),
      child: Material(
          color: Colors.transparent,
          child: Column(children: [
            ListTile(
                dense: true,
                onTap: () => widget.onSelectDay(day),
                leading: SizedBox(
                    width: 38,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(day.day.toString().padLeft(2, '0'),
                              style: TextStyle(
                                  color: AppPalette.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18)),
                          Text(names[day.weekday - 1],
                              style: TextStyle(
                                  color: AppPalette.secondary, fontSize: 10)),
                        ])),
                title: Text(
                    logs.isEmpty
                        ? 'Sem apontamentos'
                        : logs.length == 1
                            ? logs.single.projectName ??
                                logs.single.projectId ??
                                'Projeto'
                            : '${logs.length} apontamentos',
                    style:
                        TextStyle(color: AppPalette.secondary, fontSize: 12)),
                subtitle: logs.length == 1
                    ? Text(
                        '${logs.single.taskName ?? logs.single.targetId} • '
                        '${logs.single.startTime}–${logs.single.endTime}',
                        style: TextStyle(
                            color: AppPalette.secondary, fontSize: 11))
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(WorkDuration.format(minutes),
                      style: TextStyle(
                          color: AppPalette.text, fontWeight: FontWeight.w700)),
                  if (logs.length == 1)
                    IconButton(
                        tooltip: 'Editar apontamento',
                        icon: Icon(Icons.edit_outlined,
                            size: 17, color: AppPalette.text),
                        onPressed: () => widget.onEdit(logs.single)),
                ])),
            if (logs.length > 1)
              for (final log in logs)
                ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 22, right: 12),
                    title: Text(log.projectName ?? log.projectId ?? 'Projeto',
                        style: TextStyle(
                            color: AppPalette.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 12)),
                    subtitle: Text(
                        '${log.taskName ?? log.targetId} • ${log.startTime}–${log.endTime}',
                        style: TextStyle(
                            color: AppPalette.secondary, fontSize: 11)),
                    onTap: () => widget.onSelectDay(day),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(WorkDuration.format(WorkDuration.minutes(log)),
                          style: TextStyle(color: AppPalette.text)),
                      IconButton(
                          tooltip: 'Editar apontamento',
                          icon: Icon(Icons.edit_outlined,
                              size: 17, color: AppPalette.text),
                          onPressed: () => widget.onEdit(log)),
                    ])),
          ])),
    );
  }
}
