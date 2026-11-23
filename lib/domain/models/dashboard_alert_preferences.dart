class DashboardAlertPreferences {
  const DashboardAlertPreferences({
    this.enabled = true,
    this.overdue = true,
    this.deadlines = true,
    this.comments = true,
  });

  final bool enabled, overdue, deadlines, comments;
  bool get hasTopics => overdue || deadlines || comments;
  bool get active => enabled && hasTopics;
  bool allowsDeadline(int differenceDays) =>
      active && (differenceDays < 0 ? overdue : deadlines);

  factory DashboardAlertPreferences.fromJson(Map<String, dynamic>? data) {
    bool flag(String key) => data?[key] is bool ? data![key] as bool : true;
    return DashboardAlertPreferences(
      enabled: flag('enabled'),
      overdue: flag('overdue'),
      deadlines: flag('deadlines'),
      comments: flag('comments'),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'overdue': overdue,
        'deadlines': deadlines,
        'comments': comments,
      };
}
