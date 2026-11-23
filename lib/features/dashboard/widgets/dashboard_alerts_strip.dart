import '../../../domain/models/dashboard_alert_preferences.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_visuals.dart';
import '../../../domain/models/deadline_alert.dart';
import '../../../domain/models/project_model.dart';
import '../../../data/services/project_update_service.dart';

enum _StripTopic { all, overdue, deadlines, comments }

class DashboardAlertsStrip extends StatefulWidget {
  const DashboardAlertsStrip(
      {super.key,
      required this.projects,
      this.updates = const [],
      this.updatesUnavailable = false,
      this.preferences = const DashboardAlertPreferences(),
      this.onConfigure,
      required this.onOpen,
      required this.formatDate});
  final List<ProjectModel> projects;
  final List<PendingProjectUpdate> updates;
  final bool updatesUnavailable;
  final VoidCallback onOpen;
  final VoidCallback? onConfigure;
  final DashboardAlertPreferences preferences;
  final String Function(DateTime) formatDate;
  @override
  State<DashboardAlertsStrip> createState() => _DashboardAlertsStripState();
}

class _DashboardAlertsStripState extends State<DashboardAlertsStrip> {
  _StripTopic topic = _StripTopic.all;
  @override
  void didUpdateWidget(covariant DashboardAlertsStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.preferences;
    if ((topic == _StripTopic.overdue && !p.overdue) ||
        (topic == _StripTopic.deadlines && !p.deadlines) ||
        (topic == _StripTopic.comments && !p.comments)) topic = _StripTopic.all;
  }

  void select(_StripTopic value) => setState(() {
        topic = topic == value ? _StripTopic.all : value;
      });
  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    if (!preferences.active) return const SizedBox.shrink();
    final projects = widget.projects;
    final updatesUnavailable = widget.updatesUnavailable;
    final onOpen = widget.onOpen;
    final formatDate = widget.formatDate;
    final updates =
        preferences.comments ? widget.updates : <PendingProjectUpdate>[];

