import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/features/comment_queue/comment_queue.dart';
import 'support/comment_queue_memory.dart';

const sent = EdeskSendResult(
    confirmed: true,
    statusCode: 200,
    message: 'Publicado.',
    responseBody:
        '{"operation":"comentarios","commentSaved":true,"percentageConfirmed":true}');

void main() {
  test(
      'Persisted chunks preserve Unicode, formatting, images and reject changed content',
      () {
    final data = queueFixture().data;
    data['images'] = [List.filled(400000, 'A').join()];
    data['html'] =
        '[[EDESK_HTML]]<p><strong>Ação concluída — revisão</strong></p>';
    final comment = QueuedComment(data);
    final parts = encodeQueueParts(comment);
    expect(parts.length, greaterThan(1));
    final restored = decodeQueueParts(comment.id, parts);
    expect(restored.data, comment.data);
    expect(() => decodeQueueParts(queueFixture('2265002').id, parts),
        throwsStateError);
    expect(
        () => decodeQueueParts(comment.id, parts.skip(1)), throwsA(anything));
  });
  test(
      'Snapshot is immutable, retains images and has a stable content identity',
      () async {
    final data = queueFixture().data;
    data['images'] = ['aW1hZ2Vt'];
    final comment = QueuedComment(data);
    (data['images'] as List).clear();
    expect(comment.images, ['aW1hZ2Vt']);
    expect(comment.percentage, 43);
    expect(QueuedComment(comment.data).id, comment.id);
    expect(queueFixture('2265002').id, isNot(queueFixture().id));
    final store = MemoryCommentQueue();
    expect(await store.enqueue(comment), true);
    expect(await store.enqueue(comment), false);
    expect(store.entries, hasLength(1));
  });
  test('Batch is sequential and never reposts a confirmed entry', () async {
    final store = MemoryCommentQueue();
    final a = queueFixture(), b = queueFixture('2265002');
    await store.enqueue(a);
    await store.enqueue(b);
    final receipt = Completer<EdeskSendResult>();
    final calls = <String>[];
    final runner = CommentQueueRunner(store, (c) async {
      calls.add(c.projectId);
      return calls.length == 1 ? receipt.future : sent;
    });
    final running = runner.run([a.id, b.id]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, [a.projectId]);
    expect(store.entries[a.id]!['state'], 'sending');
    receipt.complete(sent);
    await running;
    expect(calls, [a.projectId, b.projectId]);
    await runner.run([a.id, b.id]);
    expect(calls, hasLength(2));
    expect(store.histories, hasLength(2));
  });
  test('Uncertain delivery stops the batch and remains ineligible for retry',
      () async {
    final store = MemoryCommentQueue();
    final a = queueFixture(), b = queueFixture('2265002');
    await store.enqueue(a);
    await store.enqueue(b);
    var calls = 0;
    final runner = CommentQueueRunner(store, (_) async {
      calls++;
      throw TimeoutException('Unknown delivery');
    });
    await runner.run([a.id, b.id]);
    expect(store.entries[a.id]!['state'], 'uncertain');
    expect(store.entries[b.id]!['state'], 'ready');
    await runner.run([a.id]);
    expect(calls, 1);
  });
  test('Partial percentage receipt does not repost the saved comment',
      () async {
    final store = MemoryCommentQueue();
    final a = queueFixture();
    await store.enqueue(a);
    var calls = 0;
    final runner = CommentQueueRunner(store, (_) async {
      calls++;
      return const EdeskSendResult(
          confirmed: false,
          statusCode: 502,
          message: 'Percentual pendente.',
          responseBody:
              '{"operation":"comentarios","commentSaved":true,"percentageConfirmed":false}');
    });
    await runner.run([a.id]);
    await runner.run([a.id]);
    expect(store.entries[a.id]!['state'], 'percentagePending');
    expect(store.histories, [a.id]);
    expect(calls, 1);
  });
  test('History persistence failure does not enable another publication',
      () async {
    final store = MemoryCommentQueue()..failHistory = true;
    final a = queueFixture();
    await store.enqueue(a);
    var calls = 0;
    final runner = CommentQueueRunner(store, (_) async {
      calls++;
      return sent;
    });
    await runner.run([a.id]);
    expect(runner.historyFailures, [a.id]);
    expect(store.entries[a.id]!['state'], 'sent');
    await runner.run([a.id]);
    expect(calls, 1);
    store.failHistory = false;
    await store.saveHistory(a.id, a, percentagePending: false);
    expect(store.histories, [a.id]);
  });
  test('Two runners cannot claim the same queued comment', () async {
    final store = MemoryCommentQueue();
    final a = queueFixture();
    await store.enqueue(a);
    var calls = 0;
    Future<EdeskSendResult> sender(QueuedComment _) async {
      calls++;
      return sent;
    }

    await Future.wait([
      CommentQueueRunner(store, sender).run([a.id]),
      CommentQueueRunner(store, sender).run([a.id])
    ]);
    expect(calls, 1);
  });
  test('Account change during delivery stops the next comment', () async {
    final store = MemoryCommentQueue();
    final a = queueFixture(), b = queueFixture('2265002');
    await store.enqueue(a);
    await store.enqueue(b);
    var calls = 0;
    final runner = CommentQueueRunner(store, (_) async {
      calls++;
      store.authorized = false;
      return sent;
    });
    await runner.run([a.id, b.id]);
    expect(calls, 1);
    expect(store.entries[b.id]!['state'], 'ready');
    expect(store.entries[a.id]!['state'], 'sending');
  });
  test(
      'Only explicit retry of a known pre-publication failure releases an entry',
      () async {
    final store = MemoryCommentQueue();
    final a = queueFixture();
    await store.enqueue(a);
    await CommentQueueRunner(
        store,
        (_) async => const EdeskSendResult(
            confirmed: false,
            statusCode: 409,
            message: 'Integração ocupada.',
            responseBody: '')).run([a.id]);
    expect(store.entries[a.id]!['state'], 'failed');
    await store.retry(a.id);
    await CommentQueueRunner(store, (_) async => sent).run([a.id]);
    expect(store.entries[a.id]!['state'], 'sent');
  });
  test('Stopping a batch waits for current receipt and leaves others ready',
      () async {
    final store = MemoryCommentQueue();
    final a = queueFixture(), b = queueFixture('2265002');
    await store.enqueue(a);
    await store.enqueue(b);
    late CommentQueueRunner runner;
    runner = CommentQueueRunner(store, (_) async {
      runner.stopRequested = true;
      return sent;
    });
    await runner.run([a.id, b.id]);
    expect(store.entries[a.id]!['state'], 'sent');
    expect(store.entries[b.id]!['state'], 'ready');
  });
}
