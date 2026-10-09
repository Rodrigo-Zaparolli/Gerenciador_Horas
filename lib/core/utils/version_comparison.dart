/// Compares release versions numerically, ignoring build metadata.
/// Invalid versions and prereleases do not trigger an automatic update.
bool isNewerRelease(String candidate, String installed) {
  List<int>? parse(String value) {
    final match =
        RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+[^\s]+)?$').firstMatch(value.trim());
    if (match == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  final latest = parse(candidate);
  final current = parse(installed);
  if (latest == null || current == null) return false;
  for (var i = 0; i < 3; i++) {
    if (latest[i] != current[i]) return latest[i] > current[i];
  }
  return false;
}
