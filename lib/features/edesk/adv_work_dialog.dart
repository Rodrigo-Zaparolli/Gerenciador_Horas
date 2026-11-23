import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../domain/models/project_model.dart';
import '../../data/services/edesk_integration.dart';
import '../../data/services/edesk_credentials_service.dart';
import '../../data/services/edesk_creation_request.dart';

class AdvWorkDialog extends StatefulWidget {
  const AdvWorkDialog(
      {super.key,
      required this.project,
      this.sender,
      this.authorized,
      this.pluginNs = false});
  final bool pluginNs;
  final ProjectModel project;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? sender;
  final bool Function()? authorized;
  static Future<void> show(BuildContext context, ProjectModel project) =>
      showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AdvWorkDialog(project: project));
  static Future<void> showPluginNs(
          BuildContext context, ProjectModel project) =>
      showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AdvWorkDialog(project: project, pluginNs: true));
  @override
  State<AdvWorkDialog> createState() => _AdvWorkDialogState();
}

class _AdvWorkDialogState extends State<AdvWorkDialog> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController(text: 'Implantação Finalizada');
  final description = TextEditingController();
  final plugin = TextEditingController();
  late final customer = TextEditingController(text: widget.project.client);
  @override
  void initState() {
    super.initState();
    if (widget.pluginNs) subject.text = 'Solicitação de NS de plugin';
  }

  late final String? owner =
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  bool busy = false, finished = false, uncertain = false;
  bool postStarted = false;
  String? message;
  bool get authorized =>
      widget.authorized?.call() ??
      (owner != null && FirebaseAuth.instance.currentUser?.uid == owner);
  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    plugin.dispose();
    customer.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    final request = edeskCreationRequest(data);
    final health =
        await EdeskIntegrationApi.call('/healthz', authenticated: false);
    if (health['advWorkCreate'] != true) {
      throw StateError(
          'Atualize a integração local para a versão com criação de trabalho ADV. Nenhum trabalho foi enviado.');
    }
    final credentials = await EdeskCredentialsService().ler();
    if (!authorized)
      throw StateError('Sua conta mudou. Abra o projeto novamente.');
    if (credentials == null)
      throw StateError(
          'Configure o acesso ao E-Desk antes de criar o trabalho.');
    postStarted = true;
    return EdeskIntegrationApi.call('/api/edesk/adv',
        timeout: const Duration(minutes: 4),
        body: {
          'request': {...request, 'edeskCredenciais': credentials},
          'enviar': true,
        });
  }

  Future<void> send() async {
    if (busy ||
        finished ||
        uncertain ||
        !authorized ||
        !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      message = null;
      postStarted = false;
    });
    try {
      if (widget.sender != null) postStarted = true;
      final result = await (widget.sender ?? create)(edeskCreationRequest({
        'solicitacao': widget.project.id.trim(),
        'confirmed': true,
        'subject': subject.text.trim(),
        'description': widget.pluginNs
            ? 'Cliente: ${customer.text.trim()}\nPlugin / produto: ${plugin.text.trim()}\n\n${description.text.trim()}'
            : description.text.trim(),
      }));
      if (!mounted || !authorized) return;
      if (result['confirmed'] != true) {
        throw StateError(result['message']?.toString() ??
            'Cadastro não confirmado. Confira o E-Desk antes de repetir.');
      }
      setState(() {
        finished = true;
        message =
            result['message']?.toString() ?? 'Trabalho confirmado no E-Desk.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          uncertain = postStarted;
          message =
              '$error${uncertain ? '\nNão repita o cadastro sem conferir o E-Desk. Feche e reabra este modal após a conferência.' : ''}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(widget.pluginNs
            ? 'Solicitar NS de plugin'
            : 'Criar trabalho para ADV'),
        content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              'Solicitação ${widget.project.id} — ${widget.project.client}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          const Text(
                              'Grupo: FLUXO DE IMPLANTAÇÃO PROMOB\nTipo de Trabalho: Programação\nEquipe: Go Live'),
                          const SizedBox(height: 8),
                          const Text(
                              'Será criado um trabalho nesta solicitação. Atendente e agendamento não serão preenchidos, conforme o fluxo demonstrado.'),
                          const SizedBox(height: 16),
                          if (widget.pluginNs) ...[
                            TextFormField(
                                controller: customer,
                                enabled: !busy && !finished && !uncertain,
                                maxLength: 300,
                                decoration:
                                    const InputDecoration(labelText: 'Cliente'),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Informe o cliente.'
                                        : null),
                            const SizedBox(height: 8),
                            TextFormField(
                                controller: plugin,
                                enabled: !busy && !finished && !uncertain,
                                maxLength: 300,
                                decoration: const InputDecoration(
                                    labelText: 'Plugin / produto',
                                    hintText:
                                        'Informe o plugin para o qual deseja solicitar o NS.'),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Informe o plugin.'
                                        : null),
                            const SizedBox(height: 8),
                          ],
                          TextFormField(
                              controller: subject,
                              enabled: !busy && !finished && !uncertain,
                              maxLength: 200,
                              decoration: InputDecoration(
                                  labelText: 'Assunto do trabalho',
                                  helperText: widget.pluginNs
                                      ? 'Identifique o plugin no assunto. Trabalhos com o mesmo assunto não serão duplicados.'
                                      : null,
                                  helperMaxLines: 3),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Informe o assunto.'
                                      : null),
                          const SizedBox(height: 8),
                          TextFormField(
                              controller: description,
                              enabled: !busy && !finished && !uncertain,
                              minLines: 5,
                              maxLines: 12,
                              maxLength: widget.pluginNs ? 9000 : 10000,
                              decoration: InputDecoration(
                                  labelText: 'Detalhamento do trabalho',
                                  hintText: widget.pluginNs
                                      ? 'Descreva a solicitação e os dados necessários para liberar o NS.'
                                      : 'Descreva o encerramento e o que o ADV precisa tratar.'),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
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
              label: Text(busy ? 'Criando e conferindo…' : 'Criar no E-Desk')),
        ],
      ));
}
