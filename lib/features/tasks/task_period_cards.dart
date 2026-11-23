import 'package:flutter/material.dart';
import '../../core/theme/cores_app.dart';
import 'task_hours_filter.dart';
import 'task_period_summary.dart';

class TaskPeriodCards extends StatelessWidget {
  const TaskPeriodCards(
      {super.key,
      required this.summary,
      required this.filter,
      required this.onChanged});
  final TaskPeriodSummary summary;
  final TaskHoursFilter filter;
  final ValueChanged<TaskHoursFilter> onChanged;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth < 650
            ? constraints.maxWidth
            : (constraints.maxWidth - 20) / 3;
        return Wrap(spacing: 10, runSpacing: 8, children: [
          card(width, 'Total do período', summary.totalMinutes, summary.count,
              TaskHoursFilter.all, CoresApp.destaque, Icons.schedule),
          card(
              width,
              'Horas cobradas',
              summary.chargedMinutes,
              summary.chargedCount,
              TaskHoursFilter.charged,
              CoresApp.sucesso,
              Icons.check_circle_outline,
              ratio: summary.chargedRatio),
          card(
              width,
              'Horas não cobradas',
              summary.nonChargedMinutes,
              summary.nonChargedCount,
              TaskHoursFilter.nonCharged,
              Colors.amber.shade700,
              Icons.block,
              ratio: summary.nonChargedRatio),
        ]);
      });

  Widget card(double width, String title, int minutes, int count,
          TaskHoursFilter value, Color color, IconData icon,
          {double? ratio}) =>
      SizedBox(
        width: width,
        child: Semantics(
            button: true,
            selected: filter == value,
            child: Material(
              color: color.withValues(alpha: filter == value ? .16 : .06),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: filter == value ? color : CoresApp.borda,
                      width: filter == value ? 1.5 : 1)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  onTap: () => onChanged(value),
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Icon(icon, size: 28, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(title,
                                  style: TextStyle(
                                      color: CoresApp.textoSecundario)),
                              Text(summary.hours(minutes),
                                  style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900)),
                              Text(
                                  '$count apontamentos${ratio == null ? '' : ' · ${summary.percent(ratio)}'}',
                                  style: TextStyle(color: color, fontSize: 12)),
                              if (ratio != null) ...[
                                const SizedBox(height: 7),
                                LinearProgressIndicator(
                                    value: ratio.clamp(0, 1),
                                    color: color,
                                    backgroundColor:
                                        color.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(4))
                              ],
                            ])),
                      ]))),
            )),
      );
}
