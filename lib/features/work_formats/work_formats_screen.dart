import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';

class WorkFormatsScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const WorkFormatsScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
  });

  @override
  State<WorkFormatsScreen> createState() => _WorkFormatsScreenState();
}

class _WorkFormatsScreenState extends State<WorkFormatsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<WorkFormat> _workFormats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkFormats();
  }

  Future<void> _loadWorkFormats() async {
    setState(() => _isLoading = true);
    try {
      final formats = await _firebaseService.getWorkFormats();
      setState(() {
        _workFormats = formats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar modelos: $e')),
        );
      }
    }
  }

  Future<void> _deleteFormat(String id) async {
    try {
      await _firebaseService.deleteWorkFormat(id);
      await _loadWorkFormats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir modelo: $e')),
        );
      }
    }
  }

  void _openFormatDetailDialog({WorkFormat? format}) {
    final isEditing = format != null;
    final idController = TextEditingController(text: format?.id ?? '');
    final nameController = TextEditingController(text: format?.name ?? '');

    // Controladores para inclusão manual do número e do nome da etapa simultaneamente
    final stepOrderController = TextEditingController();
    final stepNameController = TextEditingController();

    final List<Map<String, String>> currentStepsWithOrder = [];

    if (format?.steps != null) {
      for (int i = 0; i < format!.steps.length; i++) {
        final stepData = format.steps[i];
        if (stepData is Map) {
          currentStepsWithOrder.add({
            'order': stepData['order']?.toString() ?? '${i + 1}',
            'name': stepData['name']?.toString() ?? '',
          });
        } else {
          currentStepsWithOrder.add({
            'order': '${i + 1}',
            'name': stepData.toString(),
          });
        }
      }
    }

    // Sugere o próximo número automaticamente ao abrir ou se baseia no total
    if (stepOrderController.text.isEmpty) {
      stepOrderController.text = '${currentStepsWithOrder.length + 1}';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void addStep() {
              final orderText = stepOrderController.text.trim();
              final nameText = stepNameController.text.trim();

              if (nameText.isNotEmpty) {
                setDialogState(() {
                  currentStepsWithOrder.add({
                    'order': orderText.isEmpty
                        ? '${currentStepsWithOrder.length + 1}'
                        : orderText,
                    'name': nameText,
                  });
                  stepNameController.clear();
                  // Prepara o próximo número sugerido de forma inteligente
                  final nextVal =
                      (double.tryParse(orderText.replaceAll(',', '.')) ??
                              currentStepsWithOrder.length.toDouble()) +
                          1.0;
                  stepOrderController.text = nextVal % 1 == 0
                      ? nextVal.toInt().toString()
                      : nextVal.toString();
                });
              }
            }

            void removeStep(int index) {
              setDialogState(() {
                currentStepsWithOrder.removeAt(index);
              });
            }

            void editStep(int index) {
              final currentEntry = currentStepsWithOrder[index];
              final editController =
                  TextEditingController(text: currentEntry['name']);
              final orderController =
                  TextEditingController(text: currentEntry['order']);

              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    backgroundColor: const Color(0xFF1E1E2C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: const Text(
                      'Editar Etapa e Número',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    content: SizedBox(
                      width: 350,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: orderController,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*[.,]?\d{0,5}'))
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Número / Posição (Ex: 01, 3)',
                              labelStyle: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white30),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0xFF00B4D8)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: editController,
                            style: const TextStyle(color: Colors.white),
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Descrição da Etapa',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white30),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: Color(0xFF00B4D8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar',
                            style: TextStyle(color: Colors.white60)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B4D8),
                        ),
                        onPressed: () {
                          final newText = editController.text.trim();
                          final newOrder = orderController.text.trim();

                          if (newText.isNotEmpty && newOrder.isNotEmpty) {
                            setDialogState(() {
                              currentStepsWithOrder[index] = {
                                'order': newOrder,
                                'name': newText,
                              };
                            });
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Salvar',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  );
                },
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF2B2B3D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing
                        ? 'Detalhes do Modelo / Trabalhos'
                        : 'Novo Modelo de Projeto',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: idController,
                              enabled: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'ID',
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white30),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF00B4D8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Nome do Tipo de Projeto',
                                labelStyle: TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white30),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF00B4D8),
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
                            'Trabalhos Internos (Etapas):',
                            style: TextStyle(
                              color: Color(0xFF00B4D8),
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
                              color: const Color(0xFF1E1E2C),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Total: ${currentStepsWithOrder.length}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Linha de cadastro com campo de Número e Nome lado a lado
                      Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: stepOrderController,
                              style: const TextStyle(color: Colors.white),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*[.,]?\d{0,5}'))
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Nº',
                                labelStyle: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                isDense: true,
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Color(0xFF00B4D8)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: stepNameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Descrição da Etapa (ex: Contato)',
                                hintStyle: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                                isDense: true,
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF00B4D8),
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => addStep(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00B4D8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                            ),
                            onPressed: addStep,
                            icon: const Icon(
                              Icons.add,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Incluir',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: currentStepsWithOrder.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child: Text(
                                    'Nenhum trabalho cadastrado para este tipo.',
                                    style: TextStyle(color: Colors.white38),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: currentStepsWithOrder.length,
                                separatorBuilder: (_, __) => const Divider(
                                  color: Colors.white10,
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final entry = currentStepsWithOrder[index];

                                  return InkWell(
                                    key: ValueKey('${entry['name']}-$index'),
                                    onTap: () => editStep(index),
                                    child: ListTile(
                                      leading: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00B4D8),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          entry['order'] ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        entry['name'] ?? '',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              color: Colors.white70,
                                              size: 18,
                                            ),
                                            onPressed: () => editStep(index),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent,
                                              size: 20,
                                            ),
                                            onPressed: () => removeStep(index),
                                          ),
                                        ],
                                      ),
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4D8),
                  ),
                  onPressed: () async {
                    if (idController.text.trim().isEmpty ||
                        nameController.text.trim().isEmpty) {
                      return;
                    }

                    if (isEditing && format.id != idController.text.trim()) {
                      try {
                        await _firebaseService.deleteWorkFormat(format.id);
                      } catch (_) {}
                    }

                    final updatedFormat = WorkFormat(
                      id: idController.text.trim(),
                      name: nameController.text.trim(),
                      steps: currentStepsWithOrder,
                    );

                    try {
                      await _firebaseService.saveWorkFormat(updatedFormat);
                      if (context.mounted) {
                        Navigator.pop(context);
                        _loadWorkFormats();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao salvar: $e')),
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Salvar alterações',
                    style: TextStyle(
                      color: Colors.white,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (String value) {},
          userName: '',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cadastro de Trabalho (Modelos de Projetos)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4D8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _openFormatDetailDialog(),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Novo Modelo',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B3D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1B4965),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              'ID Modelo',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: Text(
                              'Nº Trabalhos',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Tipos de Projetos',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              'Ações',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF00B4D8),
                              ),
                            )
                          : _workFormats.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Nenhum modelo cadastrado.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _workFormats.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    color: Colors.white10,
                                    height: 1,
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = _workFormats[index];
                                    return InkWell(
                                      onTap: () => _openFormatDetailDialog(
                                        format: item,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 14,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 80,
                                              child: Text(
                                                item.id,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                '${item.workCount}',
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 100,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.edit,
                                                      color: Colors.white70,
                                                      size: 20,
                                                    ),
                                                    onPressed: () =>
                                                        _openFormatDetailDialog(
                                                      format: item,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.delete,
                                                      color: Colors.redAccent,
                                                      size: 20,
                                                    ),
                                                    onPressed: () =>
                                                        _deleteFormat(item.id),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
