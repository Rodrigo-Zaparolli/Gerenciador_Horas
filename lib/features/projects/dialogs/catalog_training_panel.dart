import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../data/services/project_excel_preview_service.dart';

class CatalogTrainingPanel extends StatefulWidget {
  const CatalogTrainingPanel(
      {super.key,
      required this.reference,
      required this.sheet,
      required this.range,
      this.request});
  final String reference, sheet, range;
  final NativeExcelRequest? request;
  @override
  State<CatalogTrainingPanel> createState() => _CatalogTrainingPanelState();
}

class _CatalogTrainingPanelState extends State<CatalogTrainingPanel> {
  Uint8List? image;
  String? error;
  bool loading = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant CatalogTrainingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.sheet != widget.sheet ||
        oldWidget.range != widget.range) load();
  }

  Future<void> load() async {
    final epoch = ++generation;
    setState(() {
      loading = true;
      error = null;
      image = null;
    });
    try {
      final encoded =
          await ProjectExcelPreviewService(nativeRequest: widget.request)
              .renderRangeAsBase64(
                  fileReference: widget.reference,
                  rangeReference:
                      "'${widget.sheet.replaceAll("'", "''")}'!${widget.range}",
                  preserveLayout: true);
      final bytes = base64Decode(
          encoded.contains(',') ? encoded.split(',').last : encoded);
      if (!mounted || epoch != generation) return;
      setState(() {
        image = bytes;
        loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != generation) return;
      setState(() {
        loading = false;
        error =
            'Não foi possível ler o treinamento. Confira o arquivo vinculado e a integração local.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Icon(Icons.school_outlined),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('Treinamento Catalog',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(
                      tooltip: 'Atualizar treinamento',
                      onPressed: loading ? null : load,
                      icon: const Icon(Icons.refresh))
                ]),
                Text('${widget.sheet} · ${widget.range}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (image != null)
                  Image.memory(image!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                          'A imagem retornada pela integração não é válida.')),
                const SizedBox(height: 6),
                const Text(
                    'Tabela original calculada pelo Excel. Use Atualizar treinamento após alterações no arquivo.',
                    style: TextStyle(fontSize: 12)),
              ])));
}
