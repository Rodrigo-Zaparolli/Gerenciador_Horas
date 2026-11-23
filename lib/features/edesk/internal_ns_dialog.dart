import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/edesk_integration.dart';
import '../../data/services/edesk_credentials_service.dart';
import '../../data/services/edesk_creation_request.dart';

const internalNsEntryUrl = edeskEntryUrl;

Map<String, dynamic> internalNsRequest(
        {required String operationId,
        required String subject,
        required String description}) =>
    edeskCreationRequest({
      'operationId': operationId,
      'confirmed': true,
      'subject': subject.trim(),
      'description': description.trim(),
    });

class InternalNsDialog extends StatefulWidget {
  const InternalNsDialog({super.key, this.sender, this.authorized});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? sender;
  final bool Function()? authorized;
  static Future<void> show(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const InternalNsDialog());
  @override
  State<InternalNsDialog> createState() => _InternalNsDialogState();
}

class _InternalNsDialogState extends State<InternalNsDialog> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController(text: 'NS para uso interno');
  final description = TextEditingController();
  late final owner =
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  late final operation = List.generate(16,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
  bool busy = false, finished = false, uncertain = false, postStarted = false;
  String? message;
  bool get authorized =>
      widget.authorized?.call() ??
      (owner != null && FirebaseAuth.instance.currentUser?.uid == owner);
  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    if (data['url'] != internalNsEntryUrl) {
      throw StateError(
          'O endereço de abertura do E-Desk não foi preparado. Feche e abra o formulário novamente. Nenhuma solicitação foi enviada.');
    }
    final health =
        await EdeskIntegrationApi.call('/healthz', authenticated: false);
    if (health['internalNsCreate'] != true) {
      throw StateError(
          'Atualize e reinicie a integração local para solicitar NS de uso interno. Nenhuma solicitação foi enviada.');
    }
    final credentials = await EdeskCredentialsService().ler();
    if (!authorized) {
      throw StateError('A conta mudou. Abra o formulário novamente.');
    }
    if (credentials == null) {
      throw StateError(
          'Configure o acesso ao E-Desk antes de criar a solicitação.');
    }
    postStarted = true;
    return EdeskIntegrationApi.call('/api/edesk/ns-interno',
        timeout: const Duration(minutes: 15),
        body: {
          'request': {...data, 'edeskCredenciais': credentials},
          'enviar': true
        });
  }

  Future<void> send() async {
    if (busy ||
        finished ||
        uncertain ||
        !authorized ||
        !form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
      postStarted = false;
    });
    try {
      if (widget.sender != null) postStarted = true;
      final result = await (widget.sender ?? create)(internalNsRequest(
          operationId: operation,
          subject: subject.text,
          description: description.text));
      if (!mounted || !authorized) return;
      if (result['confirmed'] != true) {
        throw StateError(result['message']?.toString() ??
            'Resultado não confirmado. Confira o E-Desk antes de repetir.');
      }
      setState(() {
        finished = true;
        message = result['message']?.toString() ??
            'Solicitação confirmada no E-Desk.';
      });
    } catch (error) {
      if (mounted && authorized) {
        setState(() {
          uncertain = postStarted;
          message =
              '$error${uncertain ? '\nConfira a solicitação no E-Desk antes de tentar novamente.' : ''}';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Solicitar NS de uso interno'),
        content: SizedBox(
            width: 660,
            child: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Nova solicitação no E-Desk',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          const Text(
                              'Grupo de Serviço: Sales OPS\nServiço: Serviços Internos\nProcesso: Uso Interno - Novo NS'),
                          const SizedBox(height: 12),
                          const Text(
                              'Revise o pedido. Esta solicitação é para uso interno e não será cadastrada como um projeto de cliente.'),
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: subject,
                              enabled: !busy && !finished && !uncertain,
                              maxLength: 200,
                              decoration:
                                  const InputDecoration(labelText: 'Assunto'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Informe o assunto.'
                                  : null),
                          const SizedBox(height: 8),
                          TextFormField(
                              controller: description,
                              enabled: !busy && !finished && !uncertain,
                              minLines: 5,
                              maxLines: 12,
                              maxLength: 10000,
                              decoration: const InputDecoration(
                                  labelText: 'Detalhamento',
                                  hintText:
                                      'Solicito NS Plugin [nome do plugin] para uso interno.'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Informe o detalhamento.'
                                  : null),
                          if (busy) const LinearProgressIndicator(),
                          if (message != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: SelectableText(message!,
                                    style: TextStyle(
                                        color: finished
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Theme.of(context)
                                                .colorScheme
                                                .error))),
                        ])))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Fechar')),
          FilledButton.icon(
              onPressed:
                  busy || finished || uncertain || !authorized ? null : send,
              icon: const Icon(Icons.add_task),
              label: Text(busy
                  ? 'Criando e conferindo…'
                  : 'Criar solicitação no E-Desk'))
        ],
      ));
}
