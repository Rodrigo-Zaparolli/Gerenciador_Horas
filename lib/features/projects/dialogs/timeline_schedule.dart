import 'dart:convert';

DateTime? timelineDay(dynamic raw) {
  final text = '$raw';
  final date = DateTime.tryParse(text);
  return date != null && date.toIso8601String().substring(0, 10) == text ? date : null;
}

String timelineDayText(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

int? timelineSeconds(dynamic value, {bool duration = false}) {
  int? seconds;
  final number = value is num ? value : num.tryParse('$value');
  if (number != null && number.isFinite && number >= 0) {
    seconds = (number * 86400).round();
  } else if (value is String && RegExp(r'^\d+:[0-5]\d(?::[0-5]\d)?$').hasMatch(value.trim())) {
    final parts = value.trim().split(':').map(int.parse).toList();
    seconds = parts[0] * 3600 + parts[1] * 60 + (parts.length == 3 ? parts[2] : 0);
  }
  return seconds != null && (duration || seconds < 86400) ? seconds : null;
}

String timelineClock(int seconds) =>
    '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

num? timelineTimeInput(String text, {required bool duration}) {
  var value = text.trim();
  if (RegExp(r'^\d{1,6}$').hasMatch(value)) {
    value = value.padLeft(3, '0');
    value = '${value.substring(0,value.length-2)}:${value.substring(value.length-2)}';
  }
  if (!RegExp(r'^\d+:[0-5]\d(?::[0-5]\d)?$').hasMatch(value)) return null;
  final seconds = timelineSeconds(value, duration: duration);
  return seconds == null || seconds > 366*86400 ? null : seconds/86400;
}

/// Immediate draft only. Excel remains authoritative for holidays and formulas.
List<Map<String, dynamic>> timelineDraftRows(Map<String, dynamic> data,
    Map<String, Map<String, dynamic>> pending) {
  final fields = {for (final f in (data['fields'] as List? ?? []).whereType<Map>()) '${f['cell']}': f};
  final rows = [for (final r in (data['rows'] as List? ?? []).whereType<Map>())
    <String, dynamic>{...r, 'cells': List<dynamic>.from(r['cells'] as List)}];
  final byRow = {for (final r in rows) r['row']: r};
  dynamic draft(Map f) => pending['${f['sheet']}!${f['cell']}']?['value'] ?? f['value'];
  for (final row in rows) {
    final cells = row['cells'] as List;
    final h = fields['H${row['row']}'];
    if (h != null && cells.length > 7) cells[7] = draft(h);
    final c = fields['C${row['row']}'];
    if (c == null || c['timelineDateEditable'] != true) continue;
    final edit = pending['${c['sheet']}!${c['cell']}'];
    var date = timelineDay(edit?['value'] ?? c['value']);
    final driver = c['dateDriver'];
    if (driver is Map && driver['previousDate'] is String) {
      final previousNumber = int.tryParse('${driver['previousDate']}'.substring(1));
      final previous = byRow[previousNumber];
      final previousDate = timelineDay(previous?['date']);
      if (previous != null && previousDate != null) {
        final previousCells = previous['cells'] as List;
        if (edit != null && date != null) {
          previousCells[7] = DateTime.utc(date.year, date.month, date.day)
              .difference(DateTime.utc(previousDate.year, previousDate.month, previousDate.day)).inDays;
        } else {
          final days = int.tryParse('${previousCells[7]}');
          date = days == null || days < 0 ? null : DateTime(previousDate.year, previousDate.month, previousDate.day + days);
        }
      }
    }
    row['date'] = date?.toIso8601String().substring(0, 10);
    cells[2] = date == null ? 'Confira os dias' : timelineDayText(date);
  }
  return rows;
}

class TimelineAppointment {
  const TimelineAppointment(this.start, this.end);
  final DateTime start, end;
  static TimelineAppointment? fromRow(Map row) {
    final date = timelineDay(row['date']);
    final cells = row['cells'] as List? ?? [];
    final start = row['startSeconds'] is int ? row['startSeconds'] as int : cells.length > 9 ? timelineSeconds(cells[9]) : null;
    final duration = row['durationSeconds'] is int ? row['durationSeconds'] as int : cells.length > 10 ? timelineSeconds(cells[10], duration: true) : null;
    if (date == null || start == null || start < 0 || start >= 86400 || duration == null || duration <= 0 || duration > 366 * 86400) return null;
    final begin = DateTime.utc(date.year, date.month, date.day).add(Duration(seconds: start));
    return TimelineAppointment(begin, begin.add(Duration(seconds: duration)));
  }

  /// Floating local times: the workbook has no timezone. Outlook reviews them
  /// in the calendar's local timezone; nothing is sent or saved automatically.
  String ics({required String uid, required String title, required String description, DateTime? now}) {
    String date(DateTime d) => d.toIso8601String().substring(0, 19).replaceAll('-', '').replaceAll(':', '');
    String escape(String v) => v.replaceAll('\\', '\\\\').replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\n', r'\n').replaceAll(';', r'\;').replaceAll(',', r'\,');
    String fold(String text) {
      final lines = <String>[];
      var line = '';
      for (final rune in text.runes) {
        final char = String.fromCharCode(rune);
        if (utf8.encode(line + char).length > 75) { lines.add(line); line = ' '; }
        line += char;
      }
      return [...lines, line].join('\r\n');
    }
    return [
      'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Gerenciador de Horas//Cronograma//PT-BR',
      'CALSCALE:GREGORIAN', 'BEGIN:VEVENT', 'UID:${escape(uid)}',
      'DTSTAMP:${date((now ?? DateTime.now()).toUtc())}Z',
      'DTSTART:${date(start)}', 'DTEND:${date(end)}',
      'SUMMARY:${escape(title)}', 'DESCRIPTION:${escape(description)}',
      'END:VEVENT', 'END:VCALENDAR', ''
    ].map(fold).join('\r\n');
  }
}

class TimelineBatchEntry {
  const TimelineBatchEntry(this.row, this.label, this.description, this.appointment);
  final int row;
  final String label, description;
  final TimelineAppointment? appointment;
}

class TimelineCalendarBatch {
  const TimelineCalendarBatch(this.entries);
  final List<TimelineBatchEntry> entries;
  List<TimelineBatchEntry> get valid => entries.where((e) => e.appointment != null).toList();
  List<TimelineBatchEntry> get invalid => entries.where((e) => e.appointment == null).toList();

  factory TimelineCalendarBatch.fromRows(List<dynamic> rows) {
    if (rows.length > 500) throw StateError('O cronograma excede 500 linhas. Confira a planilha antes de agendar.');
    final seen = <int>{};
    final entries = <TimelineBatchEntry>[];
    for (final raw in rows) {
      if (raw is! Map || raw['row'] is! int || (raw['row'] as int) < 1 || !seen.add(raw['row'] as int)) {
        throw StateError('As linhas do cronograma estão ausentes ou repetidas. Recarregue antes de agendar.');
      }
      final cells = raw['cells'] is List ? raw['cells'] as List : const [];
      final label = cells.length > 1 && cells[1] is String ? (cells[1] as String).trim() : '';
      entries.add(TimelineBatchEntry(raw['row'] as int,
        label.isNotEmpty ? label : 'Linha ${raw['row']}',
        cells.length > 3 ? '${cells[3]}' : '',
        label.isNotEmpty ? TimelineAppointment.fromRow({...raw,'cells':cells}) : null));
    }
    return TimelineCalendarBatch(List.unmodifiable(entries));
  }

  String ics({required String projectId, required String client, required String revision, DateTime? now}) {
    if (valid.isEmpty) throw StateError('Não há etapas com data e horários válidos para agendar.');
    final stamp = now ?? DateTime.now();
    var header = '';
    final events = <String>[];
    for (final entry in valid) {
      final file = entry.appointment!.ics(uid:'$projectId-${entry.row}-$revision@gerenciador-horas',
        title:'$client · ${entry.label}', description:'Solicitação $projectId\n${entry.description}', now:stamp);
      final start = file.indexOf('BEGIN:VEVENT\r\n');
      final end = file.indexOf('\r\nEND:VEVENT\r\n',start) + '\r\nEND:VEVENT\r\n'.length;
      if (header.isEmpty) header = file.substring(0,start);
      events.add(file.substring(start,end));
    }
    return '$header${events.join()}END:VCALENDAR\r\n';
  }
}
