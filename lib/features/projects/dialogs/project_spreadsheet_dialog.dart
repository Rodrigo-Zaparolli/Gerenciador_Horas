import '../../../core/config/checklist_block_pilot_access.dart';
import 'spreadsheet_status_cache.dart';
import 'spreadsheet_draft.dart';
import 'package:flutter/foundation.dart';
import 'project_worksheet_preference.dart';
import 'project_documents_dialog.dart';
import 'dart:async';
import 'spreadsheet_store.dart';
import 'spreadsheet_sheet_settings.dart';
import 'catalog_training_panel.dart';
import 'catalog_checklist_tasks.dart';
import 'catalog_worksheet_roles.dart';
import 'company_contacts.dart';
import 'project_spreadsheet_kind.dart';
import 'checklist_status_preview.dart';
import 'checklist_live_preview.dart';
import 'checklist_stage_dialog.dart';
import 'workbook_sheet_dialog.dart';
import 'spreadsheet_dialog_chrome.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/config/pilot_feature_access.dart';
import '../../../data/services/native_local_files_service.dart';
import '../../../data/services/firebase_service.dart';
import '../../../data/services/recoverable_draft.dart';
import 'spreadsheet_phase_dates.dart';
import 'checklist_dates_button.dart';
import 'spreadsheet_stage_dates_dialog.dart';
import 'spreadsheet_phase_send_dialog.dart';
import '../../../domain/models/project_model.dart';

class ProjectSpreadsheetDialog extends StatefulWidget {
  const ProjectSpreadsheetDialog(
      {super.key,
      required this.project,
      this.uidProvider,
      this.emailProvider,
      this.transport,
      this.contactsLoader,
      this.store,
      this.sheetSettingsStore,
      this.phaseDatesSaver,
      this.initialTab = 0});
  final Future<List<CompanyContact>> Function()? contactsLoader;
  final int initialTab;
  final SpreadsheetStore? store;
  final SpreadsheetSheetSettingsStore? sheetSettingsStore;
  final Future<void> Function(List<Map<String, dynamic>>)? phaseDatesSaver;
  final ProjectModel project;
  final String? Function()? uidProvider, emailProvider;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? transport;

  static Future<void> show(BuildContext context, ProjectModel project) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!PilotFeatureAccess.allows(uid: user?.uid, email: user?.email)) return;
    final preference = ProjectWorksheetPreference.load(user!.uid, project.id)
        .catchError((Object _) => null);
    String? routeWorksheet;
    await showDialog<Object?>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
            builder: (_, setRouteState) => FutureBuilder<String?>(
                future: preference,
                builder: (_, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return AlertDialog(
                        title: const Text('Planilha do projeto'),
                        content: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator()),
                              SizedBox(width: 12),
                              Flexible(
                                  child: Text('Carregando a guia preferida...'))
                            ]),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Fechar'))
                        ]);
                  }
                  if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
                    return AlertDialog(
                        content:
                            const Text('A conta mudou. Feche esta janela.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Fechar'))
                        ]);
                  }
                  final initial = routeWorksheet ??
                      snapshot.data ??
                      defaultProjectWorksheet(project.serviceType);
                  if (initial == null || mappedWorksheetTab(initial) != null) {
                    return ProjectSpreadsheetDialog(
                        project: project,
                        initialTab: mappedWorksheetTab(initial) ?? 0);
                  }
                  return WorkbookSheetDialog(
                    draftOwner: user.uid,
                    fileReference: project.excelLink,
                    onMappedWorksheet: (name) async {
                      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
                        return;
                      }
                      setRouteState(() => routeWorksheet = name);
                      unawaited(ProjectWorksheetPreference.save(
                              user.uid, project.id, name)
                          .catchError((Object _) {}));
                    },
                    projectId: project.id,
                    client: project.client,
                    serviceType: project.serviceType,
                    initialWorksheet: initial,
                    allowed: () =>
                        FirebaseAuth.instance.currentUser?.uid == user.uid,
                    onWorksheetOpened: (name) =>
                        ProjectWorksheetPreference.save(
                            user.uid, project.id, name),
                    call: (args) => NativeLocalFiles.call(
                        args['action'] as String,
                        reference: project.excelLink,
                        projectId: project.id,
                        projectField: 'excelLink',
                        worksheet: args['worksheet'] as String?,
                        firstRow: args['firstRow'] as int?,
                        firstColumn: args['firstColumn'] as int?,
                        revision: args['revision'] as String?,
                        changes: (args['changes'] as List?)
                            ?.cast<Map<String, dynamic>>()),
                  );
                })));
  }

  @override
  State<ProjectSpreadsheetDialog> createState() =>
      _ProjectSpreadsheetDialogState();
}

class _ProjectSpreadsheetDialogState extends State<ProjectSpreadsheetDialog> {
  final tabContentKey = GlobalKey();
  int? requestedMappedTab;
  bool _requestedCatalogGuide = false;
  final _catalogTasksKey = GlobalKey();
  final Map<String, Map<String, dynamic>> pending = {};
  final Map<String, String> calculatedEmails = {};
  final Map<String, String> _stageWorks = {};
  List<Map<String, dynamic>> _phaseJobs = [];
  String? _phaseRevision;
  String get _phaseScope =>
      'spreadsheet-phase-sync.${widget.project.id}.${widget.project.excelLink}';

  List<Map<String, dynamic>> phaseJobsForDraft(
      {Map<String, dynamic>? calculatedStatus}) {
    final fields = (data?['fields'] as List? ?? []).whereType<Map>();
    final changed = fields
        .where((f) =>
            f['stagePeriod'] != null &&
            pending.containsKey(keyOf(Map<String, dynamic>.from(f))))
        .toList();
    final stages = changed.map((f) => f['stagePeriod'].toString()).toSet();
    final calculated =
        (calculatedStatus?['rows'] as List? ?? []).whereType<Map>();
    for (final field in fields.where((f) => f['stagePeriod'] != null)) {
      final matches =
          calculated.where((r) => r['label'] == field['stagePeriod']).toList();
      if (matches.length == 1 &&
          matches.single[field['endpoint']] is String &&
          matches.single[field['endpoint']] != field['value']) {
        final stage = field['stagePeriod'].toString();
        final related = (widget.project.subTasks ?? <TaskModel>[]).any(
            (t) => spreadsheetStageKey(t.stage) == spreadsheetStageKey(stage));
        if (related || _stageWorks.containsKey(stage)) stages.add(stage);
      }
    }
    final jobs = [
      for (final stage in stages)
        _phaseJobForStage(stage, calculatedStatus: calculatedStatus)
    ];
    if (jobs.map((j) => '${j['request']}/${j['work']}').toSet().length !=
        jobs.length) {
      throw StateError(
          'Cada etapa precisa estar relacionada a uma fase diferente antes de salvar.');
    }
    for (final job in jobs) {
      final start = DateTime.tryParse(job['start'].toString()),
          end = DateTime.tryParse(job['end'].toString());
      if (start == null || end == null || end.isBefore(start)) {
        throw StateError(
            'O período de ${job['stage']} ficou inválido. Ajuste o início e o fim antes de salvar.');
      }
    }
    return jobs;
  }

  Map<String, dynamic> _phaseJobForStage(String stage,
      {Map<String, dynamic>? calculatedStatus}) {
    final fields = (data!['fields'] as List)
        .whereType<Map>()
        .where((f) => f['stagePeriod'] == stage)
        .toList();
    String date(String endpoint) {
      final rows = (calculatedStatus?['rows'] as List? ?? [])
          .whereType<Map>()
          .where((r) => r['label'] == stage)
          .toList();
      if (rows.length == 1 && rows.single[endpoint] is String)
        return rows.single[endpoint].toString();
      return current(Map<String, dynamic>.from(
          fields.singleWhere((f) => f['endpoint'] == endpoint))).toString();
    }

    final mapped = _stageWorks[stage] ??
        fields
            .map((f) => pending['${f['sheet']}!${f['cell']}']?['phaseWork'])
            .whereType<String>()
            .firstOrNull;
    final tasks = (widget.project.subTasks ?? <TaskModel>[])
        .where((t) => mapped != null
            ? t.edeskWorkNumber == mapped
            : spreadsheetStageKey(t.stage) == spreadsheetStageKey(stage))
        .toList();
    if (tasks.length != 1)
      throw StateError(
          'Relacione uma fase única à etapa $stage antes de salvar.');
    return spreadsheetPhaseJob(
        tasks.single, widget.project.id, date('start'), date('end'), stage);
  }

