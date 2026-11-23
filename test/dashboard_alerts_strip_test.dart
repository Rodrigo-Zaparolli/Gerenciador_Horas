import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/project_update_service.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/dashboard_alerts_strip.dart';
import 'dashboard_cards_test.dart' as fixture;

void main() {
  for (final width in [1093.0, 1600.0]) {
    testWidgets('strip includes comment deadlines and opens full central at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final project = fixture.project([])..client = 'Cliente com comentario pendente';
      final today = DateTime(2026, 11, 23);
      var opened = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: DashboardAlertsStrip(projects: const [], updates: [
          PendingProjectUpdate(project, ProjectCommentUpdate('a', today.subtract(const Duration(days: 15)), 'enviado'), today),
        ], onOpen: () => opened = true, formatDate: ProjectUpdateService.formatDate),
      ))));
      expect(find.text('Atualizações de comentários (1)'), findsOneWidget);
      expect(find.text(project.client), findsOneWidget);
      expect(find.text('Em atraso'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Comentários'));
      await tester.pumpAndSettle();
      expect(opened, isFalse);
      expect(find.text('Projetos com datas a vencer nos próximos dias'), findsNothing);
      expect(find.text(project.client), findsOneWidget);
      await tester.tap(find.text('Comentários'));
      await tester.pumpAndSettle();
      expect(find.text('Projetos com datas a vencer nos próximos dias'), findsOneWidget);
      await tester.tap(find.text('Prazos próximos'));
      await tester.pumpAndSettle();
      expect(find.text(project.client), findsNothing);
      expect(find.text('Atualizações de comentários (1)'), findsNothing);
      expect(opened, isFalse);
      if (width < 1200) {
        await tester.tap(find.text('Ver todos os alertas'));
      } else {
        await tester.tap(find.byTooltip('Ver todos os alertas'));
      }
      expect(opened, isTrue);
    });
  }
}
