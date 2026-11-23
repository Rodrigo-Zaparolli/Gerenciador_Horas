import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_phase_dates.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

void main() {
  test('Rennova checklist dates persist into the start and end shown after reopening the work', () {
    const names = ['Contato inicial', 'Levantamento de Escopo', 'Desenvolvimento', 'Implantação', 'Pós-Implantação'];
    const starts = ['2026-11-16', '2026-11-25', '2026-11-26', '2026-12-14', '2027-01-16'];
    const ends = ['2026-11-19', '2026-12-10', '2026-12-11', '2027-01-15', '2027-01-29'];
    final raw = [for (var i = 0; i < names.length; i++) <String, dynamic>{
      'subId': '${i+2}', 'stage': names[i], 'startDate': '2026-11-16',
      'estimatedHours': '08:00', 'hourType': 'Hs Cobradas', 'status': 'INI_PRO',
    }];
    final jobs = [for (var i = 0; i < names.length; i++) spreadsheetPhaseJob(
      TaskModel.fromJson(raw[i]), '2267266', starts[i], ends[i], names[i])];
    final saved = spreadsheetPhasePatch(raw, jobs, '2267266');
    for (var i = 0; i < names.length; i++) {
      final reopened = TaskModel.fromJson(saved[i]);
      expect(phaseDay(reopened.startDate), starts[i]);
      expect(phaseDay(reopened.planStart), starts[i]);
      expect(phaseDay(reopened.planEnd), ends[i]);
      expect(reopened.estimatedHours, '08:00');
      expect(reopened.status, 'INI_PRO');
    }
    expect(spreadsheetPhasePatch(saved, jobs, '2267266'), saved);
    expect(raw[3]['startDate'], '2026-11-16');
  });
  test('Repairs a stale displayed start even when planned dates already match', () {
    final raw = <String, dynamic>{'subId': '5', 'stage': 'Implantação',
      'startDate': '2026-11-16', 'planStart': '2026-12-14', 'planEnd': '2027-01-15'};
    final job = spreadsheetPhaseJob(TaskModel.fromJson(raw), '1', '2026-12-14', '2027-01-15', 'Implantação');
    final saved = spreadsheetPhasePatch([raw], [job], '1');
    expect(phaseDay(TaskModel.fromJson(saved.single).startDate), '2026-12-14');
    expect(() => spreadsheetPhasePatch([{...raw, 'startDate': '2026-12-10'}], [job], '1'), throwsStateError);
  });
  final tasks = [
    {'subId':'2','stage':'Implantação','planStart':'2026-09-10','planEnd':'2026-12-04','estimatedHours':'40:00','status':'TRAB','hourType':'Hs Cobradas','customField':'preserve'},
    {'subId':'3','stage':'Pós-Implantação','planStart':'2026-12-07','planEnd':'2026-12-16','estimatedHours':'10:00'},
  ];
  Map<String,dynamic> job() => {'work':'2','request':'2263850','phase':'Implantação','stage':'Implantação','beforeStart':'2026-09-10','beforeEnd':'2026-12-04','start':'2026-09-11','end':'2026-12-05'};
  test('changes only matched phase dates and repeated confirmation is idempotent', () {
    final result=spreadsheetPhasePatch(tasks,[job()],'2263850');
    expect(result.first['planStart'],'2026-09-11T00:00:00.000');
    expect(result.first['planEnd'],'2026-12-05T00:00:00.000');
    for(final key in ['estimatedHours','status','hourType','customField']) {
      expect(result.first[key],tasks.first[key]);
    }
    expect(result.last,tasks.last);
    expect(tasks.first['planStart'],'2026-09-10');
    expect(spreadsheetPhasePatch(result,[job()],'2263850'),result);
  });
  test('rejects wrong request, stale dates, ambiguity and invalid ranges', () {
    for(final bad in [
      {...job(),'request':'other'}, {...job(),'beforeStart':'2026-01-01'},
      {...job(),'end':'2026-01-01'}, {...job(),'phase':'Contato Inicial'},
    ]) {
      expect(()=>spreadsheetPhasePatch(tasks,[bad],'2263850'),throwsStateError);
    }
    expect(()=>spreadsheetPhasePatch([...tasks,tasks.first],[job()],'2263850'),throwsStateError);
    expect(()=>spreadsheetPhasePatch(tasks,[job(),job()],'2263850'),throwsStateError);
  });
  test('stage names match spelling and OH suffix without conflating stages', () {
    expect(spreadsheetStageKey('Pós-Implantação (OH)'),spreadsheetStageKey('Pós Implantação'));
    expect(spreadsheetStageKey('Implantação'),isNot(spreadsheetStageKey('Pós-Implantação')));
  });
}
