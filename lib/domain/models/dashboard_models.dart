enum TimerState { stopped, running, paused }

class TimeLog {
  String id; // Changed from 'final String id;' to allow setters
  final String targetId;
  final DateTime date;
  String startTime;
  String endTime;
  String durationFormatted;
  bool isRegistered;
  String? projectName;
  String? taskName;
  String? typeHs;

  TimeLog({
    required this.id,
    required this.targetId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.durationFormatted,
    required this.isRegistered,
    this.projectName,
    this.taskName,
    this.typeHs,
    required hours,
    required description,
  });

  get hours => null;

  get description => null;

  get projectId => null;
}

class FilterOptions {
  DateTime? selectedDate;
  String? serviceType;
  String shift;

  FilterOptions({
    this.selectedDate,
    this.serviceType,
    this.shift = 'Todos',
  });

  bool get hasFilter =>
      selectedDate != null || serviceType != null || shift != 'Todos';

  void clear() {
    selectedDate = null;
    serviceType = null;
    shift = 'Todos';
  }
}
