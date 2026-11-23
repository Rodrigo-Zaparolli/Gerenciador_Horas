import 'package:flutter/material.dart';
import '../../../data/services/native_local_files_service.dart';
import 'catalog_worksheet_roles.dart';

typedef CatalogFileRequest = Future<Map<String, dynamic>>
    Function(String action, {String? reference});

bool validCatalogRange(String value) {
  final match = RegExp(r'^([A-Z]{1,3})([1-9][0-9]*):([A-Z]{1,3})([1-9][0-9]*)$')
      .firstMatch(value.trim().toUpperCase());
  if (match == null) return false;
  int col(String text) => text.codeUnits.fold(0, (sum, c) => sum * 26 + c - 64);
  final left = col(match[1]!), right = col(match[3]!);
  final top = int.parse(match[2]!), bottom = int.parse(match[4]!);
  return left <= right &&
      top <= bottom &&
      right <= 16384 &&
      bottom <= 1048576 &&
      (right - left + 1) * (bottom - top + 1) <= 600;
}

class CatalogPanelSettings extends StatefulWidget {
  const CatalogPanelSettings(
      {super.key,
      required this.initial,
      required this.mainReference,
      required this.mainSheets,
      required this.onChanged,
      this.request});
  final Map<String, String> initial;
  final String mainReference;
  final List<String> mainSheets;
  final void Function(Map<String, String>, bool) onChanged;
  final CatalogFileRequest? request;
  @override
  State<CatalogPanelSettings> createState() => _CatalogPanelSettingsState();
}

class _CatalogPanelSettingsState extends State<CatalogPanelSettings> {
  late bool enabled = widget.initial['catalogEnabled'] == 'true';
  late bool external = widget.initial['catalogSource'] == 'external';
  late String reference = widget.initial['catalogReference'] ?? '';
  late String sheet =
      widget.initial['catalogSheet'] ?? 'Cronograma Treinamento Catalog';
  late String checklistSheet = catalogChecklistSheet(widget.initial);
  late final range =
      TextEditingController(text: widget.initial['catalogRange'] ?? 'B34:I38');
  List<String> sheets = [];
  bool loading = false;
  String? error;
  int generation = 0;
  Future<Map<String, dynamic>> call(String action, {String? reference}) =>
      widget.request != null
          ? widget.request!(action, reference: reference)
          : NativeLocalFiles.call(action, reference: reference);
  void emit() => widget.onChanged(
          {
            'catalogEnabled': '$enabled',
            'catalogSource': external ? 'external' : 'main',
            'catalogReference': reference,
            'catalogSheet': sheet,
            'catalogChecklistSheet': checklistSheet,
            'catalogRange': range.text.trim().toUpperCase(),
          },
          !enabled ||
              (!loading &&
                  error == null &&
                  sheets.contains(sheet) &&
                  catalogChecklistOptions(sheets).contains(checklistSheet) &&
                  validCatalogRange(range.text) &&
                  (!external || reference.isNotEmpty)));
  @override
  void initState() {
    super.initState();
    sheets = external ? [] : widget.mainSheets;
    if (enabled) WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    generation++;
    range.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final epoch = ++generation;
    if (!external) {
      setState(() {
        sheets = widget.mainSheets;
        loading = false;
        error = null;
      });
      emit();
      return;
    }
    if (reference.isEmpty) {
      setState(() {
        sheets = [];
        loading = false;
        error = null;
      });
      emit();
      return;
    }
    setState(() {
      loading = true;
      error = null;
      sheets = [];
    });
    emit();
    try {
      final result = await call('excel-editor-sheets', reference: reference);
      if (!mounted || epoch != generation) return;
      setState(() {
        sheets =
            (result['sheetNames'] as List? ?? []).whereType<String>().toList();
        loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != generation) return;
      setState(() {
        loading = false;
        error =
            'Não foi possível listar as abas. Confira a integração e o arquivo.';
      });
    }
    emit();
  }

  Future<void> pick() async {
    setState(() {
      loading = true;
      error = null;
    });
    emit();
    try {
      final result = await call('pick-file');
      if (!mounted) return;
      final selected = result['reference'];
      if (selected is String && selected.isNotEmpty) reference = selected;
      await refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Não foi possível selecionar a planilha.';
      });
      emit();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exibir Treinamento Catalog'),
                value: enabled,
                onChanged: loading
                    ? null
                    : (value) {
                        setState(() => enabled = value);
                        emit();
                        if (enabled) refresh();
                      }),
            if (enabled) ...[
              DropdownButtonFormField<bool>(
                  initialValue: external,
                  decoration:
                      const InputDecoration(labelText: 'Origem do treinamento'),
                  items: const [
                    DropdownMenuItem(
                        value: false, child: Text('Mesma planilha')),
                    DropdownMenuItem(value: true, child: Text('Outra planilha'))
                  ],
                  onChanged: loading
                      ? null
                      : (value) {
                          setState(() => external = value!);
                          refresh();
                        }),
              if (external) ...[
                const SizedBox(height: 8),
                Text(
                    reference.isEmpty
                        ? 'Nenhuma planilha vinculada.'
                        : reference,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                TextButton.icon(
                    onPressed: loading ? null : pick,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Selecionar planilha do Catalog')),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  key: ValueKey(sheets.join('|') + sheet),
                  initialValue: sheets.contains(sheet) ? sheet : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Aba do cronograma (datas e horas)'),
                  items: sheets
                      .map((name) => DropdownMenuItem(
                          value: name,
                          child: Text(name, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: loading
                      ? null
                      : (value) {
                          setState(() => sheet = value!);
                          emit();
                        }),
              const SizedBox(height: 12),
              TextField(
                  controller: range,
                  enabled: !loading,
                  decoration: InputDecoration(
                      labelText: 'Intervalo da tabela',
                      hintText: 'B34:I38',
                      errorText: validCatalogRange(range.text)
                          ? null
                          : 'Informe um intervalo válido de até 600 células.'),
                  onChanged: (_) {
                    setState(() {});
                    emit();
                  }),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                    'catalog-checklist-${sheets.join('|')}-$checklistSheet'),
                initialValue:
                    catalogChecklistOptions(sheets).contains(checklistSheet)
                        ? checklistSheet
                        : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Aba de tarefas do Catalog'),
                items: catalogChecklistOptions(sheets)
                    .map((name) => DropdownMenuItem(
                        value: name,
                        child: Text(name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: loading
                    ? null
                    : (value) {
                        setState(() => checklistSheet = value!);
                        emit();
                      },
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (external && !loading)
                TextButton(
                    onPressed: refresh, child: const Text('Recarregar abas')),
              const Text(
                  'O vínculo do treinamento não substitui a planilha principal.'),
            ],
          ]);
}
