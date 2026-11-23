import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/edesk_service.dart';
import '../../data/services/project_update_service.dart';
import 'comment_queue.dart';

class FirebaseCommentQueueStore implements CommentQueueStore {
  FirebaseCommentQueueStore() : owner = FirebaseAuth.instance.currentUser?.uid;
  final String? owner;
  @override
  bool get authorized =>
      owner != null && FirebaseAuth.instance.currentUser?.uid == owner;
  void _check() {
    if (!authorized) throw StateError('A conta mudou. Abra a fila novamente.');
  }

  CollectionReference<Map<String, dynamic>> get collection =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('comment_queue');
  @override
  Stream<List<QueueEntry>> watch() {
    _check();
    return collection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) {
      _check();
      return s.docs
          .map((d) => QueueEntry(d.id, d.data()))
          .where((e) => e.active)
          .toList();
    });
  }

  @override
  Future<QueueEntry?> get(String id) async {
    _check();
    final doc =
        await collection.doc(id).get(const GetOptions(source: Source.server));
    _check();
    return doc.exists ? QueueEntry(id, doc.data()!) : null;
  }

  @override
  Future<bool> enqueue(QueuedComment comment) async {
    _check();
    final parts = encodeQueueParts(comment);
    return FirebaseFirestore.instance.runTransaction<bool>((tx) async {
      final ref = collection.doc(comment.id);
      final previous = await tx.get(ref);
      _check();
      if (previous.exists && previous.data()?['state'] != 'cancelled') {
        return false;
      }
      for (var i = 0; i < parts.length; i++) {
        tx.set(ref.collection('content').doc('$i'), {'data': parts[i]});
      }
      tx.set(ref, {
        ...comment.metadata,
        'state': 'ready',
        'parts': parts.length,
        'createdAt': FieldValue.serverTimestamp(),
        'message': '',
        'historySaved': false
      });
      return true;
    }).timeout(const Duration(seconds: 30));
  }

  @override
  Future<QueuedComment> load(String id) async {
    _check();
    final entry = await get(id);
    if (entry == null) throw StateError('O comentário não está mais na fila.');
    final parts = entry.data['parts'];
    if (parts is! int || parts < 1 || parts > 26) {
      throw StateError('Conteúdo da fila inválido.');
    }
    final content = await Future.wait([
      for (var i = 0; i < parts; i++)
        collection
            .doc(id)
            .collection('content')
            .doc('$i')
            .get(const GetOptions(source: Source.server))
    ]);
    _check();
    final savedParts = content
        .map((d) =>
            d.data()?['data'] as String? ??
            (throw StateError('Conteúdo incompleto.')))
        .toList();
    return decodeQueueParts(id, savedParts);
  }

  @override
  Future<String?> claim(String id) async {
    _check();
    final attempt = collection.doc().id;
    return FirebaseFirestore.instance.runTransaction<String?>((tx) async {
      final ref = collection.doc(id);
      final doc = await tx.get(ref);
      _check();
      if (doc.data()?['state'] != 'ready') return null;
      tx.update(ref, {
        'state': 'sending',
        'attempt': attempt,
        'startedAt': FieldValue.serverTimestamp()
      });
      return attempt;
    });
  }

  @override
  Future<void> finish(
      String id, String attempt, String state, String message) async {
    _check();
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final ref = collection.doc(id);
      final doc = await tx.get(ref);
      _check();
      if (doc.data()?['state'] != 'sending' ||
          doc.data()?['attempt'] != attempt) {
        throw StateError(
            'A tentativa de envio mudou. Confira o resultado no E-Desk.');
      }
      tx.update(ref, {
        'state': state,
        'message': message,
        'finishedAt': FieldValue.serverTimestamp()
      });
    });
  }

  Future<void> _transition(String id, Set<String> from, String next) async {
    _check();
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final ref = collection.doc(id);
      final doc = await tx.get(ref);
      _check();
      if (!from.contains(doc.data()?['state'])) {
        throw StateError('Este comentário não pode ser alterado neste estado.');
      }
      tx.update(ref, {'state': next});
    });
  }

  @override
  Future<void> remove(String id) =>
      _transition(id, {'ready', 'failed'}, 'cancelled');
  @override
  Future<void> retry(String id) => _transition(id, {'failed'}, 'ready');
  @override
  Future<void> saveHistory(String id, QueuedComment comment,
      {required bool percentagePending}) async {
    _check();
    final saved = await get(id);
    if (saved == null || !saved.published) {
      throw StateError('Publicação ainda não confirmada.');
    }
    final now = DateTime.now();
    final user = FirebaseAuth.instance.currentUser!;
    final batch = FirebaseFirestore.instance.batch();
    batch.set(
        FirebaseFirestore.instance
            .collection('users')
            .doc(owner)
            .collection('projects')
            .doc(comment.projectId)
            .collection('comentarios_edesk')
            .doc('fila_$id'),
        {
          ...comment.snapshot,
          ...ProjectUpdateService.confirmedCommentFields(now),
          'usuarioId': owner,
          'usuario': user.displayName ?? user.email ?? 'Usuário',
          'dataHora': saved.data['finishedAt'] ?? Timestamp.fromDate(now),
          'enviadoEm': saved.data['finishedAt'] ?? Timestamp.fromDate(now),
          'modoExecucao': 'Envio',
          'filaId': id,
          'tentativas': 1,
          'percentualPendente': percentagePending,
        });
    batch.update(collection.doc(id), {'historySaved': true});
    _check();
    await batch.commit();
  }
}

Future<EdeskSendResult> sendQueuedComment(QueuedComment comment) async {
  final service = EdeskService();
  try {
    return await service.executarComentarioViaPython(
        pageUri: Uri.parse('https://promob.e-desk.com.br'),
        solicitacao: comment.projectId,
        idTrabalho: comment.workId,
        tipoComentario: comment.type,
        texto: comment.html,
        editorDeltaPreview: (comment.data['delta'] as List).cast<dynamic>(),
        imagemBase64: comment.imagePayload,
        percentualRealizado: comment.percentage,
        enviar: true,
        commentBatchConfirmed: true);
  } finally {
    service.dispose();
  }
}
