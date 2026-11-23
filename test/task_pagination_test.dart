import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/task_logs_table.dart';

void main() {
  testWidgets('editing on a later page preserves the real log identity', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final logs = List.generate(15, (i) => TimeLog(
      id: 'log-$i', targetId: '900001_2', projectId: '900001',
      date: DateTime(2026, 11, 23), startTime: '08:00', endTime: '09:00',
      durationFormatted: '01:00', durationMinutes: 60, isRegistered: true,
      description: 'Registro $i', projectName: 'Teste', taskName: 'Etapa',
      typeHs: 'Hs Cobradas'));
    String? edited;
    Widget page(List<TimeLog> entries) => MaterialApp(home: Scaffold(body: TaskLogsTable(
      logs: entries, selected: const {}, onSelect: (_, __) {}, onSelectAll: (_) {},
      onAction: (log, action) { if(action == TaskLogAction.edit) edited = log.id; })));
    await tester.pumpWidget(page(logs));
    await tester.pumpAndSettle();
    expect(find.text('Registro 10'), findsNothing);
    await tester.tap(find.byTooltip('Próxima página'));
    await tester.pumpAndSettle();
    expect(find.text('Registro 10'), findsOneWidget);
    await tester.tap(find.byTooltip('Editar apontamento').first);
    expect(edited, 'log-10');
    await tester.pumpWidget(page(logs.take(3).toList()));
    await tester.pumpAndSettle();
    expect(find.text('Registro 0'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
