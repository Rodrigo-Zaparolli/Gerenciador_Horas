import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/comment_queue/comment_queue_dialog.dart';
import 'support/comment_queue_memory.dart';
import 'comment_queue_test.dart' show sent;

void main() {
  testWidgets('Changing account closes review and hides the old account queue',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryCommentQueue();
    final a = queueFixture();
    await store.enqueue(a);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommentQueueDialog(
                store: store,
                sender: (_) async {
                  calls++;
                  return sent;
                }))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar conteúdo'));
    await tester.pumpAndSettle();
    expect(find.text(a.text), findsWidgets);
    store.authorized = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(a.text), findsNothing);
    expect(find.text('A conta mudou. Feche e abra a fila novamente.'),
        findsOneWidget);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    await store.updates.close();
  });
  testWidgets('Queue selection and final confirmation precede publication',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryCommentQueue();
    final a = queueFixture();
    await store.enqueue(a);
    await store.enqueue(queueFixture('2265002'));
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommentQueueDialog(
                store: store,
                sender: (_) async {
                  calls++;
                  return sent;
                }))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Revisar conteúdo').first);
    await tester.pumpAndSettle();
    expect(find.text(a.text), findsWidgets);
    expect(find.text('Percentual: 43.0%'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Fechar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selecionar prontos (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar e enviar (2)'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Confirmar envio'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Enviado'), findsNothing);
    expect(find.text('Revisar conteúdo'), findsNothing);
    expect(store.histories, hasLength(2));
    expect(await store.enqueue(a), false);
    await tester.pumpWidget(const SizedBox());
    await store.updates.close();
  });
}
