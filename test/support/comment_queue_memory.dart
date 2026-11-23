import 'dart:async';
import 'package:gerenciador_horas/features/comment_queue/comment_queue.dart';

class MemoryCommentQueue implements CommentQueueStore {
  final entries = <String, Map<String, dynamic>>{};
  final content = <String, QueuedComment>{};
  final updates = StreamController<List<QueueEntry>>.broadcast();
  final histories = <String>[];
  bool failHistory = false;
  @override
  bool authorized = true;
  void emit() => updates.add(entries.entries
      .map((e) => QueueEntry(e.key, Map.of(e.value)))
      .where((e) => e.state != 'cancelled')
      .toList());
  @override
  Stream<List<QueueEntry>> watch() async* {
    yield entries.entries
        .map((e) => QueueEntry(e.key, Map.of(e.value)))
        .toList();
    yield* updates.stream;
  }

  @override
  Future<QueueEntry?> get(String id) async =>
      entries[id] == null ? null : QueueEntry(id, Map.of(entries[id]!));
  @override
  Future<bool> enqueue(QueuedComment comment) async {
    if (entries.containsKey(comment.id) &&
        entries[comment.id]!['state'] != 'cancelled') return false;
    content[comment.id] = comment;
    entries[comment.id] = {
      ...comment.metadata,
      'state': 'ready',
      'historySaved': false
    };
    emit();
    return true;
  }

  @override
  Future<QueuedComment> load(String id) async => content[id]!;
  @override
  Future<String?> claim(String id) async {
    if (!authorized || entries[id]!['state'] != 'ready') return null;
    entries[id]!.addAll({'state': 'sending', 'attempt': id});
    emit();
    return id;
  }

  @override
  Future<void> finish(
      String id, String attempt, String state, String message) async {
    entries[id]!.addAll({'state': state, 'message': message});
    emit();
  }

  @override
  Future<void> remove(String id) async {
    entries[id]!['state'] = 'cancelled';
    emit();
  }

  @override
  Future<void> retry(String id) async {
    if (entries[id]!['state'] != 'failed') throw StateError('Not retryable');
    entries[id]!['state'] = 'ready';
    emit();
  }

  @override
  Future<void> saveHistory(String id, QueuedComment comment,
      {required bool percentagePending}) async {
    if (failHistory) throw StateError('Offline');
    if (!histories.contains(id)) histories.add(id);
    entries[id]!['historySaved'] = true;
    emit();
  }
}

QueuedComment queueFixture([String project = '2265001']) => QueuedComment({
      'projectId': project,
      'client': 'Cliente $project',
      'workId': '3',
      'workName': 'Implantação',
      'type': 'Interno',
      'text': 'Reunião realizada e próximos passos alinhados.',
      'html':
          '[[EDESK_HTML]]<p>Reunião realizada e próximos passos alinhados.</p>',
      'delta': [
        {'insert': 'Reunião realizada e próximos passos alinhados.\n'}
      ],
      'images': <String>[],
      'percentage': 43.0,
      'snapshot': {
        'comentario': 'Reunião realizada e próximos passos alinhados.',
        'tipoComentario': 'Interno',
        'projetoId': project,
        'percentualRealizado': 43.0
      },
    });
