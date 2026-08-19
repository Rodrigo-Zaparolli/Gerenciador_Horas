import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';

class ChecklistProjectDialog extends StatefulWidget {
  final ProjectModel project;
  final FirebaseService firebaseService;
  final VoidCallback onProjectUpdated;

  const ChecklistProjectDialog({
    super.key,
    required this.project,
    required this.firebaseService,
    required this.onProjectUpdated,
  });

  @override
  State<ChecklistProjectDialog> createState() => _ChecklistProjectDialogState();
}

class _ChecklistProjectDialogState extends State<ChecklistProjectDialog> {
  late List<Map<String, dynamic>> _checklistItems;
  final TextEditingController _newItemController = TextEditingController();
  final TextEditingController _newItemOrderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checklistItems = widget.project.checklist != null
        ? List<Map<String, dynamic>>.from(widget.project.checklist!
            .map((item) => Map<String, dynamic>.from(item)))
        : [];

    _newItemOrderController.text = '${_checklistItems.length + 1}';
  }

  @override
  void dispose() {
    _newItemController.dispose();
    _newItemOrderController.dispose();
    super.dispose();
  }

  double get _progressPercentage {
    if (_checklistItems.isEmpty) return 0.0;
    int completedCount =
        _checklistItems.where((item) => item['completed'] == true).length;
    return completedCount / _checklistItems.length;
  }

  void _addItem() {
    final name = _newItemController.text.trim();
    final order = _newItemOrderController.text.trim();

    if (name.isNotEmpty) {
      setState(() {
        _checklistItems.add({
          'order': order.isEmpty ? '${_checklistItems.length + 1}' : order,
          'name': name,
          'completed': false,
        });
        _newItemController.clear();
        final nextVal = (double.tryParse(order.replaceAll(',', '.')) ??
                _checklistItems.length.toDouble()) +
            1.0;
        _newItemOrderController.text =
            nextVal % 1 == 0 ? nextVal.toInt().toString() : nextVal.toString();
      });
    }
  }

  Future<void> _importChecklistModel() async {
    try {
      final formats = await widget.firebaseService.getChecklistFormats();
      if (!mounted) return;

      if (formats.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nenhum modelo de check list cadastrado.')),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: CoresTelas.fundoModal,
            title: Text('Selecionar Modelo de Check List',
                style: TextStyle(color: CoresApp.textoPrincipal, fontSize: 16)),
            content: SizedBox(
              width: 400,
              height: 300,
              child: ListView.builder(
                itemCount: formats.length,
                itemBuilder: (context, index) {
                  final ChecklistFormat format = formats[index];
                  return ListTile(
                    title: Text(format.name,
                        style: TextStyle(color: CoresApp.textoPrincipal)),
                    subtitle: Text('${format.items.length} itens',
                        style: TextStyle(
                            color: CoresApp.textoSecundario, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        for (var item in format.items) {
                          _checklistItems.add({
                            'order': item['order']?.toString() ??
                                '${_checklistItems.length + 1}',
                            'name': item['name']?.toString() ?? '',
                            'completed': false,
                          });
                        }
                        _newItemOrderController.text =
                            '${_checklistItems.length + 1}';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Modelo "${format.name}" importado com sucesso!')),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancelar',
                    style: TextStyle(color: CoresApp.textoSecundario)),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar modelos: $e')),
        );
      }
    }
  }

  Future<void> _saveChanges() async {
    widget.project.checklist = _checklistItems;
    try {
      await widget.firebaseService.salvarProjeto(widget.project);
      widget.onProjectUpdated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Check list atualizado com sucesso!'),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar check list: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int completedCount =
        _checklistItems.where((item) => item['completed'] == true).length;

    return AlertDialog(
      backgroundColor: CoresTelas.fundoModal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: CoresApp.borda),
      ),
      title: Row(
        children: [
          Icon(Icons.checklist_rounded, color: CoresApp.destaque),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Check List - Projeto ${widget.project.id}',
              style: TextStyle(color: CoresApp.textoPrincipal, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.library_add_rounded, color: CoresApp.destaque),
            tooltip: 'Importar de Modelo',
            onPressed: _importChecklistModel,
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: CoresApp.textoSecundario),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progresso: $completedCount de ${_checklistItems.length} concluídos',
                  style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  '${(_progressPercentage * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: CoresApp.destaque,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progressPercentage,
                backgroundColor: CoresTelas.fundoModalSecundario,
                valueColor: AlwaysStoppedAnimation<Color>(CoresApp.destaque),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _newItemOrderController,
                    style:
                        TextStyle(color: CoresApp.textoPrincipal, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Nº',
                      labelStyle: TextStyle(
                          color: CoresApp.textoSecundario, fontSize: 11),
                      isDense: true,
                      filled: true,
                      fillColor: CoresTelas.campoFormulario,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _newItemController,
                    style:
                        TextStyle(color: CoresApp.textoPrincipal, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Adicionar item avulso...',
                      hintStyle: TextStyle(
                          color: CoresApp.textoSecundario.withOpacity(0.5),
                          fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: CoresTelas.campoFormulario,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _addItem,
                  child: const Text('Adicionar',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: CoresTelas.fundoModalSecundario,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CoresApp.bordaSuave),
                ),
                child: _checklistItems.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum item no check list deste projeto.',
                          style: TextStyle(
                              color: CoresApp.textoSecundario, fontSize: 12),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _checklistItems.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: CoresApp.bordaSuave, height: 1),
                        itemBuilder: (context, index) {
                          final item = _checklistItems[index];
                          final isCompleted = item['completed'] == true;

                          return CheckboxListTile(
                            activeColor: CoresApp.destaque,
                            checkColor: Colors.black,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: CoresApp.destaque.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item['order']?.toString() ?? '',
                                    style: TextStyle(
                                      color: CoresApp.destaque,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item['name']?.toString() ?? '',
                                    style: TextStyle(
                                      color: isCompleted
                                          ? CoresApp.textoSecundario
                                          : CoresApp.textoPrincipal,
                                      fontSize: 12,
                                      decoration: isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            value: isCompleted,
                            onChanged: (bool? value) {
                              setState(() {
                                item['completed'] = value ?? false;
                              });
                            },
                            secondary: IconButton(
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: CoresApp.erro, size: 18),
                              onPressed: () {
                                setState(() {
                                  _checklistItems.removeAt(index);
                                });
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar',
              style: TextStyle(color: CoresApp.textoSecundario)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: CoresApp.destaque,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TamanhosApp.raioBotao)),
          ),
          onPressed: _saveChanges,
          child: const Text('Salvar alterações',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }
}
