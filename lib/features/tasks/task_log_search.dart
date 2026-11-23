import '../../domain/models/dashboard_models.dart';

String _normalize(String value) {
  var text = value.toLowerCase().replaceAll('_', '/');
  const replacements = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'ê': 'e',
    'è': 'e',
    'í': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ü': 'u',
    'ç': 'c'
  };
  replacements.forEach((from, to) => text = text.replaceAll(from, to));
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool taskTextMatches(String text, String query) {
  final words = _normalize(query).split(' ').where((word) => word.isNotEmpty);
  final searchable = _normalize(text);
  return words.every(searchable.contains);
}

bool taskLogMatches(TimeLog log, String query, {String? openedTarget}) {
  if (openedTarget != null) {
    final target = _normalize(openedTarget);
    final logTarget = _normalize(log.targetId);
    if (target.contains('/')) {
      if (logTarget != target) return false;
    } else if (logTarget.split('/').first != target &&
        _normalize(log.projectId ?? '') != target) {
      return false;
    }
  }
  return taskTextMatches(
      [
        log.targetId,
        log.projectId ?? '',
        log.projectName ?? '',
        log.taskName ?? '',
        log.description ?? '',
        log.dateFormatted,
      ].join(' '),
      query);
}
