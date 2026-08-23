import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';

// Tela principal para gerenciamento e cadastro de modelos de projetos e etapas
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
  // Instância do serviço do Firebase para comunicação com o banco de dados
  final FirebaseService _firebaseService = FirebaseService();

  // Lista local para armazenar os modelos de projetos carregados
  List<WorkFormat> _workFormats = [];

  // Controla o estado de carregamento inicial da tela
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkFormats(); // Carrega os dados assim que a tela é iniciada
  }

  // Função assíncrona para buscar os modelos cadastrados no Firebase
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
          SnackBar(
            content: Text('Erro ao carregar modelos: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  // Função assíncrona para excluir um modelo de projeto do Firebase pelo ID
  Future<void> _deleteFormat(String id) async {
    try {
      await _firebaseService.deleteWorkFormat(id);
      await _loadWorkFormats(); // Atualiza a lista após a exclusão
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

  // Abre o diálogo interativo para criar ou editar um modelo de projeto e suas etapas
  void _openFormatDetailDialog({WorkFormat? format}) {
    final isEditing = format != null;
    final idController = TextEditingController(text: format?.id ?? '');
    final nameController = TextEditingController(text: format?.name ?? '');

    final stepOrderController = TextEditingController();
    final stepNameController = TextEditingController();

    final List<Map<String, String>> currentStepsWithOrder = [];

    // Mapeia as etapas existentes caso seja uma edição
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

    if (stepOrderController.text.isEmpty) {
      stepOrderController.text = '${currentStepsWithOrder.length + 1}';
    }

    // Exibe o modal/diálogo de cadastro ou edição moderno
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Função interna para adicionar uma nova etapa à lista temporária
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

            // Função interna para remover uma etapa pelo índice
            void removeStep(int index) {
              setDialogState(() {
                currentStepsWithOrder.removeAt(index);
              });
            }

            // Função interna para abrir sub-diálogo de edição de uma etapa específica
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
                    backgroundColor: CoresTelas.fundoModalSecundario,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: CoresApp.borda, width: 1),
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
                            style:
                                const TextStyle(color: CoresApp.textoPrincipal),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*[.,]?\d{0,5}'))
                            ],
                            decoration: InputDecoration(
                              labelText: 'Número / Posição (Ex: 01, 3)',
                              labelStyle: const TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12),
                              filled: true,
                              fillColor: CoresTelas.campoFormulario,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: CoresApp.borda),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: CoresApp.primaria),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: editController,
                            style:
                                const TextStyle(color: CoresApp.textoPrincipal),
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Descrição da Etapa',
                              labelStyle: const TextStyle(
                                  color: CoresApp.textoSecundario),
                              filled: true,
                              fillColor: CoresTelas.campoFormulario,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: CoresApp.borda),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: CoresApp.primaria),
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
                            style: TextStyle(color: CoresApp.textoSecundario)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.primaria,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                            style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontWeight: FontWeight.bold)),
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
                side: const BorderSide(color: CoresApp.borda, width: 1),
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
                        child: const Icon(Icons.layers_outlined,
                            color: CoresApp.primaria, size: 20),
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
                    icon: const Icon(Icons.close,
                        color: CoresApp.textoSecundario),
                    onPressed: () => Navigator.pop(context),
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
                      // Campos ID e Nome
                      Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: idController,
                              style: const TextStyle(
                                  color: CoresApp.textoPrincipal),
                              decoration: InputDecoration(
                                labelText: 'ID',
                                labelStyle: const TextStyle(
                                    color: CoresApp.textoSecundario),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: CoresApp.borda),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: CoresApp.primaria),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: const TextStyle(
                                  color: CoresApp.textoPrincipal),
                              decoration: InputDecoration(
                                labelText: 'Nome do Tipo de Projeto',
                                labelStyle: const TextStyle(
                                    color: CoresApp.textoSecundario),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: CoresApp.borda),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: CoresApp.primaria),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Título Etapas
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
                                  color: CoresApp.primaria.withOpacity(0.3)),
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

                      // Inserção de Etapas
                      Row(
                        children: [
                          SizedBox(
                            width: 85,
                            child: TextField(
                              controller: stepOrderController,
                              style: const TextStyle(
                                  color: CoresApp.textoPrincipal),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*[.,]?\d{0,5}'))
                              ],
                              decoration: InputDecoration(
                                labelText: 'Nº',
                                labelStyle: const TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 12),
                                isDense: true,
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: CoresApp.borda),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: CoresApp.primaria),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: stepNameController,
                              style: const TextStyle(
                                  color: CoresApp.textoPrincipal),
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
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide:
                                      const BorderSide(color: CoresApp.borda),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: CoresApp.primaria),
                                ),
                              ),
                              onSubmitted: (_) => addStep(),
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
                                borderRadius: BorderRadius.circular(8),
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
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Lista de etapas cadastradas no modal
                      Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: CoresApp.fundoSecundario,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: CoresApp.borda),
                        ),
                        child: currentStepsWithOrder.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child: Text(
                                    'Nenhum trabalho cadastrado para este tipo.',
                                    style:
                                        TextStyle(color: CoresApp.textoFraco),
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
                                itemBuilder: (context, index) {
                                  final entry = currentStepsWithOrder[index];
                                  return ListTile(
                                    key: ValueKey('${entry['name']}-$index'),
                                    onTap: () => editStep(index),
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: CoresApp.primaria,
                                        borderRadius: BorderRadius.circular(6),
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
                                          onPressed: () => editStep(index),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: CoresApp.erro,
                                            size: 18,
                                          ),
                                          onPressed: () => removeStep(index),
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: CoresApp.textoSecundario),
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
                          SnackBar(
                            content: Text('Erro ao salvar: $e'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresDashboard.fundo,
      // Altura ajustada para 60 para corresponder perfeitamente ao Cabecalho
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
      // Corpo principal envolto em um Container com gradiente suave de fundo
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0B0F19),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho da página com visual moderno
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
                          borderRadius: BorderRadius.circular(2),
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
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _openFormatDetailDialog(),
                    icon: const Icon(Icons.add_rounded,
                        color: CoresApp.textoPrincipal),
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
              const SizedBox(height: 24),

              // Container principal da tabela com efeito de card elevado e borda suave
              Container(
                decoration: BoxDecoration(
                  color: CoresDashboard.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CoresApp.borda, width: 1),
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
                    // Cabeçalho refinado das colunas da tabela
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: CoresDashboard.cabecalhoTabela,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        border: const Border(
                          bottom: BorderSide(color: CoresApp.borda, width: 1),
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

                    // Conteúdo da Tabela
                    _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(50.0),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: CoresApp.primaria,
                              ),
                            ),
                          )
                        : _workFormats.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(50.0),
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
                                separatorBuilder: (_, __) => const Divider(
                                  color: CoresApp.bordaSuave,
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final item = _workFormats[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _openFormatDetailDialog(
                                        format: item,
                                      ),
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
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color:
                                                      CoresApp.fundoSecundario,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: CoresApp.borda),
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
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: CoresApp.primaria
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
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
                                                    onPressed: () =>
                                                        _openFormatDetailDialog(
                                                      format: item,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Excluir',
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: CoresApp.erro,
                                                      size: 18,
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
