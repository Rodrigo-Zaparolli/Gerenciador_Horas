import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/tabela_projetos_widget.dart';

class _UnusedFirebaseService extends Fake implements FirebaseService {}

void main() {
  for (final closeBeforeSave in [false, true]) {
    testWidgets(
      'Inline log comment saves without opening editor; close=$closeBeforeSave',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final horizontal = ScrollController();
        final vertical = ScrollController();
        addTearDown(horizontal.dispose);
        addTearDown(vertical.dispose);
        final date = DateTime(2099, 1, 1);
        final project = ProjectModel(
          id: 'project',
          id2: '',
          client: 'Cliente',
          serviceType: 'Servico',
          stage: 'Etapa',
          task: '',
          status: 'TRAB',
          startDate: date,
          estimatedHours: '01:00',
          leader: '',
          hourType: 'Hs Cobradas',
          subTasks: [
            TaskModel(
              subId: '1',
              stage: 'Etapa',
              status: 'TRAB',
              startDate: date,
              estimatedHours: '01:00',
              hourType: 'Hs Cobradas',
            )
          ],
        );
        final log = TimeLog(
          id: 'log',
          targetId: 'project_1',
          date: date,
          startTime: '09:00',
          endTime: '10:00',
          durationFormatted: '01:00',
          isRegistered: false,
        );
        final saving = Completer<void>();
        String? savedDescription;
        TimeLog? savedLog;
        var editorOpened = false;
        var deleteRequested = false;
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
          body: TabelaProjetosWidget(
            projects: [project],
            statusList: const ['TRAB'],
            expandedProjectIds: const {'project'},
            selectedTargetId: 'project',
            timeLogs: [log],
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
            onEditLog: (_) {
              editorOpened = true;
            },
            onSaveLogDescription: (item, description) async {
              savedLog = item;
              savedDescription = description;
              await saving.future;
            },
            onDeleteLog: (_) {
              deleteRequested = true;
            },
            onRegisterLog: (_) {},
            onMarkTaskCompleted: (_) {},
            formatDuration: (_) => '01:00',
            firebaseService: _UnusedFirebaseService(),
          ),
        )));
        final field =
            find.widgetWithText(TextField, 'Comentário do registro...');
        await tester.enterText(field, '  Revisado  ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(savedLog, same(log));
        expect(savedDescription, 'Revisado');
        expect(editorOpened, isFalse);
        if (closeBeforeSave) {
          await tester.pumpWidget(const SizedBox.shrink());
        }
        saving.complete();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        if (!closeBeforeSave) {
          expect(find.text('Comentário do registro salvo com sucesso!'),
              findsOneWidget);
          await tester.ensureVisible(find.byTooltip('Excluir Apontamento'));
          await tester.tap(find.byTooltip('Excluir Apontamento'));
          await tester.pump();
          expect(deleteRequested, isTrue);
          expect(field, findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