  void keepPhaseQueue() {
    if (_phaseJobs.isEmpty) {
      RecoverableDraft.clear(owner, _phaseScope);
      return;
    }
    RecoverableDraft.save(
        owner, _phaseScope, {'revision': _phaseRevision, 'jobs': _phaseJobs});
  }

  Future<void> syncPhaseDates({bool verifyExcel = true}) async {
    if (!authorized || _phaseJobs.isEmpty) return;
    final jobs = _phaseJobs.map((j) => Map<String, dynamic>.from(j)).toList();
    if (verifyExcel) {
      final checked = await request('excel-editor-read');
      if (!mounted || !authorized) return;
      if (!matches(checked))
        throw StateError('A planilha retornada não corresponde ao projeto.');
      final fields = (checked['fields'] as List).whereType<Map>();
      for (final job in jobs) {
        for (final endpoint in ['start', 'end']) {
          final matches = fields
              .where((f) =>
                  f['stagePeriod'] == job['stage'] && f['endpoint'] == endpoint)
              .toList();
          final statusRows = ((checked['statusPreview'] as Map?)?['rows'] as List? ?? [])
              .whereType<Map>().where((r) => spreadsheetStageKey('${r['label']}') == spreadsheetStageKey('${job['stage']}')).toList();
          final verified = matches.length == 1
              ? matches.single['value'] == job[endpoint]
              : statusRows.length == 1 && statusRows.single[endpoint] == job[endpoint];
          if (!verified)
            throw StateError(
                'As datas da planilha mudaram. Confira a etapa antes de sincronizar as fases.');
        }
      }
    }
    if (widget.phaseDatesSaver != null) {
      await widget.phaseDatesSaver!(jobs);
    } else if (widget.transport == null) {
      await FirebaseService().applySpreadsheetPhaseDates(
          ownerUid: owner!,
          projectId: widget.project.id,
          reference: widget.project.excelLink!,
          jobs: jobs);
    } else {
      throw StateError('A sincronização das fases não está disponível.');
    }
    if (!mounted || !authorized) return;
    for (final job in jobs) {
      final target = (widget.project.subTasks ?? <TaskModel>[]).where(
          (t) => t.edeskWorkNumber == job['work'] && t.stage == job['phase']);
      if (target.length == 1) {
        target.single.startDate = DateTime.parse(job['start']);
        target.single.planStart = DateTime.parse(job['start']);
        target.single.planEnd = DateTime.parse(job['end']);
      }
    }
    _phaseJobs = [];
    keepPhaseQueue();
    setState(() {
      error = null;
      notice =
          'Planilha salva e datas das fases atualizadas no sistema. Use Enviar fases ao E-Desk no cabeçalho.';
    });
  }

