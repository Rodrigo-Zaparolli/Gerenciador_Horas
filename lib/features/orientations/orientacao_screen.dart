import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
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

  /// Largura do card.
  double largura;

  /// Altura mínima da área de conteúdo.
  ///
  /// O card pode crescer além dessa altura quando o texto/imagens
  /// ocuparem mais espaço.
  double alturaTexto;

  /// Imagens/prints salvos no Firebase em Base64.
  List<String> imagens;

  OrientacaoModel({
    required this.id,
    required this.titulo,
    required String textoInicial,
    this.expandido = true,
    this.editandoTitulo = false,
    this.posicao = const Offset(50, 50),
    this.largura = 380.0,
    this.alturaTexto = 100.0,
    List<String>? imagens,
  })  : controller = TextEditingController(text: textoInicial),
        tituloController = TextEditingController(text: titulo),
        imagens = List<String>.from(imagens ?? []);

  Map<String, dynamic> toJson() {
    return {
      'titulo': titulo,
      'texto': controller.text,
      'expandido': expandido,
      'posX': posicao.dx,
      'posY': posicao.dy,
      'largura': largura,
      'alturaTexto': alturaTexto,
      'imagens': List<String>.from(imagens),
    };
  }

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
    required String userName,
  });

  @override
  State<OrientacaoScreen> createState() => _OrientacaoScreenState();
}

