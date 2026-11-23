import '../../../shared/widgets/movable_document_dialog.dart';
import 'plan_sheet_editor.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'timeline_schedule.dart';
import 'timeline_time_field.dart';
import 'timeline_batch_dialog.dart';
import '../../../data/services/file_download.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../data/services/native_local_files_service.dart';
import '../../../data/services/recoverable_draft.dart';
import '../../../data/services/firebase_service.dart';
import '../../../domain/models/project_model.dart';
import 'spreadsheet_phase_dates.dart';
import '../../../core/platform/project_pdf_window.dart';

/// The native Excel/Word render is authoritative; never rebuild the PDF in Dart.
class ProjectDocumentsDialog extends StatefulWidget {
  const ProjectDocumentsDialog(
      {super.key,
      required this.project,
      this.initialMode = 'timeline',
      this.transport,
      this.uidProvider,
      this.phaseDatesSaver});
  final ProjectModel project;
  final String initialMode;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? transport;
  final String? Function()? uidProvider;
  final Future<void> Function(List<Map<String, dynamic>>)? phaseDatesSaver;
  static Future<void> show(BuildContext context, ProjectModel project,
          {String initialMode = 'timeline'}) =>
      showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ProjectDocumentsDialog(
              project: project, initialMode: initialMode));
  @override
  State<ProjectDocumentsDialog> createState() => _ProjectDocumentsDialogState();
}

