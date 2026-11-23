import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/projects/widgets/project_toolbar_actions.dart';

void main() {
  for (final width in [320.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('compact toolbar routes actions at $width / $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final called = <String>[];
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
                body: ProjectSectionHeading(
                    projectCount: 16,
                    actions: ProjectToolbarActions(
                      onQueue: () => called.add('queue'),
                      onReceived: () => called.add('received'),
                      onAudit: () => called.add('audit'),
                      onInternalNs: () => called.add('ns'),
                      onDocumentation: () => called.add('documentation'),
                    )))));
        expect(find.text('Solicitar NS de uso interno'), findsNothing);
        expect(find.text('Trabalhos recebidos'), findsNothing);
        expect(find.text('Conferir no E-Desk'), findsNothing);
        await tester.tap(find.text('Fila de comentários'));
        await tester.pumpAndSettle();
        expect(called, ['queue']);
        for (final entry in {
          'Trabalhos recebidos': 'received',
          'Conferir no E-Desk': 'audit',
          'Solicitar NS de uso interno': 'ns',
          'Solicitar documentação de plugin': 'documentation',
        }.entries) {
          await tester.tap(find.text('Ações'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(entry.key));
          await tester.pumpAndSettle();
          expect(called.last, entry.value);
          expect(find.text(entry.key), findsNothing);
        }
        expect(called, ['queue', 'received', 'audit', 'ns', 'documentation']);
        expect(tester.takeException(), isNull);
        if (width > 1000) {
          expect(
              (tester.getCenter(find.text('Projetos e tarefas')).dy -
                      tester.getCenter(find.text('Ações')).dy)
                  .abs(),
              lessThan(25));
        }
      });
    }
  }
}
