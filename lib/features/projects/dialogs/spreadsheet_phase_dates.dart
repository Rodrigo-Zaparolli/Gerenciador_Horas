import '../../../domain/models/project_model.dart';

String spreadsheetStageKey(String value) => value
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'\s*\(oh\)\s*$'), '')
    .replaceAll('ç', 'c')
    .replaceAll('ã', 'a')
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('ó', 'o')
    .replaceAll(RegExp(r'[-\s]+'), ' ');

String phaseDay(DateTime? value) => value == null
    ? ''
    : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

Map<String, dynamic> spreadsheetPhaseJob(TaskModel task, String request,
        String start, String end, String stage) =>
    {
      'work': task.edeskWorkNumber,
      'request': task.edeskSolicitacao?.trim().isNotEmpty == true
          ? task.edeskSolicitacao
          : request,
      'phase': task.stage,
      'stage': stage,
      'beforeStart': phaseDay(task.planStart),
      'beforeDisplayStart': phaseDay(task.startDate),
      'beforeEnd': phaseDay(task.planEnd),
      'start': start,
      'end': end,
    };

/// Atomic, date-only patch, rejecting stale/ambiguous work mappings.
List<Map<String, dynamic>> spreadsheetPhasePatch(
    List<dynamic> raw, List<Map<String, dynamic>> jobs, String request) {
  final tasks = raw.map((t) => Map<String, dynamic>.from(t as Map)).toList();
  final seen = <String>{};
  for (final job in jobs) {
    if (!seen.add('${job['request']}/${job['work']}') ||
        job['request'] != request) {
      throw StateError('Vínculo de fase inválido ou repetido.');
    }
    final matches = tasks.where((map) {
      final task = TaskModel.fromJson(map);
      return task.edeskWorkNumber == job['work'] &&
          (task.edeskSolicitacao?.trim().isNotEmpty == true
                  ? task.edeskSolicitacao
                  : request) ==
              job['request'];
    }).toList();
    if (matches.length != 1)
      throw StateError('A fase relacionada não é única. Confira o cadastro.');
    final target = matches.single;
    final task = TaskModel.fromJson(target);
    if (task.stage != job['phase'])
      throw StateError('O trabalho relacionado mudou. Confira a fase.');
    final start = DateTime.tryParse(job['start']?.toString() ?? '');
    final end = DateTime.tryParse(job['end']?.toString() ?? '');
    if (start == null || end == null || end.isBefore(start) ||
        phaseDay(start) != job['start'] || phaseDay(end) != job['end'])
      throw StateError('Período de fase inválido.');
    if (phaseDay(task.planStart) == job['start'] &&
        phaseDay(task.planEnd) == job['end'] &&
        phaseDay(task.startDate) == job['start']) continue;
    if (phaseDay(task.planStart) != job['beforeStart'] ||
        phaseDay(task.planEnd) != job['beforeEnd']) {
      throw StateError(
          'As datas da fase mudaram no sistema. Confira antes de sincronizar.');
    }
    if (job.containsKey('beforeDisplayStart') &&
        phaseDay(task.startDate) != job['beforeDisplayStart'] &&
        phaseDay(task.startDate) != job['start']) {
      throw StateError('O início do trabalho mudou. Confira antes de sincronizar.');
    }
    target['startDate'] = start.toIso8601String();
    target['planStart'] = start.toIso8601String();
    target['planEnd'] = end.toIso8601String();
  }
  return tasks;
}
