import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_actions_pilot.dart';

void main() {
  testWidgets('Compact actions route every menu item to its own callback',
      (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectActionsPilot(
                hasFolder: true,
                hasExcel: true,
                onFolder: () => selected = 'folder',
                onExcel: () => selected = 'open',
                onEditSpreadsheet: () => selected = 'edit',
                onEditWork: () => selected = 'work',
                onChecklist: () => selected = 'check',
                onComment: () => selected = 'comment',
                onEmail: () => selected = 'email',
                onAdv: () => selected = 'adv',
                onZendesk: () => selected = 'zendesk',
                projectId: '2265123',
                client: 'Cliente de teste',
                onPhases: () => selected = 'phases',
                onPluginNs: () => selected = 'plugin-ns'))));
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.text('Pasta'), findsNothing);
    expect(find.text('Planilha'), findsNothing);
    for (final item in {
      'Editar planilha no sistema': 'edit',
      'Abrir pasta': 'folder',
      'Abrir planilha no Excel': 'open',
      'Editar trabalho': 'work',
      'Checklist': 'check',
      'Comentários': 'comment',
      'E-mails': 'email',
      'Criar trabalho para ADV': 'adv',
      'Solicitar NS de plugin': 'plugin-ns',
      'Enviar fases ao E-Desk': 'phases',
      'Abrir solicitação no Zendesk': 'zendesk',
    }.entries) {
      await tester.tap(find.byTooltip('Ações do projeto'));
      await tester.pumpAndSettle();
      expect(find.text('Abrir pasta'), findsNothing);
      expect(find.text('Abrir planilha no Excel'), findsNothing);
      expect(tester.widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>)).map((e) => e.value).toList(),
          ['spreadsheet', 'work', 'comment', 'email', 'more']);
      if (['folder', 'open', 'check', 'adv', 'plugin-ns', 'phases', 'zendesk']
          .contains(item.value)) {
        await tester.tap(find.text('Mais ações…'));
        await tester.pumpAndSettle();
        expect(find.text('Cliente de teste'), findsOneWidget);
        expect(find.text('Solicitação 2265123'), findsOneWidget);
        expect(find.text('Editar planilha no sistema'), findsNothing);
        await tester.ensureVisible(find.text(item.key));
      }
      await tester.tap(find.text(item.key));
      await tester.pumpAndSettle();
      expect(selected, item.value);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProjectActionsPilot(
                hasFolder: false,
                hasExcel: false,
                onFolder: () => selected = 'folder',
                onExcel: () => selected = 'open',
                onEditSpreadsheet: () => selected = 'edit',
                onEditWork: () => selected = 'work',
                onChecklist: () => selected = 'check',
                onComment: () => selected = 'comment',
                onEmail: () => selected = 'email'))));
    await tester.tap(find.byTooltip('Ações do projeto'));
    await tester.pumpAndSettle();
    final entries = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>)).toList();
    expect(
        entries
            .where((e) => ['folder', 'open', 'spreadsheet'].contains(e.value))
            .every((e) => !e.enabled),
        isTrue);
    await tester.tap(find.text('Mais ações…'));
    await tester.pumpAndSettle();
    expect(find.text('Editar planilha no sistema'), findsNothing);
    for (final label in ['Abrir pasta', 'Abrir planilha no Excel']) {
      final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, label));
      expect(tile.enabled, false);
      expect(tile.onTap, isNull);
    }
    expect(
        entries
            .where(
                (e) => ['work', 'check', 'comment', 'email'].contains(e.value))
            .every((e) => e.enabled),
        isTrue);
  });
}
