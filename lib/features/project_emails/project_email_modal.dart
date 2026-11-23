import 'package:gerenciador_horas/data/services/recoverable_draft.dart';
import 'package:gerenciador_horas/shared/widgets/recovery_error.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/core/platform/local_files.dart';
import 'package:gerenciador_horas/data/services/browser_local_files_service.dart';
import 'package:gerenciador_horas/data/services/native_local_files_service.dart';
import 'package:gerenciador_horas/data/services/file_download.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'email_document.dart';
import 'email_workbook.dart';
import 'email_draft_store.dart';
import 'products_image_field.dart';
import 'email_body_preview.dart';
import 'email_recipient_fields.dart';
import 'sharepoint_email_links.dart';
import '../../data/services/edesk_integration.dart';

class ProjectEmailModal extends StatefulWidget {
  final ProjectModel project;
  final EmailDraftStore? store;
  final Future<Uint8List?> Function()? workbookLoader;
  final Future<List<EmailAttachment>?> Function()? attachmentPicker;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? sharePointResolver;
  const ProjectEmailModal(
      {super.key, required this.project, this.store, this.workbookLoader, this.sharePointResolver, this.attachmentPicker});
  static Future<void> show(BuildContext context, ProjectModel project) =>
      showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ProjectEmailModal(project: project));
  @override
  State<ProjectEmailModal> createState() => _ProjectEmailModalState();
}

class _ProjectEmailModalState extends State<ProjectEmailModal> {
  late final String? _uid;
  late final EmailDraftStore _store;
  ProjectEmailKind _kind = ProjectEmailKind.initial;
  final _fields = <String, TextEditingController>{};
  final _subject = TextEditingController(), _body = TextEditingController();
  final _contacts = <EmailContact>[];
  final _projectContacts = <EmailContact>[];
  final _externalRecipients = <EmailContact>[];
  final _internalRecipients = <EmailContact>[];
  final _restoredRecipientSelections = <String,String>{};
  bool _workbookRecipientsLoaded = false;
  List<EmailContact> get _modelRecipients => _kind.isInternal ? _internalRecipients
      : _kind == ProjectEmailKind.finishes ? _externalRecipients.where((c) => c.role == 'Proprietário' || c.role == 'Responsável Técnico').toList()
      : _kind == ProjectEmailKind.finalization ? _externalRecipients : _projectContacts;
  Set<String> get _allowedRecipientEmails =>
      (_workbookRecipientsLoaded ? _projectContacts : <EmailContact>[])
          .where((c) => validEmail(c.email))
          .map((c) => c.email.trim().toLowerCase()).toSet();
  void _applyModelRecipients() {
    final destinations = {..._restoredRecipientSelections,
      for(final c in _contacts.where((c) => ['Para','Cc'].contains(c.destination)))
        c.email.trim().toLowerCase():c.destination};
    final defaults = _modelRecipients.map((c) => EmailContact.fromJson(c.toJson())).toList();
    if (_recipientSelectionManual) {
      for (final c in defaults) { c.destination = 'Não incluir'; }
      for (final c in _projectContacts) {
        final destination = destinations[c.email.trim().toLowerCase()];
        if (destination == null) continue;
        final existing = defaults.where((d) => d.email.trim().toLowerCase() == c.email.trim().toLowerCase()).firstOrNull;
        if (existing != null) { existing.destination = destination; }
        else { defaults.add(EmailContact.fromJson(c.toJson())..destination = destination); }
      }
    }
    _contacts
      ..clear()
      ..addAll(defaults);
  }
  bool _recipientSelectionManual = false;
  final _automaticallyImported = <String>{};
  final _sharePointNames = <String, String>{};
  Map<String, String> get _emailLinkLabels {
    if (!_sameAccount) return const {};
    final fantasy = _fields['nome_fantasia']?.text.trim() ?? '';
    final system = (_fields['sistema']?.text ?? '')
        .replaceFirst(RegExp(r'^\s*(?:Enterprise|Professional|Promob|Maker)(?:\s+(?:Produção\s+Completa|Produção\s+Simplificada))?\s*[-–—]?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^Promob\s+', caseSensitive: false), '').trim();
    return emailClientLinkLabels(_body.text, _sharePointNames,
        clientName: fantasy.isNotEmpty ? fantasy : system.isNotEmpty ? system : widget.project.client);
  }
  bool _resolvingLinks = false;
  String _linkStatus = '';
  bool get _professionalProject => RegExp(r'professional|profissional|maker', caseSensitive: false)
      .hasMatch(widget.project.serviceType);
  bool get _enterpriseProject => widget.project.serviceType.toLowerCase().contains('enterprise');
  final _recipientKey = GlobalKey<EmailRecipientFieldsState>();
  final _attachments = <EmailAttachment>[];
  Uint8List? _productsImage;
  final _cache = <ProjectEmailKind, Map<String, dynamic>>{};
  final _saved = <ProjectEmailKind, String>{};
  String _subjectTemplate = '', _bodyTemplate = '', _message = '';
  String _localStatus = '';
  String _lastRecovery = '';
  String _summaryInMessage = '';
  bool _closing = false, _allowClose = false, _discardOnClose = false;
  String get _recoveryKey => 'email.${widget.project.id}.${_kind.name}';

