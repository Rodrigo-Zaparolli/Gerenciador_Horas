import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'comment_queue.dart';
import 'comment_queue_store.dart';

class CommentQueueDialog extends StatefulWidget {
  const CommentQueueDialog(
      {super.key, required this.store, required this.sender});
  final CommentQueueStore store;
  final QueueCommentSender sender;
  static Future<void> show(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommentQueueDialog(
          store: FirebaseCommentQueueStore(), sender: sendQueuedComment));
  @override
  State<CommentQueueDialog> createState() => _CommentQueueDialogState();
}

class _CommentQueueDialogState extends State<CommentQueueDialog> {
  late final runner = CommentQueueRunner(widget.store, widget.sender);
  late final stream = widget.store.watch();
  final selected = <String>{};
  bool busy = false;
  String message = '';
  Timer? accountTimer;
  Route<dynamic>? childRoute;
  String dialogTitle(BuildContext context, String title) {
    childRoute = ModalRoute.of(context);
    return title;
  }

  late bool accountAllowed;
  @override
  void initState() {
    super.initState();
    accountAllowed = widget.store.authorized;
    accountTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && accountAllowed != widget.store.authorized) {
        if (!widget.store.authorized && childRoute?.navigator != null) {
          childRoute!.navigator!.removeRoute(childRoute!);
        }
        setState(() {
          accountAllowed = widget.store.authorized;
          selected.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    accountTimer?.cancel();
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy || !widget.store.authorized) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => message = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(QueueEntry entry) async {
    await perform(() async {
      final comment = await widget.store.load(entry.id);
      if (!mounted || !widget.store.authorized) return;
      setState(() => busy = false);
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(dialogTitle(
                    context, '${comment.projectId} — ${comment.client}')),
                content: SizedBox(
                    width: 760,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(
                              '${comment.type} · ${comment.data['workName'] ?? ''} · Trabalho ${comment.workId}'),
                          if (comment.percentage != null)
                            Text('Percentual: ${comment.percentage}%'),
                          const Divider(),
                          SelectableText(comment.text),
                          for (final image in comment.images)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _image(image)),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar'))
                ],
              ));
    });
  }

  Widget _image(String image) {
    try {
      return Image.memory(
          base64Decode(
              image.startsWith('data:') ? image.split(',').last : image),
          width: 640,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Text('Não foi possível exibir esta imagem.'));
    } catch (_) {
      return const Text('Não foi possível exibir esta imagem.');
    }
  }

  Future<void> send(List<QueueEntry> entries) async {
    if (busy || !widget.store.authorized) return;
    final ready =
        entries.where((e) => e.ready && selected.contains(e.id)).toList();
    if (ready.isEmpty) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(dialogTitle(
                  context, 'Enviar ${ready.length} comentário(s)?')),
              content: SizedBox(
                  width: 600,
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        const Text(
                            'Os comentários serão publicados no E-Desk, um por vez, conforme a revisão da fila.'),
                        const SizedBox(height: 12),
                        for (final entry in ready)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                  '${entry.data['projectId']} — ${entry.data['client']}\n${entry.data['type']} · Trabalho ${entry.data['workId']}')),
                      ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirmar envio'))
              ],
            ));
    if (accepted != true || !mounted || busy || !widget.store.authorized) {
      return;
    }
    await perform(() async {
      message = 'Enviando um comentário por vez…';
      await runner.run(ready.map((e) => e.id).toList(), changed: refresh);
      selected.clear();
      message = runner.historyFailures.isEmpty
          ? 'Processamento encerrado. Confira o resultado individual de cada comentário.'
          : 'Há publicações confirmadas com histórico pendente no app. Use Salvar histórico, sem reenviar.';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: SizedBox(
              width: 1160,
              height: MediaQuery.sizeOf(context).height * .85,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(children: [
                          const Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Fila de comentários',
                                    style: TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    'Revise os comentários preparados antes de publicar no E-Desk.'),
                              ])),
                          IconButton(
                              tooltip: 'Fechar fila',
                              onPressed:
                                  busy ? null : () => Navigator.pop(context),
                              icon: const Icon(Icons.close)),
                        ])),
                    const Divider(height: 1),
                    Expanded(
                        child: !widget.store.authorized
                            ? const Center(
                                child: Text(
                                    'A conta mudou. Feche e abra a fila novamente.'))
                            : StreamBuilder<List<QueueEntry>>(
                                stream: stream,
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return const Center(
                                        child: Text(
                                            'Não foi possível carregar a fila. Confira a conexão e abra novamente.'));
                                  }
                                  if (!snapshot.hasData) {
                                    return const Center(
                                        child: CircularProgressIndicator());
                                  }
                                  final entries = snapshot.data!
                                      .where((entry) => entry.active)
                                      .toList();
                                  if (entries.isEmpty) {
                                    return const Center(
                                        child: Text(
                                            'Nenhum comentário na fila. Prepare um comentário e use Adicionar à fila.'));
                                  }
                                  final ready =
                                      entries.where((e) => e.ready).toList();
                                  return Column(children: [
                                    CheckboxListTile(
                                        title: Text(
                                            'Selecionar prontos (${ready.length})'),
                                        value: ready.isNotEmpty &&
                                            ready.every(
                                                (e) => selected.contains(e.id)),
                                        onChanged: busy
                                            ? null
                                            : (value) => setState(() {
                                                  selected.clear();
                                                  if (value == true) {
                                                    selected.addAll(
                                                        ready.map((e) => e.id));
                                                  }
                                                })),
                                    Expanded(
                                        child: ListView.separated(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20),
                                            itemCount: entries.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 10),
                                            itemBuilder: (context, i) {
                                              final entry = entries[i];
                                              return Card(
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            CheckboxListTile(
                                                                contentPadding:
                                                                    EdgeInsets
                                                                        .zero,
                                                                value: selected
                                                                    .contains(
                                                                        entry
                                                                            .id),
                                                                onChanged: busy ||
                                                                        !entry
                                                                            .ready
                                                                    ? null
                                                                    : (value) =>
                                                                        setState(
                                                                            () {
                                                                          if (value ==
                                                                              true) {
                                                                            selected.add(entry.id);
                                                                          } else {
                                                                            selected.remove(entry.id);
                                                                          }
                                                                        }),
                                                                title: Text(
                                                                    '${entry.data['projectId']} — ${entry.data['client']}',
                                                                    style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .bold)),
                                                                subtitle: Text(
                                                                    '${entry.data['type']} · Trabalho ${entry.data['workId']} · ${entry.data['imageCount']} imagem(ns)'
                                                                    '${entry.data['percentage'] == null ? '' : ' · ${entry.data['percentage']}%'}')),
                                                            Text(entry.data[
                                                                        'preview']
                                                                    ?.toString() ??
                                                                ''),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(entry.label,
                                                                style: TextStyle(
                                                                    fontWeight: FontWeight.bold,
                                                                    color: entry.published
                                                                        ? Theme.of(context).colorScheme.primary
                                                                        : entry.ready
                                                                            ? null
                                                                            : Theme.of(context).colorScheme.error)),
                                                            if ((entry.data[
                                                                        'message'] ??
                                                                    '') !=
                                                                '')
                                                              Text(entry.data[
                                                                      'message']
                                                                  .toString()),
                                                            Wrap(
                                                                spacing: 8,
                                                                runSpacing: 4,
                                                                children: [
                                                                  TextButton(
                                                                      onPressed: busy
                                                                          ? null
                                                                          : () => review(
                                                                              entry),
                                                                      child: const Text(
                                                                          'Revisar conteúdo')),
                                                                  if (entry
                                                                          .ready ||
                                                                      entry.state ==
                                                                          'failed')
                                                                    TextButton(
                                                                        onPressed: busy
                                                                            ? null
                                                                            : () => perform(() async {
                                                                                  await widget.store.remove(entry.id);
                                                                                  selected.remove(entry.id);
                                                                                }),
                                                                        child: const Text('Retirar da fila')),
                                                                  if (entry
                                                                          .state ==
                                                                      'failed')
                                                                    TextButton(
                                                                        onPressed: busy
                                                                            ? null
                                                                            : () => perform(() => widget.store.retry(entry
                                                                                .id)),
                                                                        child: const Text(
                                                                            'Liberar nova tentativa')),
                                                                  if (entry
                                                                          .published &&
                                                                      entry.data[
                                                                              'historySaved'] !=
                                                                          true)
                                                                    TextButton(
                                                                        onPressed: busy
                                                                            ? null
                                                                            : () => perform(() async {
                                                                                  final comment = await widget.store.load(entry.id);
                                                                                  await widget.store.saveHistory(entry.id, comment, percentagePending: entry.state == 'percentagePending');
                                                                                }),
                                                                        child: const Text('Salvar histórico')),
                                                                ]),
                                                          ])));
                                            })),
                                    Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Align(
                                            alignment: Alignment.centerRight,
                                            child: FilledButton.icon(
                                                onPressed: busy ||
                                                        !widget.store.authorized
                                                    ? null
                                                    : () => send(entries),
                                                icon: const Icon(Icons.send),
                                                label: Text(
                                                    'Revisar e enviar (${ready.where((e) => selected.contains(e.id)).length})')))),
                                  ]);
                                })),
                    if (busy) const LinearProgressIndicator(),
                    if (message.isNotEmpty && widget.store.authorized)
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(message)),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Row(children: [
                          const Expanded(
                              child: Text(
                                  'Envios sem confirmação não são repetidos automaticamente.',
                                  style: TextStyle(fontSize: 12))),
                          if (runner.running)
                            TextButton(
                                onPressed: () {
                                  runner.stopRequested = true;
                                  setState(() => message =
                                      'A fila será interrompida após a resposta do comentário atual.');
                                },
                                child: const Text('Parar após este')),
                          TextButton(
                              onPressed:
                                  busy ? null : () => Navigator.pop(context),
                              child: const Text('Fechar')),
                        ])),
                  ]))));
}
