import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/personal_reminder.dart';
import 'package:gerenciador_horas/data/services/personal_reminder_repository.dart';
import 'package:gerenciador_horas/features/reminders/personal_reminders.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_toolbar_actions.dart';

class MemoryReminders implements PersonalReminderRepository {
  final stream = StreamController<List<PersonalReminder>>.broadcast();
  int acknowledgments = 0;
  @override
  Stream<List<PersonalReminder>> watch() => stream.stream;
  @override
  String newId() => 'new';
  @override
  Future<void> save(PersonalReminder r, {String? expectedRevision}) async {}
  @override
  Future<void> complete(PersonalReminder r, bool done) async {}
  @override
  Future<void> remove(PersonalReminder r) async {}
  @override
  Future<void> acknowledge(List<PersonalReminder> r, DateTime now) async {
    acknowledgments++;
  }
}

PersonalReminder reminder({int day = 17, bool done = false, String ack = ''}) =>
    PersonalReminder(
        id: 'a',
        title: 'Review',
        day: DateTime(2026, 11, day),
        revision: '1',
        done: done,
        acknowledgedOn: ack);
void main() {
  testWidgets('Minha agenda appears beside heading and opens management', (tester) async {
    tester.view.physicalSize = const Size(320,900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo=MemoryReminders();
    await tester.pumpWidget(MaterialApp(home:PersonalReminderHost(owner:'a',repository:repo,authorized:()=>true,clock:()=>DateTime(2026,11,17),child:const Scaffold(body:ProjectSectionHeading(projectCount:14)))));
    await tester.pumpAndSettle();
    expect(find.text('Minha agenda'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.tap(find.text('Minha agenda')); await tester.pumpAndSettle();
    expect(find.byType(PersonalReminderCenter),findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await repo.stream.close();
  });
  test('Scheduled minute gates popup and persists time', () {
    final r = PersonalReminder(
        id: 'timed',
        title: 'Meeting',
        day: DateTime(2026, 11, 17),
        revision: '1',
        minuteOfDay: 14 * 60 + 30);
    expect(r.needsPopup(DateTime(2026, 11, 17, 14, 29, 59)), isFalse);
    expect(r.needsPopup(DateTime(2026, 11, 17, 14, 30)), isTrue);
    expect(r.needsPopup(DateTime(2026, 11, 18)), isTrue);
    expect(PersonalReminder.fromMap(r.id, r.toMap())!.timeLabel, '14:30');
    expect(PersonalReminder.fromMap(r.id, {...r.toMap(), 'minuteOfDay': 1440}),
        isNull);
  });
  testWidgets('Timed popup fires while page stays open, not before time',
      (tester) async {
    final repo = MemoryReminders();
    var now = DateTime(2026, 11, 17, 14, 29);
    await tester.pumpWidget(MaterialApp(
        home: PersonalReminderHost(
            owner: 'a',
            repository: repo,
            authorized: () => true,
            clock: () => now,
            child: const Scaffold(body: Text('Home')))));
    repo.stream.add([
      PersonalReminder(
          id: 'timed',
          title: 'Meeting',
          day: DateTime(2026, 11, 17),
          revision: '1',
          minuteOfDay: 870)
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(PersonalReminderCenter), findsNothing);
    now = DateTime(2026, 11, 17, 14, 30);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalReminderCenter), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await repo.stream.close();
  });
  test('Due dates, completion and daily acknowledgment', () {
    final now = DateTime(2026, 11, 17, 12);
    expect(reminder().needsPopup(now), isTrue);
    expect(reminder(day: 16).needsPopup(now), isTrue);
    expect(reminder(day: 18).due(now), isFalse);
    expect(reminder(done: true).due(now), isFalse);
    expect(reminder(ack: '2026-11-17').needsPopup(now), isFalse);
    expect(
        reminder(ack: '2026-11-17').needsPopup(DateTime(2026, 11, 18)), isTrue);
  });
  test('Invalid dates rejected and data round trips', () {
    final legacy = PersonalReminder.fromMap(
        'a', {...reminder().toMap(), 'acknowledgedOn': '2026-11-17'});
    expect(legacy!.needsPopup(DateTime(2026, 11, 17)), isTrue);
    expect(
        PersonalReminder.fromMap(
            'a', {...reminder().toMap(), 'day': '2026-02-30'}),
        isNull);
    expect(PersonalReminder.fromMap('a', reminder().toMap())!.dateLabel,
        '17/11/2026');
  });
  testWidgets('Center acknowledges once and session prevents popup loop',
      (tester) async {
    final repo = MemoryReminders();
    var now = DateTime(2026, 11, 17);
    var allowed = true;
    final controller =
        PersonalReminderController(repo, () => allowed, clock: () => now);
    repo.stream.add([reminder()]);
    await tester.pump();
    expect(controller.hasUnseenDue, isTrue);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => controller.open(context, automatic: true),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Review'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(repo.acknowledgments, 1);
    expect(controller.hasUnseenDue, isFalse);
    now = DateTime(2026, 11, 18);
    expect(controller.hasUnseenDue, isTrue);
    allowed = false;
    repo.stream.add([reminder(day: 18)]);
    await tester.pump();
    expect(controller.items.single.day, DateTime(2026, 11, 17));
    controller.dispose();
    await repo.stream.close();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Automatic popup opens on stream delivery without user input',
      (tester) async {
    final repo = MemoryReminders();
    await tester.pumpWidget(MaterialApp(
        home: PersonalReminderHost(
            owner: 'a',
            repository: repo,
            authorized: () => true,
            clock: () => DateTime(2026, 11, 17),
            child: const Scaffold(body: Text('Home')))));
    await tester.pumpAndSettle();
    repo.stream.add([reminder()]);
    await tester.idle();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Lembretes de hoje e pendências'), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(repo.acknowledgments, 1);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalReminderCenter), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await repo.stream.close();
  });
  testWidgets('Managing reminders never acknowledges pending popup',
      (tester) async {
    final repo = MemoryReminders();
    final controller = PersonalReminderController(repo, () => true,
        clock: () => DateTime(2026, 11, 17));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => controller.open(context),
                    child: const Text('Manage'))))));
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    repo.stream.add([reminder()]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(repo.acknowledgments, 0);
    expect(controller.hasUnseenDue, isTrue);
    controller.dispose();
    await repo.stream.close();
    await tester.pumpWidget(const SizedBox());
  });
}
