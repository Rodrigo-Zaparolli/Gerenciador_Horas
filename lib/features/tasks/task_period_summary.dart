import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';
import 'task_hours_filter.dart';

/// A single set of totals shared by the overview and the period cards.
/// Administrative registration is deliberately unrelated to E-Desk receipts.
class TaskPeriodSummary {
  TaskPeriodSummary(Iterable<TimeLog> source) {
    for (final log in source) {
      count++;
      works.add(log.targetId.trim().replaceAll('_', '/'));
      projects.add(log.projectId?.trim().isNotEmpty == true
          ? log.projectId!.trim()
          : log.targetId.replaceAll('_', '/').split('/').first.trim());
      final minutes = WorkDuration.minutes(log);
      totalMinutes += minutes;
      if (taskLogIsCharged(log)) {
        chargedMinutes += minutes;
        chargedCount++;
      }
    }
  }

  int count = 0;
  int totalMinutes = 0;
  int chargedMinutes = 0;
  int chargedCount = 0;
  final Set<String> works = {};
  final Set<String> projects = {};
  int get nonChargedMinutes => totalMinutes - chargedMinutes;
  int get nonChargedCount => count - chargedCount;
  double get chargedRatio =>
      totalMinutes == 0 ? 0 : chargedMinutes / totalMinutes;
  double get nonChargedRatio =>
      totalMinutes == 0 ? 0 : nonChargedMinutes / totalMinutes;
  String hours(int minutes) => WorkDuration.format(minutes);
  String percent(double ratio) =>
      '${(ratio * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
}
