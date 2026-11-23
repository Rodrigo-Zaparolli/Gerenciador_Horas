import 'spreadsheet_phase_dates.dart';
import '../../../domain/models/work_duration.dart';

class ChecklistHoursStage {
  const ChecklistHoursStage(this.name, this.hours);
  final String name, hours;
}

class ChecklistHoursRow {
  const ChecklistHoursRow(
      this.index, this.stage, this.minutes, this.count, this.warning);
  final int index, count;
  final ChecklistHoursStage stage;
  final int? minutes;
  final String? warning;
  bool get selectable =>
      warning == null &&
      minutes != null &&
      (RegExp(r'^\d+:[0-5]\d$').hasMatch(stage.hours.trim())
              ? WorkDuration.parse(stage.hours)
              : null) !=
          minutes;
}

String _key(String value) => spreadsheetStageKey(value)
    .replaceAll('í', 'i')
    .replaceAll('ú', 'u')
    .replaceAll('ô', 'o')
    .replaceAll('õ', 'o')
    .replaceAll('â', 'a')
    .replaceAll('à', 'a');

class ChecklistHoursComparison {
  const ChecklistHoursComparison(this.rows, this.unmatched);
  final List<ChecklistHoursRow> rows;
  final List<String> unmatched;
  factory ChecklistHoursComparison.build(
      Map<String, dynamic> data, List<ChecklistHoursStage> stages) {
    if (data['checklistHoursVersion'] != 1 || data['tasks'] is! List) {
      throw StateError(
          'Atualize e reinicie a integração local para importar as horas do checklist.');
    }
    final totals = <String, int>{},
        counts = <String, int>{},
        duplicates = <String, int>{};
    final labels = <String, String>{}, invalid = <String>{}, seen = <String>{};
    for (final stage in stages) {
      final k = _key(stage.name);
      duplicates[k] = (duplicates[k] ?? 0) + 1;
    }
    for (final raw in data['tasks'] as List) {
      if (raw is! Map ||
          raw['group'] is! String ||
          raw['sheet'] is! String ||
          raw['cell'] is! String) {
        throw StateError(
            'O checklist retornou uma tarefa sem identificação. Nenhuma hora foi alterada.');
      }
      final id = '${raw['sheet']}!${raw['cell']}';
      if (!seen.add(id))
        throw StateError(
            'O checklist retornou tarefas repetidas. Nenhuma hora foi alterada.');
      final k = _key(raw['group'] as String);
      if (k.isEmpty)
        throw StateError(
            'Há uma tarefa sem etapa no checklist. Nenhuma hora foi alterada.');
      labels[k] = raw['group'] as String;
      counts[k] = (counts[k] ?? 0) + 1;
      final minutes = raw['estimatedMinutes'];
      if (raw['estimatedValid'] != true || minutes is! int || minutes < 0) {
        invalid.add(k);
        continue;
      }
      totals[k] = (totals[k] ?? 0) + minutes;
    }
    return ChecklistHoursComparison([
      for (var i = 0; i < stages.length; i++)
        ChecklistHoursRow(
            i,
            stages[i],
            invalid.contains(_key(stages[i].name))
                ? null
                : totals[_key(stages[i].name)],
            counts[_key(stages[i].name)] ?? 0,
            (duplicates[_key(stages[i].name)] ?? 0) > 1
                ? 'Nome de etapa repetido no trabalho'
                : !counts.containsKey(_key(stages[i].name))
                    ? 'Sem correspondência no checklist'
                    : invalid.contains(_key(stages[i].name))
                        ? 'Há horas inválidas ou não consultadas nesta etapa'
                        : null)
    ], [
      for (final k in labels.keys)
        if (!duplicates.containsKey(k)) labels[k]!
    ]);
  }
}
