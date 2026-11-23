import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/timeline_time_field.dart';
import 'package:gerenciador_horas/features/projects/dialogs/timeline_schedule.dart';

void main() {
  test('Compact input is HHMM, retains seconds and rejects invalid starts', () {
    expect(timelineTimeInput('1000', duration:true), 10/24);
    expect(timelineTimeInput('830', duration:false), 8.5/24);
    expect(timelineTimeInput('08:00:30', duration:false), 28830/86400);
    expect(timelineTimeInput('25:00', duration:false), isNull);
    expect(timelineTimeInput('25:00', duration:true), 25/24);
  });
  testWidgets('Time field remains editable while typing and normalizes on completion', (tester) async {
    String? edited;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:TimelineTimeField(
      text:'08:00:00',duration:true,enabled:true,onChanged:(value)=>edited=value))));
    final input=find.byType(TextFormField);
    final element=tester.element(input);
    await tester.enterText(input,'1000');
    await tester.pump();
    expect(tester.element(input),same(element));
    expect(edited,'1000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('10:00:00'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
