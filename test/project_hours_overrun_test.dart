import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/progresso_projeto_widget.dart';
import 'dashboard_cards_test.dart' as fixtures;

void main() {
  for (final hours in ['16:00', '17:00', '20:00']) {
    testWidgets('Project hours ring with $hours actual against 17 planned',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
        width: 650,
        height: 300,
        child: ProgressoProjetoWidget(
          activeProject: fixtures.project([]),
          timeLogs: [fixtures.log('a', '100', hours)],
          parseTimeToHours: fixtures.parseHours,
          formatHours: fixtures.formatHours,
          formatDateShort: (_) => '23/11/2026',
        ),
      ))));
      final ring = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator));
      final actual = fixtures.parseHours(hours);
      expect(ring.value, (actual / 17).clamp(0.0, 1.0));
      expect(ring.color, actual > 17 ? AppPalette.danger : AppPalette.accent);
      expect(find.text('${(actual / 17 * 100).round()}%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
