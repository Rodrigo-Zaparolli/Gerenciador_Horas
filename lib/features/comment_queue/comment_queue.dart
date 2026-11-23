import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../data/services/edesk_service.dart';

class QueuedComment {
  QueuedComment(Map<String, dynamic> value) : _json = jsonEncode(value) {
    if (projectId.isEmpty ||
        !RegExp(r'^\d+$').hasMatch(workId) ||
        !RegExp(r'^\d+$').hasMatch(projectId)) {
      throw const FormatException(
          'Confira a solicitação e o ID do trabalho antes de adicionar à fila.');
    }
    if (!['Interno', 'Externo', 'Padrão', 'Padrão (Interno)'].contains(type)) {
      throw const FormatException('Tipo de comentário inválido.');
    }
    if (utf8.encode(_json).length > 6 * 1024 * 1024 ||
        utf8.encode(jsonEncode(snapshot)).length > 750000) {
      throw const FormatException(
          'As imagens deste comentário excedem o tamanho da fila. Reduza os prints e tente novamente.');
    }
    final percentage = data['percentage'];
    if (percentage != null &&
        (percentage is! num ||
            !percentage.isFinite ||
            percentage < 0 ||
            percentage > 100)) {
      throw const FormatException('O percentual deve estar entre 0 e 100.');
    }
    if (text.trim().isEmpty && images.isEmpty) {
      throw const FormatException('O comentário está vazio.');
    }
  }
  final String _json;
  Map<String, dynamic> get data => Map<String, dynamic>.from(jsonDecode(_json));
  String get encoded => _json;
  String get id => sha256.convert(utf8.encode(_json)).toString();
  String get projectId => data['projectId'] as String;
  String get client => data['client'] as String;
  String get workId => data['workId'] as String;
  String get type => data['type'] as String;
  String get text => data['text'] as String;
  String get html => data['html'] as String;
  List<String> get images => (data['images'] as List).cast<String>();
  Map<String, dynamic> get snapshot =>
      Map<String, dynamic>.from(data['snapshot'] as Map);
  double? get percentage => (data['percentage'] as num?)?.toDouble();
  String? get imagePayload => images.isEmpty
      ? null
      : images.length == 1
          ? images.single
          : jsonEncode(images);
  Map<String, dynamic> get metadata => {
        'workName': data['workName'] ?? '',
        'projectId': projectId,
        'client': client,
        'workId': workId,
        'type': type,
        'preview': text.length > 140 ? '${text.substring(0, 140)}…' : text,
        'imageCount': images.length,
        'percentage': percentage,
      };
}

List<String> encodeQueueParts(QueuedComment comment) {
  final encoded = base64Encode(utf8.encode(comment.encoded));
  return [
    for (var i = 0; i < encoded.length; i += 350000)
      encoded.substring(
          i, i + 350000 < encoded.length ? i + 350000 : encoded.length)
  ];
}

QueuedComment decodeQueueParts(String id, Iterable<String> parts) {
  final comment = QueuedComment(Map<String, dynamic>.from(
      jsonDecode(utf8.decode(base64Decode(parts.join()))) as Map));
  if (comment.id != id) {
    throw StateError('O conteúdo salvo foi alterado ou está incompleto.');
  }
  return comment;
}

class QueueEntry {
  const QueueEntry(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  String get state => data['state'] as String? ?? 'uncertain';
  bool get ready => state == 'ready';
  bool get active =>
      state != 'cancelled' && !(state == 'sent' && data['historySaved'] == true);
  bool get published => ['sent', 'percentagePending'].contains(state);
  String get label => switch (state) {
        'ready' => 'Pronto para enviar',
        'sending' => 'Em envio — confira se foi interrompido',
        'sent' => 'Enviado',
        'percentagePending' => 'Publicado; percentual pendente',
        'failed' => 'Falhou antes de publicar',
        'cancelled' => 'Retirado da fila',
        _ => 'Precisa de conferência',
      };
}

abstract class CommentQueueStore {
  bool get authorized;
  Stream<List<QueueEntry>> watch();
  Future<QueueEntry?> get(String id);
  Future<bool> enqueue(QueuedComment comment);
  Future<QueuedComment> load(String id);
  Future<String?> claim(String id);
  Future<void> finish(String id, String attempt, String state, String message);
  Future<void> remove(String id);
  Future<void> retry(String id);
  Future<void> saveHistory(String id, QueuedComment comment,
      {required bool percentagePending});
}

typedef QueueCommentSender = Future<EdeskSendResult> Function(
    QueuedComment comment);

class CommentQueueRunner {
  CommentQueueRunner(this.store, this.sender);
  final CommentQueueStore store;
  final QueueCommentSender sender;
  bool running = false;
  bool stopRequested = false;
  final List<String> historyFailures = [];
  Future<void> run(List<String> ids, {void Function()? changed}) async {
    if (running) return;
    running = true;
    stopRequested = false;
    historyFailures.clear();
    try {
      for (final id in ids.toSet()) {
        if (stopRequested || !store.authorized) break;
        // Validate the saved snapshot before reserving a publication attempt.
        final comment = await store.load(id);
        if (comment.id != id) {
          throw StateError(
              'O conteúdo da fila não corresponde ao comentário revisado.');
        }
        if (stopRequested || !store.authorized) break;
        final attempt = await store.claim(id);
        if (attempt == null) continue;
        if (!store.authorized) break;
        changed?.call();
        EdeskSendResult result;
        try {
          result = await sender(comment);
        } catch (_) {
          if (store.authorized) {
            await store.finish(id, attempt, 'uncertain',
                'A resposta do envio não foi confirmada. Confira no E-Desk antes de repetir.');
          }
          changed?.call();
          break;
        }
        if (!store.authorized) break;
        final state = result.commentPublished
            ? result.confirmed
                ? 'sent'
                : 'percentagePending'
            : !result.confirmed &&
                    [400, 401, 403, 409].contains(result.statusCode)
                ? 'failed'
                : 'uncertain';
        // Save the receipt before the app history. A history failure never
        // makes an already published comment eligible for another POST.
        await store.finish(id, attempt, state, result.message);
        changed?.call();
        if (state == 'sent' || state == 'percentagePending') {
          try {
            await store.saveHistory(id, comment,
                percentagePending: state == 'percentagePending');
          } catch (_) {
            historyFailures.add(id);
          }
        }
        if (state != 'sent') break;
      }
    } finally {
      running = false;
      changed?.call();
    }
  }
}