  void _recoverLocally() {
    if (_discardOnClose || !_ready || _busy || !_sameAccount) return;
    final snapshot = _snapshot();
    final encoded = jsonEncode(snapshot);
    if (encoded == _lastRecovery) return;
    _lastRecovery = encoded;
    final saved = RecoverableDraft.save(_uid, _recoveryKey, snapshot);
    _localStatus = saved
        ? 'Cópia de recuperação salva neste dispositivo.'
        : 'Não foi possível salvar a cópia local. Use Salvar neste projeto.';
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _recoverLocally();
  }

  bool _busy = true,
      _ready = false,
      _customBody = false,
      _customSubject = false;
  bool get _sameAccount => _uid != null && _store.currentUserId == _uid;
  void _applyWorkbookSignature({Map<String,String>? previous}) {
    final keys = ['consultor','email_consultor','telefone_consultor'];
    final before = previous ?? {for(final key in keys) key:_fields[key]!.text};
    _fields['telefone_consultor']!.text = emailConsultantPhone(
      _fields['email_consultor']!.text, _fields['telefone_consultor']!.text);
    final consultant = {for(final key in keys) key:_fields[key]!.text};
    if (_customBody) _body.text = updateEmailSender(_body.text,before,consultant,
      includePhone:_kind==ProjectEmailKind.finishes);
  }
  @override
  void initState() {
    super.initState();
    _store = widget.store ?? FirebaseEmailDraftStore();
    _uid = _store.currentUserId;
    for (final field in emailFieldLabels.keys) {
      _fields[field] = TextEditingController();
    }
    _load();
  }

  Map<String, String> get _values => {
        for (final entry in _fields.entries) entry.key: entry.value.text,
        if (_productsImage != null) 'produtos': productsImageMarker,
        'equipe': _contacts
            .where((c) => c.group == 'Cyncly')
            .map((c) => '${c.role}: ${c.name}')
            .join('\n'),
      };
  Map<String, dynamic> _snapshot() => {
        'fields': _values,
        'contacts': [
          ..._contacts.map((c) => c.toJson()),
          if (!_workbookRecipientsLoaded) for(final e in _restoredRecipientSelections.entries)
            if (!_contacts.any((c)=>c.email.trim().toLowerCase()==e.key))
              EmailContact(email:e.key,destination:e.value).toJson(),
        ],
        'body': _customBody ? _body.text : null,
        'subject': _customSubject ? _subject.text : null,
        'productsImage':
            _productsImage == null ? null : base64Encode(_productsImage!),
        'recipientsConfigured': true,
        'recipientSelectionManual': _recipientSelectionManual,
        'sharePointNames': Map<String, String>.from(_sharePointNames),
      };
  void _render() {
    if (!_customSubject) {
      _subject.text = renderEmailTemplate(_subjectTemplate, _values, markMissing: true);
    }
    if (!_customBody) _body.text = renderEmailTemplate(_bodyTemplate, _values, markMissing: true);
    if (_kind.isInternal) {
      _body.text = emailBodyWithSummary(_body.text, _fields['resumo']!.text,
          previousSummary: _summaryInMessage);
      _summaryInMessage = _fields['resumo']!.text;
    }
    if (_productsImage != null && _kind.isInternal) {
      _body.text = _body.text.replaceAll('[PREENCHER: Produtos adquiridos]', '');
      _body.text = emailBodyWithProductsImage(_body.text);
    }
    _body.text = cleanRemovedEmailFields(_body.text, _kind,
        consultantPhone: _fields['telefone_consultor']!.text);
    if (_kind == ProjectEmailKind.finishes) {
      _body.text = finishesAttachmentText(_body.text, finishesSpreadsheet(_attachments));
    }
  }

