import 'package:flutter/material.dart';
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
          // Cria padrões caso não tenha nada salvo
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

            // Ouve alterações no texto para salvar automaticamente
            model.controller.addListener(() => _salvarBloco(model));

            _orientacoes.add(model);
          }
        }
      });
    } catch (_) {
      // Tratar falha de carregamento silenciosamente se necessário
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
      return const Scaffold(
        backgroundColor: Color(0xFF1E1E2C),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF00B4D8))),
      );
    }

    final orientacoesFiltradas = _orientacoes.where((item) {
      return item.titulo.toLowerCase().contains(_filtroPesquisa.toLowerCase());
    }).toList();

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
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
                                color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Pesquisar pelo nome da orientação...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.white38, size: 20),
                              suffixIcon: _pesquisaController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear,
                                          color: Colors.white38, size: 16),
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
                                  vertical: 10, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Colors.white24),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: Color(0xFF00B4D8)),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF2B2B3D),
                            ),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4.0,
                              color: const Color(0xFF2B2B3D),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 280,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2B2B3D),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
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
                                              color: Colors.white,
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
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nova Orientação'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C6E91),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
                      style: TextStyle(color: Colors.white54, fontSize: 14),
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
                          color: const Color(0xFF2B2B3D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
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
                                                    color: Color(0xFF00B4D8),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  decoration:
                                                      const InputDecoration(
                                                    isDense: true,
                                                    contentPadding:
                                                        EdgeInsets.symmetric(
                                                            vertical: 4,
                                                            horizontal: 8),
                                                    border:
                                                        OutlineInputBorder(),
                                                    filled: true,
                                                    fillColor:
                                                        Color(0xFF1E1E2C),
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
                                                    color: Color(0xFF00B4D8)),
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
                                                      color: Color(0xFF00B4D8),
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                const Icon(Icons.edit,
                                                    size: 14,
                                                    color: Colors.white38),
                                              ],
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(
                                      item.expandido
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      color: Colors.white70,
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
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent, size: 20),
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
                                        color: Colors.white, fontSize: 14),
                                    decoration: const InputDecoration(
                                      hintText:
                                          'Digite aqui as regras, links ou orientações...',
                                      hintStyle:
                                          TextStyle(color: Colors.white38),
                                      border: OutlineInputBorder(
                                        borderSide:
                                            BorderSide(color: Colors.white24),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide:
                                            BorderSide(color: Colors.white24),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(0xFF00B4D8)),
                                      ),
                                      filled: true,
                                      fillColor: Color(0xFF1E1E2C),
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
                                            Icons.signal_cellular_alt,
                                            color: Colors.white38,
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
