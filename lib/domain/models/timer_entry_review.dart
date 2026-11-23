import 'dashboard_models.dart';
import 'work_duration.dart';

int? entryClock(String text, {bool end = false}) {
  var value = text.trim();
  if (RegExp(r'^\d{3,4}$').hasMatch(value)) {
    value =
        '${value.substring(0, value.length - 2)}:${value.substring(value.length - 2)}';
  }
  final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(value);
  if (match == null) return null;
  final minutes = int.parse(match[1]!) * 60 + int.parse(match[2]!);
  return minutes < 1440 || end && minutes == 1440 ? minutes : null;
}

class TimerEntryReview {
  const TimerEntryReview(
      {required this.day,
      required this.start,
      required this.end,
      required this.minutes,
      required this.description});
  final DateTime day;
  final int start, end, minutes;
  final String description;
  String get startText => WorkDuration.format(start);
  String get endText => WorkDuration.format(end);
  String get durationText => WorkDuration.format(minutes);

  static TimerEntryReview parse(
      {required DateTime day,
      required String start,
      required String end,
      required int minutes,
      required String description,
      required DateTime now}) {
    final date = DateTime(day.year, day.month, day.day);
    if (date.isAfter(DateTime(now.year, now.month, now.day))) {
      throw const FormatException('Escolha hoje ou uma data anterior.');
    }
    final begin = entryClock(start), finish = entryClock(end, end: true);
    if (begin == null || finish == null || finish <= begin) {
      throw const FormatException(
          'Informe início e fim válidos, no mesmo dia. O fim deve ser posterior ao início.');
    }
    if (minutes < 1 || minutes > finish - begin) {
      throw const FormatException(
          'Informe um intervalo de pelo menos um minuto. Confira os horários e a duração.');
    }
    if (description.length > 2000)
      throw const FormatException('Use até 2000 caracteres no comentário.');
    return TimerEntryReview(
        day: date,
        start: begin,
        end: finish,
        minutes: minutes,
        description: description.trim());
  }
}

/// Includes registered entries and timer drafts, including previous-day overnight entries.
String? timerEntryConflict(TimerEntryReview entry, List<TimeLog> logs,
    {required String ownId, required String ownTarget}) {
  final from = DateTime.utc(entry.day.year, entry.day.month, entry.day.day)
      .add(Duration(minutes: entry.start));
  final until = DateTime.utc(entry.day.year, entry.day.month, entry.day.day)
      .add(Duration(minutes: entry.end));
  for (final log in logs) {
    if (log.id == ownId && log.targetId == ownTarget) continue;
    final start = entryClock(log.startTime),
        end = entryClock(log.endTime, end: true);
    if (start == null || end == null || end == start) {
      return 'Não foi possível conferir um apontamento de ${log.dateFormatted} sem horários válidos. Revise em Tarefas antes de salvar.';
    }
    final date = DateTime.utc(log.date.year, log.date.month, log.date.day);
    final a = date.add(Duration(minutes: start));
    final b = date.add(Duration(minutes: end + (end < start ? 1440 : 0)));
    if (from.isBefore(b) && until.isAfter(a)) {
      return 'Sobreposição com ${log.projectName ?? log.targetId}: ${log.dateFormatted}, ${log.startTime} às ${log.endTime}. Ajuste o intervalo antes de salvar.';
    }
  }
  return null;
}
