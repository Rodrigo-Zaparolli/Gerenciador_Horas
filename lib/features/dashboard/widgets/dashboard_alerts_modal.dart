import '../../../domain/models/dashboard_alert_preferences.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_appearance.dart';
import '../../../core/theme/app_palette.dart';
import '../../../data/services/project_update_service.dart';
import '../../../domain/models/deadline_alert.dart';
import 'dashboard_alert_widgets.dart';

enum _AlertFilter { all, overdue, deadlines, comments }

enum _AlertOrder { urgency, client }

class DashboardAlertsModal extends StatefulWidget {
  const DashboardAlertsModal(
      {super.key,
      required this.deadlines,
      required this.updates,
      this.updatesUnavailable = false,
      this.preferences = const DashboardAlertPreferences()});
  final List<DeadlineAlert> deadlines;
  final List<PendingProjectUpdate> updates;
  final bool updatesUnavailable;
  final DashboardAlertPreferences preferences;

  static Future<String?> show(BuildContext context,
          List<DeadlineAlert> deadlines, List<PendingProjectUpdate> updates,
          {bool updatesUnavailable = false,
          DashboardAlertPreferences preferences =
              const DashboardAlertPreferences()}) =>
      showDialog<String>(
          context: context,
          builder: (_) => DashboardAlertsModal(
              deadlines: deadlines,
              updates: updates,
              updatesUnavailable: updatesUnavailable,
              preferences: preferences));

  @override
  State<DashboardAlertsModal> createState() => _DashboardAlertsModalState();
}

class _DashboardAlertsModalState extends State<DashboardAlertsModal> {
  List<DeadlineAlert> get _deadlines => widget.deadlines
      .where((e) => widget.preferences.allowsDeadline(e.differenceDays))
      .toList();
  List<PendingProjectUpdate> get _updates =>
      widget.preferences.active && widget.preferences.comments
          ? widget.updates
          : const [];
  bool get _updatesUnavailable =>
      widget.preferences.comments && widget.updatesUnavailable;
  _AlertFilter filter = _AlertFilter.all;
  _AlertOrder order = _AlertOrder.urgency;
  bool deadlinesExpanded = true, commentsExpanded = true;
  Color get accent =>
      AppPalette.dark ? const Color(0xFF22D3EE) : AppPalette.primary;
  int get overdueCount =>
      _deadlines.where((e) => e.differenceDays < 0).length +
      _updates.where((e) => e.overdueDays > 0).length;

