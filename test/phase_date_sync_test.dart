import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/edesk/phase_date_sync.dart';
import 'package:gerenciador_horas/features/edesk/work_audit.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

void main() {
  Map<String, dynamic> task() => {
        'subId': '5',
        'stage': 'Implantacao',
        'planStart': '2026-07-31T00:00:00.000',
        'planEnd': '2026-11-30T00:00:00.000',
        'status': 'TRAB_EXE',
        'estimatedHours': '30:30',
        'custom': 'preservado'
      };
  List<Map<String, dynamic>> patch(List<dynamic> tasks) => phaseDatePatch(tasks,
      request: '2260860',
      work: '5',
      phase: 'Implantacao',
      expectedStart: '31/07/2026',
      expectedEnd: '30/11/2026',
      start: DateTime(2026, 7, 31),
      end: DateTime(2026, 12, 15));
  test('reject invalid dates and reversed ranges', () {
    expect(parsePhaseDate('31/02/2026'), isNull);
    expect(parsePhaseDate('00/01/2026'), isNull);
    expect(parsePhaseDate('29/02/2024'), DateTime(2024, 2, 29));
    expect(parsePhaseDate('3/11/2026'), DateTime(2026, 11, 3));
    expect(
        () =>
            validatePhaseDates(DateTime(2026, 12, 15), DateTime(2026, 11, 30)),
        throwsFormatException);
  });
  test(
      'confirmed dates refresh comparison and the next audit without mutating project',
      () {
    final project = ProjectModel.fromJson({
      'id': '2265173',
      'client': 'Rimo',
      'subTasks': [
        {...task(), 'edeskSolicitacao': '2265173'}
      ]
    });
    final result = PhaseDateSyncResult(
        toEdesk: false,
        start: DateTime(2026, 7, 31),
        end: DateTime(2026, 12, 15));
    final refreshed =
        result.refreshProject(project, project.subTasks!.single, project.id);
    expect(project.subTasks!.single.planEnd, DateTime(2026, 11, 30));
    expect(refreshed.subTasks!.single.planEnd, DateTime(2026, 12, 15));
    expect(refreshed.subTasks!.single.estimatedHours, '30:30');
    final fields = result.refreshFields([
      AuditFieldResult('end', '30/11/2026', '15/12/2026', 'Divergência'),
      AuditFieldResult('hours', '04:00', '04:00', 'Igual')
    ]);
    expect(fields.first.app, '15/12/2026');
    expect(fields.first.state, 'Igual');
    expect(fields.last.app, '04:00');
    final targets = projectAuditTargets([refreshed]);
    expect(targets.single.expected['5']?['end'], '15/12/2026');
  });
  test('E-Desk destination refreshes its column without modifying app dates',
      () {
    final result = PhaseDateSyncResult(
        toEdesk: true,
        start: DateTime(2026, 7, 31),
        end: DateTime(2026, 12, 15));
    final fields = result.refreshFields(
        [AuditFieldResult('end', '15/12/2026', '30/11/2026', 'Divergência')]);
    expect(fields.single.app, '15/12/2026');
    expect(fields.single.edesk, '15/12/2026');
    expect(fields.single.state, 'Igual');
  });
  test('changes only selected task dates without mutating source', () {
    final source = task();
    final other = {...task(), 'subId': '6'};
    final result = patch([source, other]);
    expect(result.first['planEnd'], '2026-12-15T00:00:00.000');
    expect(source['planEnd'], '2026-11-30T00:00:00.000');
    expect(
        {...result.first}
          ..remove('planStart')
          ..remove('planEnd'),
        {...source}
          ..remove('planStart')
          ..remove('planEnd'));
    expect(result.last, other);
  });
  test('blocks absent, duplicate or mismatched work references', () {
    expect(() => patch([]), throwsStateError);
    expect(() => patch([task(), task()]), throwsStateError);
    expect(
        () => patch([
              {...task(), 'edeskSolicitacao': '999'}
            ]),
        throwsStateError);
  });
  test('blocks stale dates and phase names', () {
    expect(
        () => patch([
              {...task(), 'planEnd': '2026-12-01T00:00:00.000'}
            ]),
        throwsStateError);
    expect(
        () => patch([
              {...task(), 'stage': 'Outro'}
            ]),
        throwsStateError);
  });
}
