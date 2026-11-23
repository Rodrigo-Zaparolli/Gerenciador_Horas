import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_documents_dialog.dart';
import 'timeline_schedule_test.dart' show schedule;

Map<String, dynamic> document({int days = 3}) {
  final data = schedule();
  data.addAll({'revision': 'r1', 'timelineCalculationVersion': 1, 'warnings': [],
    'columns': [for (var i=0; i<11; i++) {'letter': String.fromCharCode(65+i), 'label': 'Coluna'}]});
  for (final f in (data['fields'] as List).whereType<Map>()) {
    if ('${f['cell']}'.startsWith('H')) { f['timelineDays'] = true; f['kind'] = 'number'; f['readOnly'] = false; }
  }
  final rows = data['rows'] as List;
  rows[0]['cells'][7] = days;
  rows[1]['date'] = '2026-11-${14+days}';
  rows[2]['date'] = '2026-11-${17+days}';
  return data;
}

Finder daysField() => find.byWidgetPredicate((w) => w is TextFormField && w.key is ValueKey && '${(w.key as ValueKey).value}'.contains('Timeline!H19')).first;

void main() {
  testWidgets('Automatic date calculation ignores obsolete replies and never saves', (tester) async {
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = Completer<Map<String,dynamic>>();
    final calls = <String>[];
    var calculations = 0;
    await tester.pumpWidget(MaterialApp(home: ProjectDocumentsDialog(
      project: ProjectModel.fromJson({'id': '1', 'excelLink': 'ref'}), uidProvider: () => 'owner',
      transport: (args) async {
        calls.add(args['operation'] as String);
        if (args['operation'] == 'timeline-calculate') {
          calculations++;
          if (calculations == 1) return first.future;
          return document(days: 5);
        }
        return document();
      },
    )));
    await tester.pumpAndSettle();
    final originalFieldElement = tester.element(daysField());
    await tester.enterText(daysField(), '4');
    await tester.pump();
    expect(tester.element(daysField()), same(originalFieldElement));
    expect(find.text('18/11/2026'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 850));
    await tester.enterText(daysField(), '5');
    await tester.pump();
    expect(find.text('19/11/2026'), findsOneWidget);
    final obsolete = document(days: 4);
    (obsolete['rows'] as List)[1]['date'] = '2099-01-01';
    first.complete(obsolete);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(calculations, 2);
    expect(find.text('01/01/2099'), findsNothing);
    expect(find.text('19/11/2026'), findsOneWidget);
    expect(calls, isNot(contains('timeline-save')));
    await tester.enterText(daysField(), '3');
    await tester.pump();
    expect(find.text('17/11/2026'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
