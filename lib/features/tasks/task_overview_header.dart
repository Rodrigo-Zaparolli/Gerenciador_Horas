import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:flutter/material.dart';
import '../../core/theme/cores_app.dart';
import 'task_hours_filter.dart';
import 'task_period_summary.dart';

class TaskOverviewHeader extends StatelessWidget {
  const TaskOverviewHeader(
      {super.key,
      required this.summary,
      required this.onPdf,
      this.filter = TaskHoursFilter.all,
      this.onBilling});
  final TaskPeriodSummary summary;
  final VoidCallback onPdf;
  final TaskHoursFilter filter;
  final ValueChanged<TaskHoursFilter>? onBilling;
  @override
  Widget build(BuildContext context) => Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: AppVisuals.panel(radius: 18, prominent: true),
      child: LayoutBuilder(builder: (context, constraints) {
        final title = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.assignment_outlined, color: CoresApp.destaque, size: 42),
          const SizedBox(width: 10),
          Flexible(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text('Tarefas Executadas',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 28,
                        fontWeight: FontWeight.w900)),
                Text('Projetos, apontamentos e horas',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: CoresApp.textoSecundario, fontSize: 13))
              ]))
        ]);
        final stats = [
          metric('APONTAMENTOS', '${summary.count}'),
          metric('PROJETOS', '${summary.projects.length}'),
          metric('TOTAL DO PERÍODO', summary.hours(summary.totalMinutes),
              value: TaskHoursFilter.all),
          metric('COBRADAS', summary.hours(summary.chargedMinutes),
              value: TaskHoursFilter.charged,
              color: CoresApp.sucesso,
              detail: summary.percent(summary.chargedRatio)),
          metric('NÃO COBRADAS', summary.hours(summary.nonChargedMinutes),
              value: TaskHoursFilter.nonCharged,
              color: Colors.amber.shade700,
              detail: summary.percent(summary.nonChargedRatio)),
          IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Exportar PDF',
              onPressed: onPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20))
        ];
        if (constraints.maxWidth >= 1100)
          return Row(children: [Expanded(child: title), for (final stat in stats) Padding(padding: const EdgeInsets.only(left: 8), child: stat)]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title,
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: stats)
        ]);
      }));
  Widget metric(String label, String text,
      {TaskHoursFilter? value, Color? color, String? detail}) {
    final accent = color ?? CoresApp.destaque;
    return Semantics(
        button: value != null,
        selected: value != null && filter == value,
        child: SizedBox(
            width: detail == null ? 154 : 166,
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    onTap: value == null || onBilling == null
                        ? null
                        : () => onBilling!(value),
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: AppVisuals.panel(
                            accent: accent,
                            prominent: value != null && filter == value,
                            radius: 10),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: CoresApp.textoSecundario,
                                      fontSize: 10,
                                      height: 1.2)),
                              const SizedBox(height: 4),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Icon(label == 'PROJETOS' ? Icons.folder_outlined : label == 'APONTAMENTOS' ? Icons.layers_outlined : value == TaskHoursFilter.charged ? Icons.check_circle_outline : value == TaskHoursFilter.nonCharged ? Icons.error_outline : Icons.schedule, color: accent, size: 25),
                                    const SizedBox(width: 8),
                                    Flexible(
                                        child: Text(text,
                                            maxLines: 1,
                                            style: TextStyle(
                                                color: color ??
                                                    CoresApp.textoPrincipal,
                                                fontSize: 25,
                                                height: 1.1,
                                                fontWeight: FontWeight.w800))),
                                    if (detail != null) ...[
                                      const SizedBox(width: 4),
                                      Text(detail,
                                          style: TextStyle(
                                              color: accent, fontSize: 9))
                                    ]
                                  ])
                            ]))))));
  }
}
