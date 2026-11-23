import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/hours_overlap.dart';

TimeLog log(String id, String target, String start, String end,
        {int day = 13}) =>
    TimeLog(
        id: id,
        targetId: target,
        date: DateTime(2026, 11, day),
        startTime: start,
        endTime: end,
        durationFormatted: '01:00',
        isRegistered: true,
        taskName: 'Trabalho',
        description: 'Atividade');

void main() {
  test('Checks hidden projects even for an individual send', () async {
    final selected = log('a', '100_1', '09:00', '10:00');
    await expectLater(
        verifyHoursForSend([selected],
            loadDay: (_) async =>
                [selected, log('hidden', '200_2', '09:30', '11:00')],
            authorized: () => true),
        throwsStateError);
  });
  test('Endpoint touching is valid and returns fresh objects', () async {
    final selected = log('a', '100_1', '09:00', '10:00'),
        fresh = log('a', '100_1', '09:00', '10:00');
    final result = await verifyHoursForSend([selected],
        loadDay: (_) async => [fresh, log('b', '200_2', '10:00', '11:00')],
        authorized: () => true);
    expect(identical(result.single, fresh), isTrue);
  });
  test('Unrelated overlap does not block the selected interval', () async {
    final selected = log('a', '100_1', '14:00', '15:00');
    expect(
        await verifyHoursForSend([selected],
            loadDay: (_) async => [
                  selected,
                  log('b', '200_2', '09:00', '11:00'),
                  log('c', '300_3', '10:00', '12:00')
                ],
            authorized: () => true),
        hasLength(1));
  });
  test('Equal document ids in distinct projects are not conflated', () async {
    final a = log('same', '100_1', '09:00', '10:00'),
        b = log('same', '200_2', '10:00', '11:00');
    expect(
        await verifyHoursForSend([a, b],
            loadDay: (_) async => [a, b], authorized: () => true),
        hasLength(2));
  });
  test('Changed or deleted selection aborts the batch', () async {
    final a = log('a', '100_1', '09:00', '10:00');
    for (final fresh in <List<TimeLog>>[
      [],
      [log('a', '100_1', '09:00', '10:30')]
    ]) {
      await expectLater(
          verifyHoursForSend([a],
              loadDay: (_) async => fresh, authorized: () => true),
          throwsStateError);
    }
  });
  test('Load failures and account switches abort preparation', () async {
    final a = log('a', '100_1', '09:00', '10:00');
    var allowed = true;
    await expectLater(
        verifyHoursForSend([a],
            loadDay: (_) async => throw Exception('offline'),
            authorized: () => true),
        throwsException);
    await expectLater(
        verifyHoursForSend([a],
            loadDay: (_) async {
              allowed = false;
              return [a];
            },
            authorized: () => allowed),
        throwsStateError);
  });
  test(
      'Days are loaded once without conflating identical clocks on other dates',
      () async {
    final a = log('a', '100_1', '09:00', '10:00'),
        b = log('b', '200_2', '09:00', '10:00', day: 14);
    var loads = 0;
    expect(
        await verifyHoursForSend([a, b],
            loadDay: (day) async {
              loads++;
              return [a, b].where((l) => hoursLogDay(l) == day).toList();
            },
            authorized: () => true),
        hasLength(2));
    expect(loads, 2);
  });
  test('Duplicates, containment, midnight and invalid clocks', () {
    expect(
        registeredHoursProblem(
            [log('a', '1', '08:00', '12:00'), log('b', '2', '09:00', '10:00')]),
        contains('sobrepostos'));
    expect(registeredHoursProblem([log('a', '1', '23:00', '24:00')]), isNull);
    expect(
        registeredHoursProblem([log('a', '1', '24:00', '24:00')]), isNotNull);
    expect(
        registeredHoursProblem([log('a', '1', '09:00', '09:00')]), isNotNull);
  });
}
