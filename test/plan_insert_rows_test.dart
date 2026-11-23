import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:gerenciador_horas/features/projects/dialogs/plan_sheet_editor.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_documents_dialog.dart';

Map<String, dynamic> plan({bool inserted = false, bool saved = false}) => {
  'revision': saved ? 'r2' : 'r1', 'planRowsVersion': 1, 'planLastRow': inserted ? 207 : 205,
  'fields': [
    {'sheet': 'Plano de Projeto', 'cell': 'B10', 'kind': 'text', 'value': 'Acordo existente'},
    if (inserted) {'sheet': 'Plano de Projeto', 'cell': 'B11', 'kind': 'text', 'value': saved ? 'Novo acordo' : ''},
  ],
  'mirror': {
    'imageBase64': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    'width': 800, 'height': 900, 'cells': [
      {'cell': 'B10', 'left': .1, 'top': .1, 'width': .7, 'height': .05},
      if (inserted) {'cell': 'B11', 'left': .1, 'top': .2, 'width': .7, 'height': .05},
    ]
  }
};

void main() {
  testWidgets('Right click selects exact row and inserts above or below only after choosing', (tester) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final inserted = <(int,int,bool)>[];
    final data = plan();
    (data['mirror'] as Map)['rows'] = [
      {'row':10,'top':.1,'height':.05},
      {'row':11,'top':.2,'height':.05},
    ];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:PlanSheetEditor(
      data:data,pending:const {},enabled:true,onChanged:(_,__) {},
      onInsertRows:(row,count,below) async { inserted.add((row,count,below)); }))));
    await tester.pumpAndSettle();
    final target=find.bySemanticsLabel('Editar célula B10: Acordo existente');
    await tester.tap(target,buttons:kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(inserted,isEmpty);
    expect(find.byKey(const ValueKey('selected-plan-row-10')),findsOneWidget);
    expect(find.text('Linha 10'),findsNWidgets(2));
    await tester.tap(find.text('Inserir linha acima'));
    await tester.pumpAndSettle();
    expect(inserted,[(10,1,false)]);
    await tester.tap(target,buttons:kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inserir linha abaixo'));
    await tester.pumpAndSettle();
    expect(inserted,[(10,1,false),(10,1,true)]);
    final image=tester.getTopLeft(find.byType(Image));
    await tester.tapAt(image+const Offset(20,200),buttons:kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Linha 11'),findsNWidgets(2));
    await tester.tap(find.text('Inserir linha acima'));
    await tester.pumpAndSettle();
    expect(inserted.last,(11,1,false));
    expect(tester.takeException(),isNull);
  });
  testWidgets('Inserting below previews new editable fields; save is explicit and retains row operation', (tester) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saved = false;
    final saves = <Map<String,dynamic>>[];
    await tester.pumpWidget(MaterialApp(home: ProjectDocumentsDialog(
      project: ProjectModel.fromJson({'id': '1', 'excelLink': 'ref'}), initialMode: 'plan', uidProvider: () => 'owner',
      transport: (args) async {
        if (args['operation'] == 'plan-preview') {
          final changes = args['changes'] as List;
          expect(changes.single['operation'], 'insert-plan-rows');
          expect(changes.single['row'], 11);
          expect(changes.single['count'], 2);
          return {...plan(inserted: true), 'planEditBaseline': plan(inserted: true), 'pdfBase64': 'JVBERi0xLjQK'};
        }
        if (args['operation'] == 'plan-save') {
          saves.add(args);
          saved = true;
          return {'saved':true};
        }
        return plan(inserted: saved, saved: saved);
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Editar célula B10: Acordo existente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inserir linhas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0');
    await tester.tap(find.text('Inserir na prévia'));
    await tester.pumpAndSettle();
    expect(find.text('Informe de 1 a 20 linhas.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.tap(find.text('Inserir na prévia'));
    await tester.pumpAndSettle();
    expect(saves, isEmpty);
    await tester.tap(find.bySemanticsLabel('Editar célula B11: '));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Novo acordo');
    await tester.pump();
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(saves, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar na planilha').last);
    await tester.pumpAndSettle();
    final changes = saves.single['changes'] as List;
    expect(changes.where((c) => c['operation'] == 'insert-plan-rows'), hasLength(1));
    expect(changes.singleWhere((c) => c['cell'] == 'B11')['value'], 'Novo acordo');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
