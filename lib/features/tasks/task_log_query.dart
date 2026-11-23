import '../../domain/models/dashboard_models.dart';
import 'task_hours_filter.dart';
import 'task_log_search.dart';

/// The explicit parent binding wins over request aliases. Legacy records
/// without a binding can match any request belonging to that project.
bool taskLogInProject(TimeLog log, String? projectId,
    {Set<String> requests = const {}}) {
  if (projectId == null) return true;
  final bound = log.projectId?.trim() ?? '';
  if (bound.isNotEmpty) return bound == projectId;
  final request = log.targetId.replaceAll('_', '/').split('/').first.trim();
  return request == projectId || requests.contains(request);
}

/// Filters loaded records only; subscriptions and persistence stay in TimeLogStore.
List<TimeLog> filterTaskLogs(
  Iterable<TimeLog> source, {
  String search = '',
  String? work,
  String? projectId,
  Set<String> projectRequests = const {},
  DateTime? start,
  DateTime? end,
  TaskHoursFilter billing = TaskHoursFilter.all,
  bool includePending = false,
}) {
  DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);
  final first = start == null ? null : day(start);
  final last = end == null ? null : day(end);
  return source.where((log) {
    if (!includePending && !log.isRegistered) return false;
    if (!taskLogInProject(log, projectId, requests: projectRequests))
      return false;
    if (!taskLogMatchesHoursFilter(log, billing)) return false;
    final date = day(log.date);
    if (first != null && date.isBefore(first)) return false;
    if (last != null && date.isAfter(last)) return false;
    return taskLogMatches(log, search, openedTarget: work);
  }).toList()
    ..sort((a, b) {
      final date = day(b.date).compareTo(day(a.date));
      return date != 0 ? date : b.startTime.compareTo(a.startTime);
    });
}
