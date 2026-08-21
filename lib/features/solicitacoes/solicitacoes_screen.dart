// ignore_for_file: unnecessary_cast

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class SolicitacoesScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const SolicitacoesScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
  });

  @override
  State<SolicitacoesScreen> createState() => _SolicitacoesScreenState();
}

class _SolicitacoesScreenState extends State<SolicitacoesScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  int? _selectedProjetoIndex;
  int? _selectedPluginIndex;

  List<Map<String, dynamic>> _projetosRows = [];
  List<Map<String, dynamic>> _pluginsRows = [];
  bool _isLoading = true;

  String get _userId {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuário não autenticado.');
    return user.uid;
  }

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    try {
      final projSnapshot = await _db
          .collection('users')
          .doc(_userId)
          .collection('acompanhamento_projetos')
          .get();

      final plugSnapshot = await _db
          .collection('users')
          .doc(_userId)
          .collection('acompanhamento_plugins')
          .get();

      setState(() {
        _projetosRows = projSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        _pluginsRows = plugSnapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();

        if (_projetosRows.isEmpty) {
          _adicionarProjetoPadrao();
        }
        if (_pluginsRows.isEmpty) {
          _adicionarPluginPadrao();
        }
      });
    } catch (e) {
      debugPrint('Erro ao carregar do Firebase: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _adicionarProjetoPadrao() async {
    final docRef = _db
        .collection('users')
        .doc(_userId)
        .collection('acompanhamento_projetos')
        .doc();
    final novoItem = {
      'id': docRef.id,
      'campo0': '2257355 - Implantação Promob Studio Start EDCASA',
      'campo1': '01/07/2026',
      'campo2': 'Andamento',
      'campo3': 'Flávia',
      'campo4': '18/08/2026',
      'campo5': '31/08/2026',
    };
    await docRef.set(novoItem);
    _projetosRows.add(novoItem);
  }

  Future<void> _adicionarPluginPadrao() async {
    final docRef = _db
        .collection('users')
        .doc(_userId)
        .collection('acompanhamento_plugins')
        .doc();
    final novoItem = {
      'id': docRef.id,
      'campo0': '2253817 - Promob Studio Start Woody',
      'campo1': '10/09/2026',
      'campo2': 'Teste',
      'campo3': 'Bruna',
      'campo4': '07/08/2026',
      'campo5': '22/08/2026',
      'campo6': '-',
      'campo7': 'Multicam SL3012',
    };
    await docRef.set(novoItem);
    _pluginsRows.add(novoItem);
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  DateTime? _parseData(String dataStr) {
    try {
      List<String> parts = dataStr.split('/');
      return DateTime(
          int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) {
      return null;
    }
  }

  String _calcularDiasSemAtualizacao(String dataAtualizacaoStr) {
    DateTime? dataAtualizacao = _parseData(dataAtualizacaoStr);
    if (dataAtualizacao == null) return '0';

    DateTime hoje = DateTime.now();
    DateTime dataHojeLimpa = DateTime(hoje.year, hoje.month, hoje.day);
    DateTime dataAtualizacaoLimpa = DateTime(
        dataAtualizacao.year, dataAtualizacao.month, dataAtualizacao.day);

    int diferenca = dataHojeLimpa.difference(dataAtualizacaoLimpa).inDays;
    return diferenca < 0 ? '0' : diferenca.toString();
  }

  String _calcularAtualizacaoObrigatoria(DateTime dataBase) {
    DateTime novaData = dataBase.add(const Duration(days: 12));
    if (novaData.weekday == DateTime.saturday) {
      novaData = novaData.subtract(const Duration(days: 1));
    } else if (novaData.weekday == DateTime.sunday) {
      novaData = novaData.add(const Duration(days: 1));
    }
    return _formatarData(novaData);
  }

  Future<void> _atualizarDataProjeto(DateTime selectedDate) async {
    if (_selectedProjetoIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Selecione uma linha na tabela Acompanhamento de Projetos!'),
          backgroundColor: CoresDashboard.atrasado,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    String dataFormatada = _formatarData(selectedDate);
    String dataObrigatoria = _calcularAtualizacaoObrigatoria(selectedDate);

    final item = _projetosRows[_selectedProjetoIndex!];
    item['campo4'] = dataFormatada;
    item['campo5'] = dataObrigatoria;

    setState(() {});

    await _db
        .collection('users')
        .doc(_userId)
        .collection('acompanhamento_projetos')
        .doc(item['id'])
        .update({
      'campo4': dataFormatada,
      'campo5': dataObrigatoria,
    });
  }

  Future<void> _atualizarDataPlugin(DateTime selectedDate) async {
    if (_selectedPluginIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Selecione uma linha na tabela Acompanhamento Pugins em Desenvolvimento!'),
          backgroundColor: CoresDashboard.atrasado,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    String dataFormatada = _formatarData(selectedDate);
    String dataObrigatoria = _calcularAtualizacaoObrigatoria(selectedDate);

    final item = _pluginsRows[_selectedPluginIndex!];
    item['campo4'] = dataFormatada;
    item['campo5'] = dataObrigatoria;

    setState(() {});

    await _db
        .collection('users')
        .doc(_userId)
        .collection('acompanhamento_plugins')
        .doc(item['id'])
        .update({
      'campo4': dataFormatada,
      'campo5': dataObrigatoria,
    });
  }

  void _excluirLinha(int index, bool isProjeto) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CoresTelas.fundoModal,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TamanhosApp.raioTabela)),
        title: const Text('Excluir Linha',
            style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: const Text('Deseja realmente excluir este registro?',
            style: TextStyle(color: CoresApp.textoSecundario, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: CoresApp.textoFraco)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: CoresDashboard.atrasado,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TamanhosApp.raioBotao))),
            onPressed: () async {
              try {
                final lista = isProjeto ? _projetosRows : _pluginsRows;
                final item = lista[index];
                final collectionName = isProjeto
                    ? 'acompanhamento_projetos'
                    : 'acompanhamento_plugins';

                await _db
                    .collection('users')
                    .doc(_userId)
                    .collection(collectionName)
                    .doc(item['id'])
                    .delete();

                setState(() {
                  lista.removeAt(index);
                  if (isProjeto) {
                    _selectedProjetoIndex = null;
                  } else {
                    _selectedPluginIndex = null;
                  }
                });
              } catch (e) {
                debugPrint('Erro ao excluir do Firebase: $e');
              }
              Navigator.pop(context);
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _editarLinha(int index, bool isProjeto) {
    final lista = isProjeto ? _projetosRows : _pluginsRows;
    final item = lista[index];

    int totalCampos = isProjeto ? 6 : 8;
    List<TextEditingController> controllers = List.generate(totalCampos, (i) {
      return TextEditingController(text: item['campo$i']?.toString() ?? '');
    });

    String statusSelecionado =
        item['campo2'] == 'Parado' ? 'Parado' : 'Andamento';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(TamanhosApp.raioTabela)),
              title: const Text('Editar Registro',
                  style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(totalCampos, (i) {
                      if (isProjeto && i == 2) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: DropdownButtonFormField<String>(
                            value: statusSelecionado,
                            dropdownColor: CoresTelas.fundoModal,
                            style: const TextStyle(
                                color: CoresApp.textoPrincipal, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Status (Campo 3)',
                              labelStyle:
                                  TextStyle(color: CoresApp.textoSecundario),
                              enabledBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: CoresApp.borda)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: CoresApp.primaria)),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Andamento',
                                  child: Text('Andamento',
                                      style: TextStyle(
                                          color: CoresApp.textoPrincipal))),
                              DropdownMenuItem(
                                  value: 'Parado',
                                  child: Text('Parado',
                                      style: TextStyle(
                                          color: CoresDashboard.atrasado))),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setStateDialog(() {
                                  statusSelecionado = value;
                                  controllers[i].text = value;
                                });
                              }
                            },
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: TextField(
                          controller: controllers[i],
                          style: const TextStyle(
                              color: CoresApp.textoPrincipal, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Campo ${i + 1}',
                            labelStyle: const TextStyle(
                                color: CoresApp.textoSecundario),
                            enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(color: CoresApp.borda)),
                            focusedBorder: const OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: CoresApp.primaria)),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(color: CoresApp.textoFraco)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: CoresApp.sucesso,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(TamanhosApp.raioBotao))),
                  onPressed: () async {
                    Map<String, dynamic> dadosAtualizados = {'id': item['id']};
                    for (int i = 0; i < controllers.length; i++) {
                      dadosAtualizados['campo$i'] = controllers[i].text;
                    }

                    final collectionName = isProjeto
                        ? 'acompanhamento_projetos'
                        : 'acompanhamento_plugins';
                    await _db
                        .collection('users')
                        .doc(_userId)
                        .collection(collectionName)
                        .doc(item['id'])
                        .update(dadosAtualizados);

                    setState(() {
                      lista[index] = dadosAtualizados;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _adicionarProjeto() async {
    DateTime hoje = DateTime.now();
    final docRef = _db
        .collection('users')
        .doc(_userId)
        .collection('acompanhamento_projetos')
        .doc();
    final novoProjeto = {
      'id': docRef.id,
      'campo0': 'Novo Projeto - Solicitação',
      'campo1': '30/12/2026',
      'campo2': 'Andamento',
      'campo3': 'Rodrigo',
      'campo4': _formatarData(hoje),
      'campo5': _calcularAtualizacaoObrigatoria(hoje),
    };

    await docRef.set(novoProjeto);
    setState(() {
      _projetosRows.add(novoProjeto);
    });
  }

  Future<void> _adicionarPlugin() async {
    DateTime hoje = DateTime.now();
    final docRef = _db
        .collection('users')
        .doc(_userId)
        .collection('acompanhamento_plugins')
        .doc();
    final novoPlugin = {
      'id': docRef.id,
      'campo0': 'Nova Solicitação + Cliente',
      'campo1': '30/12/2026',
      'campo2': 'Desenv.',
      'campo3': 'Rodrigo',
      'campo4': _formatarData(hoje),
      'campo5': _calcularAtualizacaoObrigatoria(hoje),
      'campo6': '-',
      'campo7': 'Plugin Exemplo',
    };

    await docRef.set(novoPlugin);
    setState(() {
      _pluginsRows.add(novoPlugin);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresDashboard.fundo,
      appBar: Cabecalho(
        selectedIndex: widget.selectedIndex,
        onSelectTab: widget.onSelectTab,
        searchQuery: '',
        onSearchChanged: (value) {},
        userName: '',
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: CoresApp.sucesso))
          : Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: CoresApp.primaria,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Pasta de Solicitações',
                        style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CoresDashboard.card,
                        borderRadius:
                            BorderRadius.circular(TamanhosApp.raioTabela),
                        border: Border.all(color: CoresDashboard.tabelaBorda),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.folder_shared_rounded,
                                        size: 16, color: CoresApp.primaria),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Acompanhamento de Projetos',
                                      style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  onPressed: _adicionarProjeto,
                                  icon: const Icon(Icons.add, size: 14),
                                  label: const Text('Adicionar Linha',
                                      style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: CoresApp.sucesso,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    minimumSize: const Size(0, 32),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            TamanhosApp.raioBotao)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildTabelaProjetos()),
                                const SizedBox(width: 12),
                                SizedBox(
                                    width: 250,
                                    child: _buildCalendarioLateral(
                                        _atualizarDataProjeto)),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Divider(
                                color: CoresDashboard.tabelaDivisor, height: 1),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.extension_rounded,
                                        size: 16, color: CoresApp.primaria),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Acompanhamento Pugins em Desenvolvimento',
                                      style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  onPressed: _adicionarPlugin,
                                  icon: const Icon(Icons.add, size: 14),
                                  label: const Text('Adicionar Linha',
                                      style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: CoresApp.sucesso,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    minimumSize: const Size(0, 32),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            TamanhosApp.raioBotao)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildTabelaPlugins()),
                                const SizedBox(width: 12),
                                SizedBox(
                                    width: 250,
                                    child: _buildCalendarioLateral(
                                        _atualizarDataPlugin)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCalendarioLateral(ValueSetter<DateTime> onDateSelected) {
    return Container(
      decoration: BoxDecoration(
        color: CoresDashboard.tabelaFundo,
        borderRadius: BorderRadius.circular(TamanhosApp.raioTabela),
        border: Border.all(color: CoresDashboard.tabelaBorda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TamanhosApp.raioTabela),
        child: Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary:
                  CoresApp.primaria, // Ajustado para usar cor primária moderna
              onPrimary: Colors.white,
              surface: CoresDashboard.tabelaFundo,
              onSurface: CoresApp.textoPrincipal,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 210,
              height: 210,
              child: CalendarDatePicker(
                initialDate: DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                onDateChanged: onDateSelected,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabelaProjetos() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TamanhosApp.raioTabela),
        border: Border.all(color: CoresDashboard.tabelaBorda),
        color: CoresDashboard.tabelaFundo,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return DataTable(
              showCheckboxColumn: false,
              columnSpacing: 12.0,
              horizontalMargin: 12.0,
              // Possível ajuste: alterar a altura máxima/mínima e do cabeçalho da linha para compactar ou espaçar
              dataRowMaxHeight: 44, // Altura máxima da linha
              dataRowMinHeight: 36, // Altura mínima da linha
              headingRowHeight: 40, // Altura do cabeçalho
              headingRowColor:
                  WidgetStateProperty.all(CoresDashboard.cabecalhoTabela),
              columns: const [
                DataColumn(
                    label: Text('Cliente + Solicitação',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Vencimento',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Status',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Líder',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Último Coment.',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Dias s/Atual',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Atualiz. Obrigatória',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Ações',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
              ],
              rows: List.generate(_projetosRows.length, (index) {
                final row = _projetosRows[index];
                bool isHighlight = (row['campo2'] == 'Parado' ||
                    row['campo0'].toString().contains('CANCELADO'));
                bool isSelected = _selectedProjetoIndex == index;

                String ultimoComentarioData = row['campo4'] ?? '';
                String diasSemAtualizacao =
                    _calcularDiasSemAtualizacao(ultimoComentarioData);

                List<DataCell> cells = [
                  DataCell(Text(row['campo0'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario,
                          fontWeight: isHighlight
                              ? FontWeight.bold
                              : FontWeight.normal))),
                  DataCell(Text(row['campo1'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isHighlight
                            ? CoresDashboard.atrasado.withOpacity(0.15)
                            : CoresDashboard.statusAndamento.withOpacity(0.15),
                        borderRadius:
                            BorderRadius.circular(TamanhosApp.raioBadge),
                        border: Border.all(
                          color: isHighlight
                              ? CoresDashboard.atrasado.withOpacity(0.4)
                              : CoresDashboard.statusAndamento.withOpacity(0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        row['campo2'] ?? '',
                        style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonteStatus,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresDashboard.statusAndamento,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(row['campo3'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(ultimoComentarioData,
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(diasSemAtualizacao,
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario,
                          fontWeight: FontWeight.bold))),
                  DataCell(Text(row['campo5'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                ];

                cells.add(
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: CoresApp.primaria.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.edit,
                                size: TamanhosApp.iconeAcao,
                                color: CoresApp.primaria),
                            onPressed: () => _editarLinha(index, true),
                            tooltip: 'Editar',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: CoresDashboard.atrasado.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.delete,
                                size: TamanhosApp.iconeAcao,
                                color: CoresDashboard.atrasado),
                            onPressed: () => _excluirLinha(index, true),
                            tooltip: 'Excluir',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                return DataRow(
                  selected: isSelected,
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (isSelected) {
                      return CoresDashboard.tabelaLinhaSelecionada;
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return CoresDashboard.tabelaHover;
                    }
                    return null;
                  }),
                  onSelectChanged: (selected) {
                    setState(() {
                      _selectedProjetoIndex = (selected == true) ? index : null;
                    });
                  },
                  cells: cells,
                );
              }),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabelaPlugins() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TamanhosApp.raioTabela),
        border: Border.all(color: CoresDashboard.tabelaBorda),
        color: CoresDashboard.tabelaFundo,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return DataTable(
              showCheckboxColumn: false,
              columnSpacing: 12.0,
              horizontalMargin: 12.0,
              // Possível ajuste: alterar a altura máxima/mínima e do cabeçalho da linha para compactar ou espaçar
              dataRowMaxHeight: 44, // Altura máxima da linha
              dataRowMinHeight: 36, // Altura mínima da linha
              headingRowHeight: 40, // Altura do cabeçalho
              headingRowColor:
                  WidgetStateProperty.all(CoresDashboard.cabecalhoTabela),
              columns: const [
                DataColumn(
                    label: Text('Solicitação + Cliente',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Entrega',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Fase',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Consultor',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Atualização',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Dia S/Atual',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Atualiz. Obrigatória',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('NS',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Plugin',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
                DataColumn(
                    label: Text('Ações',
                        style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonteCabecalho,
                            fontWeight: FontWeight.bold,
                            color: CoresApp.textoPrincipal))),
              ],
              rows: List.generate(_pluginsRows.length, (index) {
                final row = _pluginsRows[index];
                bool isHighlight = (row['campo2'] == 'Parado' ||
                    row['campo0'].toString().contains('CANCELADO'));
                bool isSelected = _selectedPluginIndex == index;

                String atualizacaoData = row['campo4'] ?? '';
                String diasSemAtualizacao =
                    _calcularDiasSemAtualizacao(atualizacaoData);

                List<DataCell> cells = [
                  DataCell(Text(row['campo0'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario,
                          fontWeight: isHighlight
                              ? FontWeight.bold
                              : FontWeight.normal))),
                  DataCell(Text(row['campo1'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(row['campo2'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(row['campo3'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(atualizacaoData,
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(diasSemAtualizacao,
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario,
                          fontWeight: FontWeight.bold))),
                  DataCell(Text(row['campo5'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(row['campo6'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                  DataCell(Text(row['campo7'] ?? '',
                      style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonte,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresApp.textoSecundario))),
                ];

                cells.add(
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: CoresApp.primaria.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.edit,
                                size: TamanhosApp.iconeAcao,
                                color: CoresApp.primaria),
                            onPressed: () => _editarLinha(index, false),
                            tooltip: 'Editar',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: CoresDashboard.atrasado.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.delete,
                                size: TamanhosApp.iconeAcao,
                                color: CoresDashboard.atrasado),
                            onPressed: () => _excluirLinha(index, false),
                            tooltip: 'Excluir',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                return DataRow(
                  selected: isSelected,
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (isSelected) {
                      return CoresDashboard.tabelaLinhaSelecionada;
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return CoresDashboard.tabelaLinhaExpandida;
                    }
                    return null;
                  }),
                  onSelectChanged: (selected) {
                    setState(() {
                      _selectedPluginIndex = (selected == true) ? index : null;
                    });
                  },
                  cells: cells,
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
