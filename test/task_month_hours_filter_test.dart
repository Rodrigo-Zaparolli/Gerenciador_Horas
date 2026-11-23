import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/task_history_month.dart';
import 'package:gerenciador_horas/features/tasks/task_history_month_panel.dart';
import 'package:gerenciador_horas/features/tasks/task_hours_filter.dart';

TimeLog entry(String name, String? type, int minutes, {int month = 11}) =>
    TimeLog(
      id: name,
      targetId: '2267266_2',
      projectId: '2267266',
      date: DateTime(2026, month, 17),
      startTime: '08:00',
      endTime: '09:00',
      durationFormatted: '',
      durationMinutes: minutes,
      typeHs: type,
      projectName: name,
      taskName: 'Implantação',
      isRegistered: true,
    );

void main() {
  test('filters agree with existing monthly charged and non-charged totals',
      () {
    final logs = [
      entry('cobrada', 'Hs Cobradas', 60),
      entry('não cobrada', 'Hs Não Cobradas', 30),
      entry('legado', 'HS NAO COBRADAS', 15),
      entry('interna', 'Hs Internas', 5),
      entry('sem tipo', null, 1),
      entry('outro mês', 'Hs Cobradas', 900, month: 10)
    ];
    final month = TaskHistoryMonth(2026, 11, logs);
    final charged = month.logs.where(
        (log) => taskLogMatchesHoursFilter(log, TaskHoursFilter.charged));
    final nonCharged = month.logs.where(
        (log) => taskLogMatchesHoursFilter(log, TaskHoursFilter.nonCharged));
    expect(charged.map((e) => e.projectName), ['cobrada']);
    expect(nonCharged.map((e) => e.projectName),
        ['não cobrada', 'legado', 'interna', 'sem tipo']);
    expect(month.chargedMinutes, 60);
    expect(month.minutes - month.chargedMinutes, 51);
    expect(charged.length + nonCharged.length, month.logs.length);
  });

  testWidgets('month cards filter rows and keep both monthly totals available',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final logs = [
      entry('Cliente cobrado', 'Hs Cobradas', 60),
      entry('Cliente não cobrado', 'Hs Não Cobradas', 30),
      entry('Outro mês', 'Hs Cobradas', 900, month: 10)
    ];
    var filter = TaskHoursFilter.all;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
              builder: (_, setState) => TaskHistoryMonthPanel(
                    data: TaskHistoryMonth(
                        2026,
                        11,
                        logs.where(
                            (log) => taskLogMatchesHoursFilter(log, filter))),
                    summaryData: TaskHistoryMonth(2026, 11, logs),
                    hoursFilter: filter,
                    onHoursFilterChanged: (value) =>
                        setState(() => filter = value),
                    onSelectDay: (_) {},
                    onEdit: (_) {},
                  )),
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Horas cobradas'));
    await tester.pumpAndSettle();
    expect(filter, TaskHoursFilter.charged);
    var panel = tester
        .widget<TaskHistoryMonthPanel>(find.byType(TaskHistoryMonthPanel));
    expect(panel.data.logs.map((e) => e.projectName), ['Cliente cobrado']);
    expect(panel.summaryData!.minutes, 90);
    expect(panel.summaryData!.chargedMinutes, 60);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    await tester.tap(find.text('Não cobradas'));
    await tester.pumpAndSettle();
    panel = tester
        .widget<TaskHistoryMonthPanel>(find.byType(TaskHistoryMonthPanel));
    expect(panel.data.logs.map((e) => e.projectName), ['Cliente não cobrado']);
    expect(panel.summaryData!.minutes, 90);
    await tester.tap(find.text('Total do mês').first);
    await tester.pumpAndSettle();
    panel = tester
        .widget<TaskHistoryMonthPanel>(find.byType(TaskHistoryMonthPanel));
    expect(filter, TaskHoursFilter.all);
    expect(panel.data.logs.length, 2);
    expect(panel.data.logs.any((e) => e.projectName == 'Outro mês'), false);
    expect(tester.takeException(), isNull);
  });
}