class _OrientacaoScreenState extends State<OrientacaoScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  bool _isLoading = true;
  String? _erroCarregamento;

  final List<OrientacaoModel> _orientacoes = [];

  String _filtroPesquisa = '';

  final TextEditingController _pesquisaController = TextEditingController();

  /// Card que atualmente está com foco para receber Ctrl + V.
  String? _cardComFoco;

  /// Evita múltiplos Ctrl+V simultâneos.
  bool _colandoImagem = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _carregarDados();
  }

  // ============================================================
  // CONVERSÕES SEGURAS
  // ============================================================

  double _toDouble(
    dynamic value,
    double valorPadrao,
  ) {
    if (value == null) {
      return valorPadrao;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(
            value.replaceAll(',', '.'),
          ) ??
          valorPadrao;
    }

    return valorPadrao;
  }

  bool _toBool(
    dynamic value,
    bool valorPadrao,
  ) {
    if (value is bool) {
      return value;
    }

    if (value is String) {
      final valor = value.toLowerCase().trim();

      if (valor == 'true' || valor == '1') {
        return true;
      }

      if (valor == 'false' || valor == '0') {
        return false;
      }
    }

    if (value is num) {
      return value != 0;
    }

    return valorPadrao;
  }

  String _toString(
    dynamic value,
    String valorPadrao,
  ) {
    if (value == null) {
      return valorPadrao;
    }

    return value.toString();
  }

  // ============================================================
  // IMAGENS
  // ============================================================

  List<String> _toImages(dynamic value) {
    if (value == null || value is! List) {
      return [];
    }

    return value
        .whereType<String>()
        .where(
          (item) => item.trim().isNotEmpty,
        )
        .toList();
  }

  // ============================================================
  // CARREGAR DADOS
  // ============================================================

  Future<void> _carregarDados() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _erroCarregamento = null;
      });
    }

    try {
      debugPrint('==============================================');
      debugPrint('ORIENTAÇÕES - INICIANDO CARREGAMENTO');
      debugPrint('==============================================');

      final dadosRemotos = await _firebaseService.getOrientacoes();

      debugPrint(
        'Orientações encontradas no Firebase: '
        '${dadosRemotos.length}',
      );

      final List<OrientacaoModel> orientacoesCarregadas = [];

      for (final item in dadosRemotos) {
        try {
          final String id = _toString(
            item['id'],
            DateTime.now().microsecondsSinceEpoch.toString(),
          );

          final String titulo = _toString(
            item['titulo'],
            'Orientação',
          );

          final String texto = _toString(
            item['texto'],
            '',
          );

          final bool expandido = _toBool(
            item['expandido'],
            true,
          );

          final double posX = _toDouble(
            item['posX'],
            50.0,
          );

          final double posY = _toDouble(
            item['posY'],
            50.0,
          );

          final double largura = _toDouble(
            item['largura'],
            380.0,
          );

          final double alturaTexto = _toDouble(
            item['alturaTexto'],
            100.0,
          );

          final List<String> imagens = _toImages(item['imagens']);

          debugPrint(
            'Carregando orientação: '
            'id=$id | '
            'titulo=$titulo | '
            'imagens=${imagens.length}',
          );

          final model = OrientacaoModel(
            id: id,
            titulo: titulo,
            textoInicial: texto,
            expandido: expandido,
            posicao: Offset(posX, posY),
            largura: largura.clamp(
              260.0,
              900.0,
            ),
            alturaTexto: alturaTexto.clamp(
              70.0,
              700.0,
            ),
            imagens: imagens,
          );

          model.controller.addListener(
            () => _salvarBloco(model),
          );

          orientacoesCarregadas.add(model);
        } catch (e, stackTrace) {
          debugPrint(
            'ERRO AO CONVERTER UMA ORIENTAÇÃO: $e',
          );

          debugPrint(
            stackTrace.toString(),
          );
        }
      }

      if (!mounted) {
        for (final item in orientacoesCarregadas) {
          item.dispose();
        }

        return;
      }

      setState(() {
        _orientacoes.clear();
        _orientacoes.addAll(
          orientacoesCarregadas,
        );
      });

      debugPrint(
        'Total carregado na tela: '
        '${_orientacoes.length}',
      );

      if (_orientacoes.isEmpty && dadosRemotos.isEmpty) {
        debugPrint(
          'Firebase não possui orientações. '
          'Criando modelos padrão.',
        );

        _adicionarBlocoComDetalhes(
          id: '1',
          titulo: 'Orientação #1',
          texto: '',
          pos: const Offset(40, 30),
        );

        _adicionarBlocoComDetalhes(
          id: '2',
          titulo: 'Orientação #2',
          texto: '',
          pos: const Offset(460, 30),
        );

        _adicionarBlocoComDetalhes(
          id: '3',
          titulo: 'Orientação #3',
          texto: '',
          pos: const Offset(40, 320),
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
        '==============================================',
      );

      debugPrint(
        'ERRO AO CARREGAR ORIENTAÇÕES',
      );

      debugPrint(
        '==============================================',
      );

      debugPrint(
        e.toString(),
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (mounted) {
        setState(() {
          _erroCarregamento = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // ADICIONAR BLOCO
  // ============================================================

  void _adicionarBlocoComDetalhes({
    required String id,
    required String titulo,
    required String texto,
    required Offset pos,
    bool expandido = true,
    double largura = 380.0,
    double altura = 100.0,
    List<String>? imagens,
  }) {
    final model = OrientacaoModel(
      id: id,
      titulo: titulo,
      textoInicial: texto,
      posicao: pos,
      expandido: expandido,
      largura: largura,
      alturaTexto: altura,
      imagens: imagens,
    );

    model.controller.addListener(
      () => _salvarBloco(model),
    );

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

  // ============================================================
  // SALVAR BLOCO
  // ============================================================

  Future<void> _salvarBloco(
    OrientacaoModel item,
  ) async {
    try {
      await _firebaseService.saveOrientacao(
        item.id,
        item.toJson(),
      );

      debugPrint(
        'Orientação salva: '
        '${item.id} - ${item.titulo}',
      );
    } catch (e) {
      debugPrint(
        'Erro ao salvar orientação '
        '${item.id}: $e',
      );
    }
  }

  // ============================================================
  // ADICIONAR IMAGENS PELO ARQUIVO
  // ============================================================

  Future<void> _adicionarImagens(
    OrientacaoModel item,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: [
          'png',
          'jpg',
          'jpeg',
          'webp',
        ],
      );

      if (result == null) {
        return;
      }

      final List<String> novasImagens = [];

      for (final file in result.files) {
        final bytes = file.bytes;

        if (bytes == null || bytes.isEmpty) {
          continue;
        }

        final String base64Imagem = base64Encode(bytes);

        String extensao = 'png';

        final nome = file.name.toLowerCase();

        if (nome.endsWith('.jpg') || nome.endsWith('.jpeg')) {
          extensao = 'jpeg';
        } else if (nome.endsWith('.webp')) {
          extensao = 'webp';
        }

        final String imagemBase64 = 'data:image/$extensao;base64,'
            '$base64Imagem';

        novasImagens.add(
          imagemBase64,
        );
      }

      if (novasImagens.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Não foi possível carregar '
                'as imagens selecionadas.',
              ),
            ),
          );
        }

        return;
      }

      setState(() {
        item.imagens.addAll(
          novasImagens,
        );

        _cardComFoco = item.id;
      });

      await _salvarBloco(item);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${novasImagens.length} '
              'imagem(ns) adicionada(s) à orientação.',
            ),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'Erro ao adicionar imagem: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao adicionar imagem: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  // ============================================================
  // COLAR PRINT DO CTRL + V
  // ============================================================

  Future<void> _colarPrint(
    OrientacaoModel item,
  ) async {
    if (_colandoImagem) {
      return;
    }

    setState(() {
      _cardComFoco = item.id;
      _colandoImagem = true;
    });

    try {
      final Uint8List? bytes = await Pasteboard.image;

      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Nenhuma imagem encontrada na área de transferência.',
              ),
            ),
          );
        }

        return;
      }

      final String base64Imagem = base64Encode(bytes);

      final String imagemBase64 = 'data:image/png;base64,'
          '$base64Imagem';

      setState(() {
        item.imagens.add(
          imagemBase64,
        );
      });

      await _salvarBloco(item);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Print colado no card com sucesso.',
            ),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'Erro ao colar print: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível colar o print: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _colandoImagem = false;
        });
      }
    }
  }

  // ============================================================
  // REMOVER IMAGEM
  // ============================================================

  Future<void> _removerImagem(
    OrientacaoModel item,
    int index,
  ) async {
    if (index < 0 || index >= item.imagens.length) {
      return;
    }

    setState(() {
      item.imagens.removeAt(index);
    });

    await _salvarBloco(item);
  }

  // ============================================================
  // VISUALIZAR IMAGEM
  // ============================================================

  void _visualizarImagem(
    String imagem,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.90),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Image.memory(
                    _decodeImagem(imagem),
                    fit: BoxFit.contain,
                    errorBuilder: (
                      context,
                      error,
                      stackTrace,
                    ) {
                      return Container(
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: CoresApp.superficie,
                          borderRadius: BorderRadius.circular(
                            12,
                          ),
                        ),
                        child: const Text(
                          'Não foi possível abrir esta imagem.',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // DECODIFICAR IMAGEM
  // ============================================================

  Uint8List _decodeImagem(
    String imagem,
  ) {
    try {
      String valor = imagem;

      if (valor.contains(',')) {
        valor = valor.substring(
          valor.indexOf(',') + 1,
        );
      }

      return Uint8List.fromList(
        base64Decode(valor),
      );
    } catch (_) {
      return Uint8List(0);
    }
  }

  // ============================================================
  // REMOVER BLOCO
  // ============================================================

  Future<void> _removerBloco(
    OrientacaoModel item,
  ) async {
    try {
      await _firebaseService.deleteOrientacao(
        item.id,
      );
    } catch (e) {
      debugPrint(
        'Erro ao excluir orientação: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao excluir orientação: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }

      return;
    }

    if (!mounted) {
      item.dispose();
      return;
    }

    setState(() {
      item.dispose();

      _orientacoes.remove(item);

      if (_cardComFoco == item.id) {
        _cardComFoco = null;
      }
    });
  }

  // ============================================================
  // ALTERAR TÍTULO
  // ============================================================

  void _iniciarEdicaoTitulo(
    OrientacaoModel item,
  ) {
    setState(() {
      item.tituloController.text = item.titulo;

      item.editandoTitulo = true;
    });
  }

  void _salvarTitulo(
    OrientacaoModel item,
  ) {
    final novoTitulo = item.tituloController.text.trim();

    setState(() {
      if (novoTitulo.isNotEmpty) {
        item.titulo = novoTitulo;
      }

      item.editandoTitulo = false;
    });

    _salvarBloco(item);
  }

  // ============================================================
  // REDIMENSIONAMENTO
  // ============================================================

  void _redimensionarCard(
    OrientacaoModel item,
    DragUpdateDetails details,
  ) {
    setState(() {
      item.largura = (item.largura + details.delta.dx).clamp(
        260.0,
        900.0,
      );

      item.alturaTexto = (item.alturaTexto + details.delta.dy).clamp(
        70.0,
        700.0,
      );
    });
  }

  // ============================================================
  // IMAGENS DO CARD
  // ============================================================

  Widget _buildImagens(
    OrientacaoModel item,
  ) {
    if (item.imagens.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(
        top: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.image_outlined,
                color: CoresApp.textoSecundario,
                size: 17,
              ),
              const SizedBox(
                width: 7,
              ),
              Text(
                item.imagens.length == 1
                    ? 'Print anexado'
                    : 'Prints anexados '
                        '(${item.imagens.length})',
                style: const TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 8,
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: item.imagens.length,
              separatorBuilder: (
                context,
                index,
              ) =>
                  const SizedBox(
                width: 8,
              ),
              itemBuilder: (
                context,
                index,
              ) {
                final imagem = item.imagens[index];

                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _visualizarImagem(
                          imagem,
                        );
                      },
                      child: Container(
                        width: 145,
                        height: 105,
                        decoration: BoxDecoration(
                          color: CoresApp.fundo,
                          borderRadius: BorderRadius.circular(
                            9,
                          ),
                          border: Border.all(
                            color: CoresApp.borda,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.memory(
                          _decodeImagem(
                            imagem,
                          ),
                          fit: BoxFit.cover,
                          errorBuilder: (
                            context,
                            error,
                            stackTrace,
                          ) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: CoresApp.erro,
                                size: 28,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // EXCLUIR IMAGEM
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black.withOpacity(
                          0.65,
                        ),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            _removerImagem(
                              item,
                              index,
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(
                              4,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // NÚMERO
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(
                            0.65,
                          ),
                          borderRadius: BorderRadius.circular(
                            5,
                          ),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTÃO DE COLAR PRINT
  // ============================================================

  Widget _buildBotaoColarPrint(
    OrientacaoModel item,
  ) {
    final bool selecionado = _cardComFoco == item.id;

    return Tooltip(
      message: 'Colar print (Ctrl + V)',
      child: InkWell(
        onTap: () {
          _colarPrint(item);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selecionado
                ? CoresApp.primaria.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(
              8,
            ),
            border: Border.all(
              color: selecionado ? CoresApp.primaria : CoresApp.borda,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.content_paste_rounded,
                color: CoresApp.primaria,
                size: 17,
              ),
              SizedBox(
                width: 5,
              ),
              Text(
                'Colar print',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD CARD
  // ============================================================

  Widget _buildCard(
    OrientacaoModel item,
  ) {
    return MouseRegion(
      onEnter: (_) {
        if (_cardComFoco != item.id) {
          setState(() {
            _cardComFoco = item.id;
          });
        }
      },
      cursor: SystemMouseCursors.basic,
      child: Container(
        width: item.largura,
        constraints: BoxConstraints(
          minHeight: item.alturaTexto,
        ),
        decoration: BoxDecoration(
          color: CoresApp.superficie,
          borderRadius: BorderRadius.circular(
            14,
          ),
          border: Border.all(
            color: _cardComFoco == item.id
                ? CoresApp.primaria.withOpacity(
                    0.45,
                  )
                : CoresApp.borda.withOpacity(
                    0.6,
                  ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                0.40,
              ),
              blurRadius: 12,
              offset: const Offset(
                0,
                6,
              ),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ==================================================
                  // CABEÇALHO
                  // ==================================================

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: item.editandoTitulo
                            ? Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: item.tituloController,
                                      autofocus: true,
                                      style: const TextStyle(
                                        color: CoresApp.destaque,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 10,
                                        ),
                                        border: OutlineInputBorder(),
                                        filled: true,
                                        fillColor: CoresApp.fundo,
                                      ),
                                      onSubmitted: (_) {
                                        _salvarTitulo(
                                          item,
                                        );
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check,
                                      size: 17,
                                      color: CoresApp.sucesso,
                                    ),
                                    onPressed: () {
                                      _salvarTitulo(
                                        item,
                                      );
                                    },
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              )
                            : GestureDetector(
                                onTap: () {
                                  _iniciarEdicaoTitulo(
                                    item,
                                  );
                                },
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        item.titulo,
                                        style: const TextStyle(
                                          color: CoresApp.destaque,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 6,
                                    ),
                                    const Icon(
                                      Icons.edit_rounded,
                                      size: 14,
                                      color: CoresApp.textoSecundario,
                                    ),
                                  ],
                                ),
                              ),
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      // ==================================================
                      // COLAR PRINT
                      // ==================================================

                      _buildBotaoColarPrint(
                        item,
                      ),

                      const SizedBox(
                        width: 6,
                      ),

                      // ==================================================
                      // ADICIONAR IMAGEM
                      // ==================================================

                      Tooltip(
                        message: 'Adicionar imagem',
                        child: IconButton(
                          icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: CoresApp.primaria,
                            size: 20,
                          ),
                          onPressed: () => _adicionarImagens(
                            item,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      // ==================================================
                      // EXPANDIR / MINIMIZAR
                      // ==================================================

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

                          _salvarBloco(
                            item,
                          );
                        },
                        tooltip: item.expandido ? 'Minimizar' : 'Maximizar',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      // ==================================================
                      // EXCLUIR
                      // ==================================================

                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: CoresApp.erro,
                          size: 20,
                        ),
                        onPressed: () => _removerBloco(
                          item,
                        ),
                        tooltip: 'Excluir bloco',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),

                  // ==================================================
                  // CONTEÚDO
                  // ==================================================

                  if (item.expandido) ...[
                    const SizedBox(
                      height: 12,
                    ),

                    // ==================================================
                    // ÁREA DE TEXTO
                    //
                    // Não possui altura fixa.
                    // O card começa pequeno e cresce conforme
                    // o conteúdo aumenta.
                    // ==================================================

                    TextField(
                      controller: item.controller,
                      minLines: 3,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onTap: () {
                        setState(() {
                          _cardComFoco = item.id;
                        });
                      },
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 14,
                        height: 1.45,
                      ),
                      decoration: const InputDecoration(
                        hintText:
                            'Digite aqui as regras, links ou orientações...',
                        hintStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: CoresApp.borda,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: CoresApp.borda,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: CoresApp.primaria,
                          ),
                        ),
                        filled: true,
                        fillColor: CoresApp.fundo,
                        contentPadding: EdgeInsets.all(
                          12,
                        ),
                      ),
                    ),

                    // ==================================================
                    // IMAGENS DENTRO DO MESMO CARD
                    // ==================================================

                    _buildImagens(
                      item,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    // ==================================================
                    // INFORMAÇÃO DO CTRL + V
                    // ==================================================

                    Row(
                      children: [
                        Icon(
                          Icons.keyboard_rounded,
                          size: 14,
                          color: CoresApp.textoSecundario.withOpacity(
                            0.75,
                          ),
                        ),
                        const SizedBox(
                          width: 5,
                        ),
                        Text(
                          'Clique no card e pressione Ctrl + V para colar um print',
                          style: TextStyle(
                            color: CoresApp.textoSecundario.withOpacity(
                              0.75,
                            ),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 6,
                    ),
                  ],
                ],
              ),
            ),

            // ==========================================================
            // ALÇA DE REDIMENSIONAMENTO
            //
            // Fica no canto inferior direito.
            // Arrastando:
            //   direita  = aumenta largura
            //   esquerda = diminui largura
            //   baixo    = aumenta altura
            //   cima     = diminui altura
            // ==========================================================

            Positioned(
              right: 4,
              bottom: 4,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    _redimensionarCard(
                      item,
                      details,
                    );
                  },
                  onPanEnd: (_) {
                    _salvarBloco(
                      item,
                    );
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(
                        0.12,
                      ),
                      borderRadius: BorderRadius.circular(
                        6,
                      ),
                    ),
                    child: Icon(
                      Icons.open_in_full_rounded,
                      size: 14,
                      color: CoresApp.textoSecundario.withOpacity(
                        0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _pesquisaController.dispose();

    for (final item in _orientacoes) {
      item.dispose();
    }

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: CoresApp.fundo,
        body: Center(
          child: CircularProgressIndicator(
            color: CoresApp.primaria,
          ),
        ),
      );
    }

    final orientacoesFiltradas = _orientacoes.where(
      (item) {
        return item.titulo.toLowerCase().contains(
              _filtroPesquisa.toLowerCase(),
            );
      },
    ).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,

      // ==========================================================
      // CABEÇALHO
      // ==========================================================

      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(
          60,
        ),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (String value) {},
          userName: '',
        ),
      ),

      // ==========================================================
      // CORPO
      // ==========================================================

      body: Stack(
        fit: StackFit.expand,
        children: [
          // ========================================================
          // FUNDO
          // ========================================================

          Positioned.fill(
            child: Image.asset(
              AppTheme.caminhoFundo,
              fit: BoxFit.cover,
              errorBuilder: (
                context,
                error,
                stackTrace,
              ) {
                debugPrint(
                  'Erro ao carregar imagem de fundo: '
                  '$error',
                );

                return Container(
                  color: CoresApp.fundo,
                );
              },
            ),
          ),

          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(
                AppTheme.opacidadeFundo,
              ),
            ),
          ),

          // ========================================================
          // CONTEÚDO
          // ========================================================

          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ======================================================
              // TÍTULO + PESQUISA + NOVA ORIENTAÇÃO
              // ======================================================

              Padding(
                padding: const EdgeInsets.all(
                  20,
                ),
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
                        // ==================================================
                        // PESQUISA
                        // ==================================================

                        SizedBox(
                          width: 280,
                          child: Autocomplete<String>(
                            optionsBuilder: (
                              TextEditingValue textEditingValue,
                            ) {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<String>.empty();
                              }

                              return _orientacoes
                                  .map(
                                    (
                                      e,
                                    ) =>
                                        e.titulo,
                                  )
                                  .where(
                                    (
                                      titulo,
                                    ) =>
                                        titulo.toLowerCase().contains(
                                              textEditingValue.text
                                                  .toLowerCase(),
                                            ),
                                  );
                            },
                            onSelected: (
                              String selection,
                            ) {
                              setState(() {
                                _filtroPesquisa = selection;

                                _pesquisaController.text = selection;
                              });
                            },
                            fieldViewBuilder: (
                              context,
                              controller,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                onChanged: (
                                  value,
                                ) {
                                  setState(() {
                                    _filtroPesquisa = value;

                                    _pesquisaController.text = value;
                                  });
                                },
                                style: const TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Pesquisar orientação...',
                                  hintStyle: const TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 13,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: CoresApp.textoSecundario,
                                    size: 18,
                                  ),
                                  suffixIcon:
                                      _pesquisaController.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                color: CoresApp.textoSecundario,
                                                size: 16,
                                              ),
                                              onPressed: () {
                                                setState(
                                                  () {
                                                    _pesquisaController.clear();

                                                    controller.clear();

                                                    _filtroPesquisa = '';
                                                  },
                                                );
                                              },
                                            )
                                          : null,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      10,
                                    ),
                                    borderSide: const BorderSide(
                                      color: CoresApp.borda,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      10,
                                    ),
                                    borderSide: const BorderSide(
                                      color: CoresApp.borda,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      10,
                                    ),
                                    borderSide: const BorderSide(
                                      color: CoresApp.primaria,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: CoresApp.superficie,
                                ),
                              );
                            },
                            optionsViewBuilder: (
                              context,
                              onSelected,
                              options,
                            ) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 8,
                                  color: Colors.transparent,
                                  child: Container(
                                    width: 280,
                                    decoration: BoxDecoration(
                                      color: CoresApp.superficie,
                                      borderRadius: BorderRadius.circular(
                                        10,
                                      ),
                                      border: Border.all(
                                        color: CoresApp.borda,
                                      ),
                                    ),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (
                                        context,
                                        index,
                                      ) {
                                        final option = options.elementAt(
                                          index,
                                        );

                                        return InkWell(
                                          onTap: () => onSelected(
                                            option,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(
                                              12,
                                            ),
                                            child: Text(
                                              option,
                                              style: const TextStyle(
                                                color: CoresApp.textoPrincipal,
                                                fontSize: 14,
                                              ),
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

                        const SizedBox(
                          width: 12,
                        ),

                        // ==================================================
                        // NOVA ORIENTAÇÃO
                        // ==================================================

                        ElevatedButton.icon(
                          onPressed: _adicionarBloco,
                          icon: const Icon(
                            Icons.add_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Nova Orientação',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CoresApp.primaria,
                            foregroundColor: CoresApp.textoPrincipal,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ======================================================
              // ERRO
              // ======================================================

              if (_erroCarregamento != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(
                      12,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.erro.withOpacity(
                        0.12,
                      ),
                      borderRadius: BorderRadius.circular(
                        10,
                      ),
                      border: Border.all(
                        color: CoresApp.erro.withOpacity(
                          0.4,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: CoresApp.erro,
                        ),
                        const SizedBox(
                          width: 10,
                        ),
                        const Expanded(
                          child: Text(
                            'Não foi possível carregar as orientações do Firebase.\n'
                            'Verifique o console para ver o erro.',
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _carregarDados,
                          icon: const Icon(
                            Icons.refresh,
                            color: CoresApp.primaria,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ======================================================
              // ÁREA DOS CARDS
              // ======================================================

              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (orientacoesFiltradas.isEmpty &&
                        _erroCarregamento == null)
                      const Center(
                        child: Text(
                          'Nenhuma orientação encontrada.',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 14,
                          ),
                        ),
                      ),

                    // ==================================================
                    // CARDS
                    // ==================================================

                    for (final item in orientacoesFiltradas)
                      Positioned(
                        left: item.posicao.dx,
                        top: item.posicao.dy,
                        child: GestureDetector(
                          // ==================================================
                          // ARRASTAR CARD
                          // ==================================================

                          onPanUpdate: (
                            details,
                          ) {
                            setState(() {
                              item.posicao += details.delta;
                            });
                          },

                          onPanEnd: (_) {
                            _salvarBloco(
                              item,
                            );
                          },

                          child: _buildCard(
                            item,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
