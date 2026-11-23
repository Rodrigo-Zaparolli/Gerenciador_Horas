import 'package:flutter/material.dart';
import '../../domain/models/project_model.dart';
import 'task_log_search.dart';

/// Read-only selection from the same active-project collection as Projetos.
class TaskOpenProjectPicker extends StatefulWidget {
  const TaskOpenProjectPicker({
    super.key,
    required this.loader,
    required this.authorized,
  });
  final Future<List<ProjectModel>> Function() loader;
  final bool Function() authorized;

  @override
  State<TaskOpenProjectPicker> createState() => _TaskOpenProjectPickerState();
}

class _TaskOpenProjectPickerState extends State<TaskOpenProjectPicker> {
  final search = TextEditingController();
  List<ProjectModel> projects = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
      projects = [];
    });
    try {
      if (!widget.authorized()) throw StateError('Conta alterada.');
      final result = await widget.loader();
      if (!mounted) return;
      if (!widget.authorized()) throw StateError('Conta alterada.');
      setState(() => projects = result
          .where((project) => !{'TRAB_FIM', 'TRAB_STOP'}
              .contains(project.status.trim().toUpperCase()))
          .toList()
        ..sort((a, b) =>
            a.client.toLowerCase().compareTo(b.client.toLowerCase())));
    } catch (_) {
      if (mounted) {
        setState(() {
          projects = [];
          error = widget.authorized()
              ? 'Não foi possível carregar os projetos. Tente novamente.'
              : 'A conta mudou. Feche e abra a busca novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = projects
        .where((project) => taskTextMatches(
            '${project.id} ${project.client} ${project.serviceType}',
            search.text))
        .toList();
    return AlertDialog(
      title: const Text('Trabalho aberto — escolher projeto'),
      content: SizedBox(
        width: 600,
        height: MediaQuery.sizeOf(context).height * .5,
        child: Column(children: [
          TextField(
            controller: search,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Pesquisar cliente, ID ou tipo de serviço',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            if (widget.authorized())
              TextButton(
                  onPressed: load, child: const Text('Tentar novamente')),
          ],
          Expanded(
              child: !loading && error == null && visible.isEmpty
                  ? const Center(
                      child: Text('Nenhum projeto em aberto encontrado.'))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) {
                        final project = visible[index];
                        return ListTile(
                          key: ValueKey('open-project-${project.id}'),
                          title: Text(project.client),
                          subtitle:
                              Text('${project.id} · ${project.serviceType}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            if (!widget.authorized()) {
                              setState(() {
                                projects = [];
                                error =
                                    'A conta mudou. Feche e abra a busca novamente.';
                              });
                              return;
                            }
                            Navigator.pop(context, project);
                          },
                        );
                      },
                    )),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'))
      ],
    );
  }
}
