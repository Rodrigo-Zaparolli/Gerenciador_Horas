import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/services/zendesk_service.dart';
import '../../data/services/recoverable_draft.dart';
import '../../domain/models/project_model.dart';
import '../../shared/widgets/movable_document_dialog.dart';

const slaProducts = <String, List<String>>{
  'production': ['Cut Pro', 'Builder', 'Worker', 'Manufacture Engine'],
  'design': [
    'Promob',
    'Catalog',
    'Connect V2',
    'Maker',
    'Prices',
    'Real Scene',
    'Plugins diversos'
  ],
  'gestao': ['Manager', 'FoccoLojas'],
};
const slaQuestions = [
  'Impacto na operação',
  'Clientes afetados',
  'Risco financeiro Cyncly',
  'Dificuldade de contorno',
  'Plano CS'
];
const slaOptions = [
  ['Muito baixo', 'Baixo', 'Médio', 'Alto', 'Muito alto'],
  ['Somente este', 'Poucos', 'Médios', 'Muitos', 'Todos'],
  ['Nenhum', 'Pequeno', 'Médio', 'Grande', 'Inevitável'],
  ['Muito fácil', 'Fácil', 'Médio', 'Difícil', 'Não há contorno'],
  ['Sem classificação', 'Gold', 'Platinum', 'Black', 'Pacote CS'],
];

class ZendeskDialog extends StatefulWidget {
  const ZendeskDialog(
      {super.key,
      required this.project,
      this.transport,
      this.authorized,
      this.receiptSaver});
  final ProjectModel project;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
      transport;
  final bool Function()? authorized;
  final Future<void> Function(Map<String, dynamic>)? receiptSaver;
  static Future<void> show(BuildContext context, ProjectModel project) =>
      showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ZendeskDialog(project: project));
  @override
  State<ZendeskDialog> createState() => _ZendeskDialogState();
}

class _ZendeskDialogState extends State<ZendeskDialog> {
  late final String? owner =
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
  late final subject = TextEditingController(
      text: 'Solicitação técnica — ${widget.project.client}');
  late final description = TextEditingController(
      text:
          'Dados do cliente\nSolicitação E-Desk: ${widget.project.id}\nCliente: ${widget.project.client}\n\nInformações\nBiblioteca / sistema: \nVersão do cliente: \nVersão utilizada no teste: \nOcorre em outros computadores? \nOcorre em todos os projetos? \n\nCenário\n\nTestes realizados\n\nResultado esperado\n');
  final assignee = TextEditingController();
  final customControllers = <String, TextEditingController>{};
  final customValues = <String, dynamic>{};
  String unit = 'production', product = 'Builder', status = 'hold';
  List<int?> answers = List.filled(5, null);
  int? brandId, formId, groupId, customStatus;
  Map<String, dynamic>? metadata, capture, receipt;
  Uint8List? screenshot;
  List<PlatformFile> files = [];
  bool busy = false, uncertain = false, receiptStored = false;
  bool statusReady = false;
  String? message, previousDraft;
  bool get authorized =>
      widget.authorized?.call() ??
      (owner != null && FirebaseAuth.instance.currentUser?.uid == owner);
  bool get editable => authorized && !busy && !uncertain && receipt == null;
  String get scope => 'zendesk.${widget.project.id}';
  Map<String, dynamic> get sla =>
      {'unit': unit, 'product': product, 'answers': answers};
  @override
  void initState() {
    super.initState();
    final saved = RecoverableDraft.read(owner, scope);
    if (saved != null) {
      subject.text = saved['subject'] as String? ?? subject.text;
      description.text = saved['description'] as String? ?? description.text;
      assignee.text = saved['assignee'] as String? ?? '';
      if (slaProducts.containsKey(saved['unit'])) {
        unit = saved['unit'] as String;
      }
      if (slaProducts[unit]!.contains(saved['product'])) {
        product = saved['product'] as String;
      } else {
        product = slaProducts[unit]!.first;
      }
      final raw = saved['answers'];
      if (raw is List && raw.length == 5) {
        answers = [
          for (final a in raw) a is int && a >= 1 && a <= 5 ? a : null
        ];
      }
      previousDraft = saved['sendingDraftId'] as String?;
      uncertain = previousDraft != null;
    }
  }

