import 'package:flutter/material.dart';
import '../../../data/services/edesk_service.dart';
import '../../../domain/models/project_model.dart';

typedef SpreadsheetPhaseSender = Future<EdeskSendResult> Function(
    List<Map<String, String>> phases);

Future<String?> showSpreadsheetPhaseSend(BuildContext context,
    {required ProjectModel project,
    required bool Function() authorized,
    SpreadsheetPhaseSender? sender}) {
  return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PhaseSendDialog(
          project: project, authorized: authorized, sender: sender));
}

class _PhaseSendDialog extends StatefulWidget {
  const _PhaseSendDialog(
      {required this.project, required this.authorized, this.sender});
  final ProjectModel project;
  final bool Function() authorized;
  final SpreadsheetPhaseSender? sender;
  @override
  State<_PhaseSendDialog> createState() => _PhaseSendDialogState();
}

class _PhaseSendDialogState extends State<_PhaseSendDialog> {
  final selected = <int>{};
  late final List<TaskModel> tasks;
  bool sending = false;
  String? error;
  String date(DateTime? d) => d == null ? 'Não informada' :
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  bool valid(TaskModel t) => t.phaseSendName.isNotEmpty &&
      t.planStart != null && t.planEnd != null &&
      !DateUtils.dateOnly(t.planEnd!).isBefore(DateUtils.dateOnly(t.planStart!)) &&
      tasks.where((other) => other.phaseSendName.toLowerCase() ==
          t.phaseSendName.toLowerCase()).length == 1;
  @override
  void initState() {
    super.initState();
    tasks = (widget.project.subTasks ?? <TaskModel>[]).where((t) =>
        t.edeskSolicitacao?.trim().isNotEmpty != true ||
        t.edeskSolicitacao!.trim() == widget.project.id.trim()).toList();
    for (var i = 0; i < tasks.length; i++) {
      if (valid(tasks[i])) selected.add(i);
    }
  }
  Future<void> send() async {
    if (sending || !widget.authorized() || selected.isEmpty) return;
    final phases = [for (final i in selected.toList()..sort()) {
      'nome': tasks[i].phaseSendName,
      'dataInicial': date(tasks[i].planStart),
      'dataFinal': date(tasks[i].planEnd),
    }];
    setState(() { sending = true; error = null; });
    try {
      final result = await (widget.sender?.call(phases) ??
          EdeskService().atualizarFasesViaPython(id: widget.project.id,
              cliente: widget.project.client, fases: phases));
      if (!mounted) return;
      if (!widget.authorized()) throw StateError('Sua sessão mudou. Entre novamente.');
      if (result.confirmed) {
        Navigator.pop(context, result.message.isEmpty
            ? 'Fases atualizadas no E-Desk com confirmação.' : result.message);
      } else if (result.statusCode != 499) {
        setState(() => error = result.message.isEmpty
            ? 'Envio sem confirmação. Confira o E-Desk antes de repetir.' : result.message);
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Não foi possível enviar as fases: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !sending,
    child: AlertDialog(
      title: const Text('Enviar fases ao E-Desk'),
      content: SizedBox(width: 580, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.project.id} — ${widget.project.client}'),
          const SizedBox(height: 12),
          const Text('Confira as datas salvas no sistema e selecione as fases. Ao enviar, as datas dessas fases serão atualizadas no E-Desk.'),
          if (tasks.isEmpty) const Text('Este projeto não possui fases cadastradas.'),
          for (var i = 0; i < tasks.length; i++) CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: selected.contains(i), title: Text(tasks[i].stage),
            subtitle: Text('${tasks[i].edeskPhaseName?.trim().isNotEmpty == true ? 'Fase E-Desk: ${tasks[i].phaseSendName}\n' : ''}${valid(tasks[i])
                ? '${date(tasks[i].planStart)} → ${date(tasks[i].planEnd)}'
                : 'Confira as datas ou o nome duplicado da fase no cadastro.'}'),
            onChanged: sending || !valid(tasks[i]) ? null : (value) => setState(() {
              if (value == true) { selected.add(i); } else { selected.remove(i); }
            })),
          if (sending) const LinearProgressIndicator(),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]))),
      actions: [
        TextButton(onPressed: sending ? null : () => Navigator.pop(context), child: const Text('Fechar')),
        FilledButton(onPressed: sending || selected.isEmpty || !widget.authorized() ? null : send,
            child: Text(sending ? 'Enviando…' : 'Enviar selecionadas (${selected.length})')),
      ],
    ));
}
