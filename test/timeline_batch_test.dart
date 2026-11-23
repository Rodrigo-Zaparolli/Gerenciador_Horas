import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/timeline_schedule.dart';
import 'package:gerenciador_horas/features/projects/dialogs/timeline_batch_dialog.dart';

Map<String,dynamic> row(int id, {bool invalid=false}) => {
  'row':id,'date':invalid?'2026-02-30':'2026-11-17',
  'cells':<dynamic>[id,'Etapa $id','','Descrição','','','','','',23/24,3/24],
};

void main() {
  test('single calendar contains all valid independent overnight events', () {
    final source=[row(19),row(20),row(21,invalid:true)];
    final batch=TimelineCalendarBatch.fromRows(source);
    source[0]['date']='2020-01-01';
    expect(batch.valid.length,2);
    expect(batch.invalid.length,1);
    final file=batch.ics(projectId:'123',client:'Cliente',revision:'rev');
    expect('BEGIN:VCALENDAR'.allMatches(file).length,1);
    expect('BEGIN:VEVENT\r\n'.allMatches(file).length,2);
    expect('END:VEVENT\r\n'.allMatches(file).length,2);
    expect(file,contains('UID:123-19-rev@gerenciador-horas'));
    expect(file,contains('UID:123-20-rev@gerenciador-horas'));
    expect(file,contains('DTEND:20261118T020000'));
  });
  test('invalid identity rejected and empty batches cannot export', () {
    expect(()=>TimelineCalendarBatch.fromRows([row(19),row(19)]),throwsStateError);
    expect(()=>TimelineCalendarBatch.fromRows([{}]),throwsStateError);
    final batch=TimelineCalendarBatch.fromRows([row(19,invalid:true)]);
    expect(()=>batch.ics(projectId:'1',client:'C',revision:'r'),throwsStateError);
    final missing=row(20); (missing['cells'] as List)[1]=null;
    expect(TimelineCalendarBatch.fromRows([missing]).valid,isEmpty);
  });
  test('event-like title content cannot truncate calendar events', () {
    final item=row(19); (item['cells'] as List)[1]='END:VEVENT';
    (item['cells'] as List)[3]='hello\r\nEND:VEVENT\r\nBEGIN:VEVENT';
    final file=TimelineCalendarBatch.fromRows([item,row(20)]).ics(projectId:'1',client:'C',revision:'r');
    expect(RegExp(r'^END:VEVENT$',multiLine:true).allMatches(file.replaceAll('\r','')).length,2);
    expect(file,contains(r'DESCRIPTION:Solicitação 1\nhello\nEND:VEVENT\nBEGIN:VEVENT'));
  });
  testWidgets('review requires acknowledgment and final action; stale state blocks export', (tester) async {
    var prepared=0; var current=true;
    final batch=TimelineCalendarBatch.fromRows([row(19),row(20,invalid:true)]);
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()=>showDialog<void>(context:context,builder:(_)=>TimelineBatchDialog(
        batch:batch,client:'Cliente',canPrepare:()=>current,onPrepare:()=>prepared++)),child:const Text('Abrir'))))));
    await tester.tap(find.text('Abrir')); await tester.pumpAndSettle();
    expect(prepared,0);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile)); await tester.pumpAndSettle();
    current=false;
    await tester.tap(find.text('Preparar 1 etapas')); await tester.pumpAndSettle();
    expect(prepared,0);
    expect(find.textContaining('Os dados ou a conta mudaram'),findsOneWidget);
    current=true;
    await tester.tap(find.text('Preparar 1 etapas')); await tester.pumpAndSettle();
    expect(prepared,1);
    expect(find.byType(TimelineBatchDialog),findsNothing);
  });
}