    final items = DeadlineAlert.collect(projects, DateTime.now())
        .where((e) => preferences.allowsDeadline(e.differenceDays))
        .toList();
    final overdue = items.where((e) => e.differenceDays < 0).length +
        updates.where((e) => e.overdueDays > 0).length;
    final visibleItems = items
        .where((e) => switch (topic) {
              _StripTopic.overdue => e.differenceDays < 0,
              _StripTopic.deadlines => e.differenceDays >= 0,
              _StripTopic.comments => false,
              _ => true,
            })
        .toList();
    final visibleUpdates = updates
        .where((e) => switch (topic) {
              _StripTopic.overdue => e.overdueDays > 0,
              _StripTopic.deadlines => false,
              _ => true,
            })
        .toList();
    Widget stat(String label, String value, IconData icon, Color color,
            _StripTopic category) =>
        SizedBox(
            width: 106,
            child: InkWell(
                onTap: () => select(category),
                child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    decoration: AppVisuals.panel(
                            accent: color, prominent: true, radius: 14)
                        .copyWith(
                            border: Border.all(
                                color: color,
                                width: topic == category ? 2.5 : 1)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, color: color, size: 24),
                            const SizedBox(width: 7),
                            Text(value,
                                style: TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 25,
                                    fontWeight: FontWeight.w800))
                          ]),
                      const SizedBox(height: 7),
                      Text(label,
                          style:
                              TextStyle(color: AppPalette.text, fontSize: 11)),
                    ]))));
    final overview = Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 64,
          height: 64,
          decoration: AppVisuals.iconTile(accent: Colors.amber, radius: 32),
          child: const Icon(Icons.notifications_none,
              color: Colors.amber, size: 44)),
      const SizedBox(width: 14),
      SizedBox(
          width: 175,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Central de Alertas',
                    style: TextStyle(
                        color: AppPalette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Pendências e situações que precisam de atenção.',
                    style:
                        TextStyle(color: AppPalette.secondary, fontSize: 12)),
              ])),
    ]);
    final counters = Row(mainAxisSize: MainAxisSize.min, children: [
      if (preferences.overdue)
        stat('Em atraso', '$overdue', Icons.alarm, AppPalette.danger,
            _StripTopic.overdue),
      const SizedBox(width: 10),
      if (preferences.deadlines)
        stat(
            'Prazos próximos',
            '${items.where((e) => e.differenceDays >= 0).length}',
            Icons.event,
            Colors.amber,
            _StripTopic.deadlines),
      const SizedBox(width: 10),
      stat('Comentários', updatesUnavailable ? '\u2014' : '${updates.length}',
          Icons.chat_bubble_outline, AppPalette.accent, _StripTopic.comments),
    ]);
    final list =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (topic != _StripTopic.comments &&
          (preferences.overdue || preferences.deadlines)) ...[
        Text('Projetos com datas a vencer nos próximos dias',
            style: TextStyle(
                color: AppPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (visibleItems.isEmpty)
          Text('Nenhum prazo crítico no momento.',
              style: TextStyle(color: AppPalette.secondary, fontSize: 12)),
        for (final item in visibleItems)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(
                    width: 72,
                    child: Text(item.id,
                        style: TextStyle(
                            color: AppPalette.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
                Expanded(
                    child: Text(item.client,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppPalette.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Text(formatDate(item.planEnd),
                    style:
                        TextStyle(color: AppPalette.secondary, fontSize: 11)),
                const SizedBox(width: 10),
                Container(
                    width: 76,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                        color: item.differenceDays < 0
                            ? AppPalette.danger
                            : Colors.amber.shade800,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(item.differenceDays < 0 ? 'Atrasado' : 'Ativo',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10))),
              ])),
      ],
      if (topic != _StripTopic.deadlines && preferences.comments) ...[
        const SizedBox(height: 8),
        Text(
            'Atualizações de comentários (${updatesUnavailable ? "—" : visibleUpdates.length})',
            style: TextStyle(
                color: AppPalette.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        if (updatesUnavailable)
          Text('Não foi possível consultar os comentários.',
              style: TextStyle(color: AppPalette.secondary, fontSize: 12))
        else if (visibleUpdates.isEmpty)
          Text('Nenhum comentário pendente de atualização.',
              style: TextStyle(color: AppPalette.secondary, fontSize: 12)),
        for (final update in visibleUpdates)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                  width: 72,
                  child: Text(update.project.id,
                      style:
                          TextStyle(color: AppPalette.accent, fontSize: 11))),
              Expanded(
                  child: Text(update.project.client,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppPalette.text, fontSize: 11))),
              const SizedBox(width: 8),
              Text(formatDate(update.dueDate),
                  style: TextStyle(color: AppPalette.secondary, fontSize: 11)),
              const SizedBox(width: 10),
              Text(update.overdueDays > 0 ? 'Em atraso' : 'Atualizar hoje',
                  style: TextStyle(
                      color: update.overdueDays > 0
                          ? AppPalette.danger
                          : Colors.amber,
                      fontSize: 11)),
            ]),
          ),
      ],
    ]);
    final boundedList = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(primary: false, child: list));
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: AppVisuals.panel(prominent: true, radius: 20),
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 1150)
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                      spacing: 20,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [overview, counters]),
                  const SizedBox(height: 16),
                  boundedList,
                  Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (widget.onConfigure != null)
                              TextButton.icon(
                                  onPressed: widget.onConfigure,
                                  icon: const Icon(Icons.tune, size: 18),
                                  label: const Text('Configurar alertas')),
                            TextButton(
                                onPressed: onOpen,
                                child: const Text('Ver todos os alertas')),
                          ]))
                ]);
          return Row(children: [
            overview,
            const SizedBox(width: 22),
            counters,
            const SizedBox(width: 24),
            Container(width: 1, height: 96, color: AppPalette.accent),
            const SizedBox(width: 24),
            Expanded(child: boundedList),
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.onConfigure != null)
                IconButton(
                    tooltip: 'Configurar alertas',
                    onPressed: widget.onConfigure,
                    icon: Icon(Icons.tune, color: AppPalette.accent)),
              IconButton(
                  tooltip: 'Ver todos os alertas',
                  onPressed: onOpen,
                  icon: Icon(Icons.chevron_right, color: AppPalette.accent)),
            ])
          ]);
        }));
  }
}
