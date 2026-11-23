import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/features/tasks/task_log_search.dart';

TimeLog sample({String target = '2265173_4', String? projectId = '2265173'}) => TimeLog(
  id: 'log', targetId: target, projectId: projectId,
  date: DateTime(2026, 11, 3), startTime: '08:00', endTime: '09:00',
  durationFormatted: '01:00', isRegistered: true,
  projectName: 'RIMO Indústria e Comércio', taskName: 'Treinamento Catalog',
  description: 'Solicitação de revisão',
);

void main() {
  test('finds request ID, visible work ID and unaccented request text', () {
    final log = sample();
    for (final query in ['2265173', '2265173/4', '2265173_4', 'rimo industria', 'catalog 2265173', 'solicitacao revisao']) {
      expect(taskLogMatches(log, query), isTrue, reason: query);
    }
    expect(taskLogMatches(log, '2265173/5'), isFalse);
    expect(taskLogMatches(log, 'Mesaro'), isFalse);
    expect(taskLogMatches(sample(target:'legacy',projectId:'9999999'), '9999999'), isTrue);
  });
  test('opened request includes its works; opened work isolates its own logs', () {
    expect(taskLogMatches(sample(), '', openedTarget:'2265173'), isTrue);
    expect(taskLogMatches(sample(target:'2265173_5'), '', openedTarget:'2265173_4'), isFalse);
    expect(taskLogMatches(sample(), '', openedTarget:'2265173/4'), isTrue);
    expect(taskLogMatches(sample(), 'mesaro', openedTarget:'2265173_4'), isFalse);
    expect(taskLogMatches(sample(), '', openedTarget:'2262248'), isFalse);
  });
}
