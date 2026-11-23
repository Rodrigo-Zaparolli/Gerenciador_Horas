import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:flutter/material.dart';
import '../../core/theme/cores_app.dart';
import 'task_hours_filter.dart';

enum TaskScreenAction { history, clear, pending, registerHours }

class TaskFiltersBar extends StatelessWidget {
  const TaskFiltersBar(
      {super.key,
      required this.controller,
      required this.onSearch,
      required this.workLabel,
      required this.onWork,
      required this.onClearWork,
      required this.periodLabel,
      required this.onPeriod,
      required this.filter,
      required this.onBilling,
      required this.onAction,
      required this.showHistory,
      required this.showPending,
      this.onPreviousMonth,
      this.onNextMonth,
      this.onToday});
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final String? workLabel;
  final VoidCallback onWork, onClearWork, onPeriod;
  final VoidCallback? onPreviousMonth, onNextMonth, onToday;
  final String periodLabel;
  final TaskHoursFilter filter;
  final ValueChanged<TaskHoursFilter> onBilling;
  final ValueChanged<TaskScreenAction> onAction;
  final bool showHistory, showPending;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: AppVisuals.panel(radius: 14),
      child: LayoutBuilder(builder: (context, c) {
        final search = TextField(
            controller: controller,
            onChanged: onSearch,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                prefixIcon: Icon(Icons.search, size: 17),
                prefixIconConstraints:
                    BoxConstraints(minWidth: 32, minHeight: 30),
                hintText: 'ID, cliente, trabalho ou descrição…',
                border: OutlineInputBorder()));
        final project = Row(children: [
          Expanded(
              child: Tooltip(
                  message:
                      workLabel ?? 'Selecionar projeto com todos os trabalhos',
                  child: OutlinedButton.icon(
                      onPressed: onWork,
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 9),
                          minimumSize: const Size(0, 34),
                          textStyle: const TextStyle(fontSize: 12)),
                      icon: const Icon(Icons.folder_outlined, size: 16),
                      label: Text(workLabel ?? 'Todos os projetos',
                          maxLines: 1, overflow: TextOverflow.ellipsis)))),
          if (workLabel != null)
            IconButton(
                tooltip: 'Todos os projetos',
                visualDensity: VisualDensity.compact,
                onPressed: onClearWork,
                icon: const Icon(Icons.close, size: 15))
        ]);
        final period = Row(children: [
          IconButton(
              tooltip: 'Mês anterior',
              visualDensity: VisualDensity.compact,
              onPressed: onPreviousMonth,
              icon: const Icon(Icons.chevron_left, size: 17)),
          Expanded(
              child: Tooltip(
                  message: periodLabel,
                  child: OutlinedButton.icon(
                      onPressed: onPeriod,
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 9),
                          minimumSize: const Size(0, 34),
                          textStyle: const TextStyle(fontSize: 12)),
                      icon: const Icon(Icons.calendar_month_outlined, size: 15),
                      label: Text(periodLabel,
                          maxLines: 1, overflow: TextOverflow.ellipsis)))),
          IconButton(
              tooltip: 'Próximo mês',
              visualDensity: VisualDensity.compact,
              onPressed: onNextMonth,
              icon: const Icon(Icons.chevron_right, size: 17))
        ]);
        final billing = DropdownButtonFormField<TaskHoursFilter>(
            initialValue: filter,
            key: ValueKey(filter),
            isExpanded: true,
            style: TextStyle(color: CoresApp.textoPrincipal, fontSize: 12),
            decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: TaskHoursFilter.all, child: Text('Todas as horas')),
              DropdownMenuItem(
                  value: TaskHoursFilter.charged, child: Text('Cobradas')),
              DropdownMenuItem(
                  value: TaskHoursFilter.nonCharged,
                  child: Text('Não cobradas'))
            ],
            onChanged: (v) {
              if (v != null) onBilling(v);
            });
        final menu = PopupMenuButton<TaskScreenAction>(
            tooltip: 'Ações dos apontamentos',
            iconSize: 20,
            onSelected: onAction,
            itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: TaskScreenAction.registerHours,
                      child: Text('Registrar horas em Projetos')),
                  PopupMenuItem(
                      value: TaskScreenAction.history,
                      child: Text(MediaQuery.sizeOf(context).width < 1050
                          ? 'Abrir histórico'
                          : showHistory
                              ? 'Ocultar histórico'
                              : 'Mostrar histórico')),
                  PopupMenuItem(
                      value: TaskScreenAction.pending,
                      child: Text(showPending
                          ? 'Ocultar registros pendentes'
                          : 'Mostrar registros pendentes')),
                  const PopupMenuItem(
                      value: TaskScreenAction.clear,
                      child: Text('Limpar filtros')),
                ]);
        final clear = IconButton(
            tooltip: 'Limpar filtros',
            visualDensity: VisualDensity.compact,
            onPressed: () => onAction(TaskScreenAction.clear),
            icon: const Icon(Icons.close, size: 17));
        if (c.maxWidth >= 1050)
          return Row(children: [
            Expanded(child: search),
            const SizedBox(width: 8),
            SizedBox(width: 240, child: project),
            const SizedBox(width: 8),
            SizedBox(width: 230, child: period),
            const SizedBox(width: 8),
            SizedBox(width: 150, child: billing),
            clear,
            menu
          ]);
        return Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: c.maxWidth, child: search),
              SizedBox(
                  width: c.maxWidth < 600 ? c.maxWidth : 240, child: project),
              SizedBox(
                  width: c.maxWidth < 600 ? c.maxWidth : 230, child: period),
              SizedBox(
                  width: c.maxWidth < 600 ? c.maxWidth - 85 : 150,
                  child: billing),
              clear,
              menu
            ]);
      }));
}