  Future<void> updateWorkDatesFromChecklist() async {
    if (busy || !authorized || pending.isNotEmpty || _phaseJobs.isNotEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      final checked = await request('excel-editor-read');
      if (!mounted || !authorized) return;
      if (!matches(checked)) throw StateError('A planilha retornada não corresponde ao projeto.');
      final tasks = widget.project.subTasks ?? <TaskModel>[];
      final periods = checklistPeriods(checked, [for (final task in tasks) task.stage]);
      final jobs = <Map<String, dynamic>>[];
      for (final entry in periods.entries) {
        final task = tasks[entry.key];
        if (task.edeskWorkNumber.trim().isEmpty) continue;
        if (phaseDay(task.startDate) == phaseDay(entry.value[0]) && phaseDay(task.planStart) == phaseDay(entry.value[0]) && phaseDay(task.planEnd) == phaseDay(entry.value[1])) continue;
        jobs.add(spreadsheetPhaseJob(task, widget.project.id, phaseDay(entry.value[0]), phaseDay(entry.value[1]), task.stage));
      }
      if (jobs.isEmpty) {
        setState(() => notice = 'Nenhuma data diferente com vínculo único foi encontrada. Confira as datas e os vínculos das etapas no trabalho.');
        return;
      }
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Atualizar datas no trabalho'),
        content: SizedBox(width: 600, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Aplicar as datas da planilha salva nas etapas do sistema. Não altera horas e não envia ao E-Desk. Etapas sem correspondência válida serão preservadas.'),
          const SizedBox(height: 12),
          for (final job in jobs) Text('${job['stage']}: ${job['start']} → ${job['end']}'),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar e salvar no trabalho'))],
      ));
      if (confirmed != true || !mounted || !authorized) return;
      _phaseJobs = jobs;
      _phaseRevision = checked['revision'].toString();
      keepPhaseQueue();
      await syncPhaseDates();
    } catch (e) {
      if (mounted && authorized) setState(() => error = 'Não foi possível atualizar as datas do trabalho. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> retryPhaseDates() async {
    if (busy || !authorized) return;
    setState(() => busy = true);
    try {
      await syncPhaseDates();
    } catch (e) {
      if (mounted && authorized)
        setState(() => error =
            'O Excel está salvo; a sincronização das fases ainda está pendente. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editPeriod(Map row) async {
    if (busy || !authorized || _phaseJobs.isNotEmpty) return;
    final stage = row['label'].toString();
    final fields = (data!['fields'] as List)
        .whereType<Map>()
        .where((f) => f['stagePeriod'] == stage)
        .map((f) => Map<String, dynamic>.from(f))
        .toList();
    if (fields.length != 2 || fields.any((f) => f['readOnly'] == true)) {
      setState(() => error =
          'Esta tabela ainda não permite editar as datas. Atualize a integração e recarregue a planilha.');
      return;
    }
    final start = fields.singleWhere((f) => f['endpoint'] == 'start'),
        end = fields.singleWhere((f) => f['endpoint'] == 'end');
    final all = (widget.project.subTasks ?? <TaskModel>[])
        .where((t) =>
            t.edeskWorkNumber.isNotEmpty &&
            (t.edeskSolicitacao?.trim().isNotEmpty != true ||
                t.edeskSolicitacao == widget.project.id))
        .toList();
    final tasks = all
        .where((t) =>
            all
                .where((other) => other.edeskWorkNumber == t.edeskWorkNumber)
                .length ==
            1)
        .toList();
    final revision = data!['revision'];
    final result = await editSpreadsheetStageDates(context,
        stage: stage,
        start: current(start).toString(),
        end: current(end).toString(),
        tasks: tasks,
        selectedWork: _stageWorks[stage],
        adjustedSummary:
            fields.any((f) => f['dateMode'] == 'summary-adjusted'));
    if (result == null ||
        !mounted ||
        !authorized ||
        busy ||
        data?['revision'] != revision) return;
    setState(() {
      _stageWorks[stage] = result.work;
      for (final f in fields) {
        final value = f['endpoint'] == 'start' ? result.start : result.end;
        if (value == f['value']) {
          pending.remove(keyOf(f));
        } else {
          pending[keyOf(f)] = {
            'sheet': f['sheet'],
            'cell': f['cell'],
            'before': f['value'],
            'value': value,
            'phaseWork': result.work,
          };
        }
      }
      _datePreviewPending = true;
      livePreview.pause();
      notice = 'Datas em edição. Use Aplicar ajustes de datas ao terminar.';
      persistDraft();
    });
  }

  final Set<String> hiddenPasswords = {};
  Map<String, dynamic>? data;
  Map<String, String> sheetNames = {};
  int _catalogRefresh = 0;
  String get _catalogReference => sheetNames['catalogSource'] == 'external'
      ? sheetNames['catalogReference'] ?? '' : widget.project.excelLink ?? '';
  Future<Map<String, dynamic>> requestCatalog(String action, {String? revision, List<Map<String, dynamic>>? changes, String? range}) {
    final reference = _catalogReference;
    final requestedOwner = owner;
    final taskSheet = catalogChecklistSheet(sheetNames);
    final result = _fileRequestTail.then((_) async {
      if (!mounted || !authorized || owner != requestedOwner || reference != _catalogReference) throw StateError('O vínculo ou a conta mudou.');
      final args = <String, dynamic>{'action': action, 'reference': reference,
        'serviceType': 'catalog-checklist',
        if (action != 'preview') 'sheetNames': {'entry': sheetNames['entry'] ?? 'Informações de entrada', 'checklist': taskSheet},
        if (range != null) 'range': range,
        if (revision != null) 'revision': revision,
        if (changes != null) 'changes': changes};
      final response = widget.transport != null ? await widget.transport!(args) : await NativeLocalFiles.call(action, reference: reference, serviceType: 'catalog-checklist',
        sheetNames: action == 'preview' ? null : {'entry': sheetNames['entry'] ?? 'Informações de entrada', 'checklist': taskSheet},
        range: range, revision: revision, changes: changes);
      if (!mounted || !authorized || owner != requestedOwner || reference != _catalogReference || taskSheet != catalogChecklistSheet(sheetNames)) throw StateError('O vínculo ou a conta mudou.');
      return response;
    });
    _fileRequestTail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
  SpreadsheetSheetSettingsStore? get settingsStore =>
      widget.sheetSettingsStore ??
      (widget.transport == null
          ? FirebaseSpreadsheetSheetSettingsStore()
          : null);
  bool matches(Map<String, dynamic> result, {Map<String, String>? names}) {
    final selected = names ?? sheetNames;
    return spreadsheetMatchesProject(result, widget.project.serviceType,
        checklistSheet: selected['checklist'], entrySheet: selected['entry']);
  }

  String? error, notice, owner;
  bool busy = false, settingsReady = false;
  bool _datePreviewPending = false;
  Future<void> sendSavedPhases() async {
    if (busy || !authorized || pending.isNotEmpty || _phaseJobs.isNotEmpty)
      return;
    setState(() => busy = true);
    await livePreview.pauseAndWait();
    try {
      if (!mounted || !authorized) return;
      final message = await showSpreadsheetPhaseSend(context,
          project: widget.project, authorized: () => mounted && authorized);
      if (mounted && authorized && message != null) {
        setState(() => notice = message);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        livePreview.resume();
      }
    }
  }

  SpreadsheetWriteState writeState = SpreadsheetWriteState.unchanged;
  bool _closed = false, _closing = false;
  int _recoveryEpoch = 0;
  String get _draftSheet =>
      'mapped:${sheetNames['entry'] ?? data?['entrySheet'] ?? 'Informações de entrada'}:${sheetNames['checklist'] ?? data?['checklistSheet'] ?? projectChecklistSheet(widget.project.serviceType)}';
  bool get _canDraft =>
      owner != null && (widget.project.excelLink?.isNotEmpty ?? false);
  void persistDraft() {
    if (!_canDraft || !authorized || data == null) return;
    if (pending.isEmpty) {
      clearDraft();
      return;
    }
    final saved = SpreadsheetDraft.save(
        owner,
        widget.project.id,
        widget.project.excelLink!,
        _draftSheet,
        {'revision': data!['revision'], 'changes': pending.values.toList()});
    if (!saved) {
      notice =
          'N\u00e3o foi poss\u00edvel guardar o rascunho neste computador. Salve na planilha para preservar os ajustes.';
    }
  }

  void clearDraft() {
    if (_canDraft) {
      SpreadsheetDraft.clear(
          owner, widget.project.id, widget.project.excelLink!, _draftSheet);
    }
  }

  Map<String, dynamic>? get savedDraft => !_canDraft
      ? null
      : SpreadsheetDraft.read(
          owner, widget.project.id, widget.project.excelLink!, _draftSheet);
  Future<void> recoverDraft() async {
    final draft = savedDraft;
    if (draft == null || data == null || !mounted || !authorized) return;
    final fields = [...(data!['fields'] as List), ...(data!['tasks'] as List)]
        .cast<Map<String, dynamic>>();
    final changes = SpreadsheetDraft.validatedChanges(
        draft, '${data!['revision']}', fields);
    final recover = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(changes == null
                    ? 'Rascunho de outra revis\u00e3o'
                    : 'Recuperar ajustes pendentes?'),
                content: Text(changes == null
                    ? 'A planilha mudou ou os ajustes n\u00e3o correspondem mais \u00e0s c\u00e9lulas atuais. O rascunho ser\u00e1 mantido; nenhum ajuste ser\u00e1 aplicado automaticamente.'
                    : '${changes.length} ajuste(s) foram guardados neste computador e ainda n\u00e3o foram salvos no Excel.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fechar e manter rascunho')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Descartar rascunho')),
                  if (changes != null)
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Recuperar ajustes'))
                ]));
    if (!mounted || !authorized) return;
    if (recover == null) {
      _closed = true;
      Navigator.pop(context);
      return;
    }
    if (recover == false) {
      clearDraft();
      return;
    }
    if (recover != true || changes == null) return;
    setState(() {
      _recoveryEpoch++;
      pending.addAll({
        for (final change in changes)
          '${change['sheet']}!${change['cell']}': change
      });
      notice =
          'Rascunho recuperado. Use Salvar na planilha para gravar no Excel.';
    });
  }

  late final ChecklistLivePreview livePreview;
  List<CompanyContact> contacts = [];
  SpreadsheetStore? get store =>
      widget.store ??
      (widget.transport == null ? FirebaseSpreadsheetStore() : null);
  String search = '', filter = 'Todas';
  StreamSubscription<User?>? subscription;
  String? get uid => widget.uidProvider != null
      ? widget.uidProvider!()
      : FirebaseAuth.instance.currentUser?.uid;
  String? get email => widget.emailProvider != null
      ? widget.emailProvider!()
      : FirebaseAuth.instance.currentUser?.email;
  bool get authorized {
    return !_closed &&
        uid == owner &&
        PilotFeatureAccess.allows(uid: uid, email: email);
  }

  bool _stageDialogOpen = false;
  Future<void> _fileRequestTail = Future<void>.value();
  Future<void> _snapshotWriteTail = Future<void>.value();

  void resumeSavedStatus() {
    final saved =
        pending.isEmpty ? savedSpreadsheetStatus(data, sheetNames) : null;
    if (saved != null) {
      livePreview.restore(saved);
    } else {
      livePreview.resume(clear: true);
    }
  }

  Future<bool> persistSnapshot(Map<String, dynamic> snapshot) {
    final account = owner;
    final reference = widget.project.excelLink ?? '';
    final revision = snapshot['revision'];
    final sheets = Map<String, String>.from(sheetNames);
    bool current() =>
        authorized &&
        owner == account &&
        (widget.project.excelLink ?? '') == reference &&
        data?['revision'] == revision &&
        mapEquals(sheets, sheetNames);
    final job = _snapshotWriteTail.then((_) async {
      if (!current() || store == null) return false;
      await store!.save(account!, widget.project.id, reference, snapshot);
      return current();
    });
    _snapshotWriteTail =
        job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return job;
  }

  Future<Map<String, dynamic>> request(String action,
      {String? revision,
      bool updateImplantation = false,
      List<Map<String, dynamic>>? changes,
      Map<String, String>? selectedSheets,
      bool Function()? isCurrent}) {
    final requestedOwner = owner;
    final names = Map<String, String>.from(selectedSheets ?? sheetNames);
    final edits = changes?.map((c) => Map<String, dynamic>.from(c)).toList();
    final result = _fileRequestTail.then((_) {
      if (!mounted ||
          !authorized ||
          owner != requestedOwner ||
          isCurrent != null && !isCurrent()) {
        throw StateError('A conta mudou ou o editor foi fechado.');
      }
      return _performRequest(action,
          revision: revision,
          changes: edits,
          selectedSheets: names,
          updateImplantation: updateImplantation);
    });
    _fileRequestTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, dynamic>> _performRequest(String action,
      {String? revision,
      bool updateImplantation = false,
      List<Map<String, dynamic>>? changes,
      Map<String, String>? selectedSheets}) async {
    final configured = selectedSheets ?? sheetNames;
    final selected = {for (final key in ['entry', 'checklist']) if (configured[key] != null) key: configured[key]!};
    if (widget.transport != null) {
      return widget.transport!({
        'action': action,
        'reference': widget.project.excelLink,
        'serviceType': widget.project.serviceType,
        if (selected.isNotEmpty) 'sheetNames': selected,
        if (revision != null) 'revision': revision,
        if (updateImplantation) 'updateImplantation': true,
        if (changes != null) 'changes': changes
      });
    }
    final result = await NativeLocalFiles.call(action,
        reference: widget.project.excelLink,
        projectId: widget.project.id,
        projectField: 'excelLink',
        serviceType: widget.project.serviceType,
        sheetNames: selected.isEmpty ? null : selected,
        revision: revision,
        updateImplantation: updateImplantation,
        changes: changes);
    if (mounted && authorized && result['reference'] is String) {
      widget.project.excelLink = result['reference'] as String;
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    owner = uid;
    final phaseQueue = RecoverableDraft.read(owner, _phaseScope);
    _phaseJobs = (phaseQueue?['jobs'] as List? ?? [])
        .whereType<Map>()
        .map((j) => Map<String, dynamic>.from(j))
        .toList();
    _phaseRevision = phaseQueue?['revision']?.toString();
    livePreview = ChecklistLivePreview(calculate: calculateStatus);
    if (widget.uidProvider == null) {
      subscription = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (mounted && !authorized) {
          livePreview.clear();
          setState(() {
            data = null;
            pending.clear();
            _datePreviewPending = false;
            calculatedEmails.clear();
            error = 'A conta mudou. Feche esta janela e entre novamente.';
          });
        }
      });
    }
    openConfigured();
    if (widget.uidProvider == null || widget.contactsLoader != null) {
      loadContacts();
    }
  }

  Future<void> openConfigured() async {
    if (!authorized) return;
    setState(() => busy = true);
    try {
      final names = await settingsStore?.load(
              owner!, widget.project.id, widget.project.excelLink ?? '') ??
          <String, String>{};
      if (!mounted || !authorized) return;
      setState(() {
        sheetNames = names;
        settingsReady = true;
        busy = false;
      });
      await openSaved();
    } catch (e) {
      if (mounted && authorized) {
        setState(() {
          busy = false;
          error =
              'Não foi possível carregar a configuração de abas. Use Abas para conferir antes de editar. $e';
        });
      }
    }
  }

  Future<void> openAllSheets() async {
    if (busy || !authorized || !await discard() || !mounted) return;
    await livePreview.pauseAndWait();
    if (!mounted || !authorized) return;
    setState(() {
      pending.clear();
      _datePreviewPending = false;
      calculatedEmails.clear();
    });
    try {
      final changed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (sheetContext) => WorkbookSheetDialog(
              chooser: true,
              mappedWorksheets: {
                ...configuredCatalogGuides(sheetNames),
                sheetNames['entry'] ??
                    data?['entrySheet']?.toString() ??
                    'Informações de entrada',
                sheetNames['checklist'] ??
                    data?['checklistSheet']?.toString() ??
                    projectChecklistSheet(widget.project.serviceType),
                'Implantação - Linha do Tempo',
              },
              draftOwner: owner,
              fileReference: widget.project.excelLink,
              onMappedWorksheet: (name) async {
                _requestedCatalogGuide = configuredCatalogGuides(sheetNames).contains(name);
                requestedMappedTab = _requestedCatalogGuide ? 1 : name ==
                        (sheetNames['entry'] ??
                            data?['entrySheet'] ??
                            'Informações de entrada')
                    ? 0
                    : name ==
                            (sheetNames['checklist'] ??
                                data?['checklistSheet'] ??
                                projectChecklistSheet(
                                    widget.project.serviceType))
                        ? 1
                        : 2;
                if (widget.transport == null) {
                  unawaited(ProjectWorksheetPreference.save(
                          owner!, widget.project.id, name)
                      .catchError((Object _) {
                    if (mounted) {
                      setState(() => notice =
                          'A guia abriu, mas sua prefer\u00eancia n\u00e3o foi salva.');
                    }
                  }));
                }
                Navigator.pop(sheetContext, false);
              },
              projectId: widget.project.id,
              client: widget.project.client,
              serviceType: widget.project.serviceType,
              initialWorksheet:
                  defaultProjectWorksheet(widget.project.serviceType),
              onWorksheetOpened: widget.transport == null
                  ? (name) => ProjectWorksheetPreference.save(
                      owner!, widget.project.id, name)
                  : null,
              allowed: () => mounted && authorized,
              call: (args) async {
                if (widget.transport != null) {
                  return widget.transport!(
                      {...args, 'reference': widget.project.excelLink});
                }
                return NativeLocalFiles.call(args['action'] as String,
                    reference: widget.project.excelLink,
                    projectId: widget.project.id,
                    projectField: 'excelLink',
                    worksheet: args['worksheet'] as String?,
                    firstRow: args['firstRow'] as int?,
                    firstColumn: args['firstColumn'] as int?,
                    revision: args['revision'] as String?,
                    changes: (args['changes'] as List?)
                        ?.cast<Map<String, dynamic>>());
              }));
      if (requestedMappedTab != null &&
          mounted &&
          authorized &&
          tabContentKey.currentContext != null) {
        DefaultTabController.of(tabContentKey.currentContext!)
            .animateTo(requestedMappedTab!);
        requestedMappedTab = null;
        if (_requestedCatalogGuide) {
          _requestedCatalogGuide = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !authorized) return;
            final target = _catalogTasksKey.currentContext;
            if (target != null) {
              final object = target.findRenderObject();
              final scroll = Scrollable.maybeOf(target);
              if (object != null && scroll != null) {
                unawaited(scroll.position.ensureVisible(object, duration: const Duration(milliseconds: 200), alignment: 0));
              }
            }
          });
        }
      }
      if (changed == true && mounted && authorized) {
        pending.clear();
        _datePreviewPending = false;
        await load();
      }
    } catch (e) {
      if (mounted && authorized)
        setState(() => error =
            'Não foi possível abrir a lista de guias desta planilha. $e');
    } finally {
      if (mounted && authorized) resumeSavedStatus();
    }
  }

  Future<void> configureSheets() async {
    if (!authorized || busy || !await discard() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await livePreview.pauseAndWait();
      if (!mounted || !authorized) return;
      final listed = await request('excel-editor-sheets');
      if (!mounted || !authorized) return;
      final names = (listed['sheetNames'] as List).cast<String>();
      final roles = listed['sheetCandidates'];
      final candidates = roles is Map
          ? <String, List<String>>{
              for (final role in ['entry', 'checklist'])
                if (roles[role] is List)
                  role: (roles[role] as List).whereType<String>().toList(),
            }
          : null;
      setState(() => busy = false);
      final selected = await selectSpreadsheetSheets(
          context,
          names,
          {
            ...sheetNames,
            'entry': sheetNames['entry'] ?? 'Informações de entrada',
            'checklist': sheetNames['checklist'] ??
                projectChecklistSheet(widget.project.serviceType),
          },
          candidates: candidates,
          mainReference: widget.project.excelLink ?? '',
          catalogRequest: widget.transport == null ? null : (action, {reference}) => widget.transport!({'action': action, 'reference': reference}),
          filename: listed['filename']?.toString());
      if (selected == null || !mounted || !authorized) return;
      setState(() => busy = true);
      final result =
          await request('excel-editor-read', selectedSheets: selected);
      if (!mounted || !authorized) return;
      if (!matches(result, names: selected)) {
        throw StateError('A integração não confirmou as abas selecionadas.');
      }
      await settingsStore?.save(
          owner!, widget.project.id, widget.project.excelLink ?? '', selected);
      if (!mounted || !authorized) return;
      setState(() {
        sheetNames = selected;
        settingsReady = true;
        data = result;
        pending.clear();
        _datePreviewPending = false;
        calculatedEmails.clear();
        notice = 'Abas configuradas para este projeto.';
      });
      await remember(result);
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (authorized && data != null) resumeSavedStatus();
      }
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    livePreview.dispose();
    super.dispose();
  }

  Future<bool> discard() async {
    if (pending.isEmpty) return true;
    final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Descartar alterações?'),
                    content: const Text(
                        'As alterações ainda não foram salvas na planilha.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Continuar editando')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Descartar'))
                    ])) ==
        true;
    if (confirmed) clearDraft();
    return confirmed;
  }

  Future<void> loadContacts() async {
    try {
      final result =
          await (widget.contactsLoader?.call() ?? CompanyContacts.load());
      if (mounted && authorized) setState(() => contacts = result);
    } catch (e) {
      if (mounted && authorized) {
        setState(
            () => notice = 'Não foi possível carregar os colaboradores: $e');
      }
    }
  }

  Future<void> openSaved() async {
    if (!authorized) return;
    setState(() => busy = true);
    String? warning;
    try {
      final saved = await store?.load(
          owner!, widget.project.id, widget.project.excelLink ?? '');
      if (!mounted || !authorized) return;
      final type = widget.project.serviceType.toLowerCase();
      final requiresDates = type.contains('plugin') ||
          type.contains('professional') ||
          type.contains('profissional') ||
          ((saved?['statusPreview'] as Map?)?['rows'] as List? ?? [])
              .whereType<Map>()
              .any((r) => r['start'] != null || r['end'] != null);
      final mappedDates = (saved?['fields'] as List? ?? [])
          .whereType<Map>()
          .any((f) => f['stagePeriod'] != null);
      if (saved != null && matches(saved) && (!requiresDates || mappedDates)) {
        setState(() {
          data = saved;
          busy = false;
        });
        final status = savedSpreadsheetStatus(saved, sheetNames);
        if (status != null) livePreview.restore(status);
        if (savedDraft != null) await load();
        return;
      }
    } catch (e) {
      warning = 'Não foi possível carregar a cópia salva: $e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && authorized) {
      await load();
      if (mounted && authorized && warning != null) {
        setState(() => notice = warning);
      }
    }
  }

  Future<void> remember(Map<String, dynamic> result) async {
    if (!authorized || store == null) return;
    final stamp = DateTime.now().toIso8601String();
    try {
      final persisted = await persistSnapshot(result);
      if (persisted && mounted && authorized) {
        setState(() => data = {...data!, 'syncedAt': stamp});
      }
    } catch (e) {
      if (mounted && authorized) {
        setState(() => notice =
            'O Excel foi lido/gravado, mas a cópia no sistema não foi atualizada. Use Salvar cópia no sistema para tentar novamente. $e');
      }
    }
  }

  String get synchronizationLabel {
    final date =
        DateTime.tryParse(data?['syncedAt']?.toString() ?? '')?.toLocal();
    if (date == null) return 'Cópia ainda não salva no sistema';
    return 'Última sincronização: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}. Atualize do Excel para buscar alterações externas.';
  }

  Future<void> load() async {
    if (!settingsReady) {
      await openConfigured();
      return;
    }
    if (!authorized || busy || !await discard() || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await livePreview.pauseAndWait();
      if (!mounted || !authorized) return;
      final result = await request('excel-editor-read');
      if (!matches(result)) {
        throw StateError(
            'A integração retornou um checklist diferente do tipo do projeto. Atualize e reinicie a integração v25 para usar Professional/Maker.');
      }
      if (mounted && authorized) {
        setState(() {
          data = result;
          pending.clear();
          _datePreviewPending = false;
          calculatedEmails.clear();
          notice = null;
          writeState = SpreadsheetWriteState.unchanged;
        });
      }
      if (mounted && authorized) unawaited(remember(result));
      if (mounted && authorized) {
        setState(() => busy = false);
        await recoverDraft();
      }
    } catch (e) {
      if (mounted && authorized) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (authorized && data != null) resumeSavedStatus();
      }
    }
  }

  Future<Map<String, dynamic>> calculateStatus() async {
    if (!mounted || !authorized || data == null) {
      throw StateError('A conta mudou.');
    }
    final revision = data!['revision'];
    final sheets = Map<String, String>.from(sheetNames);
    final changes = pending.values.toList();
    final result = await request('excel-editor-preview',
        revision: revision as String, changes: changes);
    if (!mounted || !authorized) throw StateError('A conta mudou.');
    if (result['preview'] != true ||
        result['statusPreview'] is! Map ||
        !matches(result)) {
      throw StateError(
          'A integra\u00e7\u00e3o n\u00e3o confirmou a pr\u00e9via. Atualize e reinicie a integra\u00e7\u00e3o v29.');
    }
    final status = Map<String, dynamic>.from(result['statusPreview'] as Map);
    // Draft calculations must never replace the saved workbook's Status table.
    if (changes.isEmpty &&
        pending.isEmpty &&
        data?['revision'] == revision &&
        mapEquals(sheets, sheetNames) &&
        !busy) {
      final snapshot = withSavedSpreadsheetStatus(data!, sheets, status);
      setState(() => data = snapshot);
      unawaited(persistSnapshot(snapshot).catchError((Object error) {
        if (mounted && authorized) {
          setState(() => notice =
              'A tabela foi calculada, mas n\u00e3o foi salva no sistema. $error');
        }
        return false;
      }));
    }
    return status;
  }

  Future<void> save({bool updateImplantation = false}) async {
    if (!authorized ||
        busy ||
        pending.isEmpty && !updateImplantation ||
        data == null) return;
    if (_phaseJobs.isNotEmpty) {
      setState(() => error =
          'Sincronize as datas das fases pendentes antes de salvar outro ajuste.');
      return;
    }
    List<Map<String, dynamic>> phaseJobs;
    try {
      phaseJobs = phaseJobsForDraft();
    } catch (e) {
      setState(() => error = e.toString());
      return;
    }
    setState(() {
      busy = true;
      writeState = SpreadsheetWriteState.saving;
      error = null;
      notice = null;
    });
    var writeStarted = false;
    try {
      await livePreview.pauseAndWait();
      if (!mounted || !authorized) return;
      if (pending.keys.any((key) => (data!['fields'] as List)
          .whereType<Map>()
          .any((f) =>
              keyOf(Map<String, dynamic>.from(f)) == key &&
              f['dateMode'] == 'summary-adjusted'))) {
        final calculated = await request('excel-editor-preview',
            revision: data!['revision'] as String,
            changes: pending.values.toList());
        if (!mounted || !authorized) return;
        if (calculated['preview'] != true ||
            calculated['revision'] != data!['revision'] ||
            !matches(calculated)) {
          throw StateError(
              'A prévia das datas não corresponde à planilha aberta. Recarregue antes de salvar.');
        }
        final status =
            Map<String, dynamic>.from(calculated['statusPreview'] as Map);
        phaseJobs = phaseJobsForDraft(calculatedStatus: status);
      }
      writeStarted = true;
      final result = await request('excel-editor-write',
          revision: data!['revision'] as String,
          updateImplantation: updateImplantation,
          changes: pending.values.toList());
      if (updateImplantation && result['implantationUpdated'] != true) {
        throw StateError(
            'A atualização da implantação não foi confirmada. Recarregue para conferir a planilha.');
      }
      if (result['saved'] != true) {
        throw StateError(
            'A gravação não foi confirmada. Recarregue para conferir antes de tentar novamente.');
      }
      if (!matches(result)) {
        throw StateError(
            'O checklist retornado não corresponde ao projeto. Recarregue do Excel para conferir.');
      }
      if (phaseJobs.isNotEmpty) {
        final savedFields = (result['fields'] as List).whereType<Map>();
        for (final job in phaseJobs) {
          for (final endpoint in ['start', 'end']) {
            final matches = savedFields
                .where((f) =>
                    f['stagePeriod'] == job['stage'] &&
                    f['endpoint'] == endpoint)
                .toList();
            if (matches.length != 1 || matches.single['value'] != job[endpoint])
              throw StateError(
                  'As datas gravadas não foram confirmadas. Confira a planilha antes de sincronizar as fases.');
          }
        }
        _phaseJobs = phaseJobs;
        _phaseRevision = result['revision'].toString();
        keepPhaseQueue();
      }
      final fields = (result['fields'] as List).cast<Map<String, dynamic>>();
      final differentEmails = calculatedEmails.entries
          .where((entry) => !fields.any((f) =>
              keyOf(f) == entry.key &&
              f['value'].toString().trim().toLowerCase() ==
                  entry.value.trim().toLowerCase()))
          .isNotEmpty;
      if (mounted && authorized) {
        setState(() {
          data = result;
          clearDraft();
          pending.clear();
          _datePreviewPending = false;
          calculatedEmails.clear();
          writeState = SpreadsheetWriteState.saved;
          notice = differentEmails
              ? 'Planilha salva, mas a fórmula do Excel retornou um e-mail diferente do cadastro. Confira o cadastro de consultores no Excel; o e-mail mostrado agora é o resultado real da planilha. Backup: ${result['backup']}'
              : 'Planilha atualizada e conferida. Backup: ${result['backup']}';
          if (result['backupCleanupWarning'] != null) {
            notice = '$notice\n${result['backupCleanupWarning']}';
          }
        });
      }
      if (mounted && authorized) await remember(result);
      if (mounted && authorized && _phaseJobs.isNotEmpty) {
        try {
          await syncPhaseDates(verifyExcel: false);
        } catch (e) {
          if (mounted && authorized)
            setState(() => error =
                'A planilha foi salva, mas as fases ainda não foram atualizadas. Use Sincronizar datas das fases. $e');
        }
      }
    } catch (e) {
      if (mounted && authorized) {
        setState(() {
          error = e.toString();
          writeState = writeStarted
              ? SpreadsheetWriteState.unconfirmed
              : SpreadsheetWriteState.unchanged;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (authorized && data != null) resumeSavedStatus();
      }
    }
  }

  String keyOf(Map<String, dynamic> field) =>
      '${field['sheet']}!${field['cell']}';
  dynamic current(Map<String, dynamic> field) =>
      pending[keyOf(field)]?['value'] ??
      calculatedEmails[keyOf(field)] ??
      field['value'];
  void change(Map<String, dynamic> field, dynamic value) => setState(() {
        final key = keyOf(field);
        if (field['label'].toString().endsWith('— Nome')) {
          for (final f
              in (data!['fields'] as List).cast<Map<String, dynamic>>()) {
            if (f['group'] == field['group'] &&
                f['label'] ==
                    field['label']
                        .toString()
                        .replaceFirst('— Nome', '— E-mail')) {
              calculatedEmails.remove(keyOf(f));
            }
          }
        }
        if (value == field['value']) {
          pending.remove(key);
        } else {
          pending[key] = {
            'sheet': field['sheet'],
            'cell': field['cell'],
            'before': field['value'],
            'value': value
          };
        }
        notice = null;
        if (field['kind'] == 'date') {
          _datePreviewPending = true;
          livePreview.pause();
          notice = 'Datas em edição. Use Aplicar ajustes de datas ao terminar.';
        } else {
          livePreview.invalidate();
        }
        persistDraft();
      });

  Future<void> close() async {
    if (_closing || writeState == SpreadsheetWriteState.saving) return;
    _closing = true;
    try {
      if (!await discard() || !mounted) return;
      _closed = true;
      livePreview.clear();
      pending.clear();
      _datePreviewPending = false;
      Navigator.pop(context);
    } finally {
      if (!_closed) _closing = false;
    }
  }

  Widget input(Map<String, dynamic> field) {
    final label = field['label'] as String;
    final kind = field['kind'];
    if (field['choices'] is List) {
      final options = (field['choices'] as List).cast<String>().toList();
      final value = current(field).toString();
      if (!options.contains(value)) options.insert(0, value);
      return DropdownButtonFormField<String>(
          key: ValueKey('${data!['revision']}:$_recoveryEpoch:${keyOf(field)}'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final option in options)
              DropdownMenuItem(
                  value: option,
                  child: Text(option, overflow: TextOverflow.ellipsis))
          ],
          onChanged: busy || !authorized || field['readOnly'] == true
              ? null
              : (value) {
                  if (value != null) change(field, value);
                });
    }
    if (label.endsWith('— Nome') &&
        contacts.isNotEmpty &&
        field['readOnly'] != true) {
      return Autocomplete<CompanyContact>(
          key: ValueKey('${data!['revision']}:$_recoveryEpoch:${keyOf(field)}'),
          initialValue: TextEditingValue(text: current(field).toString()),
          displayStringForOption: (c) => c.name,
          optionsBuilder: (text) => contacts.where((c) => '${c.name} ${c.email}'
              .toLowerCase()
              .contains(text.text.toLowerCase())),
          onSelected: (c) {
            if (busy || !authorized) return;
            change(field, c.name);
            final address = (data!['fields'] as List)
                .cast<Map<String, dynamic>>()
                .where((f) =>
                    f['group'] == field['group'] &&
                    f['label'] == label.replaceFirst('— Nome', '— E-mail'));
            if (address.isNotEmpty) {
              if (address.first['readOnly'] == true) {
                setState(
                    () => calculatedEmails[keyOf(address.first)] = c.email);
              } else {
                change(address.first, c.email);
              }
            }
          },
          optionsViewBuilder: (context, select, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                  elevation: 4,
                  child: SizedBox(
                      width: 340,
                      height: 220,
                      child: ListView(children: [
                        for (final c in options)
                          ListTile(
                              title: Text(c.name),
                              subtitle: Text(c.email),
                              onTap: () => select(c))
                      ])))),
          fieldViewBuilder: (context, controller, focus, submit) =>
              TextFormField(
                  controller: controller,
                  focusNode: focus,
                  enabled: !busy && authorized,
                  decoration: InputDecoration(labelText: label),
                  onFieldSubmitted: (_) => submit(),
                  onChanged: (v) => change(field, v)));
    }
    if (kind == 'yesno') {
      return DropdownButtonFormField<String>(
          key: ValueKey('${data!['revision']}:$_recoveryEpoch:${keyOf(field)}'),
          initialValue: current(field) as String,
          decoration: InputDecoration(labelText: label),
          items: const [
            DropdownMenuItem(value: 'Sim', child: Text('Sim')),
            DropdownMenuItem(value: 'Não', child: Text('Não'))
          ],
          onChanged: busy ? null : (v) => change(field, v));
    }
    if (kind == 'date') {
      final raw = current(field) as String;
      final date = DateTime.tryParse(raw);
      final text = date == null
          ? raw
          : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      return TextFormField(
          key: ValueKey(
              '${data!['revision']}:$_recoveryEpoch:${keyOf(field)}:$raw'),
          initialValue: text,
          readOnly: true,
          decoration: InputDecoration(
              labelText: label,
              suffixIcon: IconButton(
                  tooltip: 'Limpar data',
                  onPressed: busy || field['readOnly'] == true
                      ? null
                      : () => change(field, ''),
                  icon: const Icon(Icons.clear, size: 16))),
          onTap: busy || field['readOnly'] == true
              ? null
              : () async {
                  final selected = await showDatePicker(
                      context: context,
                      initialDate: date ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200));
                  if (selected != null && mounted && authorized) {
                    change(field, selected.toIso8601String().substring(0, 10));
                  }
                });
    }
    return TextFormField(
        key: ValueKey(
            '${data!['revision']}:$_recoveryEpoch:${keyOf(field)}:${field['label'].toString().endsWith('— E-mail') ? current(field) : ''}'),
        initialValue: current(field).toString(),
        enabled: !busy && authorized,
        readOnly: field['readOnly'] == true,
        obscureText: label.toLowerCase().contains('senha') &&
            hiddenPasswords.contains(keyOf(field)),
        decoration: InputDecoration(
            labelText: label,
            suffixIcon: label.toLowerCase().contains('senha')
                ? IconButton(
                    tooltip: hiddenPasswords.contains(keyOf(field))
                        ? 'Mostrar senha'
                        : 'Ocultar senha',
                    icon: Icon(hiddenPasswords.contains(keyOf(field))
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() {
                          final key = keyOf(field);
                          if (!hiddenPasswords.remove(key)) {
                            hiddenPasswords.add(key);
                          }
                        }))
                : null,
            helperText: calculatedEmails.containsKey(keyOf(field))
                ? 'E-mail do cadastro. A fórmula do Excel será conferida ao salvar.'
                : field['readOnly'] == true
                    ? 'Calculado pelo Excel'
                    : null),
        maxLength: 10000,
        buildCounter: (_,
                {required currentLength, required isFocused, maxLength}) =>
            null,
        onChanged: (v) => change(field, v));
  }

  Widget entry() {
    final fields = (data!['fields'] as List)
        .cast<Map<String, dynamic>>()
        .where((f) => f['timeline'] != true && f['stagePeriod'] == null)
        .toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FilledButton.icon(
                onPressed: busy ||
                        !authorized ||
                        data?['implantationUpdateVersion'] != 1
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                                    title: const Text(
                                        'Atualizar Planilha de Implantação?'),
                                    content: const Text(
                                        'Os ajustes pendentes serão salvos e as abas e etapas serão atualizadas conforme os produtos selecionados. Será criado um backup da planilha.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancelar')),
                                      FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child:
                                              const Text('Salvar e atualizar'))
                                    ]));
                        if (confirmed == true && mounted && authorized) {
                          await save(updateImplantation: true);
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar Planilha de Implantação')),
            const SizedBox(height: 6),
            Text(data?['implantationUpdateVersion'] == 1
                ? 'Após ajustar o tipo e os produtos, use este botão para atualizar as abas e etapas da implantação.'
                : 'Atualize a integração local para habilitar a atualização da implantação por aqui.'),
          ])),
      for (final group in fields.map((f) => f['group'] as String).toSet())
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth < 620
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 32) / 3;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 14),
                        Wrap(spacing: 16, runSpacing: 16, children: [
                          for (final field
                              in fields.where((f) => f['group'] == group))
                            SizedBox(width: width, child: input(field))
                        ])
                      ]);
                })))
    ]);
  }

  Widget timeline() {
    final fields = (data!['fields'] as List)
        .cast<Map<String, dynamic>>()
        .where((f) => f['timeline'] == true && f['timelineDays'] != true)
        .toList();
    if (fields.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Recarregue do Excel com a integração atualizada para carregar a tabela Detalhes do Projeto da guia Implantação - Linha do Tempo.')));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      FilledButton.icon(
          onPressed: busy || pending.isNotEmpty
              ? null
              : () async {
                  await livePreview.pauseAndWait();
                  if (!mounted || !authorized) return;
                  await ProjectDocumentsDialog.show(context, widget.project);
                  if (mounted && authorized) await load();
                },
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Editar tabela completa e dias do cronograma')),
      const SizedBox(height: 16),
      const Text(
          'Ajuste as datas dos eventos. As datas calculadas e o resumo da planilha são preservados.'),
      const SizedBox(height: 16),
      for (final field in fields)
        Padding(
            padding: const EdgeInsets.only(bottom: 16), child: input(field)),
    ]);
  }

  Future<void> editStage(String group, List<Map<String, dynamic>> tasks) async {
    if (busy || !authorized || _stageDialogOpen) return;
    _stageDialogOpen = true;
    var routeActive = true;
    final revision = data?['revision'];
    livePreview.pause();
    if (!mounted || !authorized || busy || data?['revision'] != revision) {
      _stageDialogOpen = false;
      if (mounted && authorized) livePreview.resume();
      return;
    }
    Map<String, double>? result;
    try {
      result = await showDialog<Map<String, double>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ChecklistStageDialog(
            stage: group,
            expandableBlocks:
                ChecklistBlockPilotAccess.allows(uid: uid, email: email),
            initialPreview: livePreview.data ??
                (data?['statusPreview'] is Map
                    ? Map<String, dynamic>.from(data!['statusPreview'] as Map)
                    : null),
            calculatePreview: (values) async {
              if (!mounted ||
                  !authorized ||
                  busy ||
                  data?['revision'] != revision) {
                throw StateError('A conta ou a planilha mudou.');
              }
              final changes = {...pending};
              for (final task in tasks) {
                final key = keyOf(task);
                final value = values[key];
                if (task['readOnly'] == true || value == null) continue;
                if (value == task['value']) {
                  changes.remove(key);
                } else {
                  changes[key] = {
                    'sheet': task['sheet'],
                    'cell': task['cell'],
                    'before': task['value'],
                    'value': value
                  };
                }
              }
              final response = await request('excel-editor-preview',
                  revision: revision as String,
                  changes: changes.values.toList(),
                  isCurrent: () => routeActive);
              if (!mounted ||
                  !authorized ||
                  data?['revision'] != revision ||
                  response['preview'] != true ||
                  response['statusPreview'] is! Map ||
                  !matches(response)) {
                throw StateError(
                    'A planilha mudou ou a prévia não foi confirmada.');
              }
              return Map<String, dynamic>.from(
                  response['statusPreview'] as Map);
            },
            tasks: tasks,
            values: {
              for (final task in tasks)
                keyOf(task): (current(task) as num).toDouble()
            },
            canApply: () =>
                mounted &&
                authorized &&
                !busy &&
                data?['revision'] == revision),
      );
    } finally {
      routeActive = false;
      _stageDialogOpen = false;
      if (mounted && authorized) livePreview.resume();
    }
    if (result == null ||
        !mounted ||
        !authorized ||
        busy ||
        data?['revision'] != revision) {
      return;
    }
    for (final task in tasks) {
      final value = result[keyOf(task)];
      if (value != null && task['readOnly'] != true) change(task, value);
    }
  }

  Widget checklist() {
    final all = (data!['tasks'] as List).cast<Map<String, dynamic>>();
    final shown = all
        .where((f) =>
            (f['label'] as String)
                .toLowerCase()
                .contains(search.toLowerCase()) &&
            (filter == 'Todas' ||
                filter == 'Concluídas' && current(f) == 1 ||
                filter == 'Pendentes' && current(f) != 1))
        .toList();
    final filters = Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: 'Copiar Início e Fim do checklist para as etapas do trabalho',
                    child: OutlinedButton.icon(
                    onPressed: busy || !authorized || pending.isNotEmpty || _phaseJobs.isNotEmpty ? null : updateWorkDatesFromChecklist,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: const Text('Atualizar datas'),
                  )),
                  if (pending.isNotEmpty) const Text('Salve a planilha antes de atualizar as datas do trabalho.'),
                  SizedBox(
                      width: 260,
                      child: TextField(
                          decoration: InputDecoration(
                              hintText: 'Buscar tarefa...',
                              isDense: true,
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              prefixIcon: Icon(Icons.search)),
                          onChanged: (v) => setState(() => search = v))),
                  for (final item in ['Todas', 'Pendentes', 'Concluídas'])
                    ChoiceChip(
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        label: Text(item),
                        selected: filter == item,
                        onSelected: (_) => setState(() => filter = item)),
                  Text('${shown.length} tarefas${sheetNames['catalogEnabled'] == 'true' ? ' de implantação' : ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                ])));
    final cards = <Widget>[
      for (final group in shown.map((f) => f['group'] as String).toSet())
        Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: ValueKey('checklist-stage-$group'),
              leading: const Icon(Icons.checklist_outlined),
              title: Text(group,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  '${shown.where((f) => f['group'] == group).length} tarefas'),
              trailing: const Icon(Icons.open_in_new),
              onTap: busy || !authorized
                  ? null
                  : () => editStage(
                      group, all.where((f) => f['group'] == group).toList()),
            )),
      if (sheetNames['catalogEnabled'] == 'true')
        KeyedSubtree(key: _catalogTasksKey, child: CatalogChecklistTasks(
          key: const ValueKey('catalog-checklist-tasks'),
          sourceIdentity: '$_catalogReference|${catalogChecklistSheet(sheetNames)}',
          sheet: catalogChecklistSheet(sheetNames),
          call: (action, {revision, changes}) => requestCatalog(action, revision: revision, changes: changes),
          allowed: () => mounted && authorized && !busy && pending.isEmpty && _phaseJobs.isEmpty,
          search: search, filter: filter,
          onSaved: () { setState(() => _catalogRefresh++); if (sheetNames['catalogSource'] != 'external') unawaited(openSaved()); },
        )),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1100;
      final preview = ChecklistStatusPanel(
          controller: livePreview,
          unsaved: pending.isNotEmpty,
          compact: wide,
          datesNotice: ['professional', 'profissional', 'plugin', 'enterprise']
                      .any(widget.project.serviceType.toLowerCase().contains) &&
                  !(data!['fields'] as List)
                      .whereType<Map>()
                      .any((f) => f['stagePeriod'] != null)
              ? 'Atualize a integração e recarregue do Excel para editar Início e Fim das etapas deste modelo.'
              : null,
          onEditDates: busy ||
                  !authorized ||
                  _phaseJobs.isNotEmpty ||
                  !(data!['fields'] as List)
                      .whereType<Map>()
                      .any((f) => f['stagePeriod'] != null)
              ? null
              : editPeriod,
          dateOverrides: {
            for (final f in (data!['fields'] as List).whereType<Map>().where(
                (f) =>
                    f['stagePeriod'] != null &&
                    pending.containsKey('${f['sheet']}!${f['cell']}')))
              f['stagePeriod'].toString(): {
                for (final item in (data!['fields'] as List)
                    .whereType<Map>()
                    .where((item) => item['stagePeriod'] == f['stagePeriod']))
                  item['endpoint'].toString():
                      current(Map<String, dynamic>.from(item)).toString()
              }
          });
      final catalog = sheetNames['catalogEnabled'] == 'true'
          ? CatalogTrainingPanel(
              key: ValueKey('catalog-preview-$_catalogRefresh'),
              request: (action, {reference, name, range}) => requestCatalog(action, range: range),
              reference: sheetNames['catalogSource'] == 'external' ? sheetNames['catalogReference'] ?? '' : widget.project.excelLink ?? '',
              sheet: sheetNames['catalogSheet'] ?? 'Cronograma Treinamento Catalog',
              range: sheetNames['catalogRange'] ?? 'B34:I38')
          : null;
      if (wide) {
        return Row(
            key: const ValueKey('checklist-side-by-side'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: catalog == null ? preview : ListView(primary: false, children: [preview, catalog])),
              const SizedBox(width: 8),
              SizedBox(
                  width: 300,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        filters,
                        Expanded(
                            child: ListView(
                                key: const ValueKey('checklist-task-list'),
                                primary: false,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                children: cards)),
                      ])),
            ]);
      }
      return CustomScrollView(
          key: const ValueKey('checklist-stacked-scroll'),
          primary: false,
          slivers: [
            SliverToBoxAdapter(child: preview),
            if (catalog != null) SliverToBoxAdapter(child: catalog),
            SliverToBoxAdapter(child: filters),
            SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverToBoxAdapter(child: Column(children: cards))),
          ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    final menus = <PopupMenuEntry<String>>[
      const PopupMenuItem(
          value: 'documents',
          child: Text('Cronograma e Plano de Projeto / PDF')),
      if (widget.project.serviceType.toLowerCase().contains('consultoria') ||
          widget.project.serviceType.toLowerCase().contains('plugin'))
        const PopupMenuItem(
            value: 'report', child: Text('Relatório de atividades / PDF')),
      if (widget.uidProvider == null)
        const PopupMenuItem(value: 'contacts', child: Text('Colaboradores')),
      if (data != null && pending.isEmpty && store != null)
        const PopupMenuItem(
            value: 'copy', child: Text('Salvar c\u00f3pia no sistema')),
    ];
    return PopScope(
        canPop: !busy && pending.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) close();
        },
        child: Dialog(
          insetPadding: EdgeInsets.all(size.width < 600 ? 8 : 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
              width: 1240,
              height: size.height * .92,
              child: DefaultTabController(
                  length: 3,
                  initialIndex: widget.initialTab,
                  child: Column(key: tabContentKey, children: [
                    SpreadsheetDialogHeader(
                        projectId: widget.project.id,
                        client: widget.project.client,
                        filename: data?['filename']?.toString() ?? '',
                        serviceType: widget.project.serviceType,
                        onClose: writeState == SpreadsheetWriteState.saving
                            ? null
                            : close,
                        sheetAction:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          if (size.width >= 1100)
                            TextButton.icon(
                                onPressed: busy ||
                                        !authorized ||
                                        pending.isNotEmpty ||
                                        _phaseJobs.isNotEmpty
                                    ? null
                                    : sendSavedPhases,
                                icon: const Icon(Icons.sync, size: 18),
                                label: const Text('Enviar fases ao E-Desk'))
                          else
                            IconButton(
                                tooltip:
                                    'Enviar fases ao E-Desk — salve os ajustes antes de enviar',
                                onPressed: busy ||
                                        !authorized ||
                                        pending.isNotEmpty ||
                                        _phaseJobs.isNotEmpty
                                    ? null
                                    : sendSavedPhases,
                                icon: const Icon(Icons.sync, size: 18)),
                          if (size.width >= 600)
                            TextButton.icon(
                                onPressed:
                                    busy || !authorized ? null : openAllSheets,
                                icon: const Icon(Icons.table_chart_outlined,
                                    size: 18),
                                label: const Text('Escolher guia'))
                          else
                            IconButton(
                                tooltip: 'Escolher guia',
                                onPressed:
                                    busy || !authorized ? null : openAllSheets,
                                icon: const Icon(Icons.table_chart_outlined,
                                    size: 18)),
                          IconButton(
                              tooltip: 'Configurar abas do modelo',
                              onPressed:
                                  busy || !authorized ? null : configureSheets,
                              icon: const Icon(Icons.tune, size: 18)),
                        ]),
                        moreActions: menus.isEmpty || !authorized
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: 'Mais a\u00e7\u00f5es da planilha',
                                enabled: !busy,
                                itemBuilder: (_) => menus,
                                onSelected: (value) async {
                                  if (busy || !authorized) return;
                                  if (value == 'contacts') {
                                    await CompanyContacts.show(context);
                                    if (mounted && authorized) {
                                      await loadContacts();
                                    }
                                  } else if (value == 'documents' ||
                                      value == 'report') {
                                    if (pending.isNotEmpty) {
                                      setState(() => notice =
                                          'Salve ou descarte os ajustes antes de abrir os documentos.');
                                      return;
                                    }
                                    await livePreview.pauseAndWait();
                                    if (!mounted || !authorized) return;
                                    await ProjectDocumentsDialog.show(
                                        context, widget.project,
                                        initialMode: value == 'report'
                                            ? 'report'
                                            : 'timeline');
                                    if (mounted && authorized) await load();
                                  } else if (value == 'copy' && data != null) {
                                    setState(() {
                                      busy = true;
                                      notice = null;
                                    });
                                    await remember(data!);
                                    if (mounted) setState(() => busy = false);
                                  }
                                })),
                    if (busy) const LinearProgressIndicator(minHeight: 2),
                    if (error != null || notice != null)
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 100),
                          child: SingleChildScrollView(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(error ?? notice!,
                                      style: TextStyle(
                                          color: error == null
                                              ? colors.onSurface
                                              : colors.error))))),
                    TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorWeight: 3,
                        labelStyle:
                            const TextStyle(fontWeight: FontWeight.w600),
                        tabs: [
                          const Tab(text: 'Informa\u00e7\u00f5es de entrada'),
                          Tab(
                              text: projectChecklistSheet(
                                  widget.project.serviceType,
                                  override: sheetNames['checklist'])),
                          const Tab(
                              text: 'Implanta\u00e7\u00e3o - Linha do Tempo')
                        ]),
                    Expanded(
                        child: data == null || !authorized
                            ? Center(
                                child: Text(busy
                                    ? 'Carregando a planilha...'
                                    : 'Nenhuma planilha carregada.'))
                            : TabBarView(
                                children: [entry(), checklist(), timeline()])),
                    SpreadsheetDialogFooter(
                        pendingCount: pending.length,
                        writeState: writeState,
                        loading:
                            busy && writeState != SpreadsheetWriteState.saving,
                        synchronization: synchronizationLabel,
                        actions: [
                          if (_datePreviewPending && pending.isNotEmpty)
                            OutlinedButton.icon(
                                onPressed: busy || !authorized
                                    ? null
                                    : () {
                                        setState(() {
                                          _datePreviewPending = false;
                                          notice =
                                              'Datas aplicadas à prévia. Use Salvar na planilha para gravar no Excel.';
                                          livePreview.resume();
                                        });
                                      },
                                icon:
                                    const Icon(Icons.event_available_outlined),
                                label: const Text('Aplicar ajustes de datas')),
                          if (_phaseJobs.isNotEmpty)
                            OutlinedButton.icon(
                                onPressed: busy || !authorized
                                    ? null
                                    : retryPhaseDates,
                                icon: const Icon(Icons.sync),
                                label:
                                    const Text('Sincronizar datas das fases')),
                          OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8))),
                              onPressed: busy || !authorized ? null : load,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Recarregar do Excel')),
                          TextButton(
                              onPressed:
                                  writeState == SpreadsheetWriteState.saving
                                      ? null
                                      : close,
                              child: const Text('Cancelar')),
                          FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8))),
                              onPressed: busy || !authorized || pending.isEmpty
                                  ? null
                                  : save,
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: const Text('Salvar na planilha')),
                        ]),
                  ]))),
        ));
  }
}