class _ProjectDocumentsDialogState extends State<ProjectDocumentsDialog>
    with SingleTickerProviderStateMixin {
  late final TabController documentTabs;
  final timelineScroll = ScrollController();
  String get pdfWindowKey => '$owner:${widget.project.id}:$mode';
  String get pdfTitle =>
      '${mode == 'timeline' ? 'Cronograma' : mode == 'plan' ? 'Plano de Projeto' : 'Relatório de atividades'} · ${widget.project.client} · ${widget.project.id}';
  void synchronizePdfWindow() {
    if (pdf != null && authorized) {
      updateProjectPdfWindow(
          pdfWindowKey, base64Encode(pdf!), pdfTitle, pending.isNotEmpty);
    }
  }

  void closePdfWindows() {
    for (final kind in ['timeline', 'plan', 'report']) {
      closeProjectPdfWindow('$owner:${widget.project.id}:$kind');
    }
  }

  String? owner;
  late String mode;
  bool busy = false;
  String? message;
  Map<String, dynamic>? data;
  Uint8List? pdf;
  final pending = <String, Map<String, dynamic>>{};
  final report = <String, dynamic>{};
  List<Map<String, dynamic>> phaseJobs = [];
  String get phaseScope =>
      'document-phase-dates.${widget.project.id}.${widget.project.excelLink}';
  List<String> activities = [''];
  Timer? accountTimer;
  Timer? calculationTimer;
  Future<void>? timelineCalculation;
  bool calculatingTimeline = false;
  String? calculatedDraft;
  int timelineDateEpoch = 0;
  List<dynamic>? originalTimelineRows;
  List<dynamic>? originalTimelineWarnings;
  String draftToken() => jsonEncode([mode, data?['revision'], pending]);
  bool get authorized =>
      owner != null &&
      owner ==
          (widget.uidProvider?.call() ??
              FirebaseAuth.instance.currentUser?.uid);
  String get scope => 'activity-report.${widget.project.id}';
  @override
  void initState() {
    super.initState();
    documentTabs = TabController(length: 2, vsync: this);
    owner =
        widget.uidProvider?.call() ?? FirebaseAuth.instance.currentUser?.uid;
    mode = widget.initialMode;
    final day = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final saved = RecoverableDraft.read(owner, scope);
    final phaseDraft = RecoverableDraft.read(owner, phaseScope);
    if (phaseDraft?['jobs'] is List) {
      phaseJobs = (phaseDraft!['jobs'] as List)
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
    }
    final savedReport = saved?['report'] is Map
        ? Map<String, dynamic>.from(saved!['report'])
        : <String, dynamic>{};
    report.addAll({
      'date': day.toIso8601String().substring(0, 10),
      'system': '',
      'participants': '',
      'company': widget.project.client,
      'signatureParticipants': '',
      'signatureCompany': widget.project.client,
      ...savedReport
    });
    // Every newly generated report starts with today's date; it remains editable.
    report['date'] = day.toIso8601String().substring(0, 10);
    if (saved?['activities'] is List) {
      activities = (saved!['activities'] as List).cast<String>();
    }
    accountTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !authorized) {
        closePdfWindows();
        setState(() {
          data = null;
          pdf = null;
          pending.clear();
          report.clear();
          activities.clear();
        });
      }
    });
    if (mode != 'report') unawaited(load());
  }

  @override
  void dispose() {
    calculationTimer?.cancel();
    accountTimer?.cancel();
    documentTabs.dispose();
    timelineScroll.dispose();
    closePdfWindows();
    super.dispose();
  }

  Future<Map<String, dynamic>> call(String operation) async {
    const reads = {
      'timeline-read',
      'timeline-preview',
      'timeline-calculate',
      'plan-read',
      'plan-preview'
    };
    for (var attempt = 0;; attempt++) {
      try {
        return await performCall(operation);
      } catch (e) {
        // Retry only an explicit refusal before a read starts. Never replay a
        // save, a transport timeout or a failure with an uncertain outcome.
        final refused = e.toString().contains(
            'Aguarde a leitura ou gravação da planilha em andamento.');
        if (!reads.contains(operation) ||
            !refused ||
            attempt >= 19 ||
            !mounted ||
            !authorized) rethrow;
        setState(() => message =
            'Aguardando a liberação da planilha para carregar o documento…');
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted || !authorized)
          throw StateError('A janela foi fechada ou a conta mudou.');
      }
    }
  }

  Future<Map<String, dynamic>> performCall(String operation) async {
    if (!authorized) throw StateError('A conta mudou. Feche esta janela.');
    final args = <String, dynamic>{
      'action': 'project-document',
      'operation': operation,
      'reference': widget.project.excelLink,
      'projectId': widget.project.id,
      'serviceType': widget.project.serviceType,
      if (data?['revision'] != null) 'revision': data!['revision'],
      'changes': pending.values.toList(),
      if (operation == 'report')
        'documentData': {
          ...report,
          'activities': activities.where((a) => a.trim().isNotEmpty).toList()
        }
    };
    final result = widget.transport != null
        ? await widget.transport!(args)
        : await NativeLocalFiles.call('project-document',
            operation: operation,
            reference: widget.project.excelLink,
            projectId: widget.project.id,
            projectField: operation == 'report' ? null : 'excelLink',
            serviceType: widget.project.serviceType,
            revision: data?['revision'] as String?,
            changes: pending.values.toList(),
            documentData: args['documentData'] as Map<String, dynamic>?);
    if (!mounted || !authorized) {
      throw StateError('A conta mudou ou a janela foi fechada.');
    }
    if (operation != 'report' && result['reference'] is String) {
      widget.project.excelLink = result['reference'] as String;
    }
    return result;
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy || !authorized) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      calculationTimer?.cancel();
      await timelineCalculation;
      if (!mounted || !authorized) return;
      await work();
    } catch (e) {
      if (mounted && authorized) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void accept(Map<String, dynamic> result) {
    data = result;
    calculatedDraft = null;
    if (mode == 'timeline') {
      originalTimelineRows = result['rows'] as List?;
      originalTimelineWarnings = result['warnings'] as List?;
    }
    pdf = result['pdfBase64'] is String
        ? base64Decode(result['pdfBase64'])
        : null;
    synchronizePdfWindow();
  }

  Future<void> load() => run(() async {
        accept(await call('$mode-read'));
        pending.clear();
        message = null;
      });
  Future<void> preview() => run(() async {
        final result =
            await call(mode == 'report' ? 'report' : '$mode-preview');
        // Keep original field values as the baseline for the verified save.
        pdf = base64Decode(result['pdfBase64'] as String);
        synchronizePdfWindow();
        if (!projectPdfWindowOpen(pdfWindowKey)) documentTabs.animateTo(1);
        if (mode == 'plan' && result['mirror'] is Map) {
          data = {...data!, if (result['planEditBaseline'] is Map) ...Map<String, dynamic>.from(result['planEditBaseline'] as Map), 'mirror': result['mirror']};
        }
        if (mode == 'timeline') {
          data = {
            ...data!,
            'rows': result['rows'],
            'warnings': result['warnings']
          };
          calculatedDraft = draftToken();
        }
        message = mode == 'report'
            ? 'Relatório gerado pelo Word. Confira e imprima o PDF.'
            : (result['warnings'] as List? ?? []).isNotEmpty
                ? 'Há datas sem cálculo: ${(result['warnings'] as List).join(', ')}. Confira fins de semana e feriados antes de salvar.'
                : 'Prévia recalculada. Use Salvar na planilha para gravar os ajustes.';
      });
  Future<void> save() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Salvar na planilha original?'),
                content: Text(
                    'Gravar ${pending.length} ajuste(s) no arquivo vinculado a ${widget.project.client}? Será criado um backup.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Salvar na planilha'))
                ]));
    if (confirmed != true || !mounted || !authorized) return;
    await run(() async {
      final saved = await call('$mode-save');
      if (saved['saved'] != true) {
        throw StateError(
            'A gravação não foi confirmada. Confira antes de repetir.');
      }
      pending.clear();
      pdf = null;
      markProjectPdfWindowStale(pdfWindowKey);
      data = null;
      accept(await call('$mode-read'));
      if (mode == 'timeline') {
        phaseJobs = [];
        for (final raw in (data?['periods'] as List? ?? [])) {
          final period = raw as Map;
          final start = DateTime.tryParse(period['start']?.toString() ?? '');
          final end = DateTime.tryParse(period['end']?.toString() ?? '');
          if (start == null || end == null || end.isBefore(start)) continue;
          final matches = (widget.project.subTasks ?? <TaskModel>[])
              .where((t) =>
                  spreadsheetStageKey(t.stage) ==
                  spreadsheetStageKey(period['label'].toString()))
              .toList();
          if (matches.length != 1 || matches.single.edeskWorkNumber.isEmpty) {
            continue;
          }
          final task = matches.single;
          if (phaseDay(task.planStart) == period['start'] &&
              phaseDay(task.planEnd) == period['end']) {
            continue;
          }
          phaseJobs.add(spreadsheetPhaseJob(
              task,
              widget.project.id,
              period['start'] as String,
              period['end'] as String,
              period['label'] as String));
        }
        if (phaseJobs.isNotEmpty) {
          if (!RecoverableDraft.save(owner, phaseScope, {'jobs': phaseJobs})) {
            throw StateError(
                'Excel salvo. Não foi possível guardar a recuperação das fases; confira as datas no sistema.');
          }
          try {
            await synchronizePhases();
          } catch (e) {
            throw StateError(
                'Salvo no Excel. A sincroniza\u00e7\u00e3o das fases ficou pendente: $e');
          }
        }
      }
      message =
          'Salvo no Excel com backup. Confira as fases relacionadas antes de enviar ao E-Desk.';
    });
  }

  Future<void> synchronizePhases() async {
    if (!authorized || phaseJobs.isEmpty) return;
    final checked = await call('timeline-read');
    final periods = (checked['periods'] as List? ?? []).cast<Map>();
    for (final job in phaseJobs) {
      final matches = periods.where((p) =>
          p['label'] == job['stage'] &&
          p['start'] == job['start'] &&
          p['end'] == job['end']);
      if (matches.length != 1) {
        throw StateError(
            'As datas no Excel mudaram. Confira antes de sincronizar as fases.');
      }
    }
    if (widget.phaseDatesSaver != null) {
      await widget.phaseDatesSaver!(phaseJobs);
    } else if (widget.transport != null) {
      throw StateError('Sincronização indisponível neste modo.');
    } else {
      await FirebaseService().applySpreadsheetPhaseDates(
          ownerUid: owner!,
          projectId: widget.project.id,
          reference: widget.project.excelLink!,
          jobs: phaseJobs);
    }
    if (!authorized) return;
    for (final job in phaseJobs) {
      for (final task in widget.project.subTasks ?? <TaskModel>[]) {
        if (task.edeskWorkNumber == job['work'] && task.stage == job['phase']) {
          task.planStart = DateTime.parse(job['start'] as String);
          task.planEnd = DateTime.parse(job['end'] as String);
        }
      }
    }
    phaseJobs = [];
    RecoverableDraft.clear(owner, phaseScope);
  }

  void edit(Map<String, dynamic> field, dynamic value) {
    final key = '${field['sheet']}!${field['cell']}';
    setState(() {
      if (mode == 'timeline' && field['kind'] == 'date') timelineDateEpoch++;
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
      pdf = null;
      markProjectPdfWindowStale(pdfWindowKey);
      message = 'Alterações pendentes. Aplique para conferir antes de salvar.';
      if (mode == 'timeline' && pending.isEmpty && originalTimelineRows != null) {
        data = {...data!, 'rows': originalTimelineRows, 'warnings': originalTimelineWarnings};
        calculatedDraft = null;
      }
    });
    if (mode == 'timeline') scheduleTimelineCalculation();
  }

  void scheduleTimelineCalculation() {
    calculationTimer?.cancel();
    if (!mounted || !authorized || mode != 'timeline' || pending.isEmpty) return;
    if (data?['timelineCalculationVersion'] != 1) {
      setState(() => message = 'Prévia local das datas. Atualize a integração para conferir automaticamente no Excel ou use Aplicar ajustes e conferir.');
      return;
    }
    calculationTimer = Timer(const Duration(milliseconds: 800), () => unawaited(calculateTimeline()));
  }

  Future<void> calculateTimeline() async {
    if (!mounted || !authorized || busy || timelineCalculation != null || mode != 'timeline' || pending.isEmpty) return;
    final token = draftToken();
    setState(() => calculatingTimeline = true);
    final job = () async {
      try {
        final result = await call('timeline-calculate');
        if (!mounted || !authorized || draftToken() != token || mode != 'timeline') return;
        if (result['revision'] != data?['revision'] || result['rows'] is! List) throw StateError('A resposta do Excel não corresponde ao cronograma aberto.');
        setState(() {
          data = {...data!, 'rows': result['rows'], 'warnings': result['warnings']};
          calculatedDraft = token;
          message = (result['warnings'] as List? ?? []).isNotEmpty
              ? 'Confira as datas indicadas pelo Excel: ${(result['warnings'] as List).join(', ')}.'
              : 'Datas recalculadas pelo Excel. Use Salvar na planilha para gravar.';
        });
      } catch (e) {
        if (mounted && authorized && draftToken() == token) setState(() => message = 'Não foi possível conferir automaticamente no Excel. Atualize a integração ou use Aplicar ajustes e conferir. $e');
      }
    }();
    timelineCalculation = job;
    try { await job; } finally {
      timelineCalculation = null;
      if (mounted) {
        setState(() => calculatingTimeline = false);
        if (authorized && mode == 'timeline' && pending.isNotEmpty && draftToken() != token && !busy) scheduleTimelineCalculation();
      }
    }
  }

  void openTimelineAppointment(Map row) {
    if (!authorized || busy || pending.isNotEmpty) return;
    final appointment = TimelineAppointment.fromRow(row);
    if (appointment == null) return;
    final cells = row['cells'] as List;
    final title = '${widget.project.client} · ${cells[1]}';
    final calendar = appointment.ics(
      uid: '${widget.project.id}-${row['row']}-${data?['revision']}@gerenciador-horas',
      title: title, description: 'Solicitação ${widget.project.id}\n${cells[3]}');
    downloadBytes(fileName: 'cronograma-${widget.project.id}-${row['row']}.ics',
      bytes: Uint8List.fromList(utf8.encode(calendar)), mimeType: 'text/calendar;charset=utf-8');
    setState(() => message = 'Compromisso preparado. Abra o arquivo .ics no Outlook e confira data, horário e fuso antes de salvar. Nenhum convite foi enviado.');
  }

  Future<void> reviewTimelineAppointment(Map row) async {
    if (!authorized || busy || pending.isNotEmpty) return;
    final appointment = TimelineAppointment.fromRow(row);
    if (appointment == null) return;
    String stamp(DateTime time) => '${timelineDayText(time)} ${timelineClock(time.hour*3600+time.minute*60+time.second)}';
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Agendar no Outlook'),
      content: Text('${(row['cells'] as List)[1]}\n\nInício: ${stamp(appointment.start)}\nFim: ${stamp(appointment.end)}\nDuração: ${timelineClock(appointment.end.difference(appointment.start).inSeconds)}\n\nSerá preparado um arquivo de compromisso. Abra-o no Outlook, confira e salve na agenda.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (authorized && !busy && pending.isEmpty) openTimelineAppointment(row); Navigator.pop(context); }, child: const Text('Preparar compromisso'))],
    ));
  }

  Future<void> reviewAllTimelineAppointments() async {
    if (!mounted || !authorized || busy || pending.isNotEmpty || mode != 'timeline' || data == null) return;
    final snapshot = data;
    final reference = widget.project.excelLink;
    final projectId = widget.project.id;
    final client = widget.project.client;
    final revision = data!['revision'].toString();
    bool current() => mounted && authorized && !busy && pending.isEmpty && mode == 'timeline'
        && identical(data,snapshot) && widget.project.excelLink == reference && widget.project.id == projectId;
    try {
      final batch = TimelineCalendarBatch.fromRows(data!['rows'] as List? ?? []);
      await showDialog<void>(context:context,builder:(context)=>TimelineBatchDialog(
        batch:batch,client:client,canPrepare:current,
        onPrepare:() {
          if (!current()) throw StateError('A conta ou o cronograma mudou.');
          final calendar = batch.ics(projectId:projectId,client:client,revision:revision);
          downloadBytes(fileName:'cronograma-$projectId-todas-etapas.ics',
            bytes:Uint8List.fromList(utf8.encode(calendar)),mimeType:'text/calendar;charset=utf-8');
          setState(()=>message='${batch.valid.length} compromissos preparados em um único arquivo. Importe no calendário escolhido do Outlook e confira o fuso horário.');
        },
      ));
    } catch (error) {
      if (mounted && authorized) setState(()=>message='Não foi possível preparar as etapas. $error');
    }
  }

  void reportEdit(String key, String value) {
    setState(() {
      report[key] = value;
      if (key == 'participants') report['signatureParticipants'] = value;
      if (key == 'company') report['signatureCompany'] = value;
      pdf = null;
      markProjectPdfWindowStale(pdfWindowKey);
    });
    RecoverableDraft.save(
        owner, scope, {'report': report, 'activities': activities});
  }

  Widget reportForm() => ListView(padding: const EdgeInsets.all(18), children: [
        Text('Solicitação: ${widget.project.id}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
            'Consultor: ${FirebaseAuth.instance.currentUser?.displayName ?? FirebaseAuth.instance.currentUser?.email ?? ''}'),
        const SizedBox(height: 14),
        for (final entry in <String, String>{
          'date': 'Data (AAAA-MM-DD)',
          'system': 'Nome do sistema do cliente',
          'participants': 'Participantes',
          'company': 'Nome da empresa',
          'signatureParticipants': 'Participantes na assinatura',
          'signatureCompany': 'Empresa na assinatura'
        }.entries)
          Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextFormField(
                  key: ValueKey(
                      'report-${entry.key}-${entry.key.startsWith('signature') ? report[entry.key] : ''}'),
                  initialValue: report[entry.key]?.toString() ?? '',
                  enabled: !busy,
                  decoration: InputDecoration(labelText: entry.value),
                  onChanged: (v) => reportEdit(entry.key, v))),
        const Text('Atividades realizadas',
            style: TextStyle(fontWeight: FontWeight.bold)),
        for (var i = 0; i < activities.length; i++)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.all(12), child: Text('•')),
                Expanded(
                    child: TextFormField(
                        key: ValueKey('activity-$i-${activities.length}'),
                        initialValue: activities[i],
                        enabled: !busy,
                        minLines: 2,
                        maxLines: 5,
                        decoration:
                            InputDecoration(labelText: 'Atividade ${i + 1}'),
                        onChanged: (v) {
                          activities[i] = v;
                          reportEdit('system', report['system'] as String);
                        })),
                IconButton(
                    tooltip: 'Remover atividade',
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              activities.removeAt(i);
                              pdf = null;
                              markProjectPdfWindowStale(pdfWindowKey);
                            }),
                    icon: const Icon(Icons.close))
              ])),
        TextButton.icon(
            onPressed: busy ? null : () => setState(() => activities.add('')),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar atividade'))
      ]);
  Widget timelineDate(Map field, Map row) {
    final f = Map<String, dynamic>.from(field);
    final key = '${f['sheet']}!${f['cell']}';
    final raw =
        (pending[key]?['value'] ?? row['date'] ?? f['value'])?.toString() ?? '';
    final date = DateTime.tryParse(raw);
    final text = date == null
        ? '${(row['cells'] as List)[2]}'
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return TextFormField(
        key: ValueKey('${data?['revision']}-$key-$raw'),
        initialValue: text,
        readOnly: true,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            suffixIcon: Icon(Icons.calendar_month, size: 17),
            border: OutlineInputBorder()),
        onTap: busy || !authorized
            ? null
            : () async {
                final selected = await showDatePicker(
                    context: context,
                    initialDate:
                        date != null && date.year >= 1900 && date.year <= 2200
                            ? date
                            : DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200));
                if (selected != null && mounted && authorized) {
                  final driver = f['dateDriver'];
                  if (driver is Map) {
                    pending.remove('${driver['sheet']}!${driver['cell']}');
                  }
                  edit(f, selected.toIso8601String().substring(0, 10));
                }
              });
  }

  Widget timeline() {
    final rows = pending.isNotEmpty && calculatedDraft != draftToken()
        ? timelineDraftRows(data!, pending)
        : (data?['rows'] as List? ?? []).cast<Map>();
    final columns = (data?['columns'] as List? ?? []).cast<Map>();
    final fields = (data?['fields'] as List? ?? []).cast<Map>();
    if (columns.isEmpty) {
      return const Center(
          child: Text('Nenhuma etapa do cronograma disponível.'));
    }
    double width(int c) =>
        const <int, double>{
          0: 26,
          1: 190,
          2: 130,
          3: 270,
          4: 70,
          5: 90,
          6: 55,
          7: 80,
          8: 50,
          9: 95,
          10: 95
        }[c] ??
        95;
    Widget cell(Map row, int c) {
      var value = '${(row['cells'] as List)[c]}';
      if (c == 9 || c == 10) {
        final seconds = timelineSeconds((row['cells'] as List)[c], duration: c == 10);
        if (seconds != null) value = timelineClock(seconds);
      }
      if (c == 9 || c == 10) {
        final clocks = fields.where((f) => f['cell'] == '${c==9?'J':'K'}${row['row']}' && f['timelineTime'] == true && f['readOnly'] != true);
        if (clocks.isNotEmpty) {
          final field = Map<String,dynamic>.from(clocks.single);
          final key = '${field['sheet']}!${field['cell']}';
          final draftTime = pending[key]?['value'];
          final text = draftTime is num ? timelineClock((draftTime*86400).round()) : draftTime?.toString() ?? value;
          return TimelineTimeField(key: ValueKey('${data?['revision']}-timeline-clock-$key'), text:text, duration:c==10,
            enabled: !busy && authorized,
            errorText: pending[key] != null && pending[key]!['value'] is! num ? 'Horário inválido' : null,
            onChanged:(text) => edit(field, timelineTimeInput(text,duration:c==10) ?? text));
        }
      }
      final dates = fields.where((f) =>
          f['cell'] == 'C${row['row']}' && f['timelineDateEditable'] == true);
      if (c == 2 && dates.isNotEmpty) {
        return timelineDate(dates.first, row);
      }
      final days = fields.where((f) =>
          f['cell'] == 'H${row['row']}' &&
          f['timelineDays'] == true &&
          f['readOnly'] != true);
      if (c == 7 && days.isNotEmpty) {
        final field = Map<String, dynamic>.from(days.first);
        final key = '${field['sheet']}!${field['cell']}';
        return TextFormField(
            key: ValueKey(
                '${data?['revision']}-$key-$timelineDateEpoch'),
            initialValue: (pending[key]?['value'] ?? (row['cells'] as List)[7])
                    ?.toString() ??
                '',
            enabled: !busy && authorized,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
                labelText: 'Dias',
                isDense: true,
                contentPadding: EdgeInsets.all(8)),
            onChanged: (v) {
              for (final date in fields) {
                final driver = date['dateDriver'];
                if (driver is Map &&
                    driver['sheet'] == field['sheet'] &&
                    driver['cell'] == field['cell']) {
                  pending.remove('${date['sheet']}!${date['cell']}');
                }
              }
              edit(field, int.tryParse(v) ?? v);
            });
      }
      return Tooltip(
          message: value,
          child: Text(value,
              maxLines: c == 3 ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:4),child:Align(
        alignment:Alignment.centerRight,child:Tooltip(
          message:pending.isNotEmpty ? 'Salve os ajustes antes de agendar todas as etapas' : 'Conferir as etapas e preparar um arquivo para importar no Outlook',
          child:OutlinedButton.icon(icon:const Icon(Icons.event_available_outlined,size:18),label:const Text('Agendar todas'),
            onPressed:!kIsWeb || busy || !authorized || pending.isNotEmpty ? null : reviewAllTimelineAppointments)))),
      const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
              'Edite datas, dias, Hora Início e Duração. Salve os ajustes e use Agendar na coluna Outlook para preparar o compromisso.')),
      if (calculatingTimeline || pending.isNotEmpty && calculatedDraft != draftToken())
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Prévia das datas; aguardando conferência do Excel.', style: TextStyle(fontSize: 12))),
      if (columns.length > 10 && !fields.any((field) => field['timelineTime'] == true))
        const Padding(padding: EdgeInsets.all(12), child: Text('Para editar Hora Início e Duração, instale e reinicie a integração v78.')),
      Expanded(
          child: Scrollbar(
              controller: timelineScroll,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                  key: const ValueKey('timeline-full-width-scroll'),
                  controller: timelineScroll,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                      child: DataTable(
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 80,
                          headingRowHeight: 42,
                          columnSpacing: 8,
                          horizontalMargin: 12,
                          columns: [
                        const DataColumn(label: SizedBox(width:100,child:Text('Outlook'))),
                        for (var c = 0; c < columns.length && c <= 10; c++)
                          DataColumn(
                              label: SizedBox(
                                  width: width(c),
                                  child: Text(
                                      '${columns[c]['letter']} · ${columns[c]['label']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)))
                      ],
                          rows: [
                        for (final row in rows)
                          DataRow(cells: [
                            DataCell(SizedBox(width:100,child:Tooltip(
                              message: pending.isNotEmpty ? 'Salve os ajustes antes de agendar' : TimelineAppointment.fromRow(row)==null ? 'Preencha data, início e duração válidos para agendar' : 'Preparar compromisso para abrir no Outlook',
                              child: TextButton.icon(icon:const Icon(Icons.event_available_outlined,size:17),label:const Text('Agendar',maxLines:1,softWrap:false),
                                style:TextButton.styleFrom(padding:const EdgeInsets.symmetric(horizontal:4)),
                                onPressed:!kIsWeb || busy || !authorized || pending.isNotEmpty || TimelineAppointment.fromRow(row)==null ? null : () => reviewTimelineAppointment(row))))),
                            for (var c = 0; c < columns.length && c <= 10; c++)
                              DataCell(SizedBox(
                                  width: width(c), child: cell(row, c)))
                          ])
                      ])))))
    ]);
  }

  int insertedPlanOperation = 0;
  Future<void> insertPlanRows(int row, int count, bool below) async {
    if (busy || !authorized || mode != 'plan' || data?['planRowsVersion'] != 1) return;
    final at = row + (below ? 1 : 0);
    final previous = {for (final entry in pending.entries) entry.key: Map<String, dynamic>.from(entry.value)};
    final previousData = data;
    final previousPdf = pdf;
    await run(() async {
      try {
        final shifted = shiftPlanEdits(pending, at, count);
        shifted['plan-insert-${++insertedPlanOperation}'] = {'operation': 'insert-plan-rows', 'row': at, 'count': count};
        pending..clear()..addAll(shifted);
        markProjectPdfWindowStale(pdfWindowKey);
        final result = await call('plan-preview');
        if (result['planEditBaseline'] is! Map || result['mirror'] is! Map || result['revision'] != data?['revision']) {
          throw StateError('A integração não confirmou as linhas e os campos do plano.');
        }
        data = {...data!, ...Map<String, dynamic>.from(result['planEditBaseline'] as Map), 'mirror': result['mirror']};
        pdf = base64Decode(result['pdfBase64'] as String);
        synchronizePdfWindow();
        message = 'Linhas incluídas na prévia. Você pode editar os novos campos; use Salvar na planilha para gravar.';
      } catch (_) {
        if (mounted && authorized) {
          pending..clear()..addAll(previous);
          data = previousData;
          pdf = previousPdf;
          synchronizePdfWindow();
        }
        rethrow;
      }
    });
  }

  Future<void> removePlanGuidance(List<String> names) async {
    if (busy || !authorized || mode != 'plan' || data?['planGuidanceVersion'] != 1 || names.isEmpty) return;
    final previous = {for (final entry in pending.entries) entry.key: Map<String, dynamic>.from(entry.value)};
    final previousData = data;
    final previousPdf = pdf;
    await run(() async {
      try {
        final shifted = {for (final entry in pending.entries) entry.key: Map<String,dynamic>.from(entry.value)};
        shifted['plan-guidance-${++insertedPlanOperation}'] = {'operation': 'remove-plan-guidance', 'names': names};
        pending..clear()..addAll(shifted);
        markProjectPdfWindowStale(pdfWindowKey);
        final result = await call('plan-preview');
        if (result['planEditBaseline'] is! Map || result['mirror'] is! Map || result['revision'] != data?['revision']) {
          throw StateError('A integra\u00e7\u00e3o n\u00e3o confirmou a remo\u00e7\u00e3o das orienta\u00e7\u00f5es.');
        }
        data = {...data!, ...Map<String, dynamic>.from(result['planEditBaseline'] as Map), 'mirror': result['mirror']};
        pdf = base64Decode(result['pdfBase64'] as String);
        synchronizePdfWindow();
        message = 'Setas removidas na pr\u00e9via. Use Salvar na planilha para confirmar no arquivo.';
      } catch (_) {
        if (mounted && authorized) {
          pending..clear()..addAll(previous);
          data = previousData;
          pdf = previousPdf;
          synchronizePdfWindow();
        }
        rethrow;
      }
    });
  }

  Widget planForm() => PlanSheetEditor(
      data: data!,
      pending: pending,
      enabled: !busy && authorized,
      onInsertRows: insertPlanRows,
      onRemoveGuidance: removePlanGuidance,
      onChanged: (field, value) => edit(field, value));
  Future<void> close() async {
    if (busy) return;
    if (pending.isNotEmpty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Descartar ajustes não salvos?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Continuar editando')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Descartar'))
                  ]));
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final content = mode == 'report'
        ? reportForm()
        : data == null
            ? const Center(
                child: Text(
                    'Carregue o documento pela integração local atualizada.'))
            : mode == 'timeline'
                ? timeline()
                : planForm();
    return PopScope(
        canPop: !busy && pending.isEmpty,
        child: MovableDocumentDialog(
                child: Column(children: [
                  ListTile(
                      title: Text(mode == 'report'
                          ? 'Relatório de atividades realizadas'
                          : 'Documentos e cronograma'),
                      subtitle: Text(
                          '${widget.project.id} · ${widget.project.client}'),
                      trailing: IconButton(
                          onPressed: busy ? null : close,
                          icon: const Icon(Icons.close))),
                  if (authorized)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(spacing: 10, children: [
                          for (final entry in {
                            'timeline': 'Linha do Tempo',
                            'plan': 'Plano de Projeto',
                            'report': 'Relatório de atividades'
                          }.entries)
                            ChoiceChip(
                                label: Text(entry.value),
                                selected: mode == entry.key,
                                onSelected: busy || pending.isNotEmpty
                                    ? null
                                    : (_) {
                                        setState(() {
                                          mode = entry.key;
                                          data = null;
                                          pdf = null;
                                          message = null;
                                          documentTabs.index = 0;
                                        });
                                        if (mode != 'report') unawaited(load());
                                      })
                        ])),
                  if (busy) const LinearProgressIndicator(),
                  if (message != null)
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(message!)),
                  Expanded(
                      child: !authorized
                          ? const Center(
                              child: Text(
                                  'A conta mudou. Feche e abra esta janela novamente.'))
                          : LayoutBuilder(builder: (_, constraints) {
                              final bytes = pdf;
                              final preview = bytes == null
                                  ? const Center(
                                      child: Text(
                                          'Aplique os ajustes para conferir o documento original.'))
                                  : PdfPreview(
                                      key: ValueKey(bytes),
                                      build: (_) async => bytes,
                                      allowPrinting: pending.isEmpty,
                                      allowSharing: pending.isEmpty,
                                      canChangePageFormat: false,
                                      canChangeOrientation: false,
                                      pdfFileName:
                                          '${widget.project.id}-$mode.pdf');
                              return Column(children: [
                                TabBar(controller: documentTabs, tabs: [
                                  Tab(
                                      text: mode == 'timeline'
                                          ? 'Tabela do cronograma'
                                          : 'Editar campos'),
                                  const Tab(text: 'Conferir documento / PDF')
                                ]),
                                Expanded(
                                    child: TabBarView(
                                        controller: documentTabs,
                                        children: [
                                      ClipRect(child: content),
                                      preview
                                    ]))
                              ]);
                            })),
                  Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(spacing: 12, runSpacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: busy || !authorized || pdf == null
                                ? null
                                : () {
                                    final opened = openProjectPdfWindow(
                                        pdfWindowKey,
                                        base64Encode(pdf!),
                                        pdfTitle,
                                        pending.isNotEmpty);
                                    if (opened) documentTabs.animateTo(0);
                                    if (!opened) {
                                      setState(() => message =
                                          'Permita pop-ups para este site para abrir o PDF em uma janela independente.');
                                    }
                                  },
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Abrir PDF em outra janela')),
                        TextButton(
                            onPressed: busy ? null : close,
                            child: const Text('Fechar')),
                        if (phaseJobs.isNotEmpty)
                          FilledButton.tonal(
                              onPressed: busy || !authorized
                                  ? null
                                  : () => run(synchronizePhases),
                              child: const Text(
                                  'Concluir sincronização das fases')),
                        if (mode != 'report')
                          TextButton(
                              onPressed:
                                  busy || pending.isNotEmpty ? null : load,
                              child: const Text('Recarregar')),
                        FilledButton.tonal(
                            onPressed: busy || !authorized ? null : preview,
                            child: Text(mode == 'report'
                                ? 'Gerar relatório / PDF'
                                : 'Aplicar ajustes e conferir')),
                        if (mode != 'report')
                          FilledButton(
                              onPressed: busy || !authorized || pending.isEmpty
                                  ? null
                                  : save,
                              child: const Text('Salvar na planilha'))
                      ]))
                ])));
  }
}
