import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/personal_reminder_repository.dart';
import '../../domain/models/personal_reminder.dart';

class PersonalReminderController extends ChangeNotifier {
  PersonalReminderController(this.repository, this.authorized,
      {this.clock = DateTime.now}) {
    subscription = repository.watch().listen((value) {
      if (authorized()) {
        items = value;
        error = null;
        notifyListeners();
      }
    }, onError: (_) {
      if (authorized()) {
        error =
            'Não foi possível carregar os lembretes. Confira a conexão e reabra o sistema.';
        notifyListeners();
      }
    });
  }
  final PersonalReminderRepository repository;
  final bool Function() authorized;
  final DateTime Function() clock;
  late final StreamSubscription<List<PersonalReminder>> subscription;
  List<PersonalReminder> items = [];
  String? error;
  bool opened = false, closing = false;
  Completer<void>? closed;
  final seenThisSession = <String>{};
  String popupKey(PersonalReminder reminder) =>
      '${reminderDayKey(clock())}/${reminder.id}/${reminder.revision}';
  bool get hasUnseenDue => items.any(
      (r) => r.needsPopup(clock()) && !seenThisSession.contains(popupKey(r)));
  Future<void> get whenClosed => closed?.future ?? Future.value();
  List<PersonalReminder> get due => items.where((r) => r.due(clock())).toList()
    ..sort((a, b) => a.day.compareTo(b.day));
  List<PersonalReminder> get pending => items.where((r) => !r.done).toList()
    ..sort((a, b) => a.day.compareTo(b.day));
  Future<void> open(BuildContext context, {bool automatic = false}) async {
    if (opened || closing || !authorized()) return;
    opened = true;
    closed = Completer<void>();
    // Only the automatic alert dismisses a day's reminder. Managing reminders
    // must not silently consume a newly created or edited alert.
    final alerted = automatic ? due : <PersonalReminder>[];
    notifyListeners();
    try {
      await showDialog<void>(
          context: context,
          builder: (_) => PersonalReminderCenter(
              controller: this, initialDueOnly: automatic));
      if (authorized() && automatic) {
        seenThisSession.addAll(alerted.map(popupKey));
        await repository.acknowledge(alerted, clock());
      }
    } catch (_) {
      if (authorized()) {
        error = 'Não foi possível confirmar a visualização dos lembretes.';
      }
    } finally {
      opened = false;
      if (closed?.isCompleted == false) closed!.complete();
      if (!closing) notifyListeners();
    }
  }

  @override
  void dispose() {
    closing = true;
    if (closed?.isCompleted == false) closed!.complete();
    subscription.cancel();
    super.dispose();
  }
}

class PersonalReminderScope
    extends InheritedNotifier<PersonalReminderController> {
  const PersonalReminderScope(
      {super.key,
      required PersonalReminderController controller,
      required super.child})
      : super(notifier: controller);
  static PersonalReminderController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PersonalReminderScope>()
      ?.notifier;
}

class PersonalReminderHost extends StatefulWidget {
  const PersonalReminderHost(
      {super.key,
      required this.owner,
      required this.child,
      this.repository,
      this.authorized,
      this.clock = DateTime.now});
  final String owner;
  final Widget child;
  final PersonalReminderRepository? repository;
  final bool Function()? authorized;
  final DateTime Function() clock;
  @override
  State<PersonalReminderHost> createState() => _PersonalReminderHostState();
}

class _PersonalReminderHostState extends State<PersonalReminderHost>
    with WidgetsBindingObserver {
  late PersonalReminderController controller;
  Timer? timer;
  String lastDay = '';
  bool get authorized =>
      widget.authorized?.call() ??
      FirebaseAuth.instance.currentUser?.uid == widget.owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bind();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => check());
  }

  void bind() {
    controller = PersonalReminderController(
        widget.repository ??
            FirebasePersonalReminders(
                widget.owner, () => mounted && authorized),
        () => mounted && authorized,
        clock: widget.clock);
    controller.addListener(schedule);
    schedule();
  }

  bool checkScheduled = false;
  void schedule() {
    if (!mounted || checkScheduled) return;
    checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkScheduled = false;
      if (mounted) check();
    });
    // Stream notifications can arrive while the page is idle. A post-frame
    // callback alone does not request a frame and may wait for a user click.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void check() {
    if (!mounted || !authorized || controller.opened || controller.closing) {
      return;
    }
    final day = reminderDayKey(widget.clock());
    if (lastDay != day) {
      lastDay = day;
      setState(() {});
    }
    if (WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (controller.hasUnseenDue) {
      unawaited(controller.open(context, automatic: true));
    }
  }

  @override
  void didUpdateWidget(covariant PersonalReminderHost old) {
    super.didUpdateWidget(old);
    if (old.owner != widget.owner || old.repository != widget.repository) {
      controller.removeListener(schedule);
      controller.dispose();
      bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(schedule);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PersonalReminderScope(controller: controller, child: widget.child);
}

class PersonalReminderButton extends StatelessWidget {
  const PersonalReminderButton({super.key, this.showLabel = false});
  final bool showLabel;
  @override
  Widget build(BuildContext context) {
    final controller = PersonalReminderScope.of(context);
    if (controller == null || !controller.authorized()) {
      return const SizedBox.shrink();
    }
    final count = controller.due.length;
    if (showLabel) {
      return TextButton.icon(
        onPressed: () => controller.open(context),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 12),
        ),
        icon: Badge(
            isLabelVisible: count > 0,
            child: const Icon(Icons.calendar_month_outlined, size: 17)),
        label: const Text('Minha agenda'),
      );
    }
    return IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        iconSize: 19,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        tooltip: controller.error ??
            'Minha agenda${count > 0 ? ' · $count para conferir' : ''}',
        onPressed: () => controller.open(context),
        icon: Badge(
            isLabelVisible: count > 0,
            child: const Icon(Icons.event_note_outlined)));
  }
}

