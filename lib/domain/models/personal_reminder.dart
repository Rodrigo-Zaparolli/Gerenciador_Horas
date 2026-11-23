String reminderDayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class PersonalReminder {
  const PersonalReminder(
      {required this.id,
      required this.title,
      required this.day,
      required this.revision,
      this.minuteOfDay,
      this.notes = '',
      this.done = false,
      this.acknowledgedOn = ''});
  final String id, title, revision, notes, acknowledgedOn;
  final DateTime day;
  final int? minuteOfDay;
  DateTime get scheduledAt => DateTime(day.year, day.month, day.day)
      .add(Duration(minutes: minuteOfDay ?? 0));
  String get timeLabel => minuteOfDay == null
      ? ''
      : '${(minuteOfDay! ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay! % 60).toString().padLeft(2, '0')}';
  final bool done;
  bool due(DateTime now) => !done && !scheduledAt.isAfter(now);
  bool needsPopup(DateTime now) =>
      due(now) && acknowledgedOn != reminderDayKey(now);
  String get dateLabel =>
      '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
  Map<String, dynamic> toMap() => {
        'title': title.trim(),
        'day': reminderDayKey(day),
        'minuteOfDay': minuteOfDay,
        'notes': notes.trim(),
        'done': done,
        'revision': revision,
        'popupAcknowledgedOn': acknowledgedOn
      };
  static PersonalReminder? fromMap(String id, Map<String, dynamic> data) {
    final raw = data['day'], title = data['title'], revision = data['revision'];
    if (raw is! String ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 200 ||
        revision is! String ||
        revision.isEmpty) return null;
    final day = DateTime.tryParse(raw);
    if (day == null || reminderDayKey(day) != raw) return null;
    final minute = data['minuteOfDay'];
    if (minute != null && (minute is! int || minute < 0 || minute >= 1440))
      return null;
    return PersonalReminder(
        id: id,
        title: title.trim(),
        day: DateTime(day.year, day.month, day.day),
        minuteOfDay: minute as int?,
        revision: revision,
        notes: data['notes'] is String ? data['notes'] as String : '',
        done: data['done'] == true,
        acknowledgedOn: data['popupAcknowledgedOn'] is String
            ? data['popupAcknowledgedOn'] as String
            : '');
  }
}
