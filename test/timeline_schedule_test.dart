import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/timeline_schedule.dart';

Map<String, dynamic> schedule() => {
  'fields': [
    {'sheet': 'Timeline', 'cell': 'C19', 'kind': 'date', 'value': '2026-11-14', 'timelineDateEditable': true},
    {'sheet': 'Timeline', 'cell': 'H19', 'value': 3},
    {'sheet': 'Timeline', 'cell': 'C20', 'kind': 'date', 'value': '2026-11-17', 'timelineDateEditable': true, 'dateDriver': {'previousDate': 'C19'}},
    {'sheet': 'Timeline', 'cell': 'H20', 'value': 3},
    {'sheet': 'Timeline', 'cell': 'C21', 'kind': 'date', 'value': '2026-11-20', 'timelineDateEditable': true, 'dateDriver': {'previousDate': 'C20'}},
  ],
  'rows': [
    for (var i = 0; i < 3; i++) {'row': 19+i, 'date': ['2026-11-14','2026-11-17','2026-11-20'][i],
      'cells': [i+1,'Etapa','data','','','','',3,'ET', 8/24, 10/24]}
  ]
};

void main() {
  test('14 November plus 3 days is 17 November and changing days cascades', () {
    final data = schedule();
    final rows = timelineDraftRows(data, {'Timeline!H19': {'value': 4}});
    expect(rows[1]['date'], '2026-11-18');
    expect(rows[2]['date'], '2026-11-21');
    expect((data['rows'] as List)[1]['date'], '2026-11-17');
    expect(timelineDraftRows(data, {})[1]['date'], '2026-11-17');
  });
  test('Changing a date adjusts its incoming interval and later dates', () {
    final rows = timelineDraftRows(schedule(), {'Timeline!C20': {'value': '2026-11-19'}});
    expect((rows[0]['cells'] as List)[7], 5);
    expect(rows[1]['date'], '2026-11-19');
    expect(rows[2]['date'], '2026-11-22');
  });
  test('Excel time fractions mean 08:00 start and 10:00 duration, not decimal hours', () {
    expect(timelineClock(timelineSeconds(8/24)!), '08:00:00');
    expect(timelineClock(timelineSeconds(10/24, duration: true)!), '10:00:00');
    expect(timelineSeconds('08:00:30'), 28830);
    expect(timelineSeconds('26:00:00'), isNull);
    expect(timelineSeconds('26:00:00', duration: true), 93600);
    final appointment = TimelineAppointment.fromRow((schedule()['rows'] as List).first)!;
    expect(appointment.start, DateTime.utc(2026,11,14,8));
    expect(appointment.end, DateTime.utc(2026,11,14,18));
    final file = appointment.ics(uid: 'test', title: 'Teste; cliente', description: 'Linha 1\nLinha 2');
    expect(file, contains('DTSTART:20261114T080000\r\n'));
    expect(file, contains('DTEND:20261114T180000\r\n'));
    expect(file, contains(r'SUMMARY:Teste\; cliente'));
    expect(file, contains(r'DESCRIPTION:Linha 1\nLinha 2'));
  });
  test('Overnight event rolls into the following date and invalid inputs are disabled', () {
    final row = Map<String,dynamic>.from((schedule()['rows'] as List).first as Map);
    row['startSeconds'] = 23*3600;
    row['durationSeconds'] = 3*3600;
    expect(TimelineAppointment.fromRow(row)!.end, DateTime.utc(2026,11,15,2));
    row['durationSeconds'] = 0;
    expect(TimelineAppointment.fromRow(row), isNull);
    row['date'] = '2026-02-30';
    expect(TimelineAppointment.fromRow(row), isNull);
  });
}