Future<void> showReminderEditor(
        BuildContext context, PersonalReminderController controller,
        {PersonalReminder? reminder}) =>
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ReminderEditor(controller: controller, reminder: reminder));

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({required this.controller, this.reminder});
  final PersonalReminderController controller;
  final PersonalReminder? reminder;
  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final title = TextEditingController(text: widget.reminder?.title ?? '');
  late final notes = TextEditingController(text: widget.reminder?.notes ?? '');
  late DateTime day =
      widget.reminder?.day ?? DateUtils.dateOnly(widget.controller.clock());
  late TimeOfDay time = widget.reminder?.minuteOfDay != null
      ? TimeOfDay(
          hour: widget.reminder!.minuteOfDay! ~/ 60,
          minute: widget.reminder!.minuteOfDay! % 60)
      : TimeOfDay.fromDateTime(widget.controller.clock());
  late final id = widget.reminder?.id ?? widget.controller.repository.newId();
  late final revision = widget.controller.repository.newId();
  bool busy = false;
  String? error;
  Timer? accountWatch;
  @override
  void initState() {
    super.initState();
    accountWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.controller.authorized()) {
        setState(() {});
        accountWatch?.cancel();
      }
    });
  }

  @override
  void dispose() {
    accountWatch?.cancel();
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !widget.controller.authorized()) return;
    if (title.text.trim().isEmpty ||
        title.text.trim().length > 200 ||
        notes.text.length > 2000) {
      setState(() => error =
          'Preencha o lembrete com até 200 caracteres. A observação aceita até 2000.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.repository.save(
          PersonalReminder(
              id: id,
              title: title.text.trim(),
              day: day,
              minuteOfDay: time.hour * 60 + time.minute,
              notes: notes.text.trim(),
              revision: revision,
              done: widget.reminder?.done ?? false),
          expectedRevision: widget.reminder?.revision);
      if (mounted && widget.controller.authorized()) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          title: Text(
              widget.reminder == null ? 'Novo lembrete' : 'Editar lembrete'),
          content: !widget.controller.authorized()
              ? const Text('A conta mudou. Feche esta janela.')
              : SizedBox(
                  width: 440,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        TextField(
                            key: const ValueKey('reminder-title'),
                            controller: title,
                            enabled: !busy && widget.controller.authorized(),
                            autofocus: true,
                            maxLength: 200,
                            decoration: const InputDecoration(
                                labelText: 'O que lembrar?',
                                hintText:
                                    'Ex.: rever proposta ou aniversário')),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                            key: const ValueKey('reminder-date'),
                            onPressed: busy || !widget.controller.authorized()
                                ? null
                                : () async {
                                    final picked = await showDatePicker(
                                        context: context,
                                        initialDate: day,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100, 12, 31));
                                    if (picked != null &&
                                        mounted &&
                                        widget.controller.authorized()) {
                                      setState(() => day = picked);
                                    }
                                  },
                            icon: const Icon(Icons.calendar_month),
                            label: Text(
                                'Data: ${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}')),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const ValueKey('reminder-time'),
                          onPressed: busy || !widget.controller.authorized()
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                      context: context,
                                      initialTime: time,
                                      builder: (context, child) => MediaQuery(
                                          data: MediaQuery.of(context).copyWith(
                                              alwaysUse24HourFormat: true),
                                          child: child!));
                                  if (picked != null &&
                                      mounted &&
                                      widget.controller.authorized())
                                    setState(() => time = picked);
                                },
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                              'Horário: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                            controller: notes,
                            enabled: !busy && widget.controller.authorized(),
                            maxLines: 3,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                                labelText: 'Observação (opcional)')),
                        const Text(
                            'O aviso aparece no dia e horário escolhidos, com o sistema aberto. Se estiver fechado, aparece na próxima abertura.'),
                        if (error != null)
                          Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        if (busy) const LinearProgressIndicator(),
                      ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed:
                    busy || !widget.controller.authorized() ? null : save,
                child: const Text('Salvar lembrete'))
          ]));
}

