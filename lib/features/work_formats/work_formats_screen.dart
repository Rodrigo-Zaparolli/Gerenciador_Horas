// ===============================================================
// TELA DE CADASTRO DE TRABALHO
// ===============================================================

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class WorkFormatsScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const WorkFormatsScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required String userName,
  });

  @override
  State<WorkFormatsScreen> createState() => _WorkFormatsScreenState();
}

class _WorkFormatsScreenState extends State<WorkFormatsScreen> {
  // =============================================================
  // FIREBASE
  // =============================================================

  final FirebaseService _firebaseService = FirebaseService();

  // =============================================================
  // DADOS
  // =============================================================

  List<WorkFormat> _workFormats = [];

  bool _isLoading = true;
  bool _isExporting = false;
  bool _isImporting = false;

  // =============================================================
  // INIT
  // =============================================================

  @override
  void initState() {
    super.initState();

    _loadWorkFormats();
  }

  // =============================================================
  // CARREGAR MODELOS
  // =============================================================

  Future<void> _loadWorkFormats() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final formats = await _firebaseService.getWorkFormats();

      if (mounted) {
        setState(() {
          _workFormats = formats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar modelos: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  // =============================================================
  // EXPORTAR MODELOS PARA JSON
  // =============================================================

  Future<void> _exportWorkFormats() async {
    if (_isExporting) {
      return;
    }

    if (_workFormats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não existem modelos de trabalho cadastrados para exportar.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final List<Map<String, dynamic>> formatsData = _workFormats.map((format) {
        return {
          'id': format.id,
          'name': format.name,
          'steps': format.steps.map((step) {
            if (step is Map) {
              return Map<String, dynamic>.from(step);
            }

            return {
              'order': format.steps.indexOf(step) + 1,
              'name': step.toString(),
            };
          }).toList(),
        };
      }).toList();

      final Map<String, dynamic> exportData = {
        'format': 'gerenciador_horas_work_formats',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'total': formatsData.length,
        'workFormats': formatsData,
      };

      final String jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(exportData);

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Exportar modelos de trabalho',
        fileName: 'modelos_trabalho.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        return;
      }

      String finalPath = outputPath;

      if (!finalPath.toLowerCase().endsWith('.json')) {
        finalPath = '$finalPath.json';
      }

      final File file = File(finalPath);

      await file.writeAsString(
        jsonString,
        encoding: utf8,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exportação concluída.\nArquivo salvo em:\n$finalPath',
            ),
            backgroundColor: CoresApp.sucesso,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao exportar modelos: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // =============================================================
  // IMPORTAR MODELOS DE JSON
  // =============================================================

  Future<void> _importWorkFormats() async {
    if (_isImporting) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Importar modelos de trabalho',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final PlatformFile pickedFile = result.files.first;

      String jsonString;

      if (pickedFile.bytes != null) {
        jsonString = utf8.decode(
          pickedFile.bytes!,
          allowMalformed: false,
        );
      } else if (pickedFile.path != null) {
        final File file = File(pickedFile.path!);

        jsonString = await file.readAsString(
          encoding: utf8,
        );
      } else {
        throw Exception(
          'Não foi possível acessar o arquivo selecionado.',
        );
      }

      if (jsonString.trim().isEmpty) {
        throw Exception(
          'O arquivo JSON está vazio.',
        );
      }

      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map) {
        throw Exception(
          'Formato de arquivo inválido.',
        );
      }

      final Map<String, dynamic> jsonData = Map<String, dynamic>.from(decoded);

      final dynamic rawFormats = jsonData['workFormats'];

      if (rawFormats is! List) {
        throw Exception(
          'O arquivo não contém a lista de modelos de trabalho.',
        );
      }

      final List<WorkFormat> importedFormats = [];

      for (final dynamic item in rawFormats) {
        if (item is! Map) {
          continue;
        }

        final Map<String, dynamic> data = Map<String, dynamic>.from(item);

        final String id = data['id']?.toString().trim() ?? '';

        final String name = data['name']?.toString().trim() ?? '';

        if (id.isEmpty || name.isEmpty) {
          continue;
        }

        final List<String> steps = [];

        final dynamic rawSteps = data['steps'];

        if (rawSteps is List) {
          for (final dynamic step in rawSteps) {
            if (step is String) {
              final String value = step.trim();

              if (value.isNotEmpty) {
                steps.add(value);
              }
            } else if (step is Map) {
              final Map<String, dynamic> stepMap =
                  Map<String, dynamic>.from(step);

              final dynamic stepName = stepMap['name'] ??
                  stepMap['stage'] ??
                  stepMap['title'] ??
                  stepMap['descricao'] ??
                  stepMap['description'];

              if (stepName != null) {
                final String value = stepName.toString().trim();

                if (value.isNotEmpty) {
                  steps.add(value);
                }
              }
            }
          }
        }

        importedFormats.add(
          WorkFormat(
            id: id,
            name: name,
            steps: steps,
          ),
        );
      }

      if (importedFormats.isEmpty) {
        throw Exception(
          'Nenhum modelo válido foi encontrado no arquivo.',
        );
      }

      // =========================================================
      // CONFIRMAR IMPORTAÇÃO
      // =========================================================

      if (!mounted) {
        return;
      }

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: CoresTelas.fundoModal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(
                color: CoresApp.borda,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CoresApp.primaria.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.file_download_outlined,
                    color: CoresApp.primaria,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Importar modelos',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              'Foram encontrados ${importedFormats.length} '
              'modelo(s) no arquivo.\n\n'
              'Os modelos serão adicionados ou atualizados '
              'na sua conta. Os modelos existentes que não '
              'estiverem no arquivo não serão excluídos.',
              style: const TextStyle(
                color: CoresApp.textoSecundario,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    false,
                  );
                },
                child: const Text(
                  'Cancelar',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CoresApp.primaria,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    true,
                  );
                },
                child: const Text(
                  'Importar',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      // =========================================================
      // SALVAR NO FIREBASE
      // =========================================================

      int importedCount = 0;

      for (final WorkFormat format in importedFormats) {
        await _firebaseService.saveWorkFormat(
          format,
        );

        importedCount++;
      }

      await _loadWorkFormats();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$importedCount modelo(s) importado(s) com sucesso.',
            ),
            backgroundColor: CoresApp.sucesso,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O arquivo selecionado não possui um JSON válido.',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao importar modelos: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  // =============================================================
  // EXCLUIR MODELO
  // =============================================================

  Future<void> _deleteFormat(String id) async {
    try {
      await _firebaseService.deleteWorkFormat(id);

      await _loadWorkFormats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir modelo: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  // =============================================================
  // MODAL DE CADASTRO / EDIÇÃO
  // =============================================================

  void _openFormatDetailDialog({
    WorkFormat? format,
  }) {
    final bool isEditing = format != null;

    final idController = TextEditingController(
      text: format?.id ?? '',
    );

    final nameController = TextEditingController(
      text: format?.name ?? '',
    );

    final stepOrderController = TextEditingController();

    final stepNameController = TextEditingController();

    final List<Map<String, String>> currentStepsWithOrder = [];

    if (format?.steps != null) {
      for (int i = 0; i < format!.steps.length; i++) {
        final stepData = format.steps[i];

        if (stepData is Map) {
          currentStepsWithOrder.add(
            {
              'order': stepData['order']?.toString() ?? '${i + 1}',
              'name': stepData['name']?.toString() ?? '',
            },
          );
        } else {
          currentStepsWithOrder.add(
            {
              'order': '${i + 1}',
              'name': stepData.toString(),
            },
          );
        }
      }
    }

    stepOrderController.text = '${currentStepsWithOrder.length + 1}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            void addStep() {
              final orderText = stepOrderController.text.trim();

              final nameText = stepNameController.text.trim();

              if (nameText.isNotEmpty) {
                setDialogState(
                  () {
                    currentStepsWithOrder.add(
                      {
                        'order': orderText.isEmpty
                            ? '${currentStepsWithOrder.length + 1}'
                            : orderText,
                        'name': nameText,
                      },
                    );

                    stepNameController.clear();

                    final nextVal = (double.tryParse(
                              orderText.replaceAll(
                                ',',
                                '.',
                              ),
                            ) ??
                            currentStepsWithOrder.length.toDouble()) +
                        1.0;

                    stepOrderController.text = nextVal % 1 == 0
                        ? nextVal.toInt().toString()
                        : nextVal.toString();
                  },
                );
              }
            }

            void removeStep(int index) {
              setDialogState(
                () {
                  currentStepsWithOrder.removeAt(index);
                },
              );
            }

            void editStep(int index) {
              final currentEntry = currentStepsWithOrder[index];

              final editController = TextEditingController(
                text: currentEntry['name'],
              );

              final orderController = TextEditingController(
                text: currentEntry['order'],
              );

              showDialog(
                context: dialogContext,
                builder: (editContext) {
                  return AlertDialog(
                    backgroundColor: CoresTelas.fundoModalSecundario,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(
                        color: CoresApp.borda,
                        width: 1,
                      ),
                    ),
                    title: const Text(
                      'Editar Etapa e Posição',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    content: SizedBox(
                      width: 350,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: orderController,
                            style: const TextStyle(
                              color: CoresApp.textoPrincipal,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(
                                  r'^\d*[.,]?\d{0,5}',
                                ),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Número / Posição (Ex: 01, 3)',
                              labelStyle: const TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 12,
                              ),
                              filled: true,
                              fillColor: CoresTelas.campoFormulario,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                                borderSide: const BorderSide(
                                  color: CoresApp.borda,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                                borderSide: const BorderSide(
                                  color: CoresApp.primaria,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: editController,
                            style: const TextStyle(
                              color: CoresApp.textoPrincipal,
                            ),
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Descrição da Etapa',
                              labelStyle: const TextStyle(
                                color: CoresApp.textoSecundario,
                              ),
                              filled: true,
                              fillColor: CoresTelas.campoFormulario,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                                borderSide: const BorderSide(
                                  color: CoresApp.borda,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                                borderSide: const BorderSide(
                                  color: CoresApp.primaria,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(
                            editContext,
                          );
                        },
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.primaria,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              8,
                            ),
                          ),
                        ),
                        onPressed: () {
                          final newText = editController.text.trim();

                          final newOrder = orderController.text.trim();

                          if (newText.isNotEmpty && newOrder.isNotEmpty) {
                            setDialogState(
                              () {
                                currentStepsWithOrder[index] = {
                                  'order': newOrder,
                                  'name': newText,
                                };
                              },
                            );

                            Navigator.pop(
                              editContext,
                            );
                          }
                        },
                        child: const Text(
                          'Salvar',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }

            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(
                  color: CoresApp.borda,
                  width: 1,
                ),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: CoresApp.primaria.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.layers_outlined,
                          color: CoresApp.primaria,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isEditing
                            ? 'Editar Modelo de Projeto'
                            : 'Novo Modelo de Projeto',
                        style: const TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: CoresApp.textoSecundario,
                    ),
                    onPressed: () {
                      Navigator.pop(
                        dialogContext,
                      );
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: idController,
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                              ),
                              decoration: InputDecoration(
                                labelText: 'ID',
                                labelStyle: const TextStyle(
                                  color: CoresApp.textoSecundario,
                                ),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.borda,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.primaria,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Nome do Tipo de Projeto',
                                labelStyle: const TextStyle(
                                  color: CoresApp.textoSecundario,
                                ),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.borda,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.primaria,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Trabalhos Internos (Etapas)',
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: CoresApp.primaria.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CoresApp.primaria.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              'Total: ${currentStepsWithOrder.length}',
                              style: const TextStyle(
                                color: CoresApp.primaria,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 85,
                            child: TextField(
                              controller: stepOrderController,
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(
                                    r'^\d*[.,]?\d{0,5}',
                                  ),
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Nº',
                                labelStyle: const TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12,
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.borda,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.primaria,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: stepNameController,
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Descrição da Etapa (ex: Contato)',
                                hintStyle: const TextStyle(
                                  color: CoresApp.textoFraco,
                                  fontSize: 13,
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.borda,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                  borderSide: const BorderSide(
                                    color: CoresApp.primaria,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) {
                                addStep();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.primaria,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                              ),
                            ),
                            onPressed: addStep,
                            icon: const Icon(
                              Icons.add,
                              size: 18,
                              color: CoresApp.textoPrincipal,
                            ),
                            label: const Text(
                              'Incluir',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(
                          maxHeight: 250,
                        ),
                        decoration: BoxDecoration(
                          color: CoresApp.fundoSecundario,
                          borderRadius: BorderRadius.circular(
                            10,
                          ),
                          border: Border.all(
                            color: CoresApp.borda,
                          ),
                        ),
                        child: currentStepsWithOrder.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    24.0,
                                  ),
                                  child: Text(
                                    'Nenhum trabalho cadastrado para este tipo.',
                                    style: TextStyle(
                                      color: CoresApp.textoFraco,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: currentStepsWithOrder.length,
                                separatorBuilder: (_, __) => const Divider(
                                  color: CoresApp.bordaSuave,
                                  height: 1,
                                ),
                                itemBuilder: (
                                  context,
                                  index,
                                ) {
                                  final entry = currentStepsWithOrder[index];

                                  return ListTile(
                                    key: ValueKey(
                                      '${entry['name']}-$index',
                                    ),
                                    onTap: () {
                                      editStep(
                                        index,
                                      );
                                    },
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CoresApp.primaria,
                                        borderRadius: BorderRadius.circular(
                                          6,
                                        ),
                                      ),
                                      child: Text(
                                        entry['order'] ?? '',
                                        style: const TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      entry['name'] ?? '',
                                      style: const TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: CoresApp.textoSecundario,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            editStep(
                                              index,
                                            );
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: CoresApp.erro,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            removeStep(
                                              index,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    if (idController.text.trim().isEmpty ||
                        nameController.text.trim().isEmpty) {
                      return;
                    }

                    if (isEditing && format.id != idController.text.trim()) {
                      try {
                        await _firebaseService.deleteWorkFormat(
                          format.id,
                        );
                      } catch (_) {}
                    }

                    final updatedFormat = WorkFormat(
                      id: idController.text.trim(),
                      name: nameController.text.trim(),
                      steps: currentStepsWithOrder,
                    );

                    try {
                      await _firebaseService.saveWorkFormat(
                        updatedFormat,
                      );

                      if (dialogContext.mounted) {
                        Navigator.pop(
                          dialogContext,
                        );

                        await _loadWorkFormats();
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(
                          dialogContext,
                        ).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Erro ao salvar: $e',
                            ),
                            backgroundColor: CoresApp.erro,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Salvar alterações',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =============================================================
  // BUILD
  // =============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (String value) {},
          userName: '',
        ),
      ),
      body: Container(
        color: Colors.transparent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =================================================
              // CABEÇALHO DA PÁGINA
              // =================================================

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: CoresApp.primaria,
                          borderRadius: BorderRadius.circular(
                            2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Cadastro de Trabalho (Modelos de Projetos)',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: CoresApp.textoPrincipal,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),

                  // =================================================
                  // BOTÕES
                  // =================================================

                  Row(
                    children: [
                      // =============================================
                      // IMPORTAR
                      // =============================================

                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CoresApp.textoPrincipal,
                          side: const BorderSide(
                            color: CoresApp.borda,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ),
                          ),
                        ),
                        onPressed: _isImporting ? null : _importWorkFormats,
                        icon: _isImporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CoresApp.primaria,
                                ),
                              )
                            : const Icon(
                                Icons.file_upload_outlined,
                                color: CoresApp.primaria,
                              ),
                        label: const Text(
                          'Importar',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // =============================================
                      // EXPORTAR
                      // =============================================

                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CoresApp.textoPrincipal,
                          side: const BorderSide(
                            color: CoresApp.borda,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ),
                          ),
                        ),
                        onPressed: _isExporting ? null : _exportWorkFormats,
                        icon: _isExporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: CoresApp.primaria,
                                ),
                              )
                            : const Icon(
                                Icons.file_download_outlined,
                                color: CoresApp.primaria,
                              ),
                        label: const Text(
                          'Exportar',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // =============================================
                      // NOVO MODELO
                      // =============================================

                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.primaria,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 16,
                          ),
                          elevation: 4,
                          shadowColor: CoresApp.primaria.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ),
                          ),
                        ),
                        onPressed: () {
                          _openFormatDetailDialog();
                        },
                        icon: const Icon(
                          Icons.add_rounded,
                          color: CoresApp.textoPrincipal,
                        ),
                        label: const Text(
                          'Novo Modelo',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // =================================================
              // TABELA
              // =================================================

              Container(
                decoration: BoxDecoration(
                  color: CoresDashboard.card,
                  borderRadius: BorderRadius.circular(
                    16,
                  ),
                  border: Border.all(
                    color: CoresApp.borda,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: CoresDashboard.cabecalhoTabela,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(
                            16,
                          ),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: CoresApp.borda,
                            width: 1,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              'ID MODELO',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              'Nº TRABALHOS',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'TIPOS DE PROJETOS',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(
                              'AÇÕES',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(
                              50.0,
                            ),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: CoresApp.primaria,
                              ),
                            ),
                          )
                        : _workFormats.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(
                                  50.0,
                                ),
                                child: Center(
                                  child: Text(
                                    'Nenhum modelo cadastrado no momento.',
                                    style: TextStyle(
                                      color: CoresApp.textoSecundario,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _workFormats.length,
                                separatorBuilder: (
                                  _,
                                  __,
                                ) =>
                                    const Divider(
                                  color: CoresApp.bordaSuave,
                                  height: 1,
                                ),
                                itemBuilder: (
                                  context,
                                  index,
                                ) {
                                  final item = _workFormats[index];

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        _openFormatDetailDialog(
                                          format: item,
                                        );
                                      },
                                      hoverColor: CoresDashboard.cardHover,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 2,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 100,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      CoresApp.fundoSecundario,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    6,
                                                  ),
                                                  border: Border.all(
                                                    color: CoresApp.borda,
                                                  ),
                                                ),
                                                child: Text(
                                                  item.id,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 10,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: CoresApp.primaria
                                                          .withOpacity(
                                                        0.1,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        12,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${item.workCount}',
                                                      style: const TextStyle(
                                                        color:
                                                            CoresApp.primaria,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: const TextStyle(
                                                  color:
                                                      CoresApp.textoPrincipal,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 110,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    tooltip: 'Editar',
                                                    icon: const Icon(
                                                      Icons.edit_outlined,
                                                      color: CoresApp
                                                          .textoSecundario,
                                                      size: 18,
                                                    ),
                                                    onPressed: () {
                                                      _openFormatDetailDialog(
                                                        format: item,
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Excluir',
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: CoresApp.erro,
                                                      size: 18,
                                                    ),
                                                    onPressed: () {
                                                      _deleteFormat(
                                                        item.id,
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
