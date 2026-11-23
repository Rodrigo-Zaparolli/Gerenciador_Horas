import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_send_review_policy.dart';
import 'package:gerenciador_horas/features/comment_queue/comment_queue.dart';

void main() {
  test('Only approved comment batches bypass individual review', () {
    expect(requiresEdeskSendReview('edesk_comentario.py'), isTrue);
    expect(requiresEdeskSendReview('edesk_comentario.py',
        commentBatchConfirmed: true), isFalse);
    expect(requiresEdeskSendReview('edesk_fases.py',
        commentBatchConfirmed: true), isTrue);
    expect(requiresEdeskSendReview('edesk_percentual.py',
        commentBatchConfirmed: true), isTrue);
  });
  test('Only fully completed entries leave the active queue', () {
    QueueEntry entry(String state, bool historySaved) =>
        QueueEntry('id', {'state': state, 'historySaved': historySaved});
    expect(entry('sent', true).active, isFalse);
    expect(entry('sent', false).active, isTrue);
    for (final state in ['ready', 'sending', 'failed', 'uncertain',
      'percentagePending']) {
      expect(entry(state, true).active, isTrue, reason: state);
    }
    expect(entry('cancelled', false).active, isFalse);
  });
}