  void remember() => RecoverableDraft.save(owner, scope, {
        'subject': subject.text,
        'description': description.text,
        'assignee': assignee.text,
        'unit': unit,
        'product': product,
        'answers': answers,
        if (previousDraft != null) 'sendingDraftId': previousDraft
      });
  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    assignee.dispose();
    for (final c in customControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> call(
      String action, Map<String, dynamic> data) async {
    if (!authorized) {
      throw StateError('A conta mudou. Feche e abra o formulário novamente.');
    }
    final result =
        await (widget.transport ?? ZendeskService.call)(action, data);
    if (!mounted || !authorized) throw StateError('A conta mudou.');
    return result;
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !authorized) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted && authorized) {
        setState(
            () => message = error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> connect() => run(() async {
        final result = await call('connect', {});
        metadata = result;
        brandId = null;
        formId = null;
        groupId = null;
        customValues.clear();
        for (final c in customControllers.values) {
          c.clear();
        }
        final brands = (result['brands'] as List).cast<Map>();
        final forms = (result['forms'] as List).cast<Map>();
        final brand =
            brands.where((x) => '${x['name']}'.toLowerCase() == 'promob');
        if (brand.length == 1) brandId = brand.single['id'] as int;
        final form = forms.where((x) => '${x['name']}'
            .toLowerCase()
            .contains('support promob manufacturing'));
        if (form.length == 1) formId = form.single['id'] as int;
        final defaults = (result['customStatuses'] as List).cast<Map>().where(
          (item) => item['category'] == 'hold' &&
            '${item['name']}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == 'onholdrd');
        customStatus = defaults.length == 1 ? defaults.single['id'] as int : null;
        statusReady = customStatus != null;
        message =
            'Sessão conectada: ${(result['agent'] as Map)['name']}. Formulários e campos consultados no Zendesk.';
        if (!statusReady) {
          message = '$message A situação On-hold · R&D não foi identificada. Escolha a situação antes de enviar.';
        }
      });
  void invalidate() {
    capture = null;
    screenshot = null;
    remember();
  }

  Future<void> capturePriority() => run(() async {
        if (answers.any((a) => a == null)) {
          throw StateError('Responda as cinco perguntas antes de capturar.');
        }
        final expected = jsonEncode(sla);
        capture = null;
        screenshot = null;
        final result = await call('capture', sla);
        if (expected != jsonEncode(sla)) {
          throw StateError('As respostas mudaram. Capture novamente.');
        }
        final bytes = base64Decode(result['imageBase64'] as String);
        capture = result;
        screenshot = bytes;
        message =
            'Print real capturado na ferramenta oficial. Confira a imagem antes de enviar.';
      });
  Future<void> pickFiles() async {
    if (!editable) return;
    final result = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: true);
    if (!mounted || !editable || result == null) return;
    final selected = [...files, ...result.files];
    if (selected.length > 5 ||
        selected.fold<int>(0, (sum, file) => sum + file.size) >
            8 * 1024 * 1024 ||
        selected.any((f) => f.bytes == null)) {
      setState(() => message =
          'Selecione até cinco arquivos, com tamanho total de até 8 MB.');
      return;
    }
    setState(() => files = selected);
  }

  List<Map> get fields {
    if (metadata == null || formId == null) return [];
    final forms = (metadata!['forms'] as List).cast<Map>();
    final form = forms.where((f) => f['id'] == formId);
    if (form.isEmpty) return [];
    final ids = form.single['fieldIds'] as List;
    return (metadata!['fields'] as List)
        .cast<Map>()
        .where((f) => ids.contains(f['id']))
        .toList();
  }

  Map<String, dynamic> get requestData => {
        'subject': subject.text.trim(),
        'description': description.text.trim(),
        'draftId': capture?['draftId'],
        'sla': sla,
        'agentId': (metadata?['agent'] as Map?)?['id'],
        'formId': formId,
        'brandId': brandId,
        'groupId': groupId,
        'assigneeEmail': assignee.text.trim(),
        'type': type,
        'status': customStatus ?? status,
        'fields': {
          for (final field in fields)
            if (customValues.containsKey('${field['id']}'))
              '${field['id']}': customValues['${field['id']}']
        },
        'attachments': [
          for (final file in files)
            {'name': file.name, 'base64': base64Encode(file.bytes!)}
        ],
      };
  String type = 'problem';
  Future<void> saveReceipt() async {
    if (receipt == null) return;
    try {
      if (widget.receiptSaver != null) {
        await widget.receiptSaver!(receipt!);
      } else {
        await ZendeskService.saveReceipt(owner!, widget.project.id, receipt!);
      }
      if (!mounted || !authorized) return;
      receiptStored = true;
      previousDraft = null;
      remember();
    } catch (_) {
      if (mounted && authorized) {
        message =
            'Chamado criado no Zendesk. O vínculo no projeto ainda não foi salvo; use Salvar vínculo novamente. O chamado não será reenviado.';
      }
    }
  }

  Future<void> send() async {
    if (!editable || capture == null || metadata == null) return;
    if (!statusReady) {
      setState(() => message = 'Escolha a situação do chamado antes de enviar.');
      return;
    }
    if (subject.text.trim().isEmpty ||
        description.text.trim().isEmpty ||
        formId == null) {
      setState(() => message =
          'Preencha o assunto, a descrição e escolha o formulário do Zendesk.');
      return;
    }
    for (final field in fields) {
      final value = customValues['${field['id']}'];
      if (field['required'] == true &&
          (value == null || value == '' || value is List && value.isEmpty)) {
        setState(
            () => message = 'Preencha o campo obrigatório: ${field['name']}');
        return;
      }
    }
    final snapshot = jsonEncode(requestData);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Criar solicitação no Zendesk?'),
                content: SizedBox(
                    width: 700,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(subject.text,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Text(
                              'Projeto ${widget.project.id} · ${widget.project.client}\nSolicitante: ${(metadata!['agent'] as Map)['name']}\nSituação: ${statusLabel()}\nObservação interna · ${files.length} anexo(s)'),
                          const SizedBox(height: 12),
                          Text(description.text),
                          const SizedBox(height: 12),
                          Text(
                              'Prioridade da solicitação: ${capture!['priority']} · ${capture!['points']} pontos'),
                          if (screenshot != null) Image.memory(screenshot!),
                          const SizedBox(height: 10),
                          const Text(
                              'Esta confirmação cria um chamado real. O registro da prioridade na ferramenta SLA será feito separadamente, após receber o número.')
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Voltar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirmar criação'))
                ]));
    if (!mounted ||
        confirmed != true ||
        !editable ||
        snapshot != jsonEncode(requestData)) {
      return;
    }
    await run(() async {
      previousDraft = capture!['draftId'] as String;
      remember();
      try {
        receipt = await call('create', {...requestData, 'confirmed': true});
        uncertain = false;
        message = receipt!['message'] as String?;
        await saveReceipt();
      } catch (_) {
        uncertain = true;
        rethrow;
      }
    });
  }

  Future<void> checkPrevious() => run(() async {
        final result = await call('receipt', {'draftId': previousDraft});
        if (result['state'] == 'confirmed') {
          receipt = result;
          uncertain = false;
          await saveReceipt();
          message = 'Chamado anterior localizado. Nenhum novo envio foi feito.';
        } else if (result['state'] == 'prepared') {
          uncertain = false;
          previousDraft = null;
          remember();
          message =
              'Não houve criação neste rascunho. Confira os dados e capture novamente antes de enviar.';
        } else {
          message =
              'Envio anterior não confirmado. Confira o Zendesk antes de criar outro chamado.';
        }
      });
  Future<void> registerPriority() async {
    if (receipt == null || busy || receipt!['slaRegistered'] == true) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title:
                    const Text('Registrar prioridade na ferramenta oficial?'),
                content: Text(
                    'Registrar ${capture?['priority'] ?? receipt!['priority']} no ticket ${receipt!['ticketId']}.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Registrar'))
                ]));
    if (confirmed != true || !mounted || !authorized) return;
    await run(() async {
      receipt = await call('register-sla',
          {'draftId': receipt!['draftId'], 'sla': sla, 'confirmed': true});
      message = receipt!['message'] as String?;
      await saveReceipt();
    });
  }

  String statusLabel() {
    if (!statusReady) return 'Selecione a situação';
    if (customStatus == null) {
      return const {
        'new': 'Novo',
        'open': 'Aberto',
        'pending': 'Pendente',
        'hold': 'Em espera'
      }[status]!;
    }
    return '${(metadata!['customStatuses'] as List).cast<Map>().firstWhere((x) => x['id'] == customStatus)['name']}';
  }

  Widget input(String label, TextEditingController controller,
          {int lines = 1}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: controller,
              enabled: editable,
              maxLines: lines,
              onChanged: (_) {
                remember();
              },
              decoration: InputDecoration(
                  labelText: label,
                  isDense: true,
                  border: const OutlineInputBorder())));
  Widget choose(String label, List<DropdownMenuItem<int>> items, int? value,
          void Function(int?) changed) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
              initialValue: value,
              key: ValueKey('$label-$value-${metadata?['agent']}'),
              isExpanded: true,
              items: items,
              onChanged: editable ? changed : null,
              decoration: InputDecoration(
                  labelText: label,
                  isDense: true,
                  border: const OutlineInputBorder())));
  Widget leftPanel() => SizedBox(
      width: 260,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Zendesk', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: authorized && !busy && !uncertain && receipt == null
                ? connect
                : null,
            icon: const Icon(Icons.link),
            label: Text(
                metadata == null ? 'Conectar Zendesk' : 'Atualizar campos')),
        const SizedBox(height: 12),
        Text(metadata == null
            ? 'Entre na janela que será aberta. A sessão do Zendesk fica separada do E-Desk.'
            : 'Solicitante: ${(metadata!['agent'] as Map)['name']}'),
        const SizedBox(height: 16),
        if (metadata != null) ...[
          choose(
              'Marca',
              [
                for (final x in (metadata!['brands'] as List).cast<Map>())
                  DropdownMenuItem(
                      value: x['id'] as int,
                      child:
                          Text('${x['name']}', overflow: TextOverflow.ellipsis))
              ],
              brandId,
              (v) => setState(() => brandId = v)),
          choose(
              'Formulário',
              [
                for (final x in (metadata!['forms'] as List).cast<Map>())
                  DropdownMenuItem(
                      value: x['id'] as int,
                      child:
                          Text('${x['name']}', overflow: TextOverflow.ellipsis))
              ],
              formId,
              (v) => setState(() {
                    formId = v;
                    customValues.clear();
                    for (final c in customControllers.values) {
                      c.clear();
                    }
                  })),
          choose(
              'Grupo responsável',
              [
                for (final x in (metadata!['groups'] as List).cast<Map>())
                  DropdownMenuItem(
                      value: x['id'] as int,
                      child:
                          Text('${x['name']}', overflow: TextOverflow.ellipsis))
              ],
              groupId,
              (v) => setState(() => groupId = v)),
        ],
        input('Responsável · e-mail Zendesk (opcional)', assignee),
        DropdownButtonFormField<String>(
            initialValue: type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: const [
              DropdownMenuItem(value: 'problem', child: Text('Problema')),
              DropdownMenuItem(value: 'incident', child: Text('Incidente')),
              DropdownMenuItem(value: 'question', child: Text('Dúvida')),
              DropdownMenuItem(value: 'task', child: Text('Tarefa'))
            ],
            onChanged: editable ? (v) => setState(() => type = v!) : null),
        const SizedBox(height: 18),
        for (final field in fields) customField(field),
      ]));
  Widget customField(Map field) {
    final key = '${field['id']}',
        label = '${field['name']}${field['required'] == true ? ' *' : ''}';
    final kind = field['type'];
    if (kind == 'checkbox') {
      return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: customValues[key] == true,
          onChanged:
              editable ? (v) => setState(() => customValues[key] = v) : null);
    }
    if (kind == 'tagger') {
      return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
              initialValue: customValues[key] as String?,
              isExpanded: true,
              key: ValueKey('$formId-$key'),
              decoration: InputDecoration(labelText: label),
              items: [
                for (final option in (field['options'] as List).cast<Map>())
                  DropdownMenuItem(
                      value: '${option['value']}',
                      child: Text('${option['name']}',
                          overflow: TextOverflow.ellipsis))
              ],
              onChanged: editable
                  ? (v) => setState(() => customValues[key] = v)
                  : null));
    }
    if (kind == 'multiselect') {
      return ExpansionTile(title: Text(label), children: [
        for (final option in (field['options'] as List).cast<Map>())
          CheckboxListTile(
              title: Text('${option['name']}'),
              value:
                  (customValues[key] as List? ?? []).contains(option['value']),
              onChanged: editable
                  ? (checked) => setState(() {
                        final values =
                            List<String>.from(customValues[key] as List? ?? []);
                        if (checked == true) {
                          values.add('${option['value']}');
                        } else {
                          values.remove(option['value']);
                        }
                        customValues[key] = values;
                      })
                  : null)
      ]);
    }
    final controller = customControllers.putIfAbsent(key,
        () => TextEditingController(text: customValues[key]?.toString() ?? ''));
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: controller,
            enabled: editable,
            maxLines: kind == 'textarea' ? 3 : 1,
            decoration: InputDecoration(
                labelText: label,
                helperText: kind == 'date' ? 'AAAA-MM-DD' : null,
                isDense: true,
                border: const OutlineInputBorder()),
            onChanged: (value) => customValues[key] = value));
  }

  Widget priorityPanel() => SizedBox(
      width: 280,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Priorização oficial',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
            'Preencha as respostas. A integração acessa o site oficial, confere o resultado e captura o print verdadeiro.'),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
            initialValue: unit,
            decoration: const InputDecoration(labelText: 'Unidade'),
            items: const [
              DropdownMenuItem(value: 'production', child: Text('Production')),
              DropdownMenuItem(value: 'design', child: Text('Design')),
              DropdownMenuItem(value: 'gestao', child: Text('Gestão / Sales'))
            ],
            onChanged: editable
                ? (v) => setState(() {
                      unit = v!;
                      product = slaProducts[unit]!.first;
                      invalidate();
                    })
                : null),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
            key: ValueKey('sla-$unit'),
            initialValue: product,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Produto SLA'),
            items: [
              for (final value in slaProducts[unit]!)
                DropdownMenuItem(value: value, child: Text(value))
            ],
            onChanged: editable
                ? (v) => setState(() {
                      product = v!;
                      invalidate();
                    })
                : null),
        for (var i = 0; i < 5; i++)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<int>(
                  key: ValueKey('sla-answer-$i'),
                  initialValue: answers[i],
                  isExpanded: true,
                  decoration: InputDecoration(labelText: slaQuestions[i]),
                  items: [
                    for (var n = 0; n < 5; n++)
                      DropdownMenuItem(
                          value: n + 1,
                          child: Text('${n + 1} · ${slaOptions[i][n]}'))
                  ],
                  onChanged: editable
                      ? (v) => setState(() {
                            answers[i] = v;
                            invalidate();
                          })
                      : null)),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: editable ? capturePriority : null,
            icon: const Icon(Icons.screenshot_monitor),
            label: const Text('Capturar priorização')),
        if (capture != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  '${capture!['priority']} · ${capture!['points']} pontos\n${capture!['forecast']}\nCaptura oficial · nenhum registro SLA salvo.')),
      ]));
  Widget editor() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        input('Assunto', subject),
        input('Descrição · observação interna', description, lines: 16),
        if (screenshot != null) ...[
          Text('Prioridade da solicitação: ${capture!['priority']}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          InkWell(
              onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => Dialog(
                          child: Column(children: [
                        Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                                onPressed: () => Navigator.pop(c),
                                icon: const Icon(Icons.close))),
                        Expanded(
                            child: InteractiveViewer(
                                minScale: .3,
                                maxScale: 5,
                                child: Image.memory(screenshot!)))
                      ]))),
              child: Image.memory(screenshot!, fit: BoxFit.fitWidth)),
          const SizedBox(height: 12)
        ],
        OutlinedButton.icon(
            onPressed: editable ? pickFiles : null,
            icon: const Icon(Icons.attach_file),
            label: const Text('Adicionar anexos')),
        for (final file in files)
          ListTile(
              dense: true,
              title: Text(file.name),
              trailing: IconButton(
                  onPressed: editable
                      ? () => setState(() => files.remove(file))
                      : null,
                  icon: const Icon(Icons.close))),
      ]);
  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: MovableDocumentDialog(
          child: Column(children: [
        ListTile(
            leading: const Icon(Icons.confirmation_number_outlined),
            title: const Text('Nova solicitação no Zendesk'),
            subtitle: Text('${widget.project.id} · ${widget.project.client}'),
            trailing: IconButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close))),
        if (busy) const LinearProgressIndicator(),
        if (busy)
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                  'Aguarde a operação no navegador da integração. Se solicitado, conclua o login no Zendesk.')),
        if (message != null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(message!)),
        Expanded(
            child: !authorized
                ? const Center(
                    child: Text(
                        'A conta mudou. Feche e abra esta janela novamente.'))
                : receipt != null
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(children: [
                          const Icon(Icons.check_circle_outline, size: 40),
                          Text(
                              'Chamado ${receipt!['ticketId']} criado e conferido'),
                          SelectableText('${receipt!['url']}'),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: () => launchUrl(
                                  Uri.parse(receipt!['url'] as String)),
                              child: const Text('Abrir chamado')),
                          if (!receiptStored)
                            OutlinedButton(
                                onPressed: busy ? null : () => run(saveReceipt),
                                child: const Text('Salvar vínculo no projeto')),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed:
                                  busy || receipt!['slaRegistered'] == true
                                      ? null
                                      : registerPriority,
                              child: Text(receipt!['slaRegistered'] == true
                                  ? 'Prioridade registrada'
                                  : 'Registrar prioridade com este ID'))
                        ]))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                            builder: (context, size) => size.maxWidth > 1150
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                        leftPanel(),
                                        const SizedBox(width: 20),
                                        Expanded(child: editor()),
                                        const SizedBox(width: 20),
                                        priorityPanel()
                                      ])
                                : Column(children: [
                                    Wrap(
                                        spacing: 20,
                                        runSpacing: 16,
                                        children: [
                                          leftPanel(),
                                          priorityPanel()
                                        ]),
                                    const SizedBox(height: 24),
                                    editor()
                                  ])))),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (uncertain)
                    OutlinedButton(
                        onPressed: busy ? null : checkPrevious,
                        child: const Text('Conferir envio anterior')),
                  if (receipt == null)
                    DropdownButton<Object>(
                        value: statusReady ? customStatus ?? status : null,
                        hint: const Text('On-hold · R&D · carregar do Zendesk'),
                        items: [
                          const DropdownMenuItem<Object>(
                              value: 'new', child: Text('Novo')),
                          const DropdownMenuItem<Object>(
                              value: 'open', child: Text('Aberto')),
                          const DropdownMenuItem<Object>(
                              value: 'pending', child: Text('Pendente')),
                          const DropdownMenuItem<Object>(
                              value: 'hold', child: Text('Em espera')),
                          if (metadata != null)
                            for (final item
                                in (metadata!['customStatuses'] as List)
                                    .cast<Map>())
                              DropdownMenuItem<Object>(
                                  value: item['id'] as int,
                                  child: Text('${item['name']}'))
                        ],
                        onChanged: editable && metadata != null
                            ? (v) => setState(() {
                                  statusReady = true;
                                  if (v is int) {
                                    customStatus = v;
                                  } else {
                                    customStatus = null;
                                    status = v as String;
                                  }
                                })
                            : null),
                  if (receipt == null)
                    FilledButton.icon(
                        onPressed:
                            editable && capture != null && metadata != null && statusReady
                                ? send
                                : null,
                        icon: const Icon(Icons.send),
                        label: const Text('Conferir e criar chamado')),
                  TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('Fechar')),
                ])),
      ])));
}
