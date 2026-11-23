import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_spreadsheet_dialog.dart';
import 'project_spreadsheet_dialog_test.dart' show snapshot;

void main() {
  for (final editType in [false, true]) {
    testWidgets('Update saves explicitly with template flag, changed type: $editType', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = snapshot();
      data['fields'] = <Map<String, dynamic>>[...(data['fields'] as List).cast<Map<String, dynamic>>()];
      data['implantationUpdateVersion'] = 1;
      (data['fields'] as List).add({'sheet': 'Informações de entrada', 'cell': 'C3',
        'label': 'Tipo Projeto', 'kind': 'text', 'group': 'Projeto', 'value': 'PROFESSIONAL',
        'choices': ['PROFESSIONAL', 'ENTERPRISE PRODUÇÃO COMPLETA']});
      final writes = <Map<String, dynamic>>[];
      await tester.pumpWidget(MaterialApp(home: ProjectSpreadsheetDialog(
        project: ProjectModel.fromJson({'id': '1', 'serviceType': 'Enterprise'}),
        uidProvider: () => 'owner', emailProvider: () => 'owner@example.test', contactsLoader: () async => [],
        transport: (args) async {
          if (args['action'] == 'excel-editor-preview') return {'preview': true, 'revision': 'v1', 'checklistSheet': 'Checklist-Processo', 'statusPreview': {'rows': []}};
          if (args['action'] == 'excel-editor-write') {
            writes.add(args);
            return {...data, 'revision': 'v2', 'saved': true, 'implantationUpdated': true};
          }
          return data;
        })));
      await tester.pumpAndSettle();
      if (editType) {
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('ENTERPRISE PRODUÇÃO COMPLETA').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Atualizar Planilha de Implantação'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.text('Salvar e atualizar'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single['updateImplantation'], true);
      expect((writes.single['changes'] as List).length, editType ? 1 : 0);
      expect(find.text('Salvo no Excel'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
