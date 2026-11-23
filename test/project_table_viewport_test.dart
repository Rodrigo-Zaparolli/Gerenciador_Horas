import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/project_table_viewport.dart';

void main() {
  for (final width in [900.0, 1366.0, 1920.0]) {
    testWidgets('all rows and trailing actions fit at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ProjectTableViewport(
                      child: DataTable(
        columns: const [
          DataColumn(label: Text('Projeto')),
          DataColumn(label: Text('Cliente')),
          DataColumn(label: Text('Acoes')),
        ],
        rows: List.generate(
            20,
            (i) => DataRow(cells: [
                  DataCell(Text('Projeto $i')),
                  const DataCell(SizedBox(width: 950, child: Text('Cliente'))),
                  DataCell(IconButton(
                      key: ValueKey('delete-$i'),
                      onPressed: () {},
                      icon: const Icon(Icons.delete_outline))),
                ])),
      ))))));
      final viewport = tester.getRect(find.byType(ProjectTableViewport));
      for (var i = 0; i < 20; i++) {
        final action = tester.getRect(find.byKey(ValueKey('delete-$i')));
        expect(action.right, lessThanOrEqualTo(viewport.right + .1));
        expect(action.bottom, lessThanOrEqualTo(viewport.bottom + .1));
      }
      expect(viewport.height, greaterThan(300));
      expect(
          find.descendant(
              of: find.byType(ProjectTableViewport),
              matching: find.byType(Scrollable)),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