  Future<void> _load() async {
    _ready = false;
    _localStatus = '';
    setState(() => _busy = true);
    try {
      if (!_sameAccount) throw StateError('Entre novamente na sua conta.');
      var recovery = RecoverableDraft.read(_uid, _recoveryKey);
      Map<String, dynamic>? template, remote;
      try {
        template = await _store.loadTemplate(_uid!, _kind);
      } catch (_) {
        if (recovery == null && _cache[_kind] == null) rethrow;
      }
      try {
        remote = await _store.loadDraft(_uid!, widget.project.id, _kind);
      } catch (_) {
        if (recovery == null && _cache[_kind] == null) rethrow;
      }
      final remoteDate = remote?['updatedAt'];
      final recoveryDate =
          DateTime.tryParse(recovery?['savedAt']?.toString() ?? '');
      if (remoteDate is Timestamp &&
          recoveryDate != null &&
          remoteDate.toDate().isAfter(recoveryDate)) {
        RecoverableDraft.clear(_uid, _recoveryKey);
        recovery = null;
      }
      var draft = _cache[_kind] ?? recovery ?? remote;
      if (recovery != null) {
        _localStatus =
            'Rascunho recuperado neste dispositivo. Revise os destinatários e selecione os anexos novamente.';
      }
      if (draft == null) {
        Map<String, dynamic>? shared =
            _cache.isEmpty ? null : _cache.values.last;
        if (shared == null) {
          for (final other
              in ProjectEmailKind.values.where((kind) => kind != _kind)) {
            shared = _cache[other] ??
                RecoverableDraft.read(
                    _uid, 'email.${widget.project.id}.${other.name}') ??
                await _store.loadDraft(_uid!, widget.project.id, other);
            if (shared != null) break;
          }
        }
        if (shared != null) {
          draft = {
            'fields': shared['fields'],
            'productsImage': shared['productsImage'],
            'sharePointNames': shared['sharePointNames'],
            'contacts': [
              for (final c in shared['contacts'] as List? ?? [])
                {...Map<String, dynamic>.from(c), 'destination': 'Não incluir'}
            ]
          };
        }
      }
      if (!mounted || !_sameAccount) return;
      _subjectTemplate =
          template?['subject'] as String? ?? defaultEmailSubject(_kind);
      _bodyTemplate = cleanRemovedEmailFields(
          template?['body'] as String? ?? defaultEmailBody(_kind,
              professional: _professionalProject, enterprise: _enterpriseProject), _kind);
      if ((_professionalProject || _enterpriseProject) && _kind == ProjectEmailKind.finalization &&
          _bodyTemplate == cleanRemovedEmailFields(defaultEmailBody(_kind), _kind)) {
        _bodyTemplate = defaultEmailBody(_kind, professional: _professionalProject,
            enterprise: _enterpriseProject);
      }
      if (_enterpriseProject && _kind == ProjectEmailKind.internal &&
          _bodyTemplate == cleanRemovedEmailFields(defaultEmailBody(_kind), _kind)) {
        _bodyTemplate = defaultEmailBody(_kind, enterprise: true);
      }
      for (final controller in _fields.values) {
        controller.clear();
      }
      _fields['cliente']!.text = widget.project.client;
      _fields['razao_social']!.text = widget.project.client;
      _fields['solicitacao']!.text = widget.project.id;
      _fields['servico']!.text = widget.project.serviceType;
      _fields['saudacao']!.text = DateTime.now().hour < 12 ? 'Bom dia' : 'Boa tarde';
      _contacts.clear();
      _summaryInMessage = '';
      _productsImage = null;
      if (draft != null) {
        _sharePointNames.addAll(validSharePointNames(draft['sharePointNames']));
        final encodedImage = draft['productsImage'];
        if (encodedImage is String && encodedImage.length <= 700000) {
          try {
            final bytes = base64Decode(encodedImage);
            if (bytes.isNotEmpty && bytes.length <= 512 * 1024) {
              _productsImage = bytes;
            }
          } catch (_) {
            /* A damaged image must not prevent restoring the text. */
          }
        }
        final values = draft['fields'] as Map? ?? {};
        for (final entry in _fields.entries) {
          if (values[entry.key] is String) entry.value.text = values[entry.key];
        }
        for (final contact in draft['contacts'] as List? ?? []) {
          _contacts
              .add(EmailContact.fromJson(Map<String, dynamic>.from(contact)));
        }
      }
      final allowed = _projectContacts.map((c) => c.email.trim().toLowerCase()).toSet();
      _restoredRecipientSelections.clear();
      if (draft?['recipientSelectionManual'] == true) {
        _restoredRecipientSelections.addAll({for(final c in _contacts.where((c) => ['Para','Cc'].contains(c.destination)))
          c.email.trim().toLowerCase():c.destination});
      }
      _contacts.removeWhere((c) => !allowed.contains(c.email.trim().toLowerCase()));
      mergeAvailableEmailContacts(_contacts, _projectContacts);
      _recipientSelectionManual = draft?['recipientSelectionManual'] == true;
      if (!_recipientSelectionManual) {
        for (final contact in _contacts) {
          contact.destination = 'Não incluir';
        }
      }
      if (_kind.isInternal || _kind == ProjectEmailKind.finalization || _kind == ProjectEmailKind.finishes) _applyModelRecipients();
      _customBody = draft?['body'] is String;
      _customSubject = draft?['subject'] is String;
      if (_customBody) _body.text = draft!['body'];
      if (_customSubject) _subject.text = draft!['subject'];
      _applyWorkbookSignature();
      _render();
      _lastRecovery = jsonEncode(_snapshot());
      _ready = true;
      _saved.putIfAbsent(_kind, () => jsonEncode(_snapshot()));
      _message =
          'Destinatários precisam ser revisados. Anexos não são guardados no rascunho.';
    } catch (error) {
      _ready = false;
      if (mounted) {
        _message =
            recoveryError(error, operation: 'carregar os modelos e o rascunho');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _autoImportWorkbook();
  }

  Future<void> _autoImportWorkbook() async {
    if (!mounted || !_ready || !_sameAccount ||
        (widget.workbookLoader == null && widget.project.excelLink?.trim().isNotEmpty != true)) return;
    final reference = widget.project.excelLink ?? 'injected';
    if (_automaticallyImported.add('${_kind.name}|$reference')) await _import(automatic: true);
  }

  Future<void> _save() async {
    if (!(_recipientKey.currentState?.commitPending() ?? true)) return;
    setState(() => _busy = true);
    try {
      if (!_sameAccount) {
        throw StateError('A conta mudou. Feche e abra novamente.');
      }
      final snapshot = _snapshot();
      if (utf8.encode(jsonEncode(snapshot)).length > 900 * 1024) {
        throw const FormatException(
            'O rascunho ficou grande demais. Use um print menor e reduza o texto.');
      }
      await _store.saveDraft(_uid!, widget.project.id, _kind, snapshot);
      if (!mounted || !_sameAccount) return;
      _saved[_kind] = jsonEncode(_snapshot());
      setState(
          () => _message = 'Rascunho salvo somente neste projeto e modelo.');
      RecoverableDraft.clear(_uid, _recoveryKey);
      _lastRecovery = jsonEncode(_snapshot());
      _localStatus = 'Salvo na sua conta neste projeto e modelo.';
    } catch (error) {
      if (mounted) {
        setState(() =>
            _message = recoveryError(error, operation: 'salvar o rascunho'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import({bool linked = true, bool automatic = false}) async {
    final importKind = _kind;
    setState(() => _busy = true);
    try {
      Uint8List bytes;
      final reference = widget.project.excelLink?.trim() ?? '';
      if (widget.workbookLoader != null) {
        final selected = await widget.workbookLoader!();
        if (selected == null) return;
        bytes = selected;
      } else if (linked &&
          reference.isNotEmpty &&
          !reference.startsWith('http')) {
        bytes = BrowserLocalFiles.isReference(reference)
            ? await BrowserLocalFiles.read(reference,
                projectId: widget.project.id)
            : await NativeLocalFiles.read(reference,
                projectId: widget.project.id);
      } else {
        if (automatic) throw StateError('Vincule uma planilha local a este projeto.');
        final selection = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['xlsx', 'xlsm'],
            withData: true);
        if (selection == null) return;
        bytes = selection.files.single.bytes ??
            (throw const FormatException(
                'Não foi possível ler o arquivo selecionado.'));
      }
      final parsed = readEmailWorkbook(bytes,
          professionalInternal: _professionalProject || _kind == ProjectEmailKind.professionalInternal,
          enterpriseInternal: _enterpriseProject &&
              (_kind == ProjectEmailKind.internal || _kind == ProjectEmailKind.finalization || _kind == ProjectEmailKind.finishes));
      if (!mounted || !_sameAccount || _kind != importKind) return;
      var regenerateMessage = !automatic || !(_customBody || _customSubject);
      final accepted = automatic || !(_customBody || _customSubject) ? true : await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Importar dados da planilha?'),
                  content: StatefulBuilder(
                      builder: (context, update) => SizedBox(
                          width: 540,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text(
                                    '${parsed.contacts.length} contatos encontrados. Atualizar os dados usando a planilha vinculada? O print e os anexos serão preservados.'),
                                CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: regenerateMessage,
                                    title: const Text(
                                        'Regerar assunto e mensagem'),
                                    subtitle: const Text(
                                        'Desmarque para manter suas edições manuais.'),
                                    onChanged: (value) => update(() =>
                                        regenerateMessage = value ?? true)),
                              ])))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Importar'))
                  ]));
      if (accepted != true || !mounted || !_sameAccount || _kind != importKind) return;
      setState(() {
        {
          final destinations = {..._restoredRecipientSelections,for (final c in _contacts) c.email.trim().toLowerCase(): c.destination};
          _projectContacts.clear();
          mergeAvailableEmailContacts(_projectContacts, [...parsed.contacts,...parsed.externalRecipients,...parsed.internalRecipients]);
          _workbookRecipientsLoaded = true;
          _externalRecipients
            ..clear()
            ..addAll(parsed.externalRecipients);
          _internalRecipients
            ..clear()
            ..addAll(parsed.internalRecipients);
          _contacts
            ..clear()
            ..addAll(_projectContacts.map((c)=>EmailContact.fromJson(c.toJson())));
          for (final c in _contacts) {
            c.destination = _recipientSelectionManual
                ? destinations[c.email.trim().toLowerCase()] ?? 'Não incluir'
                : 'Não incluir';
          }
          if (_kind.isInternal || _kind == ProjectEmailKind.finalization || _kind == ProjectEmailKind.finishes) _applyModelRecipients();
          _restoredRecipientSelections.clear();
        }
        final previousConsultant = {for(final key in ['consultor','email_consultor','telefone_consultor']) key:_fields[key]!.text};
        for (final field in parsed.fields.entries) {
          _fields[field.key]?.text = field.value;
        }
        _applyWorkbookSignature(previous: previousConsultant);
        if (regenerateMessage) {
          _customBody = false;
          _customSubject = false;
        } else {
          _body.text = fillMissingEmailFields(_body.text, _values);
          _subject.text = fillMissingEmailFields(_subject.text, _values);
        }
        _render();
        _message =
            '${parsed.contacts.length} contatos e ${parsed.fields.values.where((v) => v.trim().isNotEmpty).length} campos preenchidos a partir da planilha. Os endereços ficam disponíveis nos modelos de e-mail, pelo + de Para e Cc. Revise os destinatários antes de gerar.';
        final missing = parsed.fields.entries.where((e) => e.value.trim().isEmpty)
            .map((e) => emailFieldLabels[e.key] ?? e.key).toList();
        if (missing.isNotEmpty) _message += ' Sem informação na planilha: ${missing.join(', ')}.';
        if (automatic && _customBody) {
          _message += ' Seu texto editado foi preservado e os campos pendentes disponíveis foram preenchidos. Para atualizar também valores já escritos, use Carregar dados da planilha e marque Regerar assunto e mensagem.';
        }
      });
      if (mounted && _sameAccount) _resolveSharePointNames(interactive: false);
    } catch (error) {
      if (automatic) _automaticallyImported.remove('${importKind.name}|${widget.project.excelLink ?? 'injected'}');
      if (mounted) {
        setState(() => _message =
            recoveryError(error, operation: 'ler os dados da planilha vinculada. Use Atualizar da planilha do projeto para tentar novamente'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureSharePoint() async {
    if (!_sameAccount) return;
    final links = sharePointLinksInBody(_body.text);
    if (links.isEmpty) {
      setState(() => _linkStatus = 'Carregue os links da planilha primeiro.');
      return;
    }
    final fields = {for (final link in links) link: TextEditingController(text: _sharePointNames[link] ?? '')};
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Nomes das pastas'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        children: [for (final entry in fields.entries) Padding(padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.key, maxLines: 2, overflow: TextOverflow.ellipsis),
            TextField(controller: entry.value, maxLength: 512,
              decoration: const InputDecoration(labelText: 'Nome para exibir no e-mail')),
          ]))]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usar nomes'))],
    ));
    if (accepted == true && mounted && _sameAccount) {
      setState(() {
        for (final entry in fields.entries) {
          final name = entry.value.text.trim();
          if (name.isEmpty) { _sharePointNames.remove(entry.key); }
          else { _sharePointNames[entry.key] = name; }
        }
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final field in fields.values) { field.dispose(); }
  }

  Future<void> _resolveSharePointNames({bool interactive = true}) async {
    if (!mounted || !_sameAccount || !_ready || _resolvingLinks) return;
    final links = sharePointLinksInBody(_body.text);
    if (links.isEmpty) {
      if (interactive) setState(() => _linkStatus = 'Não há links de pastas do SharePoint na mensagem. Carregue os dados da planilha primeiro.');
      return;
    }
    if (!interactive) return; // Opening Microsoft login always requires an explicit click.
    setState(() { _resolvingLinks = true; _linkStatus = 'Consultando os nomes das pastas…'; });
    try {
      if (widget.sharePointResolver == null) {
        final health = await EdeskIntegrationApi.call('/healthz',
          authenticated: false, baseUrl: 'http://127.0.0.1:8765');
        if (health['sharePointBrowserNames'] != true) {
          throw StateError('Atualize a integração para v62 e reinicie-a para buscar nomes pelo navegador. Você também pode informar os nomes manualmente.');
        }
      }
      final result = await (widget.sharePointResolver ?? ((args) => EdeskIntegrationApi.call(
        '/api/sharepoint/names', body: {'links': args['links']},
        baseUrl: 'http://127.0.0.1:8765', timeout: const Duration(seconds: 190))))({
        'owner': _uid, 'links': links, 'interactive': interactive,
      });
      if (!mounted || !_sameAccount) return;
      if (result['error'] is String) throw StateError(result['error']);
      final names = validSharePointNames(result['names']);
      final errors = <String>{for (final error in result['errors'] as List? ?? [])
        if (error is Map && error['message'] is String) error['message'] as String};
      setState(() {
        // Results belong to exact addresses, never to a title or another client.
        _sharePointNames.addAll({for (final link in links) if (names[link] != null) link: names[link]!});
        _linkStatus = result['needsConnection'] == true
          ? 'Clique em Buscar nomes no SharePoint para conectar à Microsoft.'
          : '${names.length} nome(s) de pasta atualizado(s).${errors.isEmpty ? '' : ' ${errors.join(' ')}'}';
      });
    } catch (error) {
      if (mounted && _sameAccount) {
        setState(() => _linkStatus = error is StateError ? error.message.toString()
          : 'Não foi possível consultar o SharePoint. Confira a conexão e tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _resolvingLinks = false);
    }
  }

  Future<void> _pickAttachments() async {
    try {
      final selected = widget.attachmentPicker != null
          ? await widget.attachmentPicker!()
          : await _selectAttachments();
      if (selected == null || !mounted || !_sameAccount) return;
      if (selected.fold<int>(0, (s, a) => s + a.bytes.length) +
              _attachments.fold<int>(0, (s, a) => s + a.bytes.length) >
          20 * 1024 * 1024) {
        throw const FormatException('Use até 20 MB de anexos por e-mail.');
      }
      setState(() {
        _attachments.addAll(selected);
        _render();
        _message = '${selected.length} anexo(s) adicionado(s). Confira os arquivos antes de gerar o e-mail.';
      });
    } catch (error) {
      if (mounted) {
        setState(() =>
            _message = 'Não foi possível adicionar. Use até 20 MB de anexos.');
      }
    }
  }

  Future<List<EmailAttachment>?> _selectAttachments() async {
      final result = await FilePicker.platform
          .pickFiles(allowMultiple: true, withData: true);
      if (result == null) return null;
      return [
        for (final file in result.files)
          if (file.bytes != null) EmailAttachment(file.name, file.bytes!)
      ];
  }

  Future<void> _generate() async {
    if (!_workbookRecipientsLoaded &&
        (widget.workbookLoader != null || widget.project.excelLink?.trim().isNotEmpty == true)) {
      await _import(automatic:true);
      if (!mounted || !_sameAccount) return;
      if (!_workbookRecipientsLoaded) {
        await _generationError('Não foi possível conferir os destinatários na planilha deste projeto. Use Carregar dados da planilha e confira a mensagem da leitura antes de gerar.');
        return;
      }
    }
    if (_kind == ProjectEmailKind.finishes &&
        finishesSpreadsheet(_attachments) == null) {
      await _generationError('Anexe a planilha de acabamentos (.xlsx ou .xlsm) em Selecionar Anexo antes de gerar o e-mail.');
      return;
    }
    if (!(_recipientKey.currentState?.commitPending() ?? true)) {
      await _generationError(
          'Revise os e-mails digitados nos campos Para e Cc.');
      return;
    }
    final allowed = _allowedRecipientEmails;
    if (_contacts.any((c) => ['Para', 'Cc'].contains(c.destination) &&
        !allowed.contains(c.email.trim().toLowerCase()))) {
      await _generationError('Carregue a planilha e selecione somente os endereços deste trabalho.');
      return;
    }
    try {
      if (!_sameAccount) {
        throw StateError('A conta mudou. Feche e abra novamente.');
      }
      if (_kind.isInternal) {
        _body.text = emailBodyWithSummary(_body.text, _fields['resumo']!.text,
            previousSummary: _summaryInMessage);
        _summaryInMessage = _fields['resumo']!.text;
      }
      if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
        throw const FormatException('Preencha assunto e mensagem.');
      }
      if (RegExp(r'\{[a-z_]+\}|\[PREENCHER: [^\]]+\]').hasMatch('${_subject.text}\n${_body.text}')) {
        final labels = RegExp(r'\[PREENCHER: ([^\]]+)\]')
            .allMatches('${_subject.text}\n${_body.text}').map((m) => m[1]!).toSet();
        throw FormatException('Preencha os campos destacados na prévia antes de gerar o e-mail:\n\n${labels.map((label) => '• $label').join('\n')}');
      }
      final signature =
          await rootBundle.load('assets/images/email_signature_cyncly.jpg');
      final signatureIcons = <String, Uint8List>{};
      for (final key in ['mail', 'phone', 'web']) {
        final data =
            await rootBundle.load('assets/images/email_signature_$key.png');
        signatureIcons[key] =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
      if (!mounted || !_sameAccount) return;
      final bytes = buildEmailDraft(
          linkLabels: _emailLinkLabels,
          subject: _subject.text,
          body: _body.text,
          contacts: _contacts,
          attachments: _attachments,
          signatureImage: signature.buffer
              .asUint8List(signature.offsetInBytes, signature.lengthInBytes),
          signatureName: _fields['consultor']!.text.trim(),
          signatureEmail: _fields['email_consultor']!.text.trim(),
          signaturePhone: _fields['telefone_consultor']!.text.trim().isNotEmpty
              ? _fields['telefone_consultor']!.text.trim()
              : _fields['email_consultor']!.text.trim().toLowerCase() ==
                      'rodrigo.zaparolli@cyncly.com'
                  ? '5430225800'
                  : '',
          signatureIcons: signatureIcons,
          productsImage:
              _kind.isInternal ? _productsImage : null);
      final name =
          '${_kind.name}-${widget.project.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.eml';
      final approved = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Gerar rascunho para Outlook?'),
                  content: Text(
                      'Confira os destinatários, o texto e os ${_attachments.length} anexos. O arquivo .eml será gerado para revisão no Outlook; não haverá envio automático.\n\nNo encerramento interno, confira também os dados de acesso incluídos no texto.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Revisar')),
                    FilledButton(
                        onPressed: () {
                          // Start the web download directly in the user click.
                          if (kIsWeb) {
                            try {
                              downloadBytes(
                                  fileName: name,
                                  bytes: bytes,
                                  mimeType: 'message/rfc822');
                            } catch (error) {
                              Navigator.pop(context, false);
                              _generationError(
                                  'Não foi possível iniciar o download. Tente novamente e confira as permissões de download do navegador.');
                              return;
                            }
                          }
                          Navigator.pop(context, true);
                        },
                        child: const Text('Baixar arquivo .eml'))
                  ]));
      if (approved != true || !mounted || !_sameAccount) return;
      if (!kIsWeb) {
        final path = await FilePicker.platform.saveFile(
            fileName: name,
            bytes: [TargetPlatform.android, TargetPlatform.iOS]
                    .contains(defaultTargetPlatform)
                ? bytes
                : null,
            type: FileType.custom,
            allowedExtensions: ['eml']);
        if (path == null) return;
        if (![TargetPlatform.android, TargetPlatform.iOS]
            .contains(defaultTargetPlatform)) {
          await writeLocalBytes(path, bytes);
        }
      }
      if (mounted) {
        setState(() => _message =
            'Arquivo gerado. Abra no Outlook e confira antes de enviar. A edição do .eml depende da versão do Outlook.');
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                  title: Text(kIsWeb ? 'Download iniciado' : 'Arquivo salvo'),
                  content: Text(
                      '$name\n\n${kIsWeb ? 'Pressione Ctrl + J para conferir o download. O navegador pode perguntar onde salvar ou exibir um aviso de bloqueio.' : 'Abra o arquivo salvo no Outlook.'}\n\nO arquivo não abre o Outlook automaticamente e nenhum e-mail foi enviado.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Entendi'))
                  ],
                ));
      }
    } on FormatException catch (e) {
      await _generationError(e.message);
    } catch (error) {
      await _generationError(
          'Não foi possível gerar o arquivo. ${recoveryError(error, operation: 'gerar o e-mail')}');
    }
  }

  Future<void> _generationError(String message) async {
    if (!mounted) return;
    setState(() => _message = message);
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('O e-mail ainda não foi gerado'),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Corrigir dados'))
              ],
            ));
  }

  Future<void> _editTemplate() async {
    final subject = TextEditingController(text: _subjectTemplate),
        body = TextEditingController(text: _bodyTemplate);
    final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Modelo padrão — ${_kind.label}'),
                content: SizedBox(
                    width: 650,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Aplica-se aos seus próximos rascunhos. Use campos como {cliente}, {solicitacao}, {consultor} e {equipe}. Os rascunhos com texto editado serão preservados.'),
                      const SizedBox(height: 12),
                      ExpansionTile(
                          title: const Text('Campos disponíveis no modelo'),
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: SelectableText(emailFieldLabels.entries
                                    .map((entry) =>
                                        '${entry.value}: {${entry.key}}')
                                    .join('\n')))
                          ]),
                      TextField(
                          controller: subject,
                          decoration: const InputDecoration(
                              labelText: 'Assunto padrão')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: body,
                          maxLines: 14,
                          decoration:
                              const InputDecoration(labelText: 'Texto padrão'))
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Salvar modelo'))
                ]));
    final newSubject = subject.text,
        newBody = cleanRemovedEmailFields(body.text, _kind);
    // Dialog closing animation still uses its controllers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    subject.dispose();
    body.dispose();
    if (result != true || !mounted || !_sameAccount) return;
    setState(() => _busy = true);
    try {
      await _store
          .saveTemplate(_uid!, _kind, {'subject': newSubject, 'body': newBody});
      if (mounted && _sameAccount) {
        setState(() {
          _subjectTemplate = newSubject;
          _bodyTemplate = newBody;
          _render();
          _message = 'Modelo padrão atualizado para sua conta.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Não foi possível salvar o modelo padrão.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _panel(Widget child) => Container(
      decoration: AppVisuals.card,
      padding: const EdgeInsets.all(16),
      child: Material(type: MaterialType.transparency, child: child));
  Future<void> _close() async {
    if (_closing || _busy) return;
    setState(() => _closing = true);
    try {
      final keep = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
                  title: const Text('Manter as alterações?'),
                  content: const Text(
                      'Manter guarda os dados, mensagens e print neste dispositivo para continuar depois. Descartar remove as alterações não salvas; o que já foi salvo no projeto permanece. Os anexos precisam ser selecionados novamente.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Continuar editando')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Descartar e fechar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Manter e fechar'))
                  ]));
      if (keep == null || !mounted) return;
      if (keep && !(_recipientKey.currentState?.commitPending() ?? true)) {
        return;
      }
      final snapshots = {..._cache, _kind: _snapshot()};
      if (keep) {
        if (!_sameAccount ||
            !snapshots.entries.every((entry) => RecoverableDraft.save(_uid,
                'email.${widget.project.id}.${entry.key.name}', entry.value))) {
          setState(() => _message =
              'Não foi possível manter o rascunho neste dispositivo. Salve no projeto antes de fechar.');
          return;
        }
      } else {
        _discardOnClose = true;
        for (final kind in snapshots.keys) {
          RecoverableDraft.clear(
              _uid, 'email.${widget.project.id}.${kind.name}');
        }
      }
      setState(() => _allowClose = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _pickFinishesDeadline() async {
    final previous = _fields['prazo_acabamentos']!.text;
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100,12,31));
    if (picked == null || !mounted || !_sameAccount) return;
    final value = '${picked.day.toString().padLeft(2,'0')}/${picked.month.toString().padLeft(2,'0')}/${picked.year}';
    setState(() {
      _fields['prazo_acabamentos']!.text = value;
      if (_customBody) {
        if (previous.isNotEmpty) _body.text = _body.text.replaceAll(
          'Definições de acabamentos até o dia $previous.',
          'Definições de acabamentos até o dia $value.');
        _body.text = fillMissingEmailFields(_body.text, _values);
      }
      _render();
    });
  }

  Widget _preview() =>
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Prévia do e-mail', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: _busy ? null : _pickAttachments,
              icon: const Icon(Icons.attach_file), label: const Text('Selecionar Anexo')),
        ]),
        for (final attachment in _attachments) ListTile(dense: true,
            title: Text(attachment.name), trailing: IconButton(tooltip: 'Remover anexo',
              onPressed: () => setState(() { _attachments.remove(attachment); _render(); }), icon: const Icon(Icons.close))),
        if (_kind.isInternal) ExpansionTile(title: const Text('Produtos adquiridos — print'),
            children: [ProductsImageField(image: _productsImage, enabled: !_busy,
                onChanged: (image) => setState(() {
                  _productsImage = image;
                  _fields['produtos']!.clear();
                  if (image == null) _body.text = _body.text.replaceAll(productsImageMarker, '');
                  _render();
                }))]),
        if (_kind == ProjectEmailKind.finishes) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFinishesDeadline,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(_fields['prazo_acabamentos']!.text.trim().isEmpty
              ? 'Definir prazo de retorno' : 'Prazo de retorno: ${_fields['prazo_acabamentos']!.text}'),
          ),
          const Text('Selecione a planilha de acabamentos em Selecionar Anexo. São aceitos .xlsx e .xlsm.'),
        ],
        const SizedBox(height: 16),
        TextField(
            controller: _subject,
            style: _subject.text.contains('[PREENCHER:') ? const TextStyle(color: Color(0xFF823900)) : null,
            decoration: InputDecoration(labelText: 'Assunto',
                filled: _subject.text.contains('[PREENCHER:'),
                fillColor: _subject.text.contains('[PREENCHER:') ? const Color(0xFFFFE4AA) : null),
            onChanged: (_) => setState(() => _customSubject = true)),
        const SizedBox(height: 16),
        EmailBodyPreview(body: _body.text,
          controller: _body, enabled: !_busy && _ready,
          onChanged: () => setState(() => _customBody = true),
          productsImage: _kind.isInternal ? _productsImage : null,
          linkLabels: _emailLinkLabels),
        const SizedBox(height: 12),
        Image.asset('assets/images/email_signature_cyncly.jpg',
            key: const ValueKey('email-signature-banner'),
            width: 630,
            fit: BoxFit.contain),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: '${_subject.text}\n\n${_body.text}'));
                if (mounted) {
                  setState(() => _message = _productsImage != null &&
                          _kind.isInternal
                      ? 'Texto copiado. Use Gerar rascunho para Outlook para incluir o print no corpo do e-mail.'
                      : 'Texto copiado. Destinatários e anexos precisam ser adicionados no Outlook.');
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copiar texto'))
        ]),
        const Text(
            'Revise texto, destinatários e anexos. O rascunho não é enviado automaticamente.',
            style: TextStyle(fontSize: 12)),
      ]));
  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    _recoverLocally();
    return PopScope(
        canPop: _allowClose,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _close();
        },
        child: Dialog(
            insetPadding: const EdgeInsets.all(16),
            backgroundColor: AppPalette.surface,
            child: SizedBox(
                width: 1380,
                height: MediaQuery.sizeOf(context).height * .92,
                child: Column(children: [
                  if (_localStatus.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                        child: Text(_localStatus,
                            style: TextStyle(
                                color: AppPalette.secondary, fontSize: 12))),
                  Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(children: [
                        Icon(Icons.mail_outline, color: AppPalette.primary),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('E-mails do projeto',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  '${widget.project.id} • ${widget.project.client} • Enterprise',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis)
                            ])),
                        IconButton(
                            onPressed: _close,
                            icon: const Icon(Icons.close),
                            tooltip: 'Fechar')
                      ])),
                  if (_busy) const LinearProgressIndicator(),
                  const Divider(height: 1),
                  Expanded(
                      child: AbsorbPointer(
                          absorbing: _busy || !_ready,
                          child: SingleChildScrollView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 18),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    EmailRecipientFields(
                                        key: _recipientKey,
                                        contacts: _contacts,
                                        companyContacts: _projectContacts,
                                        allowedEmails: _allowedRecipientEmails,
                                        onChanged: () => setState(() {
                                          _recipientSelectionManual = true;
                                          _restoredRecipientSelections.clear();
                                          _render();
                                        })),
                                    Text(_busy ? 'Lendo os dados do e-mail. Aguarde a conferência dos destinatários.'
                                      : _workbookRecipientsLoaded
                                          ? '${_allowedRecipientEmails.length} endereços conferidos na planilha deste projeto. Use + ou digite um desses endereços em Para/Cc.'
                                          : 'Carregue a planilha deste projeto para disponibilizar os destinatários em Para/Cc.',
                                      style: TextStyle(fontSize: 12)),
                                    const Divider(),
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                      for (final kind
                                          in const [ProjectEmailKind.initial, ProjectEmailKind.internal, ProjectEmailKind.finalization, ProjectEmailKind.finishes])
                                        ChoiceChip(
                                            label: Text(kind.label),
                                            selected: kind == (_kind == ProjectEmailKind.professionalInternal ? ProjectEmailKind.internal : _kind),
                                            onSelected: _busy ? null : (_) {
                                              if (kind == (_kind == ProjectEmailKind.professionalInternal ? ProjectEmailKind.internal : _kind)) return;
                                              if (!(_recipientKey.currentState
                                                      ?.commitPending() ??
                                                  true)) {
                                                return;
                                              }
                                              _recoverLocally();
                                              _cache[_kind] = _snapshot();
                                              _attachments.clear();
                                              _kind = kind == ProjectEmailKind.internal && _professionalProject ? ProjectEmailKind.professionalInternal : kind;
                                              _load();
                                            })
                                    ]),
                                    const SizedBox(height: 14),
                                    Wrap(spacing: 8, runSpacing: 8, children: [
                                      FilledButton.icon(
                                          onPressed: _busy ? null : _import,
                                          icon: const Icon(Icons.table_chart_outlined),
                                          label: const Text('Carregar dados da planilha')),
                                      TextButton(
                                          onPressed: () =>
                                              _import(linked: false),
                                          child:
                                              const Text('Selecionar planilha'))
                                    ]),
                                    Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                      TextButton.icon(
                                        onPressed: _busy || _resolvingLinks ? null : () => _resolveSharePointNames(),
                                        icon: _resolvingLinks ? const SizedBox(width: 16, height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
                                        label: Text(_resolvingLinks ? 'Consultando SharePoint…' : 'Buscar nomes no SharePoint')),
                                      IconButton(tooltip: 'Informar nomes das pastas',
                                        onPressed: _busy || _resolvingLinks ? null : _configureSharePoint,
                                        icon: const Icon(Icons.settings_outlined, size: 20)),
                                    ]),
                                    if (_linkStatus.isNotEmpty) Text(_linkStatus,
                                        key: const ValueKey('sharepoint-link-status'), style: const TextStyle(fontSize: 12)),
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Text(_message,
                                            style: TextStyle(
                                                color: AppPalette.secondary))),
                                    _preview(),
                                    const SizedBox(height: 16),
                                  ])))),
                  const Divider(height: 1),
                  Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(spacing: 10, runSpacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: _busy || !_ready ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Salvar neste projeto')),
                        TextButton(
                            onPressed: _busy || !_ready ? null : _editTemplate,
                            child: const Text('Editar modelo padrão')),
                        FilledButton.icon(
                            onPressed: _busy || !_ready ? null : _generate,
                            icon: const Icon(Icons.mail_outline),
                            label: const Text('Gerar e-mail para Outlook'))
                      ])),
                ]))));
  }

  @override
  void dispose() {
    _recoverLocally();
    for (final c in _fields.values) {
      c.dispose();
    }
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }
}
