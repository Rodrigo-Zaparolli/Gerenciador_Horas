import 'dart:convert';
import 'dashboard_models.dart';

String hoursLogKey(TimeLog log) => jsonEncode([log.targetId, log.id]);
DateTime hoursLogDay(TimeLog log) =>
    DateTime(log.date.year, log.date.month, log.date.day);

/// Adjacent intervals are valid; a conflict requires a shared minute.
String? registeredHoursProblem(List<TimeLog> logs, {Set<String>? focus}) {
  int? clock(String text) {
    final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(text.trim());
    if (match == null) return null;
    final h = int.parse(match[1]!), m = int.parse(match[2]!);
    return h < 24 || h == 24 && m == 0 ? h * 60 + m : null;
  }

  String label(TimeLog log) =>
      '${log.dateFormatted} · ${log.projectName ?? log.targetId}, ${log.startTime} às ${log.endTime}';
  final rows = <({TimeLog log, int start, int end, DateTime day})>[];
  for (final log in logs.where((l) => l.isRegistered)) {
    final start = clock(log.startTime), end = clock(log.endTime);
    if (start == null || end == null || start >= 1440 || end <= start) {
      return 'O horário de ${label(log)} precisa de correção. Confira na tela antes de enviar.';
    }
    rows.add((log: log, start: start, end: end, day: hoursLogDay(log)));
  }
  rows.sort((a, b) {
    final day = a.day.compareTo(b.day);
    return day == 0 ? a.start.compareTo(b.start) : day;
  });
  for (var i = 0; i < rows.length; i++) {
    for (var j = i + 1; j < rows.length; j++) {
      final a = rows[i], b = rows[j];
      if (a.day != b.day || b.start >= a.end) break;
      if (focus != null &&
          !focus.contains(hoursLogKey(a.log)) &&
          !focus.contains(hoursLogKey(b.log))) continue;
      return 'Encontrei horários sobrepostos: ${label(a.log)} e ${label(b.log)}. Ajuste esses apontamentos antes de enviar.';
    }
  }
  return null;
}

String _sendSnapshot(TimeLog log) => jsonEncode([
      hoursLogKey(log),
      hoursLogDay(log).toIso8601String(),
      log.startTime,
      log.endTime,
      log.taskName,
      log.description,
      log.typeHs,
      log.projectName,
      log.isRegistered
    ]);

/// Compare the selection with fresh server data across all projects that day.
Future<List<TimeLog>> verifyHoursForSend(
  List<TimeLog> selected, {
  required Future<List<TimeLog>> Function(DateTime) loadDay,
  required bool Function() authorized,
}) async {
  void check() {
    if (!authorized())
      throw StateError('A conta mudou. Confira os apontamentos novamente.');
  }

  check();
  if (selected.isEmpty) return [];
  if (selected.any((l) => !l.isRegistered))
    throw StateError('Há apontamentos não cadastrados na seleção.');
  final keys = selected.map(hoursLogKey).toList();
  if (keys.toSet().length != keys.length)
    throw StateError('Há apontamentos repetidos na seleção.');
  final snapshots = {
    for (final log in selected) hoursLogKey(log): _sendSnapshot(log)
  };
  final days = selected.map(hoursLogDay).toSet().toList()..sort();
  final fresh = <TimeLog>[];
  for (final day in days) {
    final result = await loadDay(day);
    check();
    fresh.addAll(result.where((l) => l.isRegistered && hoursLogDay(l) == day));
  }
  final verified = <TimeLog>[];
  for (final key in keys) {
    final matches = fresh.where((l) => hoursLogKey(l) == key).toList();
    if (matches.length != 1 ||
        _sendSnapshot(matches.single) != snapshots[key]) {
      throw StateError(
          'Os apontamentos selecionados mudaram ou não puderam ser conferidos. Confira a tela e prepare o envio novamente.');
    }
    verified.add(matches.single);
  }
  final problem = registeredHoursProblem(fresh, focus: keys.toSet());
  if (problem != null) throw StateError(problem);
  check();
  return verified;
}
