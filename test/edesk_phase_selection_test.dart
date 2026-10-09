import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/tabela_projetos_widget.dart';

class _UnusedFirebaseService extends Fake implements FirebaseService {}

class _RecordingEdesk extends Fake implements EdeskService {
  final sends = <List<Map<String, String>>>[];
  @override
  Future<EdeskSendResult> atualizarFasesViaPython(
      {required String id,
      required String cliente,
      required List<Map<String, String>> fases,
      void Function(bool, String)? onConcluido}) async {
    sends.add(fases);
    onConcluido?.call(true, 'Concluido');
    return const EdeskSendResult(
        confirmed: true,
        statusCode: 200,
        message: 'Concluido',
        responseBody: '');
  }
}

void main() {
  testWidgets(
      'Edit modal sends selected phases or all and preserves individual selection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final horizontal = ScrollController();
    final vertical = ScrollController();
    addTearDown(horizontal.dispose);
    addTearDown(vertical.dispose);
    final edesk = _RecordingEdesk();
    final date = DateTime(2026, 10, 8);
    final project = ProjectModel(
        id: 'project',
        id2: '',
        client: 'Cliente',
        serviceType: 'Servico',
        stage: 'Etapa',
        task: '',
        status: 'TRAB',
        startDate: date,
        estimatedHours: '03:00',
        leader: '',
        hourType: 'Hs Cobradas',
        subTasks: [
          for (var i = 0; i < 3; i++)
            TaskModel(
                subId: '$i',
                stage: 'Fase $i',
                status: 'TRAB',
                startDate: date,
                planEnd: DateTime(2026, 10, 10),
                estimatedHours: '01:00',
                hourType: 'Hs Cobradas'),
        ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: TabelaProjetosWidget(
        projects: [project],
        statusList: const ['TRAB'],
        expandedProjectIds: const {},
        selectedTargetId: 'project',
        timeLogs: const [],
        activeTimerTargetId: null,
        activeStartTime: null,
        timerState: TimerState.stopped,
        secondsElapsed: 0,
        showPostStopButton: false,
        horizontalController: horizontal,
        verticalController: vertical,
        onSelectTarget: (_) {},
        onToggleExpand: (_) {},
        onEditProject: (_) {},
        onDeleteProject: (_) {},
        onAddSubTask: (_) {},
        onProjectStatusChanged: (_, __) {},
        onSubTaskStatusChanged: (_, __) {},
        onEditSubTask: (_, __) {},
        onDeleteSubTask: (_, __) {},
        onStartTimer: (_) {},
        onPauseTimer: () {},
        onStopTimer: () {},
        onManualTime: (_) {},
        onEditLog: (_) {},
        onSaveLogDescription: (_, __) async {},
        onDeleteLog: (_) {},
        onRegisterLog: (_) {},
        onMarkTaskCompleted: (_) {},
        formatDuration: (_) => '01:00',
        firebaseService: _UnusedFirebaseService(),
        edeskService: edesk,
      ),
    )));

    await tester.ensureVisible(find.byTooltip('Editar Trabalho'));
    await tester.tap(find.byTooltip('Editar Trabalho'));
    await tester.pump(const Duration(milliseconds: 400));
    final update = find.text('Atualizar Fases E-Desk');
    await tester.ensureVisible(update);
    await tester.tap(update);
    await tester.pump(const Duration(milliseconds: 400));
    expect(edesk.sends, isEmpty);
    for (final index in [2, 0]) {
      final checkbox = find.byKey(ValueKey('edesk-phase-$index'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pump();
    }
    expect(find.text('2 de 3 fases para enviar'), findsOneWidget);
    await tester.ensureVisible(update);
    await tester.tap(update);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        edesk.sends.single.map((fase) => fase['nome']), ['Fase 0', 'Fase 2']);
    expect(edesk.sends.single.first['dataInicial'], '08/10/26');
    expect(edesk.sends.single.first['dataFinal'], '10/10/26');
    final mode = find.byKey(const ValueKey('edesk-phase-mode'));
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Enviar todas as fases').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('3 de 3 fases para enviar'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      final checkbox =
          tester.widget<Checkbox>(find.byKey(ValueKey('edesk-phase-$i')));
      expect(checkbox.value, isTrue);
      expect(checkbox.onChanged, isNull);
    }
    await tester.ensureVisible(update);
    await tester.tap(update);
    await tester.pump(const Duration(milliseconds: 400));
    expect(edesk.sends.last.map((fase) => fase['nome']),
        ['Fase 0', 'Fase 1', 'Fase 2']);
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Enviar fases selecionadas').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 de 3 fases para enviar'), findsOneWidget);
    expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('edesk-phase-1')))
            .value,
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
