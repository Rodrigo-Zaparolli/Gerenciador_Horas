import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/timer_entry_review.dart';
import 'package:gerenciador_horas/features/dashboard/dialogs/stop_timer_review_dialog.dart';

final today = DateTime(2026, 11, 17, 12);
TimerEntryReview entry(
        {DateTime? day,
        String start = '0830',
        String end = '1000',
        int minutes = 90}) =>
    TimerEntryReview.parse(
        day: day ?? DateTime(2026, 11, 16),
        start: start,
        end: end,
        minutes: minutes,
        description: '',
        now: today);
TimeLog log(String start, String end,
        {int day = 16,
        String id = 'other',
        String target = 'other_1',
        bool registered = true}) =>
    TimeLog(
        id: id,
        targetId: target,
        date: DateTime(2026, 11, day),
        startTime: start,
        endTime: end,
        durationFormatted: '01:00',
        isRegistered: registered,
        taskName: 'Task',
        description: '');
void main() {
  test('Four digits format immediately without disrupting partial edits', () {
    final formatter = CompactClockInputFormatter();
    for (final pair in {
      '0930': '09:30',
      '1200': '12:00',
      '0030': '00:30',
      '09': '09',
      '09:30': '09:30'
    }.entries) {
      final value = formatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(
              text: pair.key,
              selection: TextSelection.collapsed(offset: pair.key.length)));
      expect(value.text, pair.value);
      expect(value.selection.baseOffset, pair.value.length);
    }
    final deletion = formatter.formatEditUpdate(
        const TextEditingValue(text: '09:30'),
        const TextEditingValue(
            text: '093', selection: TextSelection.collapsed(offset: 2)));
    expect(deletion.text, '093');
    expect(deletion.selection.baseOffset, 2);
  });
  testWidgets(
      'Date button uses entry date, preserves comment, and allows net duration',
      (tester) async {
    TimerEntryReview? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => StopTimerReviewDialog(
                            started: DateTime(2026, 11, 16, 8),
                            stopped: DateTime(2026, 11, 16, 9),
                            workedSeconds: 3600,
                            target: 'mine_1',
                            logId: 'own',
                            label: 'Client',
                            authorized: () => true,
                            clock: () => today,
                            loadWindow: (_) async => [],
                            save: (entry) async {
                              saved = entry;
                            })),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final comment = find.byKey(const ValueKey('timer-review-description'));
    await tester.enterText(comment, 'Activity');
    // Insert at the start; the original activity must not be removed.
    final controller = tester.widget<TextField>(comment).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.byKey(const ValueKey('timer-review-insert-date')));
    await tester.pump();
    expect(controller.text, '16/11/2026: - Activity');
    await tester.tap(find.byKey(const ValueKey('timer-review-insert-date')));
    await tester.pump();
    expect(controller.text, '16/11/2026: - Activity');
    await tester.tap(find.text('Hoje'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('timer-review-insert-date')));
    await tester.pump();
    expect(controller.text, contains('17/11/2026: - '));
    expect(controller.text, contains('Activity'));
    await tester.enterText(
        find.byKey(const ValueKey('timer-review-duration')), '0030');
    await tester.tap(find.text('Salvar apontamento'));
    await tester.pumpAndSettle();
    expect(saved!.day, DateTime(2026, 11, 17));
    expect(saved!.minutes, 30);
    expect(saved!.description, contains('Activity'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Saves valid hours with an empty comment', (tester) async {
    TimerEntryReview? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => StopTimerReviewDialog(
                            started: DateTime(2026, 11, 16, 8),
                            stopped: DateTime(2026, 11, 16, 9),
                            workedSeconds: 3600,
                            target: 'mine_1',
                            logId: 'own',
                            label: 'Client',
                            authorized: () => true,
                            clock: () => today,
                            loadWindow: (_) async => [],
                            save: (entry) async {
                              saved = entry;
                            })),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar apontamento'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.description, isEmpty);
    expect(saved!.minutes, 60);
    expect(find.byType(StopTimerReviewDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Read failure preserves review; account change prevents saving',
      (tester) async {
    var allowed = true, fail = true, writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StopTimerReviewDialog(
                started: DateTime(2026, 11, 16, 8),
                stopped: DateTime(2026, 11, 16, 9),
                workedSeconds: 3600,
                target: 'mine_1',
                logId: 'own',
                label: 'Client',
                authorized: () => allowed,
                clock: () => today,
                loadWindow: (_) async {
                  if (fail) throw StateError('Offline');
                  allowed = false;
                  return [];
                },
                save: (_) async {
                  writes++;
                }))));
    await tester.tap(find.text('Salvar apontamento'));
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    expect(writes, 0);
    expect(
        (tester.widget<TextField>(
                find.byKey(const ValueKey('timer-review-start'))))
            .controller!
            .text,
        '08:00');
    fail = false;
    await tester.tap(find.text('Salvar apontamento'));
    await tester.pump();
    expect(writes, 0);
    expect(find.text('A conta mudou. Feche esta janela.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('Compact hours and midnight boundary', () {
    expect(entry().endText, '10:00');
    expect(entryClock('830'), 510);
    expect(entryClock('2400'), isNull);
    expect(entryClock('2400', end: true), 1440);
    expect(entryClock('0860'), isNull);
  });
  test('Past date and pauses preserved; invalid intervals rejected', () {
    expect(entry(minutes: 60).durationText, '01:00');
    expect(() => entry(day: DateTime(2026, 11, 18)), throwsFormatException);
    expect(() => entry(start: '1000', end: '0830'), throwsFormatException);
    expect(() => entry(minutes: 91), throwsFormatException);
    expect(() => entry(minutes: 0), throwsFormatException);
  });
  test('Conflicts across projects, including unregistered and overnight', () {
    String? conflict(List<TimeLog> logs) =>
        timerEntryConflict(entry(), logs, ownId: 'own', ownTarget: 'mine_1');
    expect(conflict([log('09:00', '11:00', registered: false)]), isNotNull);
    expect(conflict([log('23:00', '09:00', day: 15)]), isNotNull);
    expect(conflict([log('07:00', '08:30'), log('10:00', '11:00')]), isNull);
    expect(
        conflict([log('08:30', '10:00', id: 'own', target: 'mine_1')]), isNull);
    expect(conflict([log('08:30', '10:00', id: 'own')]), isNotNull);
  });
  testWidgets('Review checks overlap, retains input after failure, then saves',
      (tester) async {
    var conflict = true;
    TimerEntryReview? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => StopTimerReviewDialog(
                            started: DateTime(2026, 11, 16, 8, 30),
                            stopped: DateTime(2026, 11, 16, 10),
                            workedSeconds: 5400,
                            target: 'mine_1',
                            logId: 'own',
                            label: 'Client',
                            authorized: () => true,
                            clock: () => today,
                            loadWindow: (_) async =>
                                conflict ? [log('09:00', '11:00')] : [],
                            save: (value) async {
                              saved = value;
                            })),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar apontamento'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.textContaining('Sobreposi'), findsOneWidget);
    conflict = false;
    await tester.enterText(
        find.byKey(const ValueKey('timer-review-end')), '1100');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('timer-review-end')))
            .controller!
            .text,
        '11:00');
    await tester.tap(find.text('Salvar apontamento'));
    await tester.pumpAndSettle();
    expect(saved!.day, DateTime(2026, 11, 16));
    expect(saved!.endText, '11:00');
    expect(saved!.minutes, 150);
    await tester.pumpWidget(const SizedBox());
  });
}
