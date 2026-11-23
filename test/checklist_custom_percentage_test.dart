import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_stage_dialog.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_percentage_field.dart';

void main() {
  testWidgets('custom parent percentage propagates; child can override it',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, double>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      child: const Text('Open'),
                      onPressed: () async {
                        result = await showDialog<Map<String, double>>(
                            context: context,
                            builder: (_) => ChecklistStageDialog(
                                  stage: 'Implantação',
                                  expandableBlocks: true,
                                  canApply: () => true,
                                  values: const {},
                                  tasks: const [
                                    {
                                      'sheet': 'Checklist',
                                      'cell': 'E1',
                                      'label': 'First',
                                      'blockId': 'B',
                                      'block': 'Parent'
                                    },
                                    {
                                      'sheet': 'Checklist',
                                      'cell': 'E2',
                                      'label': 'Second',
                                      'blockId': 'B',
                                      'block': 'Parent'
                                    },
                                  ],
                                ));
                      }),
                ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final parent = find.byWidgetPredicate((w) =>
        w is ChecklistPercentageInput &&
        w.key.toString().contains('stage-block-'));
    await tester.enterText(
        find.descendant(of: parent, matching: find.byType(TextFormField)),
        '15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('15%'), findsNWidgets(3));
    final child = find.byWidgetPredicate((w) =>
        w is ChecklistPercentageInput &&
        w.key.toString().contains('stage-percent-Checklist!E2-'));
    final childInput =
        find.descendant(of: child, matching: find.byType(TextFormField));
    await tester.enterText(childInput, '101');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Use 0 a 100'), findsOneWidget);
    await tester.tap(find.text('Aplicar ajustes')); await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.enterText(childInput, '10,5');
    await tester.tap(find.text('Aplicar ajustes'));
    await tester.pumpAndSettle();
    expect(result!['Checklist!E1'], .15);
    expect(result!['Checklist!E2'], .105);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick choices remain beside the directly editable percentage',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChecklistStageDialog(
      stage: 'Test',
      canApply: () => true,
      values: const {'Checklist!E1': .25},
      tasks: const [
        {'sheet': 'Checklist', 'cell': 'E1', 'label': 'Task'}
      ],
    ))));
    final control = find.byType(ChecklistPercentageInput);
    expect(find.descendant(of: control, matching: find.byType(TextFormField)),
        findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<double>));
    await tester.pumpAndSettle();
    for (final text in ['0%', '25%', '50%', '75%', '100%']) {
      expect(find.text(text), findsWidgets);
    }
    await tester.tap(find.text('75%').last);
    await tester.pumpAndSettle();
    expect(find.text('75%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
