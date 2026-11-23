import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/tasks/task_filters_bar.dart';
import 'package:gerenciador_horas/features/tasks/task_hours_filter.dart';
import 'package:gerenciador_horas/features/tasks/task_log_query.dart';
import 'package:gerenciador_horas/features/tasks/task_logs_table.dart';
import 'package:gerenciador_horas/features/tasks/task_overview_header.dart';
import 'package:gerenciador_horas/features/tasks/task_period_cards.dart';
import 'package:gerenciador_horas/features/tasks/task_period_summary.dart';
import 'package:gerenciador_horas/features/tasks/task_work_picker.dart';
import 'package:gerenciador_horas/features/tasks/task_workspace_panel.dart';

TimeLog log(String id, String target, int day, int minutes,
        {bool charged = true,
        bool registered = true,
        String description = 'Revisão da implantação'}) =>
    TimeLog(
        id: id,
        targetId: target,
        projectId: target.split('_').first,
        date: DateTime(2026, 11, day),
        startTime: '08:00',
        endTime: '09:00',
        durationFormatted: '',
        durationMinutes: minutes,
        isRegistered: registered,
        projectName: 'Cliente exemplo',
        taskName: 'Implantação',
        description: description,
        typeHs: charged ? 'Hs Cobradas' : 'Hs Não Cobradas');