  Widget _header({bool inlineSummary = false}) => ClipRect(
      key: const ValueKey('alerts-header'),
      child: CustomPaint(
        painter: AlertHeaderWaves(accent),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                Icon(Icons.notifications_active_outlined,
                    color: AppPalette.warning, size: 32),
                if (overdueCount > 0)
                  Positioned(
                      top: -2,
                      right: -3,
                      child: Container(
                          width: 15,
                          height: 15,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: AppPalette.danger, shape: BoxShape.circle),
                          child: const Text('!',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)))),
              ]),
              const SizedBox(width: 18),
              Expanded(
                  flex: inlineSummary ? 4 : 1,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Central de Alertas',
                            style: TextStyle(
                                color: AppPalette.text,
                                fontSize:
                                    MediaQuery.sizeOf(context).width >= 1000
                                        ? 23
                                        : 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                            _deadlines.isEmpty && _updates.isEmpty
                                ? _updatesUnavailable
                                    ? 'Comentários ainda não consultados'
                                    : 'Nenhum alerta de prazo encontrado'
                                : '${_deadlines.length + _updates.length} pendências precisam de atenção',
                            style: TextStyle(
                                color: AppPalette.secondary,
                                fontSize:
                                    MediaQuery.sizeOf(context).width >= 1000
                                        ? 13
                                        : 12)),
                      ])),
              if (inlineSummary) ...[
                const SizedBox(width: 14),
                Expanded(flex: 9, child: _summary(compact: true)),
                const SizedBox(width: 8),
              ],
              IconButton(
                  tooltip: 'Fechar alertas',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: AppPalette.text, size: 26)),
            ])),
      ));

  Widget _summary({bool compact = false}) =>
      LayoutBuilder(builder: (context, size) {
        final cards = [
          if (widget.preferences.overdue)
            AlertSummaryCard(
                compact: compact,
                title: 'Em atraso',
                count: '$overdueCount',
                description: 'Projetos ou comentários vencidos',
                icon: Icons.error_outline,
                color: AppPalette.danger,
                selected: filter == _AlertFilter.overdue,
                onTap: () => setState(() => filter =
                    filter == _AlertFilter.overdue
                        ? _AlertFilter.all
                        : _AlertFilter.overdue)),
          if (widget.preferences.deadlines)
            AlertSummaryCard(
                compact: compact,
                title: 'Prazos de projetos',
                count: '${_deadlines.length}',
                description: 'Projetos e etapas com prazo de atenção',
                icon: Icons.schedule,
                color: AppPalette.warning,
                selected: filter == _AlertFilter.deadlines,
                onTap: () => setState(() => filter =
                    filter == _AlertFilter.deadlines
                        ? _AlertFilter.all
                        : _AlertFilter.deadlines)),
          AlertSummaryCard(
              compact: compact,
              title: 'Comentários',
              count: _updatesUnavailable && _updates.isEmpty
                  ? '—'
                  : '${_updates.length}',
              description: 'Projetos que precisam de atualização',
              icon: Icons.chat_bubble_outline,
              color: accent,
              selected: filter == _AlertFilter.comments,
              onTap: () => setState(() => filter =
                  filter == _AlertFilter.comments
                      ? _AlertFilter.all
                      : _AlertFilter.comments)),
        ];
        if (cards.isEmpty) return const SizedBox.shrink();
        final columns = math.min(
            cards.length,
            compact || size.maxWidth >= 900
                ? 3
                : size.maxWidth >= 580
                    ? 2
                    : 1);
        final width = (size.maxWidth - (columns - 1) * 12) / columns;
        return Padding(
            padding: compact
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: LayoutBuilder(builder: (context, inner) {
              final actual = (inner.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(spacing: 12, runSpacing: 10, children: [
                for (final card in cards)
                  SizedBox(width: math.min(width, actual), child: card),
              ]);
            }));
      });

  Widget _toolbar() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: LayoutBuilder(builder: (context, size) {
        final title = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.layers_outlined, color: accent, size: 22),
          const SizedBox(width: 10),
          Flexible(
              child: Text('Alertas por categoria',
                  style: TextStyle(
                      color: AppPalette.text,
                      fontSize:
                          MediaQuery.sizeOf(context).width >= 1000 ? 17 : 15,
                      fontWeight: FontWeight.w700))),
        ]);
        final controls = Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Ordenar por:',
                  style: TextStyle(color: AppPalette.secondary, fontSize: 11)),
              DropdownButton<_AlertOrder>(
                  value: order,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: AppPalette.text, fontSize: 12),
                  items: const [
                    DropdownMenuItem(
                        value: _AlertOrder.urgency,
                        child: Text('Mais urgentes')),
                    DropdownMenuItem(
                        value: _AlertOrder.client, child: Text('Cliente (A–Z)'))
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => order = value);
                  }),
              PopupMenuButton<_AlertFilter>(
                  tooltip: 'Filtrar alertas',
                  icon: Icon(Icons.filter_alt_outlined, color: accent),
                  onSelected: (value) => setState(() => filter = value),
                  itemBuilder: (_) => [
                        for (final value
                            in _AlertFilter.values.where((v) => switch (v) {
                                  _AlertFilter.all => true,
                                  _AlertFilter.overdue =>
                                    widget.preferences.overdue,
                                  _AlertFilter.deadlines =>
                                    widget.preferences.overdue ||
                                        widget.preferences.deadlines,
                                  _AlertFilter.comments =>
                                    widget.preferences.comments,
                                }))
                          CheckedPopupMenuItem(
                              value: value,
                              checked: filter == value,
                              child: Text(switch (value) {
                                _AlertFilter.all => 'Todos os alertas',
                                _AlertFilter.overdue => 'Somente em atraso',
                                _AlertFilter.deadlines => 'Prazos de projetos',
                                _AlertFilter.comments => 'Comentários',
                              })),
                      ]),
            ]);
        if (size.maxWidth >= 650)
          return Row(children: [Expanded(child: title), controls]);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, controls]);
      }));

  Widget _categories() {
    final deadlines = filter == _AlertFilter.comments
        ? <DeadlineAlert>[]
        : _deadlines
            .where(
                (e) => filter != _AlertFilter.overdue || e.differenceDays < 0)
            .toList();
    final updates = filter == _AlertFilter.deadlines
        ? <PendingProjectUpdate>[]
        : _updates
            .where((e) => filter != _AlertFilter.overdue || e.overdueDays > 0)
            .toList();
    deadlines.sort((a, b) => order == _AlertOrder.client
        ? a.client.toLowerCase().compareTo(b.client.toLowerCase())
        : a.differenceDays.compareTo(b.differenceDays));
    updates.sort((a, b) => order == _AlertOrder.client
        ? a.project.client
            .toLowerCase()
            .compareTo(b.project.client.toLowerCase())
        : b.overdueDays.compareTo(a.overdueDays));
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_updatesUnavailable)
            Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    color: AppPalette.warning.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                    'Não foi possível verificar os comentários. Consulte novamente pelo sino.',
                    style: TextStyle(color: AppPalette.warning, fontSize: 12))),
          if (deadlines.isEmpty && updates.isEmpty && !_updatesUnavailable)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Text(
                    _deadlines.isEmpty && _updates.isEmpty
                        ? 'Nenhum alerta pendente no momento.'
                        : 'Nenhum alerta neste filtro.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.secondary))),
          if (deadlines.isNotEmpty)
            AlertCategory(
                title: 'Prazos de projetos e etapas',
                count: deadlines.length,
                color: AppPalette.warning,
                icon: Icons.event_outlined,
                expanded: deadlinesExpanded,
                onToggle: () =>
                    setState(() => deadlinesExpanded = !deadlinesExpanded),
                children: [
                  for (final entry in deadlines)
                    AlertListEntry(
                        title: '${entry.client} - ${entry.id}',
                        description:
                            '${entry.stage.isEmpty ? entry.serviceType : entry.stage} · Vencimento: ${ProjectUpdateService.formatDate(entry.planEnd)}',
                        badge: entry.differenceDays < 0
                            ? '${-entry.differenceDays} dia(s) em atraso'
                            : entry.differenceDays == 0
                                ? 'Vence hoje'
                                : 'Vence em ${entry.differenceDays} dia(s)',
                        overdue: entry.differenceDays < 0,
                        accent: accent,
                        label: 'Ver na central',
                        onAction: () => Navigator.pop(context, 'alerts'))
                ]),
          if (updates.isNotEmpty)
            AlertCategory(
                title: 'Atualizações de comentários',
                count: updates.length,
                color: accent,
                icon: Icons.chat_bubble_outline,
                expanded: commentsExpanded,
                onToggle: () =>
                    setState(() => commentsExpanded = !commentsExpanded),
                children: [
                  for (final entry in updates)
                    AlertListEntry(
                        title: '${entry.project.client} - ${entry.project.id}',
                        description:
                            'Último comentário: ${ProjectUpdateService.formatDate(entry.comment.date)} · Atualizar até: ${ProjectUpdateService.formatDate(entry.dueDate)}',
                        badge: entry.overdueDays == 0
                            ? 'Atualizar hoje'
                            : '${entry.overdueDays} dia(s) em atraso',
                        overdue: entry.overdueDays > 0,
                        accent: accent,
                        label: 'Comentar',
                        onRecordExternal: () => Navigator.pop(context, 'external:${entry.project.id}'),
                        onAction: () => Navigator.pop(
                            context, 'comment:${entry.project.id}'))
                ]),
        ]));
  }

  Widget _footer() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            accent.withValues(alpha: .04),
            accent.withValues(alpha: .12)
          ]),
          border:
              Border(top: BorderSide(color: accent.withValues(alpha: .35)))),
      child: LayoutBuilder(builder: (context, size) {
        final info = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.info_outline, color: accent, size: 23),
          const SizedBox(width: 12),
          Flexible(
              child: Text(
                  'Confira os prazos e abra a ação desejada.\nUse “Ver na central” ou “Comentar” para agir na pendência.',
                  style: TextStyle(
                      color: AppPalette.secondary,
                      fontSize:
                          MediaQuery.sizeOf(context).width >= 1000 ? 12 : 11))),
        ]);
        final actions = Wrap(spacing: 10, runSpacing: 6, children: [
          if (_updates.isNotEmpty)
            OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'requests'),
                style: OutlinedButton.styleFrom(
                    minimumSize: MediaQuery.sizeOf(context).width >= 1000
                        ? const Size(154, 36)
                        : const Size(0, 36),
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                    textStyle: TextStyle(
                        fontSize: MediaQuery.sizeOf(context).width >= 1000
                            ? 13
                            : 12)),
                icon: const Icon(Icons.format_list_bulleted, size: 24),
                label: const Text('Ver solicitações')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                  minimumSize: MediaQuery.sizeOf(context).width >= 1000
                      ? const Size(112, 36)
                      : const Size(0, 36),
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF00101E),
                  textStyle: TextStyle(
                      fontSize:
                          MediaQuery.sizeOf(context).width >= 1000 ? 14 : 14,
                      fontWeight: FontWeight.w700)),
              icon: const Icon(Icons.check),
              label: const Text('Entendi')),
        ]);
        if (size.maxWidth >= 850)
          return Row(children: [
            Expanded(child: info),
            const SizedBox(width: 16),
            actions
          ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          info,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: actions)
        ]);
      }));

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: AppPalette.dark
          ? Color.lerp(AppPalette.surface, const Color(0xFF00101E), .65)
          : AppPalette.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accent.withValues(alpha: .75))),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
          width: math.min(1180, size.width - 24),
          height: math.min(700, size.height - 32),
          child: Column(children: [
            _header(inlineSummary: size.width >= 1024),
            Divider(height: 1, color: accent.withValues(alpha: .4)),
            Expanded(child: LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth >= 900 && constraints.maxHeight >= 400)
                return Column(children: [
                  if (size.width < 1024) _summary(),
                  _toolbar(),
                  Expanded(child: SingleChildScrollView(child: _categories())),
                ]);
              return SingleChildScrollView(
                  child: Column(children: [
                if (size.width < 1024) _summary(),
                _toolbar(),
                _categories()
              ]));
            })),
            _footer(),
          ])),
    );
  }
}
