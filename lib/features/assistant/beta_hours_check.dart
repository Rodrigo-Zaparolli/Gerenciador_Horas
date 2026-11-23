import '../../domain/models/dashboard_models.dart';
import '../../domain/models/hours_overlap.dart';

/// Shared validation for BETA and manual sends.
String? betaHoursProblem(List<TimeLog> logs) => registeredHoursProblem(logs);
