import 'package:flutter/material.dart';
import '../../domain/models/dashboard_models.dart';
import '../../domain/models/project_model.dart';
import 'task_log_search.dart';

class TaskProjectChoice {
  const TaskProjectChoice(this.id, this.client,
      {this.requests = const {}, this.works = const {}});
  final String id, client;
  final Set<String> requests, works;
  String get label => '$id · $client';
}

/// One entry per parent project, including its works and loaded history.
List<TaskProjectChoice> taskProjectChoices(
    List<ProjectModel> projects, Iterable<TimeLog> logs) {
  final clients = <String, String>{},
      requests = <String, Set<String>>{},
      works = <String, Set<String>>{};
  void add(String id, String client, String request, String? work) {
    if (id.isEmpty) return;
    clients[id] = client;
    requests.putIfAbsent(id, () => {}).add(request);
    if (work != null && work.isNotEmpty)
      works.putIfAbsent(id, () => {}).add('$request/$work');
  }

  for (final log in logs) {
    final parts = log.targetId.replaceAll('_', '/').split('/');
    final request = parts.first.trim();
    final id = log.projectId?.trim().isNotEmpty == true
        ? log.projectId!.trim()
        : request;
    add(id, log.projectName ?? '', request,
        parts.length > 1 ? parts.sublist(1).join('/') : null);
  }
  for (final project in projects) {
    add(project.id.trim(), project.client, project.id.trim(), null);
    for (final task in project.subTasks ?? <TaskModel>[]) {
      add(
          project.id.trim(),
          project.client,
          task.edeskSolicitacao?.trim().isNotEmpty == true
              ? task.edeskSolicitacao!.trim()
              : project.id.trim(),
          task.edeskWorkNumber);
    }
  }
  return [
    for (final id in clients.keys)
      TaskProjectChoice(id, clients[id]!,
          requests: Set.unmodifiable(requests[id] ?? {}),
          works: Set.unmodifiable(works[id] ?? {}))
  ]..sort((a, b) => '${a.client} ${a.id}'
      .toLowerCase()
      .compareTo('${b.client} ${b.id}'.toLowerCase()));
}

class TaskProjectPicker extends StatefulWidget {
  const TaskProjectPicker(
      {super.key,
      required this.loader,
      required this.authorized,
      required this.logs});
  final Future<List<ProjectModel>> Function() loader;
  final bool Function() authorized;
  final List<TimeLog> logs;
  @override
  State<TaskProjectPicker> createState() => _TaskProjectPickerState();
}

class _TaskProjectPickerState extends State<TaskProjectPicker> {
  String search = '';
  List<TaskProjectChoice> choices = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      choices = [];
    });
    try {
      if (!widget.authorized()) throw StateError('Conta alterada.');
      final projects = await widget.loader();
      if (!mounted) return;
      if (!widget.authorized()) throw StateError('Conta alterada.');
      setState(() => choices = taskProjectChoices(projects, widget.logs));
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Não foi possível carregar os projetos. Tente novamente.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = choices
        .where((choice) => taskTextMatches(choice.label, search))
        .toList();
    return AlertDialog(
        title: const Text('Selecionar projeto'),
        contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        content: SizedBox(
            width: 620,
            height: (MediaQuery.sizeOf(context).height * .5).clamp(180, 390),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Inclui todos os trabalhos e etapas do projeto.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => search = value),
                  decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'ID ou cliente')),
              const SizedBox(height: 8),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Wrap(children: [
                  Text(error!),
                  TextButton(
                      onPressed: load, child: const Text('Tentar novamente'))
                ]),
              Expanded(
                  child: ListView(children: [
                ListTile(
                    dense: true,
                    leading: const Icon(Icons.layers_outlined),
                    title: const Text('Todos os projetos'),
                    onTap: () {
                      if (widget.authorized())
                        Navigator.pop(context, const TaskProjectChoice('', ''));
                    }),
                if (!loading && error == null && visible.isEmpty)
                  const ListTile(title: Text('Nenhum projeto encontrado')),
                for (final choice in visible)
                  ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(choice.label,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                          choice.works.isEmpty
                              ? 'Todos os trabalhos'
                              : '${choice.works.length} trabalhos · Todos incluídos',
                          style: const TextStyle(fontSize: 11)),
                      onTap: () {
                        if (widget.authorized()) Navigator.pop(context, choice);
                      }),
              ])),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'))
        ]);
  }
}
