import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/edesk/adv_project_picker.dart';

void main() {
  testWidgets('ADV picker searches by request ID and customer without creating work', (tester) async {
    final project = ProjectModel.fromJson({'id': '2263800', 'client': 'W de Ouro', 'serviceType': 'Enterprise'});
    ProjectModel? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body:
      TextButton(onPressed: () async { selected = await showAdvProjectPicker(context,
        authorized: () => true, loader: () async => [project,
          ProjectModel.fromJson({'id': '2266963', 'client': 'PROMAD'})]); }, child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2263800'); await tester.pumpAndSettle();
    expect(find.text('PROMAD'), findsNothing);
    await tester.enterText(find.byType(TextField), 'ouro'); await tester.pumpAndSettle();
    expect(find.text('W de Ouro'), findsOneWidget);
    await tester.tap(find.text('W de Ouro')); await tester.pumpAndSettle();
    expect(selected, same(project));
  });
}
