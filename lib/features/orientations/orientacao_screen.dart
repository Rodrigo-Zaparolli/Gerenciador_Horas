import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class OrientacaoModel {
  final String id;
  String titulo;
  final TextEditingController controller;
  bool expandido;
  bool editandoTitulo;
  late TextEditingController tituloController;

  Offset posicao;
  double largura;
  double alturaTexto;

  OrientacaoModel({
    required this.id,
    required this.titulo,
    required String textoInicial,
    this.expandido = true,
    this.editandoTitulo = false,
    this.posicao = const Offset(50, 50),
    this.largura = 380.0,
    this.alturaTexto = 120.0,
  })  : controller = TextEditingController(text: textoInicial),
        tituloController = TextEditingController(text: titulo);

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'texto': controller.text,
        'expandido': expandido,
        'posX': posicao.dx,
        'posY': posicao.dy,
        'largura': largura,
        'alturaTexto': alturaTexto,
      };

  void dispose() {
    controller.dispose();
    tituloController.dispose();
  }
}

class OrientacaoScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const OrientacaoScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
  });

  @override
  State<OrientacaoScreen> createState() => _OrientacaoScreenState();
}

class _OrientacaoScreenState extends State<OrientacaoScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = true;

  final List<OrientacaoModel> _orientacoes = [];
  String _filtroPesquisa = '';
  final TextEditingController _pesquisaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    try {
      final dadosRemotos = await _firebaseService.getOrientacoes();

      setState(() {
        if (dadosRemotos.isEmpty) {
          _adicionarBlocoComDetalhes(
              id: '1',
              titulo: 'Orientação #1',
              texto: '',
              pos: const Offset(40, 30));
          _adicionarBlocoComDetalhes(
              id: '2',
              titulo: 'Orientação #2',
              texto: '',
              pos: const Offset(460, 30));
          _adicionarBlocoComDetalhes(
              id: '3',
              titulo: 'Orientação #3',
              texto: '',
              pos: const Offset(40, 320));
        } else {
          for (var item in dadosRemotos) {
            final model = OrientacaoModel(
              id: item['id'],
              titulo: item['titulo'] ?? 'Orientação',
              textoInicial: item['texto'] ?? '',
              expandido: item['expandido'] ?? true,
              posicao: Offset(item['posX'] ?? 50.0, item['posY'] ?? 50.0),
              largura: item['largura'] ?? 380.0,
              alturaTexto: item['alturaTexto'] ?? 120.0,
            );

            model.controller.addListener(() => _salvarBloco(model));
            _orientacoes.add(model);
          }
        }
      });
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _adicionarBlocoComDetalhes({
    required String id,
    required String titulo,
    required String texto,
    required Offset pos,
    bool expandido = true,
    double largura = 380.0,
    double altura = 120.0,
  }) {
    final model = OrientacaoModel(
      id: id,
      titulo: titulo,
      textoInicial: texto,
      posicao: pos,
      expandido: expandido,
      largura: largura,
      alturaTexto: altura,
    );

    model.controller.addListener(() => _salvarBloco(model));
    _orientacoes.add(model);
    _salvarBloco(model);
  }

  void _adicionarBloco() {
    final novoId = DateTime.now().millisecondsSinceEpoch.toString();
    final novaPos = Offset(
      80.0 + ((_orientacoes.length % 5) * 30),
      80.0 + ((_orientacoes.length % 5) * 30),
    );

    setState(() {
      _adicionarBlocoComDetalhes(
        id: novoId,
        titulo: 'Orientação #${_orientacoes.length + 1}',
        texto: '',
        pos: novaPos,
      );
    });
  }

  Future<void> _salvarBloco(OrientacaoModel item) async {
    try {
      await _firebaseService.saveOrientacao(item.id, item.toJson());
    } catch (_) {}
  }

  void _removerBloco(OrientacaoModel item) async {
    try {
      await _firebaseService.deleteOrientacao(item.id);
    } catch (_) {}

    setState(() {
      item.dispose();
      _orientacoes.remove(item);
    });
  }

  @override
  void dispose() {
    _pesquisaController.dispose();
    for (var item in _orientacoes) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: CoresApp.fundo,
        body:
            Center(child: CircularProgressIndicator(color: CoresApp.primaria)),
      );
    }

    final orientacoesFiltradas = _orientacoes.where((item) {
      return item.titulo.toLowerCase().contains(_filtroPesquisa.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: CoresApp.fundo,
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Orientações do Dia a Dia',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: Autocomplete<String>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<String>.empty();
                          }
                          return _orientacoes.map((e) => e.titulo).where(
                              (titulo) => titulo.toLowerCase().contains(
                                  textEditingValue.text.toLowerCase()));
                        },
                        onSelected: (String selection) {
                          setState(() {
                            _filtroPesquisa = selection;
                            _pesquisaController.text = selection;
                          });
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          if (controller.text != _pesquisaController.text &&
                              _pesquisaController.text.isEmpty) {
                            controller.text = _pesquisaController.text;
                          }
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onChanged: (value) {
                              setState(() {
                                _filtroPesquisa = value;
                                _pesquisaController.text = value;
                              });
                            },
                            style: const TextStyle(
                                color: CoresApp.textoPrincipal, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Pesquisar orientação...',
                              hintStyle: const TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 13),
                              prefixIcon: const Icon(Icons.search,
                                  color: CoresApp.textoSecundario, size: 18),
                              suffixIcon: _pesquisaController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          color: CoresApp.textoSecundario,
                                          size: 16),
                                      onPressed: () {
                                        setState(() {
                                          _pesquisaController.clear();
                                          controller.clear();
                                          _filtroPesquisa = '';
                                        });
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: CoresApp.borda),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: CoresApp.borda),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: CoresApp.primaria),
                              ),
                              filled: true,
                              fillColor: CoresApp.superficie,
                            ),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8.0,
                              color: Colors.transparent,
                              child: Container(
                                width: 280,
                                decoration: BoxDecoration(
                                  color: CoresApp.superficie,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: CoresApp.borda, width: 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.4),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                    final String option =
                                        options.elementAt(index);
                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Text(
                                          option,
                                          style: const TextStyle(
                                              color: CoresApp.textoPrincipal,
                                              fontSize: 14),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _adicionarBloco,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nova Orientação'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CoresApp.primaria,
                        foregroundColor: CoresApp.textoPrincipal,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (orientacoesFiltradas.isEmpty)
                  const Center(
                    child: Text(
                      'Nenhuma orientação encontrada.',
                      style: TextStyle(
                          color: CoresApp.textoSecundario, fontSize: 14),
                    ),
                  ),
                for (var item in orientacoesFiltradas)
                  Positioned(
                    left: item.posicao.dx,
                    top: item.posicao.dy,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          item.posicao += details.delta;
                        });
                      },
                      onPanEnd: (_) => _salvarBloco(item),
                      child: Container(
                        width: item.largura,
                        decoration: BoxDecoration(
                          color: CoresApp.superficie,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: CoresApp.borda.withOpacity(0.6), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: item.editandoTitulo
                                        ? Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller:
                                                      item.tituloController,
                                                  autofocus: true,
                                                  style: const TextStyle(
                                                    color: CoresApp.destaque,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  decoration:
                                                      const InputDecoration(
                                                    isDense: true,
                                                    contentPadding:
                                                        EdgeInsets.symmetric(
                                                            vertical: 8,
                                                            horizontal: 10),
                                                    border:
                                                        OutlineInputBorder(),
                                                    filled: true,
                                                    fillColor: CoresApp.fundo,
                                                  ),
                                                  onSubmitted: (value) {
                                                    setState(() {
                                                      if (value
                                                          .trim()
                                                          .isNotEmpty) {
                                                        item.titulo = value;
                                                      }
                                                      item.editandoTitulo =
                                                          false;
                                                    });
                                                    _salvarBloco(item);
                                                  },
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.check,
                                                    size: 16,
                                                    color: CoresApp.sucesso),
                                                onPressed: () {
                                                  setState(() {
                                                    if (item
                                                        .tituloController.text
                                                        .trim()
                                                        .isNotEmpty) {
                                                      item.titulo = item
                                                          .tituloController
                                                          .text;
                                                    }
                                                    item.editandoTitulo = false;
                                                  });
                                                  _salvarBloco(item);
                                                },
                                                tooltip: 'Salvar título',
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4),
                                                constraints:
                                                    const BoxConstraints(),
                                              ),
                                            ],
                                          )
                                        : GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                item.tituloController.text =
                                                    item.titulo;
                                                item.editandoTitulo = true;
                                              });
                                            },
                                            child: Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    item.titulo,
                                                    style: const TextStyle(
                                                      color: CoresApp.destaque,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                const Icon(Icons.edit_rounded,
                                                    size: 14,
                                                    color: CoresApp
                                                        .textoSecundario),
                                              ],
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      item.expandido
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      color: CoresApp.textoPrincipal,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        item.expandido = !item.expandido;
                                      });
                                      _salvarBloco(item);
                                    },
                                    tooltip: item.expandido
                                        ? 'Minimizar'
                                        : 'Maximizar',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: CoresApp.erro,
                                        size: 20),
                                    onPressed: () => _removerBloco(item),
                                    tooltip: 'Excluir bloco',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              if (item.expandido) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: item.alturaTexto,
                                  child: TextField(
                                    controller: item.controller,
                                    maxLines: null,
                                    expands: true,
                                    style: const TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 14),
                                    decoration: const InputDecoration(
                                      hintText:
                                          'Digite aqui as regras, links ou orientações...',
                                      hintStyle: TextStyle(
                                          color: CoresApp.textoSecundario),
                                      border: OutlineInputBorder(
                                        borderSide:
                                            BorderSide(color: CoresApp.borda),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide:
                                            BorderSide(color: CoresApp.borda),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: CoresApp.primaria),
                                      ),
                                      filled: true,
                                      fillColor: CoresApp.fundo,
                                      contentPadding: EdgeInsets.all(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    MouseRegion(
                                      cursor: SystemMouseCursors.resizeUpDown,
                                      child: GestureDetector(
                                        onPanUpdate: (details) {
                                          setState(() {
                                            item.largura = (item.largura +
                                                    details.delta.dx)
                                                .clamp(250.0, 700.0);
                                            item.alturaTexto =
                                                (item.alturaTexto +
                                                        details.delta.dy)
                                                    .clamp(60.0, 450.0);
                                          });
                                        },
                                        onPanEnd: (_) => _salvarBloco(item),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          child: const Icon(
                                            Icons.signal_cellular_alt_rounded,
                                            color: CoresApp.textoSecundario,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
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
