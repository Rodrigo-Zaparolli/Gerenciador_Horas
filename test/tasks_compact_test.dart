import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/tasks/task_filters_bar.dart';
import 'package:gerenciador_horas/features/tasks/task_history_month.dart';
import 'package:gerenciador_horas/features/tasks/task_hours_filter.dart';
import 'package:gerenciador_horas/features/tasks/task_log_query.dart';
import 'package:gerenciador_horas/features/tasks/task_logs_table.dart';
import 'package:gerenciador_horas/features/tasks/task_overview_header.dart';
import 'package:gerenciador_horas/features/tasks/task_period_cards.dart';
import 'package:gerenciador_horas/features/tasks/task_period_summary.dart';
import 'package:gerenciador_horas/features/tasks/task_work_picker.dart';
import 'package:gerenciador_horas/features/tasks/task_workspace_panel.dart';

TimeLog entry(String id, String target, DateTime day,
        {String? parent, bool charged = true}) =>
    TimeLog(
        id: id,
        targetId: target,
        projectId: parent,
        date: day,
        startTime: '08:00',
        endTime: '09:00',
        durationFormatted: '01:00',
        isRegistered: true,
        projectName: 'Cliente de exemplo',
        taskName: 'Etapa $id',
        description: 'Atividade $id',
        typeHs: charged ? 'Hs Cobradas' : 'Hs Não Cobradas');

void main() {
  test(
      'a project includes all work numbers and preserves month and billing filters',
      () {
    final logs = [
      for (var work = 1; work <= 5; work++)
        entry('$work', '226_$work', DateTime(2026, 11, 17),
            parent: '226', charged: work.isEven),
      entry('old', '226_2', DateTime(2026, 10, 17), parent: '226'),
      entry('other', '2260_1', DateTime(2026, 11, 17), parent: '2260'),
    ];
    final all = filterTaskLogs(logs, projectId: '226');
    expect(all.length, 6);
    final month = filterTaskLogs(logs,
        projectId: '226',
        start: DateTime(2026, 11),
        end: DateTime(2026, 12, 0));
    expect(month.length, 5);
    expect(month.map((e) => e.targetId).toSet(),
        {'226_1', '226_2', '226_3', '226_4', '226_5'});
    expect(filterTaskLogs(month, billing: TaskHoursFilter.charged).length, 2);
    expect(
        filterTaskLogs(month, billing: TaskHoursFilter.nonCharged).length, 3);
    expect(TaskPeriodSummary(all).projects.length, 1);
    expect(
        logs.length, 7); // Queries never mutate or delete the original records.
  });

  test(
      'request aliases only match legacy records without an explicit different parent',
      () {
    final day = DateTime(2026, 11, 17);
    final logs = [
      entry('legacy', '227_9', day),
      entry('bound', '227_10', day, parent: '226'),
      entry('other', '227_11', day, parent: 'another-project')
    ];
    final result =
        filterTaskLogs(logs, projectId: '226', projectRequests: {'227'});
    expect(result.map((e) => e.id).toSet(), {'legacy', 'bound'});
  });

  test(
      'historical calendar exposes unloaded months and does not fabricate logs',
      () {
    final logs = [entry('nov', '226_1', DateTime(2026, 11, 17))];
    final tree = taskHistoryCalendar(logs, 2026);
    expect(tree[2026]!.keys.toSet(),
        {for (var month = 1; month <= 12; month++) month});
    expect(tree[2026]![10]!.values.expand((e) => e), isEmpty);
    expect(tree[2026]![11]!.values.expand((e) => e).single, same(logs.single));
    expect(taskHistoryCalendar(logs, 2025).keys, containsAll([2025, 2026]));
    expect(logs.single.date, DateTime(2026, 11, 17));
  });

  testWidgets('picker returns one parent project with all work requests',
      (tester) async {
    final model = ProjectModel.fromJson({
      'id': '226',
      'client': 'Cliente de exemplo',
      'subTasks': [
        for (var i = 1; i <= 5; i++) {'subId': '$i', 'stage': 'Etapa $i'}
      ]
    });
    TaskProjectChoice? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showDialog<TaskProjectChoice>(
                      context: context,
                      builder: (_) => TaskProjectPicker(
                          loader: () async => [model],
                          authorized: () => true,
                          logs: const []));
                },
                child: const Text('Selecionar')))));
    await tester.tap(find.text('Selecionar'));
    await tester.pumpAndSettle();
    expect(find.text('226 · Cliente de exemplo'), findsOneWidget);
    expect(find.text('5 trabalhos · Todos incluídos'), findsOneWidget);
    expect(find.text('Etapa 1'), findsNothing);
    await tester.tap(find.text('226 · Cliente de exemplo'));
    await tester.pumpAndSettle();
    expect(selected!.id, '226');
    expect(selected!.works.length, 5);
  });

  for (final visual in [AppVisualTheme.light, AppVisualTheme.black]) {
    testWidgets('compact desktop gives the table more space in $visual',
        (tester) async {
      tester.view.physicalSize = const Size(1360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppAppearance.instance.value = visual;
      final logs = [
        for (var i = 0; i < 15; i++)
          entry('$i', '226_${i + 1}', DateTime(2026, 11, 17), parent: '226')
      ];
      final summary = TaskPeriodSummary(logs);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      TaskHoursFilter? billing;
      await tester.pumpWidget(MaterialApp(
          theme:
              visual == AppVisualTheme.light ? AppTheme.light : AppTheme.dark,
          home: Scaffold(
            appBar: AppBar(
                toolbarHeight: 68, title: const Text('Navegação preservada')),
            body: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  TaskOverviewHeader(
                      summary: summary,
                      onPdf: () {},
                      onBilling: (v) => billing = v),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
                  Expanded(
                      child: Row(children: [
                    const SizedBox(width: 225),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TaskWorkspacePanel(
                            logs: logs,
                            summary: summary,
                            workLabel: null,
                            periodLabel: 'Novembro 2026',
                            filter: TaskHoursFilter.all,
                            onBilling: (_) {},
                            selected: const {},
                            onSelect: (_, __) {},
                            onSelectAll: (_) {},
                            onAction: (_, __) {},
                            onSend: (_) {},
                            onRegisterHours: () {},
                            onRetry: () {},
                            onToggleHistory: () {}))
                  ])),
                ])),
          )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(TaskOverviewHeader)).height,
          lessThanOrEqualTo(96));
      expect(
          tester.getSize(find.byType(TaskLogsTable)).height, greaterThan(420));
      expect(find.byType(TaskPeriodCards), findsNothing);
      await tester.tap(find.text('COBRADAS'));
      expect(billing, TaskHoursFilter.charged);
    });
  }
}
