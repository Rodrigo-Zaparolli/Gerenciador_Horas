import '../../domain/models/dashboard_models.dart';

enum TaskHoursFilter { all, charged, nonCharged }

/// Same classification used by the monthly totals, including legacy types.
bool taskLogIsCharged(TimeLog log) {
  final kind = (log.typeHs ?? '').toLowerCase().replaceAll('ã', 'a');
  return kind.contains('cobrada') && !kind.contains('nao');
}

bool taskLogMatchesHoursFilter(TimeLog log, TaskHoursFilter filter) =>
    switch (filter) {
      TaskHoursFilter.all => true,
      TaskHoursFilter.charged => taskLogIsCharged(log),
      TaskHoursFilter.nonCharged => !taskLogIsCharged(log),
    };
