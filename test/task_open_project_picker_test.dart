import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/tasks/task_open_project_picker.dart';
import 'package:gerenciador_horas/features/tasks/task_log_search.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

ProjectModel project(String id, String client, {String status = 'INI_PRO'}) =>
    ProjectModel.fromJson({
      'id': id,
      'client': client,
      'status': status,
      'serviceType': 'Professional'
    });

void main() {
  testWidgets('searches active projects by ID and unaccented customer name',
      (tester) async {
    final rimo = project('2265173', 'Rimo Móveis');
    ProjectModel? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        selected = await showDialog<ProjectModel>(
                            context: context,
                            builder: (_) => TaskOpenProjectPicker(
                                  authorized: () => true,
                                  loader: () async => [
                                    rimo,
                                    project('2267266', 'Rennova'),
                                    project('1', 'Finalizado',
                                        status: 'TRAB_FIM'),
                                    project('2', 'Parado', status: 'TRAB_STOP')
                                  ],
                                ));
                      },
                      child: const Text('Buscar')),
                ))));
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();
    expect(find.text('Finalizado'), findsNothing);
    expect(find.text('Parado'), findsNothing);
    expect(find.text('Rennova'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2265173');
    await tester.pumpAndSettle();
    expect(find.text('Rennova'), findsNothing);
    await tester.enterText(find.byType(TextField), 'rimo moveis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rimo Móveis'));
    await tester.pumpAndSettle();
    expect(selected, same(rimo));
    final log = TimeLog(
        id: 'fixture',
        targetId: '2265173_4',
        projectId: '2265173',
        date: DateTime(2026, 11, 17),
        startTime: '08:00',
        endTime: '09:00',
        durationFormatted: '01:00',
        isRegistered: true);
    expect(taskLogMatches(log, '', openedTarget: selected!.id), true);
    expect(taskLogMatches(log, '', openedTarget: '2267266'), false);
  });

  testWidgets('never displays a late result after account change',
      (tester) async {
    var authorized = true;
    final response = Completer<List<ProjectModel>>();
    await tester.pumpWidget(MaterialApp(
        home: TaskOpenProjectPicker(
            authorized: () => authorized, loader: () => response.future)));
    await tester.pump();
    authorized = false;
    response.complete([project('123', 'Dados da conta anterior')]);
    await tester.pumpAndSettle();
    expect(find.text('Dados da conta anterior'), findsNothing);
    expect(find.textContaining('A conta mudou'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers retry after a failed read instead of an empty success',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: TaskOpenProjectPicker(
      authorized: () => true,
      loader: () async {
        if (++reads == 1) throw StateError('fixture offline');
        return [project('123', 'Cliente disponível')];
      },
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Não foi possível carregar'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Cliente disponível'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
