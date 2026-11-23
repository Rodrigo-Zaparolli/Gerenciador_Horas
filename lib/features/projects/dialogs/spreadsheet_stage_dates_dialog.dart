import 'package:flutter/material.dart';
import '../../../domain/models/project_model.dart';
import 'spreadsheet_phase_dates.dart';

Future<({String start, String end, String work})?> editSpreadsheetStageDates(
    BuildContext context,
    {required String stage,
    required String start,
    required String end,
    required List<TaskModel> tasks,
    String? selectedWork,
    bool adjustedSummary = false}) async {
  var first = DateTime.tryParse(start), last = DateTime.tryParse(end);
  final matches = tasks
      .where((t) => spreadsheetStageKey(t.stage) == spreadsheetStageKey(stage))
      .toList();
  var work = selectedWork ??
      (matches.length == 1 ? matches.single.edeskWorkNumber : null);
  String? error;
  String display(DateTime? date) => date == null
      ? 'Escolher data'
      : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  return showDialog<({String start, String end, String work})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
                title: Text('Datas — $stage'),
                content: SizedBox(
                    width: 420,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(adjustedSummary
                              ? 'Define datas ajustadas no resumo da Linha do Tempo. As atividades detalhadas não são reprogramadas. O cálculo original fica preservado na fórmula para recuperação.'
                              : 'Altera o início e o fim desta etapa. As atividades da Linha do Tempo são mantidas.'),
                          const SizedBox(height: 16),
                          for (final isStart in [true, false])
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: OutlinedButton.icon(
                                  icon:
                                      const Icon(Icons.calendar_month_outlined),
                                  label: Text(
                                      '${isStart ? 'Início' : 'Fim'}: ${display(isStart ? first : last)}'),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                        context: context,
                                        initialDate: (isStart ? first : last) ??
                                            DateTime.now(),
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime(2200));
                                    if (picked != null && context.mounted)
                                      refresh(() {
                                        if (isStart) {
                                          first = picked;
                                        } else {
                                          last = picked;
                                        }
                                        error = null;
                                      });
                                  },
                                )),
                          DropdownButtonFormField<String>(
                            initialValue: tasks
                                        .where((t) => t.edeskWorkNumber == work)
                                        .length ==
                                    1
                                ? work
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Fase relacionada no sistema',
                                border: OutlineInputBorder()),
                            items: [
                              for (final t in tasks)
                                DropdownMenuItem(
                                    value: t.edeskWorkNumber,
                                    child: Text(
                                        '${t.edeskWorkNumber} — ${t.stage}',
                                        overflow: TextOverflow.ellipsis))
                            ],
                            onChanged: (value) => refresh(() => work = value),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                              'Ao salvar na planilha, a fase relacionada será atualizada no Gerenciador. Depois, use Enviar fases ao E-Desk no cabeçalho da planilha.',
                              style: TextStyle(fontSize: 12)),
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                        ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () {
                        if (first == null ||
                            last == null ||
                            last!.isBefore(first!)) {
                          refresh(() => error =
                              'Informe início e fim válidos, com fim igual ou posterior ao início.');
                          return;
                        }
                        if (work == null ||
                            tasks
                                    .where((t) => t.edeskWorkNumber == work)
                                    .length !=
                                1) {
                          refresh(() => error =
                              'Selecione uma fase única para relacionar a esta etapa.');
                          return;
                        }
                        Navigator.pop(dialogContext, (
                          start: phaseDay(first),
                          end: phaseDay(last),
                          work: work!
                        ));
                      },
                      child: const Text('Aplicar datas'))
                ],
              )));
}
