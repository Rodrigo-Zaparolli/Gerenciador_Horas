import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class ChecklistFormatsScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const ChecklistFormatsScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required TimeLogStore timeLogStore,
    required String userName,
  });

  @override
  State<ChecklistFormatsScreen> createState() => _ChecklistFormatsScreenState();
}

class _ChecklistFormatsScreenState extends State<ChecklistFormatsScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  List<ChecklistFormat> _checklistFormats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChecklistFormats();
  }

  Future<void> _loadChecklistFormats() async {
    setState(() => _isLoading = true);

    try {
      final formats = await _firebaseService.getChecklistFormats();

      setState(() {
        _checklistFormats = formats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar modelos de check list: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  Future<void> _deleteFormat(String id) async {
    try {
      await _firebaseService.deleteChecklistFormat(id);
      await _loadChecklistFormats();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Modelo excluído com sucesso!'),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      }
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

  void _openFormatDetailDialog({ChecklistFormat? format}) {
    final isEditing = format != null;

    final idController = TextEditingController(
      text: format?.id ?? '',
    );

    final nameController = TextEditingController(
      text: format?.name ?? '',
    );

    final itemOrderController = TextEditingController();
    final itemNameController = TextEditingController();

    final List<Map<String, dynamic>> currentItemsWithOrder = [];

    if (format?.items != null) {
      for (int i = 0; i < format!.items.length; i++) {
        final itemData = format.items[i];

        currentItemsWithOrder.add({
          'order': itemData['order']?.toString() ?? '${i + 1}',
          'name': itemData['name']?.toString() ?? '',
          'completed': itemData['completed'] == true,
        });
      }
    }

    if (itemOrderController.text.isEmpty) {
      itemOrderController.text = '${currentItemsWithOrder.length + 1}';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void addItem() {
              final orderText = itemOrderController.text.trim();
              final nameText = itemNameController.text.trim();

              if (nameText.isNotEmpty) {
                setDialogState(() {
                  currentItemsWithOrder.add({
                    'order': orderText.isEmpty
                        ? '${currentItemsWithOrder.length + 1}'
                        : orderText,
                    'name': nameText,
                    'completed': false,
                  });

                  itemNameController.clear();

                  final nextVal = (double.tryParse(
                            orderText.replaceAll(',', '.'),
                          ) ??
                          currentItemsWithOrder.length.toDouble()) +
                      1.0;

                  itemOrderController.text = nextVal % 1 == 0
                      ? nextVal.toInt().toString()
                      : nextVal.toString();
                });
              }
            }

            void removeItem(int index) {
              setDialogState(() {
                currentItemsWithOrder.removeAt(index);
              });
            }

            void editItem(int index) {
              final item = currentItemsWithOrder[index];

              final editOrderController = TextEditingController(
                text: item['order']?.toString() ?? '',
              );

              final editNameController = TextEditingController(
                text: item['name']?.toString() ?? '',
              );

              showDialog(
                context: context,
                builder: (innerContext) {
                  return AlertDialog(
                    backgroundColor: CoresTelas.fundoModal,
                    title: Text(
                      'Editar Item do Check List',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 16,
                      ),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: editOrderController,
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 13,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Nº / Ordem',
                            labelStyle: TextStyle(
                              color: CoresApp.textoSecundario,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: CoresTelas.campoFormulario,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: editNameController,
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Descrição do Item',
                            labelStyle: TextStyle(
                              color: CoresApp.textoSecundario,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: CoresTelas.campoFormulario,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(innerContext),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.destaque,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {
                          final newOrder = editOrderController.text.trim();
                          final newName = editNameController.text.trim();

                          if (newName.isNotEmpty) {
                            setDialogState(() {
                              currentItemsWithOrder[index] = {
                                'order': newOrder.isEmpty
                                    ? '${index + 1}'
                                    : newOrder,
                                'name': newName,
                                'completed': item['completed'] ?? false,
                              };
                            });

                            Navigator.pop(innerContext);
                          }
                        },
                        child: const Text(
                          'Atualizar',
                          style: TextStyle(
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
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing
                        ? 'Editar Modelo de Check List'
                        : 'Novo Modelo de Check List',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: CoresApp.textoSecundario,
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
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
                            width: 120,
                            child: TextField(
                              controller: idController,
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                labelText: 'ID do Modelo',
                                labelStyle: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12,
                                ),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.bordaSuave,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.destaque,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: nameController,
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Nome do Modelo / Tipo de Serviço',
                                labelStyle: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12,
                                ),
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.bordaSuave,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.destaque,
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
                          Text(
                            'Itens de Verificação:',
                            style: TextStyle(
                              color: CoresApp.destaque,
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
                              color: CoresTelas.fundoModalSecundario,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: CoresApp.bordaSuave,
                              ),
                            ),
                            child: Text(
                              'Total: ${currentItemsWithOrder.length}',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
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
                            width: 80,
                            child: TextField(
                              controller: itemOrderController,
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 13,
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
                                labelStyle: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12,
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.bordaSuave,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.destaque,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: itemNameController,
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Descrição do item (ex: Verificar normas)',
                                hintStyle: TextStyle(
                                  color:
                                      CoresApp.textoSecundario.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                                isDense: true,
                                filled: true,
                                fillColor: CoresTelas.campoFormulario,
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.bordaSuave,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: CoresApp.destaque,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => addItem(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.destaque,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: addItem,
                            icon: const Icon(
                              Icons.add_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Incluir',
                              style: TextStyle(
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
                          color: CoresTelas.fundoModalSecundario,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                        child: currentItemsWithOrder.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    'Nenhum item cadastrado neste modelo.',
                                    style: TextStyle(
                                      color: CoresApp.textoSecundario,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: currentItemsWithOrder.length,
                                separatorBuilder: (_, __) => Divider(
                                  color: CoresApp.bordaSuave,
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final entry = currentItemsWithOrder[index];

                                  return ListTile(
                                    onTap: () => editItem(index),
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            CoresApp.destaque.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        entry['order']?.toString() ?? '',
                                        style: TextStyle(
                                          color: CoresApp.destaque,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      entry['name']?.toString() ?? '',
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.edit_outlined,
                                            color: CoresApp.textoSecundario,
                                            size: 18,
                                          ),
                                          tooltip: 'Editar item',
                                          onPressed: () => editItem(index),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            color: CoresApp.erro,
                                            size: 18,
                                          ),
                                          tooltip: 'Excluir item',
                                          onPressed: () => removeItem(index),
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
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        TamanhosApp.raioBotao,
                      ),
                    ),
                  ),
                  onPressed: () async {
                    if (idController.text.trim().isEmpty ||
                        nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Preencha o ID e o Nome do modelo.',
                          ),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                      return;
                    }

                    if (isEditing && format.id != idController.text.trim()) {
                      try {
                        await _firebaseService.deleteChecklistFormat(
                          format.id,
                        );
                      } catch (_) {}
                    }

                    final updatedFormat = ChecklistFormat(
                      id: idController.text.trim(),
                      name: nameController.text.trim(),
                      items: currentItemsWithOrder,
                    );

                    try {
                      await _firebaseService.saveChecklistFormat(
                        updatedFormat,
                      );

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);

                        _loadChecklistFormats();

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Modelo salvo com sucesso!',
                            ),
                            backgroundColor: CoresApp.sucesso,
                          ),
                        );
                      }
                    } catch (e) {
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao salvar modelo: $e'),
                            backgroundColor: CoresApp.erro,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text(
                    'Salvar alterações',
                    style: TextStyle(
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ============================================================
          // IMAGEM DE FUNDO
          // ============================================================

          Positioned.fill(
            child: Image.asset(
              AppTheme.caminhoFundo,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: CoresApp.fundo,
                );
              },
            ),
          ),

          // ============================================================
          // CAMADA ESCURA SOBRE A IMAGEM
          // ============================================================

          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(
                AppTheme.opacidadeFundo,
              ),
            ),
          ),

          // ============================================================
          // CONTEÚDO ORIGINAL DA TELA
          // ============================================================

          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Modelos de Check List',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: CoresApp.textoPrincipal,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CoresApp.destaque,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            TamanhosApp.raioBotao,
                          ),
                        ),
                      ),
                      onPressed: () => _openFormatDetailDialog(),
                      icon: const Icon(
                        Icons.add_rounded,
                      ),
                      label: const Text(
                        'Novo Modelo',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: CoresTelas.fundoCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: CoresApp.borda,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: CoresTelas.cabecalhoTabela,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 100,
                              child: Text(
                                'ID',
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 120,
                              child: Text(
                                'Nº Itens',
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Nome do Modelo',
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
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
                                  color: CoresApp.textoPrincipal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(
                                40.0,
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: CoresApp.destaque,
                                ),
                              ),
                            )
                          : _checklistFormats.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(
                                    40.0,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Nenhum modelo de check list cadastrado.',
                                      style: TextStyle(
                                        color: CoresApp.textoSecundario,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _checklistFormats.length,
                                  separatorBuilder: (_, __) => Divider(
                                    color: CoresApp.bordaSuave,
                                    height: 1,
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = _checklistFormats[index];

                                    return InkWell(
                                      onTap: () => _openFormatDetailDialog(
                                        format: item,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 100,
                                              child: Text(
                                                item.id,
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                '${item.items.length}',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                item.name,
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoPrincipal,
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
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 32,
                                                      minHeight: 32,
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    icon: Icon(
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
                                                  const SizedBox(
                                                    width: 4,
                                                  ),
                                                  IconButton(
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 32,
                                                      minHeight: 32,
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    icon: Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                      color: CoresApp.erro,
                                                      size: 18,
                                                    ),
                                                    onPressed: () =>
                                                        _deleteFormat(
                                                      item.id,
                                                    ),
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
