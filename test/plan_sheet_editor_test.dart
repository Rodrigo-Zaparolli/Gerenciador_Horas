import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/plan_sheet_editor.dart';

void main() {
  test('Inserting rows shifts existing text drafts while keeping earlier insertion coordinates', () {
    final edits = <String, Map<String, dynamic>>{
      'Plano!B109': {'sheet':'Plano','cell':'B109','before':'old','value':'upper'},
      'Plano!B110': {'sheet':'Plano','cell':'B110','before':'old','value':'shifted'},
      'earlier': {'operation':'insert-plan-rows','row':50,'count':2},
    };
    final shifted = shiftPlanEdits(edits, 110, 2);
    expect(shifted['Plano!B109']!['value'], 'upper');
    expect(shifted['Plano!B112']!['value'], 'shifted');
    expect(shifted['Plano!B112']!['before'], 'old');
    expect(shifted['earlier']!['row'], 50);
    expect(edits['Plano!B110']!['cell'], 'B110');
  });
  testWidgets('Actual sheet image edits only mapped cells, preserves pending values and zoom', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = <String, Map<String, dynamic>>{};
    List<String>? removed;
    final data = <String, dynamic>{'revision': 'r1', 'planGuidanceVersion': 1, 'fields': [
      {'sheet': 'Plano de Projeto', 'cell': 'B10', 'value': 'Texto original'}
    ], 'mirror': {
      'imageBase64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      'width': 800, 'height': 900,
      'adjustmentNotes': [{'name': 'Seta', 'text': 'Ajustar'}],
      'cells': [{'cell': 'B10', 'left': .1, 'top': .1, 'width': .7, 'height': .1,
        'fontSize': 11, 'fontColor': 0, 'fillColor': 16777215}]
    }};
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlanSheetEditor(
      data: data, pending: pending, enabled: true, onRemoveGuidance: (names) async { removed = names; }, onChanged: (field, value) {
        pending['${field['sheet']}!${field['cell']}'] = {...field, 'value': value};
      }))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('1 indicação de ajuste'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.bySemanticsLabel('Editar célula B10: Texto original'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Acordo revisado');
    expect(pending['Plano de Projeto!B10']?['value'], 'Acordo revisado');
    await tester.tap(find.byTooltip('Aumentar zoom'));
    await tester.pumpAndSettle();
    expect(find.text('110%'), findsOneWidget);
    expect(find.text('Acordo revisado'), findsOneWidget);
    expect(removed, isNull);
    await tester.tap(find.text('Remover setas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover todas as orientações'));
    await tester.pumpAndSettle();
    expect(removed, ['Seta']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Old integration never falls back to editing unrelated label fields', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlanSheetEditor(
      data: const {'fields': []}, pending: const {}, enabled: true, onChanged: (_, __) {}))));
    expect(find.textContaining('Atualize a integração'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
}
