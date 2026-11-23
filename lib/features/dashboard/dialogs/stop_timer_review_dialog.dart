import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../domain/models/dashboard_models.dart';
import '../../../domain/models/work_duration.dart';
import '../../../domain/models/timer_entry_review.dart';

class StopTimerReviewDialog extends StatefulWidget {
  const StopTimerReviewDialog(
      {super.key,
      required this.started,
      required this.stopped,
      required this.workedSeconds,
      required this.target,
      required this.logId,
      required this.label,
      required this.authorized,
      required this.loadWindow,
      required this.save,
      this.clock = DateTime.now});
  final DateTime started, stopped;
  final int workedSeconds;
  final String target, logId, label;
  final bool Function() authorized;
  final Future<List<TimeLog>> Function(DateTime) loadWindow;
  final Future<void> Function(TimerEntryReview) save;
  final DateTime Function() clock;
  @override
  State<StopTimerReviewDialog> createState() => _StopTimerReviewDialogState();
}

class _StopTimerReviewDialogState extends State<StopTimerReviewDialog> {
  late DateTime day = DateUtils.dateOnly(widget.started);
  late final start = TextEditingController(
      text: WorkDuration.format(
          widget.started.hour * 60 + widget.started.minute));
  late final end = TextEditingController(
      text: WorkDuration.format(
          widget.stopped.hour * 60 + widget.stopped.minute));
  final description = TextEditingController();
  final descriptionFocus = FocusNode();
  late final work = TextEditingController(
      text: WorkDuration.format(widget.workedSeconds ~/ 60));
  bool busy = false;
  Timer? accountWatch;
  String? error;
  bool get sameClocks =>
      entryClock(start.text) ==
          widget.started.hour * 60 + widget.started.minute &&
      entryClock(end.text, end: true) ==
          widget.stopped.hour * 60 + widget.stopped.minute;
  int get minutes => entryClock(work.text, end: true) ?? 0;
  String get dateLabel =>
      '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';

  void updateDuration() {
    final begin = entryClock(start.text),
        finish = entryClock(end.text, end: true);
    work.text = sameClocks
        ? WorkDuration.format(widget.workedSeconds ~/ 60)
        : begin != null && finish != null && finish > begin
            ? WorkDuration.format(finish - begin)
            : '';
    setState(() {});
  }

