import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/dialogs/checklist_dates_button.dart';

void main() {
  test('Matches dates by stage name, never position; missing stages preserved', () {
    final result = checklistPeriods({'statusPreview': {'rows': [
      {'label': 'Implantação (OH)', 'start': '2026-11-01', 'end': '2026-11-30'},
    ]}}, ['Contato Inicial', 'Implantação']);
    expect(result.keys, [1]);
    expect(result[1]![1], DateTime(2026, 11, 30));
  });
  test('Rejects invalid dates, inverted periods and ambiguous matches', () {
    expect(checklistDate('2026-02-30'), isNull);
    expect(checklistDate(''), isNull);
    final row = {'label': 'Implantação', 'start': '2026-11-01', 'end': '2026-11-30'};
    expect(checklistPeriods({'statusPreview': {'rows': [row, row]}}, ['Implantação']), isEmpty);
    expect(checklistPeriods({'statusPreview': {'rows': [row]}}, ['Implantação', 'Implantação']), isEmpty);
    expect(checklistPeriods({'statusPreview': {'rows': [{...row, 'end': '2026-10-01'}]}}, ['Implantação']), isEmpty);
  });
}
