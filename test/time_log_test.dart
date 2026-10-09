import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

void main() {
  test('Formats dates for display and searching', () {
    final log = TimeLog(
      id: 'log',
      targetId: 'project',
      date: DateTime(2026, 10, 8),
      startTime: '09:00',
      endTime: '10:00',
      durationFormatted: '01:00',
      isRegistered: false,
    );
    expect(log.dateFormatted, '08/10/2026');
  });
}