void main() {
  final entries = [
    log('a', '226_3', 18, 90),
    log('b', '226_3', 17, 30, charged: false),
    log('c', '226_4', 18, 60),
    log('d', '2260_3', 18, 40),
    log('e', '226_3', 19, 15, registered: false)
  ];

  test(
      'combined real work, dates, description and billing filters do not leak requests or stages',
      () {
    final context = filterTaskLogs(entries,
        work: '226/3',
        search: 'revisao implantacao',
        start: DateTime(2026, 11, 17),
        end: DateTime(2026, 11, 18));
    expect(context.map((e) => e.id), ['a', 'b']);
    final charged = filterTaskLogs(context, billing: TaskHoursFilter.charged);
    expect(charged.single.id, 'a');
    expect(
        filterTaskLogs(context, billing: TaskHoursFilter.nonCharged).single.id,
        'b');
    final summary = TaskPeriodSummary(context);
    expect(summary.totalMinutes, 120);
    expect(summary.chargedCount, 1);
    expect(summary.chargedMinutes, 90);
    expect(summary.nonChargedMinutes, 30);
    expect(summary.percent(summary.chargedRatio), '75,0%');
    expect(summary.works.length, 1);
  });

  test('work counts distinguish stages and administrative pending is explicit',
      () {
    expect(TaskPeriodSummary(filterTaskLogs(entries)).works.length, 3);
    expect(filterTaskLogs(entries).length, 4);
    expect(filterTaskLogs(entries, includePending: true).first.id, 'e');
    expect(entries.last.isRegistered, false);
    expect(TaskPeriodSummary([]).chargedRatio, 0);
    expect(TaskPeriodSummary([]).nonChargedRatio, 0);
  });

  test(
      'picker uses real work number rather than list order, including historical works',
      () {
    final project = ProjectModel.fromJson({
      'id': '226',
      'client': 'Cliente',
      'subTasks': [
        {'subId': '9', 'stage': 'Desenvolvimento', 'edeskSolicitacao': '227'},
      ]
    });
    final choices = taskProjectChoices([project], entries);
    expect(choices.singleWhere((c) => c.id == '226').works, contains('227/9'));
    expect(choices.singleWhere((c) => c.id == '226').requests, contains('227'));
    expect(choices.singleWhere((c) => c.id == '226').works,
        isNot(contains('226/1')));
    expect(choices.where((c) => c.id == '226').length, 1);
  });

  for (final theme in [AppVisualTheme.light, AppVisualTheme.black]) {
    for (final width in [360.0, 760.0, 1600.0]) {
      testWidgets(
          'overview, filters, period totals and flat table fit $theme / $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AppAppearance.instance.value = theme;
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final summary = TaskPeriodSummary(entries.take(2));
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme == AppVisualTheme.light
                ? ThemeMode.light
                : ThemeMode.dark,
            home: Scaffold(
                body: Column(children: [
              SizedBox(
                  height: 180,
                  child: SingleChildScrollView(
                      child: Column(children: [
                    TaskOverviewHeader(summary: summary, onPdf: () {}),
                    TaskFiltersBar(
                        controller: controller,
                        onSearch: (_) {},
                        workLabel: null,
                        onWork: () {},
                        onClearWork: () {},
                        periodLabel: 'Novembro 2026',
                        onPeriod: () {},
                        filter: TaskHoursFilter.all,
                        onBilling: (_) {},
                        onAction: (_) {},
                        showHistory: true,
                        showPending: false),
                  ]))),
              Expanded(
                  child: TaskWorkspacePanel(
                      logs: entries.take(2).toList(),
                      summary: summary,
                      workLabel: '226/3 · Implantação',
                      periodLabel: 'Novembro 2026',
                      filter: TaskHoursFilter.all,
                      onBilling: (_) {},
                      selected: const {},
                      onSelect: (_, __) {},
                      onSelectAll: (_) {},
                      onAction: (_, __) {},
                      onSend: (_) {},
                      onRegisterHours: () {},
                      onRetry: () {})),
            ]))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('18/11/2026'), findsOneWidget);
        expect(find.text('17/11/2026'), findsOneWidget);
        expect(find.text('Apontamentos do projeto'), findsOneWidget);
      });
    }
  }

  testWidgets('cards select billing directly and Total clears it',
      (tester) async {
    TaskHoursFilter? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TaskPeriodCards(
                summary: TaskPeriodSummary(entries),
                filter: TaskHoursFilter.charged,
                onChanged: (value) => selected = value))));
    await tester.tap(find.text('Horas não cobradas'));
    expect(selected, TaskHoursFilter.nonCharged);
    await tester.tap(find.text('Total do período'));
    expect(selected, TaskHoursFilter.all);
  });

  testWidgets('table selection, edit and delete remain separate callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TaskLogAction? action;
    TimeLog? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TaskLogsTable(
                logs: [entries.first],
                selected: const {},
                onSelect: (log, _) => selected = log,
                onSelectAll: (_) {},
                onAction: (_, value) => action = value))));
    await tester.tap(find.byType(Checkbox).last);
    expect(selected, same(entries.first));
    await tester.tap(find.byTooltip('Editar apontamento'));
    expect(action, TaskLogAction.edit);
    await tester.tap(find.byTooltip('Excluir apontamento'));
    expect(action, TaskLogAction.delete);
    await tester.tap(find.byTooltip('Mais ações do apontamento'));
    await tester.pumpAndSettle();
    expect(find.text('Conferir e enviar ao E-Desk'), findsOneWidget);
    expect(find.text('Conferir apontamentos do dia'), findsOneWidget);
  });

  testWidgets('pending records cannot become a send just because selected',
      (tester) async {
    List<TimeLog>? sent;
    final pending = entries.last;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TaskWorkspacePanel(
                logs: [pending],
                summary: TaskPeriodSummary([pending]),
                workLabel: null,
                periodLabel: 'Hoje',
                filter: TaskHoursFilter.all,
                onBilling: (_) {},
                selected: {taskLogKey(pending)},
                onSelect: (_, __) {},
                onSelectAll: (_) {},
                onAction: (_, __) {},
                onSend: (logs) => sent = logs,
                onRegisterHours: () {},
                onRetry: () {}))));
    await tester.tap(find.text('Enviar seleção (0)'));
    expect(sent, isNull);
    expect(find.text('Apontamentos do período'), findsOneWidget);
  });

  testWidgets('work picker refuses stale results after account changes',
      (tester) async {
    var authorized = true;
    final completer = Completer<List<ProjectModel>>();
    await tester.pumpWidget(MaterialApp(
        home: TaskProjectPicker(
            loader: () => completer.future,
            authorized: () => authorized,
            logs: entries)));
    authorized = false;
    completer.complete([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Não foi possível carregar'), findsOneWidget);
    expect(find.text('226/3 · Implantação'), findsNothing);
  });

  testWidgets(
      'selecting only a pending record never falls back to sending other rows',
      (tester) async {
    List<TimeLog>? sent;
    final mixed = [entries.first, entries.last];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TaskWorkspacePanel(
                logs: mixed,
                summary: TaskPeriodSummary(mixed),
                workLabel: null,
                periodLabel: 'Hoje',
                filter: TaskHoursFilter.all,
                onBilling: (_) {},
                selected: {taskLogKey(entries.last)},
                onSelect: (_, __) {},
                onSelectAll: (_) {},
                onAction: (_, __) {},
                onSend: (logs) => sent = logs,
                onRegisterHours: () {},
                onRetry: () {}))));
    await tester.tap(find.text('Enviar seleção (0)'));
    expect(sent, isNull);
  });
}
