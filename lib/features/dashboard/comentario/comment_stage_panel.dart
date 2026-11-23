import 'package:flutter/material.dart';
import 'comment_stage.dart';

class CommentStagePanel extends StatefulWidget {
  const CommentStagePanel(
      {super.key,
      required this.load,
      required this.onSelected,
      required this.allowed,
      this.autoLoad = false,
      this.compact = false,
      this.currentStageName,
      this.editorChanges,
      this.onInvalidated,
      this.disabled = false});
  final Future<List<CommentStage>> Function() load;
  final ValueChanged<CommentStage> onSelected;
  final bool Function() allowed;
  final bool disabled;
  final bool autoLoad;
  final bool compact;
  final String? Function()? currentStageName;
  final Listenable? editorChanges;
  final VoidCallback? onInvalidated;
  @override
  State<CommentStagePanel> createState() => _CommentStagePanelState();
}

class _CommentStagePanelState extends State<CommentStagePanel> {
  List<CommentStage> stages = [];
  CommentStage? selected;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    widget.editorChanges?.addListener(syncFromEditor);
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CommentStagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorChanges != widget.editorChanges) {
      oldWidget.editorChanges?.removeListener(syncFromEditor);
      widget.editorChanges?.addListener(syncFromEditor);
    }
  }

  @override
  void dispose() {
    widget.editorChanges?.removeListener(syncFromEditor);
    super.dispose();
  }

  void selectStage(CommentStage stage) {
    if (!mounted || !widget.allowed() || widget.disabled) return;
    setState(() => selected = stage);
    widget.onSelected(stage);
  }

  void syncFromEditor() {
    if (!mounted || loading || widget.disabled || !widget.allowed() ||
        widget.currentStageName == null || stages.isEmpty) return;
    final name = normalizeCommentStageName(widget.currentStageName!() ?? '');
    final matches = stages.where((s) => normalizeCommentStageName(s.name) == name).toList();
    if (matches.length != 1) {
      if (selected != null) {
        setState(() => selected = null);
        widget.onInvalidated?.call();
      }
      return;
    }
    if (selected?.name != matches.single.name) selectStage(matches.single);
  }

  Future<void> load() async {
    if (loading || widget.disabled || !widget.allowed()) return;
    widget.onInvalidated?.call();
    setState(() {
      loading = true;
      error = null;
      stages = [];
      selected = null;
    });
    try {
      final result = await widget.load();
      if (!mounted || !widget.allowed()) return;
      setState(() => stages = result);
    } catch (e) {
      if (mounted && widget.allowed()) {
        setState(() => error = 'Não foi possível carregar as etapas. $e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        syncFromEditor();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              key: ValueKey('${identityHashCode(stages)}-${selected?.name}'),
              initialValue: selected?.name,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Etapa do comentário',
                  isDense: true, border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              hint: Text(loading ? 'Lendo etapas…' : 'Selecionar etapa'),
              items: stages.map((s) => DropdownMenuItem(value: s.name,
                  child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: loading || widget.disabled || !widget.allowed() ? null : (name) {
                if (name != null) selectStage(stages.singleWhere((s) => s.name == name));
              })),
            if (selected != null) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(message: 'Fim: ${selected!.date} • Realizado: ${selected!.percent}',
                  child: Text(selected!.percent, style: const TextStyle(fontWeight: FontWeight.w600)))),
            IconButton(tooltip: 'Atualizar etapas da planilha',
              onPressed: loading || widget.disabled ? null : load,
              icon: loading ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 20)),
          ]),
          if (error != null) Text(error!, style: TextStyle(color: colors.error, fontSize: 12)),
        ]));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                      key: ValueKey('${identityHashCode(stages)}-${selected?.name}'),
                      initialValue: selected?.name,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Etapa do comentário',
                          isDense: true,
                          border: OutlineInputBorder()),
                      hint: const Text('Carregue as etapas da planilha'),
                      items: stages
                          .map((s) => DropdownMenuItem(
                              value: s.name,
                              child: Text(s.name,
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: loading || widget.disabled || !widget.allowed()
                          ? null
                          : (name) {
                              if (name == null || !widget.allowed()) return;
                              final stage =
                                  stages.singleWhere((s) => s.name == name);
                              selectStage(stage);
                            })),
              if (selected != null)
                Text(
                    'Fim: ${selected!.date}   •   Realizado: ${selected!.percent}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              TextButton.icon(
                  onPressed: loading || widget.disabled ? null : load,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  label: Text(loading
                      ? 'Lendo Status Projeto…'
                      : stages.isEmpty
                          ? 'Carregar etapas'
                          : 'Atualizar etapas')),
            ]),
        const SizedBox(height: 6),
        Text(
            error ??
                (selected == null
                    ? 'Escolha uma etapa para preencher nome, finalização e percentual no texto.'
                    : 'Dados da tabela Status Projeto aplicados ao texto. Agenda e demais informações preservadas.'),
            style: TextStyle(
                fontSize: 12,
                color: error == null ? colors.onSurfaceVariant : colors.error)),
      ]),
    );
  }
}