class PersonalReminderCenter extends StatefulWidget {
  const PersonalReminderCenter(
      {super.key, required this.controller, this.initialDueOnly = false});
  final PersonalReminderController controller;
  final bool initialDueOnly;
  @override
  State<PersonalReminderCenter> createState() => _PersonalReminderCenterState();
}

class _PersonalReminderCenterState extends State<PersonalReminderCenter> {
  late String filter = widget.initialDueOnly ? 'due' : 'pending';
  bool busy = false;
  String? error;
  Timer? accountWatch;
  @override
  void initState() {
    super.initState();
    accountWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.controller.authorized()) {
        setState(() {});
        accountWatch?.cancel();
      }
    });
  }

  @override
  void dispose() {
    accountWatch?.cancel();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !widget.controller.authorized()) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(PersonalReminder reminder) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Excluir lembrete?'),
                content: Text(reminder.title),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Excluir'))
                ]));
    if (ok == true && mounted) {
      await run(() => widget.controller.repository.remove(reminder));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final entries = controller.items
            .where((r) =>
                filter == 'all' ||
                filter == 'done' && r.done ||
                filter == 'pending' && !r.done ||
                filter == 'due' && r.due(controller.clock()))
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));
        return PopScope(
            canPop: !busy,
            child: AlertDialog(
                title: Text(widget.initialDueOnly
                    ? 'Lembretes de hoje e pendências'
                    : 'Minha agenda'),
                content: SizedBox(
                    width: 850,
                    height: MediaQuery.sizeOf(context).height * .62,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final option in const {
                                  'due': 'Hoje e atrasados',
                                  'pending': 'Pendentes',
                                  'done': 'Concluídos',
                                  'all': 'Todos'
                                }.entries)
                                  ChoiceChip(
                                      label: Text(option.value),
                                      selected: filter == option.key,
                                      onSelected: (_) =>
                                          setState(() => filter = option.key)),
                                FilledButton.icon(
                                    onPressed: busy || !controller.authorized()
                                        ? null
                                        : () => showReminderEditor(
                                            context, controller),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Novo lembrete'))
                              ]),
                          if (controller.error != null) Text(controller.error!),
                          if (error != null) Text(error!),
                          const SizedBox(height: 12),
                          Expanded(
                              child: !controller.authorized()
                                  ? const Center(
                                      child: Text(
                                          'A conta mudou. Feche esta janela.'))
                                  : entries.isEmpty
                                      ? const Center(
                                          child: Text(
                                              'Nenhum lembrete nesta seleção.'))
                                      : ListView.separated(
                                          itemCount: entries.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(),
                                          itemBuilder: (context, index) {
                                            final reminder = entries[index];
                                            final overdue = reminder.day
                                                .isBefore(DateUtils.dateOnly(
                                                    controller.clock()));
                                            return ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Checkbox(
                                                    value: reminder.done,
                                                    onChanged: busy
                                                        ? null
                                                        : (value) => run(() =>
                                                            controller
                                                                .repository
                                                                .complete(
                                                                    reminder,
                                                                    value ==
                                                                        true))),
                                                title: Text(reminder.title,
                                                    style: TextStyle(
                                                        decoration:
                                                            reminder.done
                                                                ? TextDecoration
                                                                    .lineThrough
                                                                : null)),
                                                subtitle: Text(
                                                    '${reminder.dateLabel}${reminder.timeLabel.isEmpty ? '' : ' ? ${reminder.timeLabel}'}${!reminder.done && reminder.due(controller.clock()) ? overdue ? ' · Atrasado' : ' · Hoje' : ''}${reminder.notes.isEmpty ? '' : '\n${reminder.notes}'}'),
                                                trailing: PopupMenuButton<
                                                        String>(
                                                    enabled: !busy,
                                                    onSelected: (action) {
                                                      if (action == 'edit') {
                                                        showReminderEditor(
                                                            context, controller,
                                                            reminder: reminder);
                                                      } else {
                                                        remove(reminder);
                                                      }
                                                    },
                                                    itemBuilder: (_) => const [
                                                          PopupMenuItem(
                                                              value: 'edit',
                                                              child: Text(
                                                                  'Editar')),
                                                          PopupMenuItem(
                                                              value: 'delete',
                                                              child: Text(
                                                                  'Excluir'))
                                                        ]));
                                          })),
                          const SizedBox(height: 8),
                          const Text(
                              'Fechar confirma a visualização de hoje. Lembretes pendentes continuam na lista até serem concluídos.',
                              style: TextStyle(fontSize: 12)),
                          if (busy) const LinearProgressIndicator(),
                        ])),
                actions: [
                  TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('Fechar'))
                ]));
      });
}