  void insertDate() {
    if (busy || !widget.authorized()) return;
    final prefix = '$dateLabel: - ';
    final text = description.text;
    final existing = text.indexOf(prefix);
    if (existing >= 0) {
      description.selection =
          TextSelection.collapsed(offset: existing + prefix.length);
    } else {
      final position =
          description.selection.isValid ? description.selection.start : 0;
      final insertion =
          '${position > 0 && text[position - 1] != '\n' ? '\n' : ''}$prefix';
      description.value = TextEditingValue(
        text:
            text.substring(0, position) + insertion + text.substring(position),
        selection: TextSelection.collapsed(offset: position + insertion.length),
      );
    }
    descriptionFocus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    accountWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.authorized()) {
        setState(() {});
        accountWatch?.cancel();
      }
    });
  }

  @override
  void dispose() {
    accountWatch?.cancel();
    start.dispose();
    end.dispose();
    description.dispose();
    descriptionFocus.dispose();
    work.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: day.isAfter(widget.clock())
            ? DateUtils.dateOnly(widget.clock())
            : day,
        firstDate: DateTime(2000),
        lastDate: DateUtils.dateOnly(widget.clock()));
    if (picked != null && mounted && widget.authorized())
      setState(() => day = picked);
  }

  Future<void> submit() async {
    if (busy || !widget.authorized()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final entry = TimerEntryReview.parse(
          day: day,
          start: start.text,
          end: end.text,
          minutes: minutes,
          description: description.text,
          now: widget.clock());
      final logs = await widget.loadWindow(entry.day);
      if (!mounted || !widget.authorized())
        throw StateError('A conta mudou. Feche esta janela.');
      final conflict = timerEntryConflict(entry, logs,
          ownId: widget.logId, ownTarget: widget.target);
      if (conflict != null) throw StateError(conflict);
      await widget.save(entry);
      if (mounted && widget.authorized()) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() => error = e
            .toString()
            .replaceFirst('FormatException: ', '')
            .replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget clockField(String label, String key, TextEditingController controller,
          {bool duration = false}) =>
      TextField(
        key: ValueKey(key),
        controller: controller,
        enabled: !busy && widget.authorized(),
        keyboardType: TextInputType.datetime,
        inputFormatters: [CompactClockInputFormatter()],
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
            labelText: label,
            hintText: '00:00',
            isDense: true,
            border: const OutlineInputBorder()),
        onChanged: (_) => duration ? setState(() {}) : updateDuration(),
        onEditingComplete: () {
          final value =
              entryClock(controller.text, end: duration || controller == end);
          if (value != null) controller.text = WorkDuration.format(value);
          FocusScope.of(context).nextFocus();
        },
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('Conferir apontamento'),
          content: !widget.authorized()
              ? const Text('A conta mudou. Feche esta janela.')
              : SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Text(widget.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(
                            'Cron\u00f4metro pausado. Confira os dados antes de salvar.',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton.icon(
                            key: const ValueKey('timer-review-date'),
                            onPressed: busy ? null : pickDate,
                            icon: const Icon(Icons.calendar_month_outlined,
                                size: 18),
                            label: Text(dateLabel),
                          )),
                          const SizedBox(width: 8),
                          TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() =>
                                      day = DateUtils.dateOnly(widget.clock())),
                              child: const Text('Hoje')),
                        ]),
                        const SizedBox(height: 14),
                        LayoutBuilder(builder: (context, constraints) {
                          final clocks = Row(children: [
                            Expanded(
                                child: clockField('In\u00edcio',
                                    'timer-review-start', start)),
                            const SizedBox(width: 10),
                            Expanded(
                                child:
                                    clockField('Fim', 'timer-review-end', end)),
                          ]);
                          final duration = clockField('Dura\u00e7\u00e3o',
                              'timer-review-duration', work,
                              duration: true);
                          if (constraints.maxWidth < 360) {
                            return Column(children: [
                              clocks,
                              const SizedBox(height: 12),
                              duration
                            ]);
                          }
                          return Row(children: [
                            Expanded(flex: 2, child: clocks),
                            const SizedBox(width: 10),
                            Expanded(child: duration)
                          ]);
                        }),
                        const SizedBox(height: 8),
                        Text(
                            'In\u00edcio e fim recalculam a dura\u00e7\u00e3o. Voc\u00ea tamb\u00e9m pode ajust\u00e1-la para descontar pausas.',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (DateUtils.dateOnly(widget.started) !=
                            DateUtils.dateOnly(widget.stopped))
                          const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  'O cron\u00f4metro atravessou datas. Informe um intervalo de um \u00fanico dia.')),
                        const SizedBox(height: 12),
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: const ValueKey('timer-review-insert-date'),
                              onPressed: busy ? null : insertDate,
                              icon: const Icon(Icons.today_outlined, size: 17),
                              label: const Text('Inserir data'),
                            )),
                        TextField(
                          key: const ValueKey('timer-review-description'),
                          controller: description,
                          focusNode: descriptionFocus,
                          enabled: !busy && widget.authorized(),
                          minLines: 4,
                          maxLines: 6,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                              labelText: 'Coment\u00e1rio (opcional)',
                              hintText:
                                  'Descreva a atividade realizada, se desejar.',
                              border: OutlineInputBorder()),
                        ),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        if (busy) const LinearProgressIndicator(),
                      ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: const Text('Voltar ao cron\u00f4metro')),
            FilledButton(
                onPressed: busy || !widget.authorized() ? null : submit,
                child: const Text('Salvar apontamento')),
          ],
        ),
      );
}

/// Wait for all four digits so the colon does not interrupt typing the hour.
class CompactClockInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed ||
        !RegExp(r'^\d{4}$').hasMatch(newValue.text)) return newValue;
    final text =
        '${newValue.text.substring(0, 2)}:${newValue.text.substring(2)}';
    int offset(int value) => value < 0
        ? text.length
        : value <= 2
            ? value
            : value + 1;
    return newValue.copyWith(
        text: text,
        selection: TextSelection(
            baseOffset: offset(newValue.selection.baseOffset),
            extentOffset: offset(newValue.selection.extentOffset),
            affinity: newValue.selection.affinity,
            isDirectional: newValue.selection.isDirectional),
        composing: TextRange.empty);
  }
}
