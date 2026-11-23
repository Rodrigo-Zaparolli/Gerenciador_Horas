import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/cores_app.dart';
import '../../domain/models/dashboard_models.dart';
import '../../domain/models/work_duration.dart';
import 'task_hours_filter.dart';

enum TaskLogAction { edit, delete, send, reviewDay, register }

String taskLogKey(TimeLog log) => '${log.projectId ?? log.targetId}|${log.id}';

/// Lazy rows keep a large period usable; horizontal scroll preserves all columns.
class TaskLogsTable extends StatefulWidget {
  const TaskLogsTable(
      {super.key,
      required this.logs,
      required this.selected,
      required this.onSelect,
      required this.onSelectAll,
      required this.onAction,
      this.busy = false});
  final List<TimeLog> logs;
  final Set<String> selected;
  final void Function(TimeLog, bool) onSelect;
  final ValueChanged<bool> onSelectAll;
  final void Function(TimeLog, TaskLogAction) onAction;
  final bool busy;

  @override
  State<TaskLogsTable> createState() => _TaskLogsTableState();
}

class _TaskLogsTableState extends State<TaskLogsTable> {
  int _page = 0;
  int _pageSize = 10;
  @override
  void didUpdateWidget(covariant TaskLogsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.logs.map(taskLogKey).toList(), widget.logs.map(taskLogKey).toList())) _page = 0;
  }
  final horizontal = ScrollController();
  final vertical = ScrollController();
  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.logs.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off, size: 42, color: CoresApp.destaque),
                const SizedBox(height: 12),
                const Text('Nenhum apontamento neste filtro',
                    textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('Altere o trabalho, período ou cobrança.',
                    textAlign: TextAlign.center),
              ])));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(1000.0, constraints.maxWidth);
      final pageCount = (widget.logs.length + _pageSize - 1) ~/ _pageSize;
      final page = _page.clamp(0, pageCount - 1);
      final first = page * _pageSize;
      final count = math.min(_pageSize, widget.logs.length - first);
      return Scrollbar(
          controller: horizontal,
          thumbVisibility: true,
          notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: width,
                child: Column(children: [
                  Container(
                      height: 44,
                      color: CoresApp.destaque.withValues(alpha: .07),
                      child: Row(children: [
                        SizedBox(
                            width: 36,
                            child: Checkbox(
                                value: widget.logs.every((log) =>
                                    widget.selected.contains(taskLogKey(log))),
                                onChanged: widget.busy
                                    ? null
                                    : (v) => widget.onSelectAll(v ?? false))),
                        cell(const Text('Data ↓'), 96),
                        cell(const Text('Projeto / Trabalho'), 210),
                        Expanded(child: const Text('Descrição do apontamento')),
                        cell(const Text('Início – Fim'), 120),
                        cell(const Text('Duração'), 70),
                        cell(const Text('Cobrança'), 112),
                        cell(const Text('Ações'), 132),
                      ])),
                  Expanded(
                      child: Scrollbar(
                          controller: vertical,
                          child: ListView.builder(
                            controller: vertical,
                            itemCount: count,
                            itemBuilder: (context, pageIndex) {
                              final index = first + pageIndex;
                              final log = widget.logs[index];
                              final charged = taskLogIsCharged(log);
                              final color = charged
                                  ? CoresApp.sucesso
                                  : Colors.amber.shade700;
                              final reference =
                                  log.targetId.replaceAll('_', '/');
                              return Container(
                                  key: ValueKey(taskLogKey(log)),
                                  decoration: BoxDecoration(
                                    color: widget.selected
                                            .contains(taskLogKey(log))
                                        ? CoresApp.destaque
                                            .withValues(alpha: .1)
                                        : index.isOdd
                                            ? CoresApp.destaque
                                                .withValues(alpha: .025)
                                            : null,
                                    border: Border(
                                        bottom: BorderSide(
                                            color: CoresApp.borda
                                                .withValues(alpha: .55))),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                            width: 36,
                                            child: Checkbox(
                                                value: widget.selected
                                                    .contains(taskLogKey(log)),
                                                onChanged: widget.busy
                                                    ? null
                                                    : (v) => widget.onSelect(
                                                        log, v ?? false))),
                                        cell(
                                            Text(log.dateFormatted,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13)),
                                            96),
                                        cell(
                                            Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      '$reference · ${log.taskName ?? 'Trabalho'}',
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 13)),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                      log.projectName ??
                                                          log.projectId ??
                                                          '',
                                                      style: TextStyle(
                                                          color: CoresApp
                                                              .textoSecundario,
                                                          fontSize: 13)),
                                                  if (!log.isRegistered)
                                                    const Text(
                                                        'Registro administrativo pendente',
                                                        style: TextStyle(
                                                            color: Colors.amber,
                                                            fontSize: 13))
                                                ]),
                                            210),
                                        Expanded(
                                            child: Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 12),
                                                child: Text(
                                                    log.description
                                                                ?.trim()
                                                                .isNotEmpty ==
                                                            true
                                                        ? log.description!
                                                        : 'Sem comentário',
                                                    style: const TextStyle(
                                                        fontSize: 13)))),
                                        cell(
                                            Text(
                                                '${log.startTime} – ${log.endTime}',
                                                style: const TextStyle(
                                                    fontSize: 13)),
                                            120),
                                        cell(
                                            Text(
                                                WorkDuration.format(
                                                    WorkDuration.minutes(log)),
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w800)),
                                            70),
                                        cell(
                                            Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                    color: color.withValues(
                                                        alpha: .12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            20)),
                                                child: Text(
                                                    charged
                                                        ? '✓ Cobrada'
                                                        : '⊘ Não cobrada',
                                                    style: TextStyle(
                                                        color: color,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700))),
                                            112),
                                        SizedBox(
                                            width: 132,
                                            child: Row(children: [
                                              IconButton(
                                                  tooltip: 'Editar apontamento',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: widget.busy
                                                      ? null
                                                      : () => widget.onAction(
                                                          log,
                                                          TaskLogAction.edit),
                                                  icon: const Icon(
                                                      Icons.edit_outlined,
                                                      size: 16)),
                                              IconButton(
                                                  tooltip:
                                                      'Excluir apontamento',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: widget.busy
                                                      ? null
                                                      : () => widget.onAction(
                                                          log,
                                                          TaskLogAction.delete),
                                                  icon: Icon(
                                                      Icons.delete_outline,
                                                      color: CoresApp.erro,
                                                      size: 16)),
                                              PopupMenuButton<TaskLogAction>(
                                                  enabled: !widget.busy,
                                                  tooltip:
                                                      'Mais ações do apontamento',
                                                  padding: EdgeInsets.zero,
                                                  iconSize: 16,
                                                  onSelected: (action) => widget
                                                      .onAction(log, action),
                                                  itemBuilder: (_) => [
                                                        if (log.isRegistered)
                                                          const PopupMenuItem(
                                                              value:
                                                                  TaskLogAction
                                                                      .send,
                                                              child: Text(
                                                                  'Conferir e enviar ao E-Desk')),
                                                        const PopupMenuItem(
                                                            value: TaskLogAction
                                                                .reviewDay,
                                                            child: Text(
                                                                'Conferir apontamentos do dia')),
                                                        if (!log.isRegistered)
                                                          const PopupMenuItem(
                                                              value:
                                                                  TaskLogAction
                                                                      .register,
                                                              child: Text(
                                                                  'Registrar no sistema')),
                                                      ]),
                                            ])),
                                      ]));
                            },
                          ))),
                  Container(height:48,padding:const EdgeInsets.symmetric(horizontal:14),
                    decoration:BoxDecoration(border:Border(top:BorderSide(color:CoresApp.borda))),
                    child:Row(children:[
                      Expanded(child:Text('Total: ${widget.logs.length} apontamentos · ${WorkDuration.format(widget.logs.fold<int>(0,(sum,log)=>sum+WorkDuration.minutes(log)))} exibidas',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:CoresApp.textoPrincipal,fontSize:12))),
                      const SizedBox(width:12),const Text('Itens por página: ',style:TextStyle(fontSize:12)),
                      DropdownButton<int>(value:_pageSize,items:[for(final n in [10,20,50,100])DropdownMenuItem(value:n,child:Text('$n'))],onChanged:(v){if(v!=null)setState((){_pageSize=v;_page=0;});}),
                      IconButton(tooltip:'Primeira página',onPressed:page>0?()=>setState(()=>_page=0):null,icon:const Icon(Icons.first_page)),
                      IconButton(tooltip:'Página anterior',onPressed:page>0?()=>setState(()=>_page=page-1):null,icon:const Icon(Icons.chevron_left)),
                      Text('${page+1} / $pageCount'),
                      IconButton(tooltip:'Próxima página',onPressed:page<pageCount-1?()=>setState(()=>_page=page+1):null,icon:const Icon(Icons.chevron_right)),
                      IconButton(tooltip:'Última página',onPressed:page<pageCount-1?()=>setState(()=>_page=pageCount-1):null,icon:const Icon(Icons.last_page)),
                    ])),
                ])),
          ));
    });
  }

  Widget cell(Widget child, double width) => SizedBox(
      width: width,
      child: Padding(padding: const EdgeInsets.only(right: 10), child: child));
}
