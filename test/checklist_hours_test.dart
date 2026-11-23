import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_hours.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_hours_button.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_form_dialog.dart';

Map<String,dynamic> fixture() => {'checklistHoursVersion':1,'filename':'Projeto.xlsm','tasks':[
  {'sheet':'Checklist','cell':'E10','group':'Contato Inicial','estimatedMinutes':60,'estimatedValid':true},
  {'sheet':'Checklist','cell':'E11','group':'Contato Inicial','estimatedMinutes':30,'estimatedValid':true},
  {'sheet':'Checklist','cell':'E12','group':'Pós-Implantação (OH)','estimatedMinutes':45,'estimatedValid':true},
]};
const stages=[ChecklistHoursStage('Contato inicial','08:00'),ChecklistHoursStage('Pós Implantação','17:00'),ChecklistHoursStage('Desenvolvimento','20:00')];

void main() {
  test('Sums estimates by named phase, preserves missing phases, no positional matching',(){
    final plan=ChecklistHoursComparison.build(fixture(),stages.reversed.toList());
    expect(plan.rows[0].warning,isNotNull);
    expect(plan.rows[0].minutes,isNull);
    expect(plan.rows[1].minutes,45);
    expect(plan.rows[2].minutes,90);
    expect(plan.rows[2].count,2);
  });
  test('Invalid estimate is not treated as zero or a partial known total',(){
    final data=fixture();(data['tasks'] as List)[1]['estimatedValid']=false;
    final plan=ChecklistHoursComparison.build(data,stages);
    expect(plan.rows[0].minutes,isNull);expect(plan.rows[0].selectable,false);
    expect(plan.rows[1].selectable,true);
  });
  test('Duplicate destinations and duplicate source cells cannot be guessed',(){
    final plan=ChecklistHoursComparison.build(fixture(),[stages[1],const ChecklistHoursStage('Pós-Implantação (OH)','00:00')]);
    expect(plan.rows.every((r)=>!r.selectable),true);
    final data=fixture();(data['tasks'] as List).add((data['tasks'] as List).first);
    expect(()=>ChecklistHoursComparison.build(data,stages),throwsStateError);
  });
  test('Requires a fresh-capability snapshot; durations can exceed 99 hours',(){
    expect(()=>ChecklistHoursComparison.build({'tasks':[]},stages),throwsStateError);
    final input=HoursInputFormatter().formatEditUpdate(TextEditingValue.empty,const TextEditingValue(text:'12000'));
    expect(input.text,'120:00');
  });
  for(final changeAccount in [false,true]) {
    testWidgets('Review applies only selected hours; account changed: $changeAccount',(tester)async{
      tester.view.physicalSize=const Size(1100,1000);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      String? uid='owner';Map<int,int>? applied;
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:ChecklistHoursButton(
        uidProvider:()=>uid,stages:()=>stages,sourceToken:()=>'project/file',load:()async=>fixture(),apply:(value)=>applied=value))));
      await tester.tap(find.text('Atualizar horas pelo checklist'));await tester.pumpAndSettle();
      expect(find.text('Aplicar nas etapas'),findsOneWidget);
      expect(applied,isNull);
      if(changeAccount) {
        uid=null;await tester.pump(const Duration(seconds:1));await tester.pumpAndSettle();
        expect(find.text('Aplicar nas etapas'),findsNothing);expect(applied,isNull);
      } else {
        await tester.tap(find.byType(Checkbox).at(1));await tester.pumpAndSettle();
        await tester.tap(find.text('Aplicar nas etapas'));await tester.pumpAndSettle();
        expect(applied,{0:90});
      }
      expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('Changing source while reading never overwrites hours',(tester)async{
    final result=Completer<Map<String,dynamic>>();var source='file-a';var applied=false;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ChecklistHoursButton(uidProvider:()=>'owner',
      stages:()=>stages,sourceToken:()=>source,load:()=>result.future,apply:(_)=>applied=true))));
    await tester.tap(find.text('Atualizar horas pelo checklist'));await tester.pump();source='file-b';
    result.complete(fixture());await tester.pumpAndSettle();
    expect(find.text('Não foi possível atualizar as horas'),findsOneWidget);expect(applied,false);
    await tester.tap(find.text('Entendi'));await tester.pumpAndSettle();await tester.pumpWidget(const SizedBox());
  });
}
