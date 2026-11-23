import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_documents_dialog.dart';

Map<String,dynamic> clockDocument({bool saved=false}) => {
  'revision':saved?'r2':'r1','timelineCalculationVersion':1,'warnings':[],'periods':[],
  'columns':[for(var i=0;i<11;i++) {'letter':String.fromCharCode(65+i),'label':'Coluna'}],
  'fields':[
    {'sheet':'Timeline','cell':'J19','kind':'number','value':saved?9/24:8/24,'timelineTime':true,'readOnly':false},
    {'sheet':'Timeline','cell':'K19','kind':'number','value':saved?2.5/24:10/24,'timelineTime':true,'timeDuration':true,'readOnly':false},
  ],
  'rows':[{'row':19,'date':'2026-11-17','startSeconds':saved?32400:28800,'durationSeconds':saved?9000:36000,
    'cells':[1,'Implantação','17/11/2026','','','','',3,'ET',saved?'09:00:00':'08:00:00',saved?'02:30:00':'10:00:00']}]
};

void main() {
  testWidgets('Start and duration save as numeric day values only after confirmation; Outlook action is visible', (tester) async {
    tester.view.physicalSize=const Size(1900,1000); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    var saved=false;
    final writes=<Map<String,dynamic>>[];
    await tester.pumpWidget(MaterialApp(home:ProjectDocumentsDialog(
      project:ProjectModel.fromJson({'id':'1','excelLink':'ref'}),uidProvider:()=> 'owner',
      transport:(args) async {
        if(args['operation']=='timeline-save') { writes.add(args);saved=true;return {'saved':true}; }
        return clockDocument(saved:saved);
      })));
    await tester.pumpAndSettle();
    expect(find.text('Outlook'),findsOneWidget);
    expect(find.text('Agendar'),findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('r1-timeline-clock-Timeline!J19')),'0900');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('r1-timeline-clock-Timeline!K19')),'02:30:00');
    await tester.pump();
    expect(writes,isEmpty);
    await tester.tap(find.text('Salvar na planilha'));
    await tester.pumpAndSettle();
    expect(writes,isEmpty);
    await tester.tap(find.widgetWithText(FilledButton,'Salvar na planilha').last);
    await tester.pumpAndSettle();
    final changes=writes.single['changes'] as List;
    expect(changes.singleWhere((c)=>c['cell']=='J19')['value'],9/24);
    expect(changes.singleWhere((c)=>c['cell']=='K19')['value'],2.5/24);
    expect(find.text('09:00:00'),findsOneWidget);
    expect(find.text('02:30:00'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
