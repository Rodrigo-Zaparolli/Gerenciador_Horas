import '../../domain/models/project_model.dart';
import 'work_audit.dart';

DateTime? parsePhaseDate(String value) {
  final match =
      RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value.trim());
  if (match == null) return null;
  final day = int.parse(match[1]!),
      month = int.parse(match[2]!),
      year = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

/// Returned only after the destination has confirmed the write.
class PhaseDateSyncResult {
  const PhaseDateSyncResult(
      {required this.toEdesk, required this.start, required this.end});
  final bool toEdesk;
  final DateTime start, end;

  List<AuditFieldResult> refreshFields(List<AuditFieldResult> fields) {
    final app = {for (final f in fields) f.field: f.app};
    final edesk = {for (final f in fields) f.field: f.edesk};
    final destination = toEdesk ? edesk : app;
    destination['start'] = auditDate(start);
    destination['end'] = auditDate(end);
    return compareAuditWork(app, edesk, fields.map((f) => f.field).toSet());
  }

  ProjectModel refreshProject(
      ProjectModel project, TaskModel task, String request) {
    if (toEdesk) return project;
    final tasks = phaseDatePatch(
        (project.subTasks ?? <TaskModel>[]).map((t) => t.toJson()).toList(),
        request: request,
        work: task.edeskWorkNumber,
        phase: task.stage,
        expectedStart: auditDate(task.planStart),
        expectedEnd: auditDate(task.planEnd),
        start: start,
        end: end);
    return ProjectModel.fromJson({...project.toJson(), 'subTasks': tasks});
  }
}

void validatePhaseDates(DateTime start, DateTime end) {
  if (DateTime(end.year, end.month, end.day)
      .isBefore(DateTime(start.year, start.month, start.day))) {
    throw const FormatException(
        'O fim deve ser igual ou posterior ao in\u00edcio.');
  }
}

/// Only date fields of an exact, unique work may change. Preserve all other data.
List<Map<String, dynamic>> phaseDatePatch(List<dynamic> rawTasks,
    {required String request,
    required String work,
    required String phase,
    required String expectedStart,
    required String expectedEnd,
    required DateTime start,
    required DateTime end}) {
  validatePhaseDates(start, end);
  final tasks =
      rawTasks.map((t) => Map<String, dynamic>.from(t as Map)).toList();
  final matches = tasks.where((t) {
    final task = TaskModel.fromJson(t);
    return task.edeskWorkNumber == work &&
        (task.edeskSolicitacao?.trim().isNotEmpty == true
                ? task.edeskSolicitacao!.trim()
                : request) ==
            request;
  }).toList();
  if (matches.length != 1) {
    throw StateError(
        'Trabalho ausente ou repetido. Confira o cadastro novamente.');
  }
  final target = matches.single;
  final task = TaskModel.fromJson(target);
  if (task.stage != phase ||
      auditDate(task.planStart) != expectedStart ||
      auditDate(task.planEnd) != expectedEnd) {
    throw StateError('O cadastro mudou. Refaca a conferencia antes de salvar.');
  }
  target['planStart'] = start.toIso8601String();
  target['planEnd'] = end.toIso8601String();
  return tasks;
}
