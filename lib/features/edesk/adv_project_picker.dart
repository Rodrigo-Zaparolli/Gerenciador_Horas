import 'package:flutter/material.dart';
import '../../domain/models/project_model.dart';
import '../../data/services/firebase_service.dart';

Future<ProjectModel?> showAdvProjectPicker(BuildContext context,
    {required bool Function() authorized,
    Future<List<ProjectModel>> Function()? loader}) => showDialog<ProjectModel>(
      context: context, builder: (_) => AdvProjectPicker(
        authorized: authorized, loader: loader ?? FirebaseService().getProjects));

class AdvProjectPicker extends StatefulWidget {
  const AdvProjectPicker({super.key, required this.authorized, required this.loader});
  final bool Function() authorized;
  final Future<List<ProjectModel>> Function() loader;
  @override
  State<AdvProjectPicker> createState() => _AdvProjectPickerState();
}

class _AdvProjectPickerState extends State<AdvProjectPicker> {
  final search = TextEditingController();
  List<ProjectModel> projects = [];
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  Future<void> load() async {
    if (!widget.authorized()) {
      setState(() { loading = false; error = 'Sua conta mudou. Abra novamente.'; });
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      final loaded = await widget.loader();
      if (!mounted) return;
      if (!widget.authorized()) throw StateError('Sua conta mudou. Abra novamente.');
      setState(() => projects = loaded);
    } catch (_) {
      if (mounted) setState(() { projects = []; error = 'Não foi possível carregar os projetos. Tente novamente.'; });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final visible = projects.where((p) => '${p.id} ${p.client} ${p.serviceType}'.toLowerCase().contains(query)).toList();
    return AlertDialog(
      title: const Text('Abrir trabalho ADV — escolher projeto'),
      content: SizedBox(width: 600, height: 380, child: Column(children: [
        TextField(controller: search, autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar cliente ou ID da solicitação'),
          onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (error != null) TextButton(onPressed: load, child: const Text('Tentar novamente')),
        Expanded(child: visible.isEmpty && !loading && error == null
          ? const Center(child: Text('Nenhum projeto encontrado.'))
          : ListView.builder(itemCount: visible.length, itemBuilder: (_, index) {
            final project = visible[index];
            return ListTile(title: Text(project.client), subtitle: Text('${project.id} · ${project.serviceType}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: !widget.authorized() ? null : () => Navigator.pop(context, project));
          })),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
