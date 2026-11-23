import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/jarvis/jarvis_request.dart';
import 'package:gerenciador_horas/features/jarvis/jarvis_review.dart';

final project=ProjectModel(id:'p1',id2:'123',client:'Café',serviceType:'Suporte',stage:'Execução',task:'Revisão',status:'Ativo',startDate:DateTime(2026,10,29),estimatedHours:'10',leader:'Teste',hourType:'Normal');
JarvisRequest request([String action='hours',String end='11:00']) => JarvisRequest(id:'a'*32,action:action,project:'123',body:'Revisar orçamento',start:'09:00',end:end,date:'29/10/2026');
Future<void> open(WidgetTester tester, JarvisRequest req, {
  Future<void> Function(ProjectModel,TimeLog)? save,
  void Function(ProjectModel,String)? comment,
  Future<void> Function(ProjectModel)? email,
  bool Function()? account,
}) async {
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context) => TextButton(onPressed:() => reviewJarvisRequest(context,req,projects:[project],accountCurrent:account ?? () => true,saveHours:save ?? (_,__) async {},openComment:comment ?? (_,__) {},openEmail:email ?? (_) async {}),child:const Text('Abrir'))))));
  await tester.tap(find.text('Abrir'));await tester.pumpAndSettle();
}
void main() {
  testWidgets('cancel never writes', (tester) async {
    var saves=0;await open(tester,request(),save:(_,__) async {saves++;});
    await tester.tap(find.text('Cancelar'));await tester.pumpAndSettle();expect(saves,0);
  });
  testWidgets('confirmed hours retain target, duration, date and stable id', (tester) async {
    final saved=<TimeLog>[];await open(tester,request(),save:(_,log) async {saved.add(log);});
    await tester.tap(find.text('Registrar horas'));await tester.pumpAndSettle();
    expect(saved,hasLength(1));expect(saved.single.projectId,'p1');expect(saved.single.targetId,'p1');
    expect(saved.single.durationMinutes,120);expect(saved.single.description,'Revisar orçamento');
    expect(saved.single.id,'jarvis_${'a'*32}');expect(saved.single.isRegistered,isTrue);
    expect(find.textContaining('Horas registradas no Gerenciador'),findsOneWidget);
  });
  testWidgets('invalid interval blocks write', (tester) async {
    var saves=0;await open(tester,request('hours','08:00'),save:(_,__) async {saves++;});
    await tester.tap(find.text('Registrar horas'));await tester.pumpAndSettle();expect(saves,0);
    expect(find.textContaining('O fim deve ser depois'),findsOneWidget);
  });
  testWidgets('changed account blocks write', (tester) async {
    var current=true;var saves=0;await open(tester,request(),save:(_,__) async {saves++;},account:() => current);
    current=false;await tester.tap(find.text('Registrar horas'));await tester.pumpAndSettle();expect(saves,0);
    expect(find.textContaining('A conta mudou'),findsOneWidget);
  });
  testWidgets('comment text reaches existing editor only after review', (tester) async {
    String? text;await open(tester,request('comment'),comment:(_,body) {text=body;});
    expect(text,isNull);await tester.tap(find.text('Continuar'));await tester.pumpAndSettle();expect(text,'Revisar orçamento');
  });
  testWidgets('email invokes draft preparation and discloses no automatic send', (tester) async {
    var opened=0;await open(tester,request('email'),email:(_) async {opened++;});
    expect(find.textContaining('não envia e-mail'),findsOneWidget);expect(opened,0);
    await tester.tap(find.text('Continuar'));await tester.pumpAndSettle();expect(opened,1);
  });
  testWidgets('double submission is blocked and failure can retry same id', (tester) async {
    final pending=Completer<void>();final ids=<String>[];
    await open(tester,request(),save:(_,log) {ids.add(log.id);return ids.length==1 ? pending.future : Future.value();});
    await tester.tap(find.text('Registrar horas'));await tester.pump();
    expect(find.text('Salvando…'),findsOneWidget);expect(ids,hasLength(1));
    pending.completeError(StateError('offline'));await tester.pumpAndSettle();
    expect(find.textContaining('Não foi possível confirmar'),findsOneWidget);
    await tester.tap(find.text('Registrar horas'));await tester.pumpAndSettle();
    expect(ids,hasLength(2));expect(ids[0],ids[1]);
  });
}
