import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart'
    as quill_extensions;
import 'comentario_dialog_layout.dart';

// Intent exclusivo para interceptar Ctrl+V no editor de comentários.
// Isso permite ler texto e imagem do clipboard do Windows no mesmo paste.
class _ColarComentarioIntent extends Intent {
  const _ColarComentarioIntent();
}

class ComentarioModal {
  static void show(BuildContext context, ProjectModel project) {
    bool modalFechado = false;
    final comentarioController = _ComentarioRichTextController();
    final editorController = quill.QuillController.basic();
    final editorFocusNode = FocusNode();
    final editorScrollController = ScrollController();
    final contadorCaracteresComentario = ValueNotifier<int>(0);
    final ImagePicker imagePicker = ImagePicker();

    // ===============================================================
    // CONTROLE DO EDITOR DE COMENTÁRIO
    // ===============================================================

    final comentarioFocusNode = FocusNode();

    // ===============================================================
    // CONTROLE DE POSIÇÃO E TAMANHO (MOVER E REDIMENSIONAR O MODAL)
    // ===============================================================
    Offset offsetModal = Offset.zero;
    double? larguraCustomizada;
    double? alturaCustomizada;

    // ===============================================================
    // CONTROLE DO FORMULÁRIO DE COMENTÁRIO
    // ===============================================================

    bool salvando = false;

    String? comentarioSelecionadoId;
    String? imagemBase64;

    // Todas as imagens que serão enviadas no mesmo comentário.
    final List<String> imagensBase64 = <String>[];

    // Blocos já confirmados no editor, preservando a ordem real
    // Texto -> imagem -> texto -> imagem... São mantidos para compatibilidade
    // com comentários já salvos no histórico.
    final List<Map<String, String>> blocosComentario = <Map<String, String>>[];

    // Mantém cada bloco de texto reutilizado como um editor rico independente.
    final Map<Map<String, String>, _ComentarioRichTextController>
        controllersBlocosTexto = {};
    final Map<Map<String, String>, FocusNode> focosBlocosTexto = {};

    // Formatação do bloco de texto atualmente em edição.
    String fonteComentario = 'Segoe UI';
    double tamanhoFonteComentario = 11;
    bool negritoComentario = false;
    bool italicoComentario = false;
    bool sublinhadoComentario = false;
    bool tachadoComentario = false;
    TextAlign alinhamentoComentario = TextAlign.left;
    Color corFonteComentario = CoresApp.textoPrincipal;

    Map<String, String> criarBlocoTexto(String texto) => {
          'tipo': 'texto',
          'valor': texto,
          'fonte': fonteComentario,
          'tamanho': tamanhoFonteComentario.toString(),
          'negrito': negritoComentario.toString(),
          'italico': italicoComentario.toString(),
          'sublinhado': sublinhadoComentario.toString(),
          'tachado': tachadoComentario.toString(),
          'alinhamento': alinhamentoComentario.name,
          'cor':
              corFonteComentario.toARGB32().toRadixString(16).padLeft(8, '0'),
        };

    void aplicarFormatacaoNaSelecao() {
      final atributos = <quill.Attribute<dynamic>>[
        quill.Attribute.clone(quill.Attribute.font, fonteComentario),
        quill.Attribute.clone(
          quill.Attribute.size,
          tamanhoFonteComentario.toString(),
        ),
        quill.Attribute.clone(
          quill.Attribute.bold,
          negritoComentario ? true : null,
        ),
        quill.Attribute.clone(
          quill.Attribute.italic,
          italicoComentario ? true : null,
        ),
        quill.Attribute.clone(
          quill.Attribute.underline,
          sublinhadoComentario ? true : null,
        ),
        quill.Attribute.clone(
          quill.Attribute.strikeThrough,
          tachadoComentario ? true : null,
        ),
        quill.Attribute.clone(
          quill.Attribute.color,
          '#${(corFonteComentario.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        ),
      ];

      for (final atributo in atributos) {
        editorController.formatSelection(atributo);
      }
    }

    void focarEditorRicoAtivo() {
      editorFocusNode.requestFocus();
    }

    void aplicarAlinhamentoComentario(TextAlign alinhamento) {
      alinhamentoComentario = alinhamento;
      final atributo = switch (alinhamento) {
        TextAlign.center => quill.Attribute.centerAlignment,
        TextAlign.right => quill.Attribute.rightAlignment,
        TextAlign.justify => quill.Attribute.justifyAlignment,
        _ => quill.Attribute.leftAlignment,
      };
      editorController.formatSelection(atributo);
    }

    TextAlign alinhamentoDoBloco(Map<String, String> bloco) {
      switch (bloco['alinhamento']) {
        case 'center':
          return TextAlign.center;
        case 'right':
          return TextAlign.right;
        case 'justify':
          return TextAlign.justify;
        default:
          return TextAlign.left;
      }
    }

    Color corDoBloco(Map<String, String> bloco) {
      final valor = bloco['cor'];
      if (valor == null || valor.isEmpty) return CoresApp.textoPrincipal;
      final parsed = int.tryParse(valor, radix: 16);
      return parsed == null ? CoresApp.textoPrincipal : Color(parsed);
    }

    String imagemComoDataUri(String imagem) {
      final valor = imagem.trim();
      if (valor.startsWith('data:')) return valor;
      return 'data:image/png;base64,$valor';
    }

    String tamanhoFonteQuill(dynamic valor) {
      final tamanho = double.tryParse(valor?.toString() ?? '');
      if (tamanho != null) return tamanho.toString();
      switch (valor) {
        case 'small':
          return '10';
        case 'large':
          return '18';
        case 'huge':
          return '24';
        default:
          return '11';
      }
    }

    String corQuill(dynamic valor) {
      final cor = valor?.toString().replaceFirst('#', '') ?? '';
      return 'ff${cor.length >= 6 ? cor.substring(cor.length - 6) : '111827'}';
    }

    List<Map<String, String>> blocosDoDocumento() {
      final resultado = <Map<String, String>>[];
      final operacoes = editorController.document.toDelta().toJson();

      for (final operacao in operacoes) {
        final dados = Map<String, dynamic>.from(operacao as Map);
        final inserir = dados['insert'];
        final atributos = dados['attributes'] is Map
            ? Map<String, dynamic>.from(dados['attributes'] as Map)
            : <String, dynamic>{};

        if (inserir is String) {
          if (inserir.isEmpty) continue;

          resultado.add({
            'tipo': 'texto',
            'valor': inserir,
            'fonte': atributos['font']?.toString() ?? 'Segoe UI',
            'tamanho': tamanhoFonteQuill(atributos['size']),
            'negrito': (atributos['bold'] == true).toString(),
            'italico': (atributos['italic'] == true).toString(),
            'sublinhado': (atributos['underline'] == true).toString(),
            'tachado': (atributos['strike'] == true).toString(),
            'alinhamento': atributos['align']?.toString() ?? 'left',
            'cor': corQuill(atributos['color']),
          });
          continue;
        }

        if (inserir is Map && inserir['image'] is String) {
          final origem = inserir['image'] as String;
          final imagem = origem.startsWith('data:') && origem.contains(',')
              ? origem.substring(origem.indexOf(',') + 1)
              : origem;
          resultado.add({
            'tipo': 'imagem',
            'valor': imagem,
            'inline': 'true',
          });
        }
      }

      return resultado;
    }

    List<dynamic> deltaDeBlocos(List<Map<String, String>> blocos) {
      final operacoes = <Map<String, dynamic>>[];

      void inserirTexto(String texto, Map<String, dynamic>? atributos) {
        if (texto.isEmpty) return;
        operacoes.add({
          'insert': texto,
          if (atributos != null && atributos.isNotEmpty)
            'attributes': atributos,
        });
      }

      bool terminaComQuebra() {
        if (operacoes.isEmpty) return true;
        final ultimo = operacoes.last['insert'];
        return ultimo is String && ultimo.endsWith('\n');
      }

      for (final bloco in blocos) {
        if (bloco['tipo'] == 'texto') {
          final atributos = <String, dynamic>{
            if (bloco['negrito'] == 'true') 'bold': true,
            if (bloco['italico'] == 'true') 'italic': true,
            if (bloco['sublinhado'] == 'true') 'underline': true,
            if (bloco['tachado'] == 'true') 'strike': true,
            if ((bloco['fonte'] ?? 'Segoe UI') != 'Segoe UI')
              'font': bloco['fonte'],
            if ((bloco['alinhamento'] ?? 'left') != 'left')
              'align': bloco['alinhamento'],
          };
          final tamanho = double.tryParse(bloco['tamanho'] ?? '');
          if (tamanho != null) atributos['size'] = tamanho.toString();
          final cor = bloco['cor'] ?? '';
          if (cor.length >= 6) {
            atributos['color'] = '#${cor.substring(cor.length - 6)}';
          }
          inserirTexto(bloco['valor'] ?? '', atributos);
          continue;
        }

        if (bloco['tipo'] == 'imagem') {
          final imagem = (bloco['valor'] ?? '').trim();
          if (imagem.isEmpty) continue;

          if (!terminaComQuebra()) inserirTexto('\n', null);
          final rotulo = bloco['rotuloInline'] ?? '';
          inserirTexto(rotulo, null);
          operacoes.add({
            'insert':
                quill.BlockEmbed.image(imagemComoDataUri(imagem)).toJson(),
          });
          inserirTexto('\n', null);
        }
      }

      if (!terminaComQuebra()) inserirTexto('\n', null);
      if (operacoes.isEmpty) inserirTexto('\n', null);
      return operacoes;
    }

    void carregarDocumentoComentario({
      List<Map<String, String>>? blocos,
      String texto = '',
      List<String> imagens = const [],
      List<dynamic>? deltaSalvo,
    }) {
      final operacoes = deltaSalvo ??
          deltaDeBlocos(
            blocos != null && blocos.isNotEmpty
                ? blocos
                : [
                    if (texto.isNotEmpty)
                      {
                        'tipo': 'texto',
                        'valor': texto,
                      },
                    ...imagens.map(
                      (imagem) => {
                        'tipo': 'imagem',
                        'valor': imagem,
                      },
                    ),
                  ],
          );
      editorController.document = quill.Document.fromJson(operacoes);
      contadorCaracteresComentario.value = editorController.document
          .toPlainText()
          .replaceAll('\uFFFC', '')
          .length;
    }

    void sincronizarEstadoEditor() {
      final blocos = blocosDoDocumento();
      blocosComentario
        ..clear()
        ..addAll(blocos);
      imagensBase64
        ..clear()
        ..addAll(
          blocos
              .where((bloco) => bloco['tipo'] == 'imagem')
              .map((bloco) => bloco['valor'] ?? '')
              .where((imagem) => imagem.isNotEmpty),
        );
      imagemBase64 = imagensBase64.isNotEmpty ? imagensBase64.last : null;
      final textoPlano =
          editorController.document.toPlainText().replaceAll('\uFFFC', '');
      if (contadorCaracteresComentario.value != textoPlano.length) {
        contadorCaracteresComentario.value = textoPlano.length;
      }
    }

    editorController.addListener(sincronizarEstadoEditor);

    _ComentarioRichTextController controllerParaBlocoTexto(
      Map<String, String> bloco,
    ) {
      return controllersBlocosTexto.putIfAbsent(bloco, () {
        final controller = _ComentarioRichTextController();
        final texto = bloco['valor'] ?? '';
        controller.text = texto;
        if (texto.isNotEmpty) {
          controller.selection =
              TextSelection(baseOffset: 0, extentOffset: texto.length);
          controller.aplicarFormatacaoNaSelecao(
            fonte: bloco['fonte'] ?? 'Segoe UI',
            tamanho: double.tryParse(bloco['tamanho'] ?? '') ?? 11,
            negrito: bloco['negrito'] == 'true',
            italico: bloco['italico'] == 'true',
            sublinhado: bloco['sublinhado'] == 'true',
            tachado: bloco['tachado'] == 'true',
            cor: corDoBloco(bloco),
          );
          controller.selection = TextSelection.collapsed(offset: texto.length);
        }
        return controller;
      });
    }

    FocusNode focoParaBlocoTexto(Map<String, String> bloco) {
      return focosBlocosTexto.putIfAbsent(bloco, () => FocusNode());
    }

    TextStyle estiloDoBloco(Map<String, String> bloco) {
      return TextStyle(
        color: corDoBloco(bloco),
        fontSize: double.tryParse(bloco['tamanho'] ?? '') ?? 11,
        fontFamily: bloco['fonte'] ?? 'Segoe UI',
        fontWeight:
            bloco['negrito'] == 'true' ? FontWeight.bold : FontWeight.normal,
        fontStyle:
            bloco['italico'] == 'true' ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (bloco['sublinhado'] == 'true') TextDecoration.underline,
          if (bloco['tachado'] == 'true') TextDecoration.lineThrough,
        ]),
      );
    }

    List<Map<String, String>> blocosParaPersistir() {
      return blocosDoDocumento();
    }

    // ===============================================================
    // INSERE UMA IMAGEM NA POSIÇÃO ATUAL DO CURSOR DO DESCRITIVO
    // ===============================================================
    //
    void adicionarImagemAoEditor(String base64Imagem) {
      final selecao = editorController.selection;
      final inicio =
          selecao.start.clamp(0, editorController.document.length - 1);
      final fim =
          selecao.end.clamp(inicio, editorController.document.length - 1);
      final textoAntes =
          editorController.document.toPlainText().substring(0, inicio);
      final prefixo =
          textoAntes.isNotEmpty && !textoAntes.endsWith('\n') ? '\n' : '';
      final imagem = quill.BlockEmbed.image(imagemComoDataUri(base64Imagem));

      editorController.replaceText(
        inicio,
        fim - inicio,
        prefixo,
        TextSelection.collapsed(offset: inicio + prefixo.length),
      );
      final posicaoImagem = editorController.selection.start;
      editorController.replaceText(
        posicaoImagem,
        0,
        imagem,
        TextSelection.collapsed(offset: posicaoImagem + 1),
      );
      editorController.replaceText(
        posicaoImagem + 1,
        0,
        '\n',
        TextSelection.collapsed(offset: posicaoImagem + 2),
      );
    }

    // ===============================================================
    // COLA TEXTO + IMAGEM DO CLIPBOARD NO DESCRITIVO
    // ===============================================================
    //
    // O TextField padrão do Flutter cola apenas o texto. Para o descritivo
    // copiado de uma origem rica (Ctrl+C), lemos também a imagem existente
    // no clipboard do Windows através do package pasteboard.
    //
    // No modelo utilizado pelo projeto, a imagem de situação pertence à
    // linha "Situação do Projeto:". Quando essa linha estiver presente no
    // texto copiado, a imagem é inserida imediatamente depois do rótulo,
    // mantendo o restante do texto abaixo dela.
    Future<void> colarConteudoRicoDoClipboard(
      StateSetter setDialogState,
    ) async {
      try {
        final resultados = await Future.wait<dynamic>([
          Pasteboard.text,
          Pasteboard.image,
        ]);
        if (modalFechado) return;

        final textoClipboard = (resultados[0] as String?) ?? '';
        final Uint8List? imagemClipboard = resultados[1] as Uint8List?;

        final selecao = editorController.selection;
        final inicio =
            selecao.start.clamp(0, editorController.document.length - 1);
        final fim =
            selecao.end.clamp(inicio, editorController.document.length - 1);

        void substituirSelecao(String texto) {
          editorController.replaceText(
            inicio,
            fim - inicio,
            texto,
            TextSelection.collapsed(offset: inicio + texto.length),
          );
        }

        // Sem imagem no clipboard: mantém a colagem normal de texto.
        if (imagemClipboard == null || imagemClipboard.isEmpty) {
          if (textoClipboard.isEmpty) return;
          substituirSelecao(textoClipboard);
          return;
        }

        final base64Imagem = base64Encode(imagemClipboard);
        const marcadorSituacao = 'Situação do Projeto:';
        final indiceMarcador = textoClipboard.indexOf(marcadorSituacao);

        setDialogState(() {
          if (indiceMarcador >= 0) {
            var corte = indiceMarcador + marcadorSituacao.length;
            while (corte < textoClipboard.length &&
                (textoClipboard[corte] == ' ' ||
                    textoClipboard[corte] == '\t')) {
              corte++;
            }

            final espacosDepoisDoMarcador = textoClipboard.substring(
              indiceMarcador + marcadorSituacao.length,
              corte,
            );
            final antesDoMarcador = textoClipboard.substring(0, indiceMarcador);
            final textoDoRotulo = '$marcadorSituacao$espacosDepoisDoMarcador';
            final textoDepois = textoClipboard.substring(corte);
            final prefixo =
                antesDoMarcador.isNotEmpty && !antesDoMarcador.endsWith('\n')
                    ? '$antesDoMarcador\n'
                    : antesDoMarcador;
            final sufixo =
                textoDepois.isNotEmpty && !textoDepois.startsWith('\n')
                    ? '\n$textoDepois'
                    : textoDepois;

            final textoAntesDaSelecao =
                editorController.document.toPlainText().substring(0, inicio);
            final separadorAntes = textoAntesDaSelecao.isNotEmpty &&
                    !textoAntesDaSelecao.endsWith('\n')
                ? '\n'
                : '';
            final insercao = '$separadorAntes$prefixo$textoDoRotulo';
            editorController.replaceText(
              inicio,
              fim - inicio,
              insercao,
              TextSelection.collapsed(offset: inicio + insercao.length),
            );
            final posicaoImagem = editorController.selection.start;
            editorController.replaceText(
              posicaoImagem,
              0,
              quill.BlockEmbed.image(imagemComoDataUri(base64Imagem)),
              TextSelection.collapsed(offset: posicaoImagem + 1),
            );
            editorController.replaceText(
              posicaoImagem + 1,
              0,
              sufixo,
              TextSelection.collapsed(
                offset: posicaoImagem + 1 + sufixo.length,
              ),
            );
          } else {
            final textoAntesDaSelecao =
                editorController.document.toPlainText().substring(0, inicio);
            final separadorAntes = textoAntesDaSelecao.isNotEmpty &&
                    !textoAntesDaSelecao.endsWith('\n') &&
                    textoClipboard.isNotEmpty
                ? '\n'
                : '';
            final antes = '$separadorAntes$textoClipboard';
            final sufixo =
                textoClipboard.isNotEmpty && !textoClipboard.endsWith('\n')
                    ? '\n'
                    : '';
            editorController.replaceText(
              inicio,
              fim - inicio,
              antes,
              TextSelection.collapsed(offset: inicio + antes.length),
            );
            final posicaoImagem = editorController.selection.start;
            editorController.replaceText(
              posicaoImagem,
              0,
              quill.BlockEmbed.image(imagemComoDataUri(base64Imagem)),
              TextSelection.collapsed(offset: posicaoImagem + 1),
            );
            editorController.replaceText(
              posicaoImagem + 1,
              0,
              sufixo,
              TextSelection.collapsed(
                  offset: posicaoImagem + 1 + sufixo.length),
            );
          }

          sincronizarEstadoEditor();
        });

        editorFocusNode.requestFocus();
      } catch (e) {
        debugPrint('[ComentarioClipboard] Erro ao colar conteúdo rico: $e');
      }
    }

    // ===============================================================
    // INDICADORES DE SITUAÇÃO (VERDE / AMARELO / VERMELHO)
    // ===============================================================
    //
    // O indicador é gravado como uma imagem PNG real. Dessa forma ele
    // continua compatível com o fluxo já existente de imagens do E-Desk,
    // mas dentro do editor recebe metadados próprios para ser exibido
    // inline e redimensionado pelo usuário.
    Future<String> gerarIndicadorBase64(
      Color cor,
      double largura,
      double altura,
    ) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = cor;
      final rect = Rect.fromLTWH(0, 0, largura, altura);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        largura.round().clamp(1, 1000),
        altura.round().clamp(1, 500),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (bytes == null) {
        throw Exception('Não foi possível gerar o indicador.');
      }

      return base64Encode(bytes.buffer.asUint8List());
    }

    Color corIndicador(String nome) {
      switch (nome) {
        case 'amarelo':
          return const Color(0xFFFFC928);
        case 'vermelho':
          return const Color(0xFFF52222);
        default:
          return const Color(0xFF47D35A);
      }
    }

    Future<void> inserirIndicador(
      String corNome,
      StateSetter setDialogState,
    ) async {
      const larguraInicial = 90.0;
      const alturaInicial = 18.0;
      final base64Indicador = await gerarIndicadorBase64(
        corIndicador(corNome),
        larguraInicial,
        alturaInicial,
      );
      if (modalFechado) return;

      setDialogState(() {
        final selecao = editorController.selection;
        final inicio = selecao.start.clamp(
          0,
          editorController.document.length - 1,
        );
        final fim = selecao.end.clamp(
          inicio,
          editorController.document.length - 1,
        );
        editorController.replaceText(
          inicio,
          fim - inicio,
          quill.BlockEmbed.image(imagemComoDataUri(base64Indicador)),
          TextSelection.collapsed(offset: inicio + 1),
        );
        sincronizarEstadoEditor();
      });

      editorFocusNode.requestFocus();
    }

    Future<void> redimensionarIndicador(
      int index,
      double fator,
      StateSetter setDialogState,
    ) async {
      if (index < 0 || index >= blocosComentario.length) return;
      final bloco = blocosComentario[index];
      if (bloco['indicador'] != 'true') return;

      final larguraAtual =
          double.tryParse(bloco['larguraIndicador'] ?? '') ?? 90.0;
      final alturaAtual =
          double.tryParse(bloco['alturaIndicador'] ?? '') ?? 18.0;

      final novaLargura = (larguraAtual * fator).clamp(40.0, 240.0);
      final novaAltura = (alturaAtual * fator).clamp(8.0, 48.0);
      final corNome = bloco['corIndicador'] ?? 'verde';
      final base64Antigo = bloco['valor'] ?? '';
      final novoBase64 = await gerarIndicadorBase64(
        corIndicador(corNome),
        novaLargura,
        novaAltura,
      );
      if (modalFechado) return;

      setDialogState(() {
        bloco['valor'] = novoBase64;
        bloco['larguraIndicador'] = novaLargura.toString();
        bloco['alturaIndicador'] = novaAltura.toString();

        final indiceImagem = imagensBase64.indexOf(base64Antigo);
        if (indiceImagem >= 0) {
          imagensBase64[indiceImagem] = novoBase64;
        }
        if (imagemBase64 == base64Antigo) {
          imagemBase64 = novoBase64;
        }
      });
    }

    // ===============================================================
    // TAMANHO VISUAL DAS IMAGENS NO EDITOR
    // ===============================================================
    //
    // Este tamanho existe somente na interface do Gerenciador de Horas.
    // A imagem Base64 original continua intacta para salvar e enviar ao E-Desk.
    // Portanto, os controles de edição nunca fazem parte do comentário enviado.
    void redimensionarImagemEditor(
      int index,
      double fator,
      StateSetter setDialogState,
    ) {
      if (index < 0 || index >= blocosComentario.length) return;

      final bloco = blocosComentario[index];
      if (bloco['tipo'] != 'imagem' || bloco['indicador'] == 'true') return;

      final larguraAtual =
          double.tryParse(bloco['larguraImagemEditor'] ?? '') ?? 760.0;
      final novaLargura = (larguraAtual * fator).clamp(120.0, 1000.0);

      setDialogState(() {
        bloco['larguraImagemEditor'] = novaLargura.toString();
      });
    }

    // Texto limpo usado no histórico/Firebase.
    // Imagens continuam persistidas em blocosComentario/imagensBase64,
    // mas nenhum marcador técnico aparece para o usuário.
    String montarTextoOrdenado() {
      final buffer = StringBuffer();

      for (final bloco in blocosParaPersistir()) {
        if (bloco['tipo'] == 'texto') {
          final valor = bloco['valor'] ?? '';
          if (valor.isNotEmpty) {
            buffer.write(valor);
            if (!valor.endsWith('\n')) buffer.write('\n');
          }
          continue;
        }

        if (bloco['tipo'] == 'imagem') {
          final rotuloInline = bloco['rotuloInline'] ?? '';
          if (rotuloInline.isNotEmpty) {
            buffer.write(rotuloInline);
            if (!rotuloInline.endsWith('\n')) buffer.write('\n');
          }
        }
      }

      return buffer.toString().trim();
    }

    String escaparHtmlComentario(String valor) {
      return valor
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&#39;');
    }

    String blocoTextoParaHtml(Map<String, String> bloco) {
      final texto = escaparHtmlComentario(bloco['valor'] ?? '')
          .replaceAll('\r\n', '<br>')
          .replaceAll('\r', '<br>');
      if (texto.isEmpty) return '';

      final linhas = texto.replaceAll('<br>', '\n').split('\n');
      final fonte = escaparHtmlComentario(bloco['fonte'] ?? 'Segoe UI');
      final tamanho = double.tryParse(bloco['tamanho'] ?? '') ?? 11;
      final negrito = bloco['negrito'] == 'true' ? 'bold' : 'normal';
      final italico = bloco['italico'] == 'true' ? 'italic' : 'normal';
      final decoracoes = <String>[
        if (bloco['sublinhado'] == 'true') 'underline',
        if (bloco['tachado'] == 'true') 'line-through',
      ];
      final decoracao = decoracoes.isEmpty ? 'none' : decoracoes.join(' ');
      final alinhamento = bloco['alinhamento'] ?? 'left';
      final corArgb = bloco['cor'] ?? 'ff111827';
      final corRgb = corArgb.length >= 6
          ? corArgb.substring(corArgb.length - 6)
          : '111827';
      final corTextoPadraoApp = CoresApp.textoPrincipal
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toLowerCase();
      final corTextoEdesk =
          corRgb.toLowerCase() == corTextoPadraoApp ? '111827' : corRgb;
      final estilo = 'font-family:$fonte;font-size:${tamanho}px;'
          'font-weight:$negrito;font-style:$italico;'
          'text-decoration:$decoracao;color:#$corTextoEdesk;'
          'text-align:$alinhamento;';

      return linhas
          .map(
            (linha) =>
                linha.isEmpty ? '' : '<span style="$estilo">$linha</span>',
          )
          .join('<br>');
    }

    // HTML final do documento. As imagens são incorporadas na posição
    // em que aparecem no editor; não existem placeholders EDESK_IMAGE.
    String montarHtmlEdesk() {
      final buffer = StringBuffer('[[EDESK_HTML]]');
      final tamanhoMarcador = '[[EDESK_HTML]]'.length;
      var terminaComQuebra = false;
      var quebraPendente = false;

      void escrever(String html) {
        if (html.isEmpty) return;
        buffer.write(html);
        terminaComQuebra = html.endsWith('<br>');
      }

      for (final bloco in blocosParaPersistir()) {
        if (bloco['tipo'] == 'texto') {
          final html = blocoTextoParaHtml(bloco);
          if (html.isEmpty) continue;

          if (quebraPendente && !html.startsWith('<br>')) {
            escrever('<br>');
          }
          escrever(html);
          quebraPendente = false;
          continue;
        }

        if (bloco['tipo'] == 'imagem') {
          if (buffer.length > tamanhoMarcador && !terminaComQuebra) {
            escrever('<br>');
          }

          final rotuloInline = bloco['rotuloInline'] ?? '';
          if (rotuloInline.isNotEmpty) {
            final blocoRotulo = Map<String, String>.from(bloco)
              ..['tipo'] = 'texto'
              ..['valor'] = rotuloInline;
            escrever(blocoTextoParaHtml(blocoRotulo));
          }

          final imagem = (bloco['valor'] ?? '').trim();
          if (imagem.isNotEmpty) {
            final src = imagem.startsWith('data:')
                ? imagem
                : 'data:image/png;base64,$imagem';
            escrever(
              '<img src="${escaparHtmlComentario(src)}" '
              'alt="" style="max-width:100%;height:auto;vertical-align:middle;">',
            );
            quebraPendente = true;
          }

          if (bloco['inline'] != 'true') quebraPendente = true;
        }
      }

      return buffer.toString();
    }

    // Texto utilizado para filtrar o histórico da lateral direita.
    String buscaHistorico = '';

    // ===============================================================
    // EXCEL DO PROJETO
    // ===============================================================

    String? imagemExcelBase64;

    // Mantém todas as tabelas do Excel adicionadas ao comentário.
    final List<String> imagensExcelBase64 = <String>[];
    final List<String> intervalosExcelAdicionados = <String>[];

    bool carregandoExcel = false;
    String? erroExcel;

    // ===============================================================
    // TIPO DO COMENTÁRIO
    // ===============================================================

    String tipoComentario = 'Interno';

// ===============================================================
// CONFIGURAÇÕES DOS COMENTÁRIOS E-DESK
// Etiquetas + campos/faixas do Excel
// ===============================================================

    String etiquetaSelecionada = 'Enterprise';

// Campo do Excel escolhido no botão "Usar imagem do Excel".
    String? campoExcelSelecionado;

// Configuração carregada do Firebase.
//
// Estrutura:
//
// {
//   'Enterprise': [
//     {
//       'nome': 'Capa do projeto',
//       'intervalo': 'A1:D20',
//     },
//   ],
// }
    Map<String, List<Map<String, String>>> camposExcelPorEtiqueta = {
      'Enterprise': [
        {
          'nome': 'Capa do projeto',
          'intervalo': 'A1:D20',
        },
        {
          'nome': 'Cronograma',
          'intervalo': 'A22:H60',
        },
        {
          'nome': 'Recursos',
          'intervalo': 'A62:F90',
        },
      ],
      'Professional': [],
      'Catalog': [],
      'Consultoria': [],
    };

// Lista exibida no dropdown "ETIQUETAS DO CHAMADO".
    List<String> etiquetasComentario = [
      'Enterprise',
      'Professional',
      'Catalog',
      'Consultoria',
    ];

    List<Map<String, String>> modelosDescricao = <Map<String, String>>[];
    String? modeloDescricaoSelecionado;

    bool carregandoConfiguracoesEdesk = false;
    bool configuracoesEdeskCarregadas = false;

    void inserirModeloDescricao(
      String nomeModelo,
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) {
      final modelo = modelosDescricao.where(
        (item) => item['nome'] == nomeModelo,
      );
      if (modelo.isEmpty) return;

      final conteudo = (modelo.first['conteudo'] ?? '').trim();
      if (conteudo.isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('O modelo "$nomeModelo" ainda não tem conteúdo.'),
            backgroundColor: CoresApp.erro,
          ),
        );
        return;
      }

      if (imagensExcelBase64.isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Adicione primeiro a imagem gerada da planilha para inserir o modelo logo abaixo dela.',
            ),
          ),
        );
        return;
      }

      final imagemAlvo = imagensExcelBase64.last;
      final operacoes = editorController.document.toDelta().toJson();
      var indice = 0;
      int? fimImagemExcel;

      for (final operacao in operacoes) {
        final dados = Map<String, dynamic>.from(operacao as Map);
        final inserir = dados['insert'];
        if (inserir is String) {
          indice += inserir.length;
          continue;
        }

        if (inserir is Map && inserir['image'] is String) {
          final origem = inserir['image'] as String;
          final imagem = origem.startsWith('data:') && origem.contains(',')
              ? origem.substring(origem.indexOf(',') + 1)
              : origem;
          if (imagem == imagemAlvo) {
            fimImagemExcel = indice + 1;
          }
          indice++;
        }
      }

      if (fimImagemExcel == null) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Não encontrei a imagem da planilha no descritivo. Adicione-a novamente para inserir o modelo.',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
        return;
      }

      final textoDocumento = editorController.document.toPlainText();
      var posicaoInsercao = fimImagemExcel;
      if (posicaoInsercao < textoDocumento.length &&
          textoDocumento[posicaoInsercao] == '\n') {
        posicaoInsercao++;
      }

      if (textoDocumento.startsWith(conteudo, posicaoInsercao)) {
        setDialogState(() {
          modeloDescricaoSelecionado = nomeModelo;
        });
        return;
      }

      final prefixo =
          posicaoInsercao > 0 && textoDocumento[posicaoInsercao - 1] != '\n'
              ? '\n'
              : '';
      final conteudoComSeparacao =
          '$prefixo$conteudo${conteudo.endsWith('\n') ? '' : '\n\n'}';

      editorController.replaceText(
        posicaoInsercao,
        0,
        conteudoComSeparacao,
        TextSelection.collapsed(
          offset: posicaoInsercao + conteudoComSeparacao.length,
        ),
      );
      setDialogState(() {
        modeloDescricaoSelecionado = nomeModelo;
      });
      editorFocusNode.requestFocus();
    }

// ===============================================================
// REFERÊNCIA DA CONFIGURAÇÃO NO FIREBASE
// ===============================================================

    DocumentReference<Map<String, dynamic>> configuracaoComentariosEdeskRef() {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('configuracoes')
          .doc('comentarios_edesk');
    }

// ===============================================================
// CARREGAR CONFIGURAÇÕES DO FIREBASE
// ===============================================================

    Future<void> carregarConfiguracoesComentariosEdesk(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (carregandoConfiguracoesEdesk) return;

      setDialogState(() {
        carregandoConfiguracoesEdesk = true;
      });

      try {
        final snapshot = await configuracaoComentariosEdeskRef().get();

        if (!dialogContext.mounted) return;

        // -------------------------------------------------------------
        // Ainda não existe configuração salva.
        // Mantemos os valores padrão definidos acima.
        // -------------------------------------------------------------

        if (!snapshot.exists) {
          configuracoesEdeskCarregadas = true;

          if (etiquetasComentario.isNotEmpty &&
              !etiquetasComentario.contains(etiquetaSelecionada)) {
            etiquetaSelecionada = etiquetasComentario.first;
          }

          return;
        }

        final dados = snapshot.data();

        if (dados == null) {
          configuracoesEdeskCarregadas = true;
          return;
        }

        // -------------------------------------------------------------
        // CARREGA ETIQUETAS
        // -------------------------------------------------------------

        final etiquetasFirebase = dados['etiquetas'];

        final novasEtiquetas = <String>[];

        if (etiquetasFirebase is List) {
          for (final item in etiquetasFirebase) {
            final nome = item.toString().trim();

            if (nome.isNotEmpty && !novasEtiquetas.contains(nome)) {
              novasEtiquetas.add(nome);
            }
          }
        }

        // -------------------------------------------------------------
        // CARREGA CAMPOS DO EXCEL
        // -------------------------------------------------------------

        final novosModelosDescricao = <Map<String, String>>[];
        final modelosFirebase = dados['modelosDescricao'];
        if (modelosFirebase is List) {
          for (final item in modelosFirebase.whereType<Map>()) {
            final nome = item['nome']?.toString().trim() ?? '';
            final conteudo = item['conteudo']?.toString() ?? '';
            if (nome.isNotEmpty) {
              novosModelosDescricao.add({
                'nome': nome,
                'conteudo': conteudo,
              });
            }
          }
        }

        final novosCampos = <String, List<Map<String, String>>>{};

        final camposFirebase = dados['camposExcel'];

        if (camposFirebase is Map) {
          for (final entry in camposFirebase.entries) {
            final etiqueta = entry.key.toString().trim();

            if (etiqueta.isEmpty) continue;

            final listaCampos = <Map<String, String>>[];

            final valor = entry.value;

            if (valor is List) {
              for (final campo in valor) {
                if (campo is Map) {
                  final nome = campo['nome']?.toString().trim() ?? '';
                  final intervalo =
                      campo['intervalo']?.toString().trim().toUpperCase() ?? '';

                  if (nome.isNotEmpty || intervalo.isNotEmpty) {
                    listaCampos.add({
                      'nome': nome,
                      'intervalo': intervalo,
                    });
                  }
                }
              }
            }

            novosCampos[etiqueta] = listaCampos;
          }
        }

        // -------------------------------------------------------------
        // ATUALIZA O MODAL PRINCIPAL
        // -------------------------------------------------------------

        setDialogState(() {
          // O Firebase é a fonte definitiva da configuração.
// Inclusive uma lista vazia precisa ser respeitada.
          etiquetasComentario = List<String>.from(novasEtiquetas);

          camposExcelPorEtiqueta = {
            for (final etiqueta in etiquetasComentario)
              etiqueta: List<Map<String, String>>.from(
                novosCampos[etiqueta] ?? const [],
              ),
          };
          modelosDescricao = novosModelosDescricao;
          if (!modelosDescricao.any(
            (modelo) => modelo['nome'] == modeloDescricaoSelecionado,
          )) {
            modeloDescricaoSelecionado = null;
          }

          if (!etiquetasComentario.contains(etiquetaSelecionada)) {
            etiquetaSelecionada =
                etiquetasComentario.isNotEmpty ? etiquetasComentario.first : '';
          }

          campoExcelSelecionado = null;
          configuracoesEdeskCarregadas = true;
        });
      } catch (e) {
        debugPrint(
          'Erro ao carregar configurações dos comentários E-Desk: $e',
        );

        // Se ocorrer erro no Firebase, mantemos a configuração local
        // para não impedir a abertura do modal.
        configuracoesEdeskCarregadas = true;
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() {
            carregandoConfiguracoesEdesk = false;
          });
        }
      }
    }

// ===============================================================
// SALVAR CONFIGURAÇÕES NO FIREBASE
// ===============================================================

    Future<void> salvarConfiguracoesComentariosEdesk({
      required List<String> etiquetas,
      required Map<String, List<Map<String, String>>> campos,
      required List<Map<String, String>> modelos,
    }) async {
      final etiquetasLimpas = etiquetas
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

      final camposFirebase = <String, dynamic>{};

      for (final etiqueta in etiquetasLimpas) {
        final lista = campos[etiqueta] ?? const [];

        camposFirebase[etiqueta] = lista
            .map(
              (campo) => {
                'nome': campo['nome']?.trim() ?? '',
                'intervalo': campo['intervalo']?.trim().toUpperCase() ?? '',
              },
            )
            .where(
              (campo) =>
                  campo['nome']!.isNotEmpty || campo['intervalo']!.isNotEmpty,
            )
            .toList();
      }

      final modelosFirebase = modelos
          .map(
            (modelo) => {
              'nome': modelo['nome']?.trim() ?? '',
              'conteudo': modelo['conteudo'] ?? '',
            },
          )
          .where((modelo) => modelo['nome']!.isNotEmpty)
          .toList();

// Substitui completamente a configuração.
// Assim, etiquetas e campos excluídos também são removidos do Firebase.
      await configuracaoComentariosEdeskRef().set(
        {
          'etiquetas': etiquetasLimpas,
          'camposExcel': camposFirebase,
          'modelosDescricao': modelosFirebase,
          'atualizadoEm': FieldValue.serverTimestamp(),
        },
      );
    }

// ===============================================================
// ETIQUETA E-DESK DO PROJETO
// ===============================================================

    DocumentReference<Map<String, dynamic>> projetoEdeskRef() {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }
      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('projects')
          .doc(project.id.trim());
    }

    Future<void> carregarEtiquetaProjeto(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      try {
        final snapshot = await projetoEdeskRef().get();
        if (!dialogContext.mounted) return;

        final etiquetaSalva =
            snapshot.data()?['etiquetaComentarioEdesk']?.toString().trim() ??
                '';

        if (etiquetaSalva.isNotEmpty &&
            etiquetasComentario.contains(etiquetaSalva)) {
          setDialogState(() {
            etiquetaSelecionada = etiquetaSalva;
            campoExcelSelecionado = null;
            imagemExcelBase64 = null;
          });
        }
      } catch (e) {
        debugPrint('Erro ao carregar etiqueta E-Desk do projeto: $e');
      }
    }

    Future<void> salvarEtiquetaProjeto(String etiqueta) async {
      final valor = etiqueta.trim();
      if (valor.isEmpty) return;

      await projetoEdeskRef().set(
        {
          'etiquetaComentarioEdesk': valor,
          'etiquetaComentarioEdeskAtualizadaEm': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

// ===============================================================
// CAMPOS DO EXCEL DA ETIQUETA ATUAL
// ===============================================================

    List<Map<String, String>> camposExcelEtiquetaAtual() {
      return camposExcelPorEtiqueta[etiquetaSelecionada] ?? const [];
    }
    // ===============================================================
    // CONTROLE E-DESK
    // ===============================================================

    bool testandoEdesk = false;
    bool enviandoEdesk = false;

    // ===============================================================
    // REFERÊNCIA DOS COMENTÁRIOS E-DESK
    // ===============================================================

    CollectionReference<Map<String, dynamic>> comentariosRef() {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('projects')
          .doc(project.id.trim())
          .collection('comentarios_edesk');
    }

    // ===============================================================
    // LOCALIZA A ETAPA CONFIGURADA PARA O E-DESK
    // ===============================================================

    TaskModel? obterTaskEdesk() {
      final tarefas = project.subTasks ?? [];

      for (final task in tarefas) {
        if (task.edeskIdTrabalho?.trim().isNotEmpty ?? false) {
          return task;
        }
      }

      return null;
    }

    // ===============================================================
    // SELECIONAR IMAGEM
    // ===============================================================

    Future<void> selecionarImagem(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      try {
        final XFile? arquivo = await imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
          maxWidth: 1600,
          maxHeight: 1600,
        );

        if (arquivo == null) return;

        final bytes = await arquivo.readAsBytes();
        if (!dialogContext.mounted) return;

        setDialogState(() {
          final novaImagem = base64Encode(bytes);
          adicionarImagemAoEditor(novaImagem);
        });
      } catch (e) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar imagem: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }

    // ===============================================================
    // LIMPAR FORMULÁRIO
    // ===============================================================

    void limparFormulario(
      StateSetter setDialogState,
    ) {
      comentarioController.clear();
      comentarioFocusNode.unfocus();
      carregarDocumentoComentario();

      setDialogState(() {
        comentarioSelecionadoId = null;
        imagensBase64.clear();
        blocosComentario.clear();
        controllersBlocosTexto.clear();
        focosBlocosTexto.clear();

        imagensExcelBase64.clear();
        intervalosExcelAdicionados.clear();
        imagemBase64 = null;
        imagemExcelBase64 = null;
        campoExcelSelecionado = null;
        tipoComentario = 'Interno';
      });
    }

    // ===============================================================
    // EXCLUIR COMENTÁRIO
    // ===============================================================

    Future<void> excluirComentario(
      BuildContext dialogContext,
      StateSetter setDialogState,
      String comentarioId,
    ) async {
      final confirmar = await showDialog<bool>(
        context: dialogContext,
        builder: (confirmContext) {
          return AlertDialog(
            backgroundColor: CoresTelas.fundoModal,
            title: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                ),
                const SizedBox(width: 8),
                Text(
                  'Excluir comentário',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                  ),
                ),
              ],
            ),
            content: Text(
              'Deseja realmente excluir este comentário?',
              style: TextStyle(
                color: CoresApp.textoPrincipal,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(confirmContext).pop(false);
                },
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CoresApp.erro,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                ),
                label: const Text('Excluir'),
                onPressed: () {
                  Navigator.of(confirmContext).pop(true);
                },
              ),
            ],
          );
        },
      );

      if (confirmar != true || !dialogContext.mounted) return;

      try {
        final ref = comentariosRef();
        await ref.doc(comentarioId).delete();
        if (!dialogContext.mounted) return;

        if (comentarioSelecionadoId == comentarioId) {
          comentarioController.clear();
          comentarioFocusNode.unfocus();
          carregarDocumentoComentario();

          setDialogState(() {
            comentarioSelecionadoId = null;
            imagemBase64 = imagemExcelBase64;
            tipoComentario = 'Interno';
          });
        }

        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Comentário excluído com sucesso.',
            ),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      } catch (e) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao excluir comentário: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }

// ===============================================================
// CARREGA IMAGEM DO EXCEL DO PROJETO
// ===============================================================

    Future<void> carregarExcelProjeto(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      // =============================================================
      // VALIDAÇÕES
      // =============================================================

      final caminho = project.excelLink?.trim() ?? '';

      if (caminho.isEmpty) {
        setDialogState(() {
          erroExcel = 'Nenhum arquivo Excel vinculado a este projeto.';
          carregandoExcel = false;
        });

        return;
      }

      final intervalo = campoExcelSelecionado?.trim().toUpperCase() ?? '';

      if (intervalo.isEmpty) {
        setDialogState(() {
          erroExcel = 'Selecione uma área do Excel para utilizar.';
          carregandoExcel = false;
        });

        return;
      }

      final arquivo = File(caminho);

      final arquivoExiste = await arquivo.exists();
      if (!dialogContext.mounted) return;
      if (!arquivoExiste) {
        setDialogState(() {
          erroExcel = 'Arquivo Excel não encontrado:\n$caminho';
          carregandoExcel = false;
        });

        return;
      }

      setDialogState(() {
        carregandoExcel = true;
        erroExcel = null;
      });

      Process? processo;

      try {
        // =============================================================
        // PYTHON
        //
        // IMPORTANTE:
        // O openpyxl foi confirmado neste Python 3.14.
        // Não usamos mais a .venv antiga para o Excel Preview.
        // =============================================================

        // Resolve os caminhos do Excel Preview sem depender do caminho
        // fixo da máquina de desenvolvimento. No aplicativo instalado,
        // os arquivos ficam ao lado do executável. Durante o desenvolvimento,
        // também aceitamos os caminhos do projeto e o Python local já usado.
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final projetoDir = Directory.current.path;
        final localAppData = Platform.environment['LOCALAPPDATA'];

        String? primeiroArquivoExistente(List<String> candidatos) {
          for (final candidato in candidatos) {
            if (candidato.trim().isNotEmpty && File(candidato).existsSync()) {
              return candidato;
            }
          }
          return null;
        }

        final candidatosPython = <String>[
          '$exeDir\\python\\python.exe',
          '$exeDir\\python\\Scripts\\python.exe',
          '$projetoDir\\python\\python.exe',
          '$projetoDir\\python\\Scripts\\python.exe',
          '$projetoDir\\.venv\\Scripts\\python.exe',
          if (localAppData != null && localAppData.trim().isNotEmpty)
            '$localAppData\\Python\\pythoncore-3.14-64\\python.exe',
        ];

        final candidatosScript = <String>[
          '$exeDir\\edesk_bot\\excel_preview.py',
          '$projetoDir\\edesk_bot\\excel_preview.py',
        ];

        final pythonExe = primeiroArquivoExistente(candidatosPython);
        final scriptExcel = primeiroArquivoExistente(candidatosScript);

        if (pythonExe == null) {
          throw Exception(
            'Python não encontrado para o Excel Preview.\n'
            'Caminhos verificados:\n${candidatosPython.join('\n')}',
          );
        }

        if (scriptExcel == null) {
          throw Exception(
            'Script excel_preview.py não encontrado.\n'
            'Caminhos verificados:\n${candidatosScript.join('\n')}',
          );
        }

        final pythonFile = File(pythonExe);
        final scriptFile = File(scriptExcel);

        // =============================================================
        // CONFERE OS ARQUIVOS
        // =============================================================

        if (!await pythonFile.exists()) {
          throw Exception(
            'Python 3.14 não encontrado:\n$pythonExe',
          );
        }

        if (!await scriptFile.exists()) {
          throw Exception(
            'Script excel_preview.py não encontrado:\n$scriptExcel',
          );
        }

        debugPrint('');
        debugPrint('==============================================');
        debugPrint('[ExcelPreview] INICIANDO PREVIEW');
        debugPrint('==============================================');
        debugPrint('[ExcelPreview] Python: $pythonExe');
        debugPrint('[ExcelPreview] Script: $scriptExcel');
        debugPrint('[ExcelPreview] Excel: $caminho');
        debugPrint('[ExcelPreview] Intervalo: $intervalo');

        // =============================================================
        // INICIA O PYTHON
        // =============================================================

        processo = await Process.start(
          pythonExe,
          [
            '-u',
            scriptExcel,
          ],
          runInShell: false,
        );

        debugPrint(
          '[ExcelPreview] Processo iniciado. PID: ${processo.pid}',
        );

        // =============================================================
        // STDERR
        // =============================================================

        final stderrBuffer = StringBuffer();

        processo.stderr
            .transform(
              const Utf8Decoder(
                allowMalformed: true,
              ),
            )
            .transform(
              const LineSplitter(),
            )
            .listen(
          (linha) {
            final texto = linha.trim();

            if (texto.isEmpty) {
              return;
            }

            stderrBuffer.writeln(texto);

            debugPrint(
              '[excel_preview.py] $texto',
            );
          },
          onError: (erro) {
            debugPrint(
              '[ExcelPreview] Erro ao ler STDERR: $erro',
            );
          },
        );

        // =============================================================
        // PREPARA A RESPOSTA
        // =============================================================

        final respostaCompleter = Completer<Map<String, dynamic>>();

        processo.stdout
            .transform(
              const Utf8Decoder(
                allowMalformed: true,
              ),
            )
            .transform(
              const LineSplitter(),
            )
            .listen(
          (linha) {
            final texto = linha.trim();

            if (texto.isEmpty) {
              return;
            }

            debugPrint(
              '[excel_preview.py stdout] $texto',
            );

            try {
              final decoded = jsonDecode(texto);

              if (decoded is Map) {
                final resposta = Map<String, dynamic>.from(decoded);

                if (!respostaCompleter.isCompleted) {
                  respostaCompleter.complete(resposta);
                }
              }
            } catch (_) {
              // Ignora qualquer saída que não seja JSON.
            }
          },
          onError: (erro) {
            if (!respostaCompleter.isCompleted) {
              respostaCompleter.completeError(
                Exception(
                  'Erro ao ler resposta do excel_preview.py: $erro',
                ),
              );
            }
          },
          onDone: () {
            if (!respostaCompleter.isCompleted) {
              final erroPython = stderrBuffer.toString().trim();

              if (erroPython.isNotEmpty) {
                respostaCompleter.completeError(
                  Exception(
                    'excel_preview.py foi encerrado sem retornar '
                    'uma resposta válida.\n\n$erroPython',
                  ),
                );
              } else {
                respostaCompleter.completeError(
                  Exception(
                    'excel_preview.py foi encerrado sem retornar '
                    'uma resposta válida.',
                  ),
                );
              }
            }
          },
        );

        // =============================================================
        // ENVIA COMANDO PARA O PYTHON
        // =============================================================

        final comando = jsonEncode({
          'acao': 'open',
          'path': caminho,
          'intervalo': intervalo,
        });

        debugPrint(
          'Excel preview -> arquivo: $caminho',
        );

        debugPrint(
          'Excel preview -> intervalo: $intervalo',
        );

        processo.stdin.writeln(comando);

        await processo.stdin.flush();

        // =============================================================
        // AGUARDA A RESPOSTA
        // =============================================================

        final resposta = await respostaCompleter.future.timeout(
          const Duration(
            seconds: 30,
          ),
          onTimeout: () {
            throw TimeoutException(
              'O excel_preview.py não respondeu em 30 segundos.',
            );
          },
        );

        if (!dialogContext.mounted) return;

        // =============================================================
        // VALIDA RETORNO
        // =============================================================

        if (resposta['ok'] != true) {
          final mensagem = resposta['erro']?.toString().trim() ??
              resposta['message']?.toString().trim() ??
              'Erro desconhecido ao gerar a imagem do Excel.';

          throw Exception(mensagem);
        }

        // =============================================================
        // RECEBE BASE64
        // =============================================================

        final base64Recebido =
            resposta['imagemBase64']?.toString().trim() ?? '';

        if (base64Recebido.isEmpty) {
          throw Exception(
            'O excel_preview.py não retornou a imagem '
            'do intervalo $intervalo.',
          );
        }

        // =============================================================
        // ATUALIZA O MODAL
        // =============================================================

        setDialogState(() {
          // A nova tabela SEMPRE é acrescentada ao comentário.
          // Não substituímos a tabela anterior, mesmo que venha de outra
          // etiqueta ou utilize o mesmo intervalo configurado.
          imagemExcelBase64 = base64Recebido;
          intervalosExcelAdicionados.add(intervalo);
          imagensExcelBase64.add(base64Recebido);
          adicionarImagemAoEditor(base64Recebido);

          erroExcel = null;
          carregandoExcel = false;
        });

        debugPrint(
          '[ExcelPreview] Imagem carregada com sucesso.',
        );

        debugPrint(
          '[ExcelPreview] Intervalo carregado: $intervalo',
        );

        debugPrint(
          '[ExcelPreview] Base64: ${base64Recebido.length} caracteres',
        );
      } on TimeoutException catch (e) {
        if (!dialogContext.mounted) return;

        debugPrint(
          '[ExcelPreview] TIMEOUT: $e',
        );

        setDialogState(() {
          erroExcel = e.message ?? 'Tempo limite excedido.';
          carregandoExcel = false;
        });
      } catch (e, stackTrace) {
        if (!dialogContext.mounted) return;

        debugPrint(
          '[ExcelPreview] ERRO: $e',
        );

        debugPrint(
          '[ExcelPreview] STACK: $stackTrace',
        );

        setDialogState(() {
          erroExcel = e.toString().replaceFirst(
                'Exception: ',
                '',
              );

          carregandoExcel = false;
        });
      } finally {
        // =============================================================
        // ENCERRA O PYTHON
        // =============================================================

        if (processo != null) {
          try {
            processo.stdin.writeln(
              jsonEncode({
                'acao': 'close',
              }),
            );

            await processo.stdin.flush();
          } catch (_) {
            // Processo já pode ter sido encerrado.
          }

          try {
            await processo.stdin.close();
          } catch (_) {
            // Ignora.
          }

          try {
            processo.kill();
          } catch (_) {
            // Ignora.
          }
        }
      }
    }

    // ===============================================================
    // SALVAR COMENTÁRIO
    // ===============================================================

    Future<void> salvarComentario(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      final texto = montarTextoOrdenado();

      if (texto.isEmpty && imagensBase64.isEmpty && imagemBase64 == null) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Digite um comentário ou adicione uma imagem.',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );

        return;
      }

      setDialogState(() {
        salvando = true;
      });

      try {
        final firebaseUser = FirebaseAuth.instance.currentUser;

        if (firebaseUser == null) {
          throw Exception('Usuário não autenticado no Firebase.');
        }

        final ref = comentariosRef();

        final dados = <String, dynamic>{
          'comentario': texto,
          'imagemBase64': imagemBase64,
          'imagensBase64': List<String>.from(imagensBase64),
          'blocosComentario': blocosParaPersistir(),
          'tipoComentario': tipoComentario,
          'modoExecucao': 'Salvo',
          'projetoId': project.id.trim(),
          'usuarioId': firebaseUser.uid,
          'usuario':
              firebaseUser.displayName ?? firebaseUser.email ?? 'Usuário',
        };

        if (comentarioSelecionadoId == null) {
          dados['status'] = 'Pendente';
          dados['dataHora'] = FieldValue.serverTimestamp();
          dados['tentativas'] = 0;

          final documento = await ref.add(dados);

          setDialogState(() {
            comentarioSelecionadoId = documento.id;
          });
        } else {
          dados['atualizadoEm'] = FieldValue.serverTimestamp();
          await ref.doc(comentarioSelecionadoId).update(dados);
        }

        comentarioFocusNode.unfocus();

        if (!dialogContext.mounted) return;

        setDialogState(() {
          salvando = false;
        });

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text('Comentário salvo com sucesso.'),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      } catch (e) {
        if (!dialogContext.mounted) return;

        setDialogState(() {
          salvando = false;
        });

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar comentário: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }

    // ===============================================================
    // TESTAR / ENVIAR PARA E-DESK
    // ===============================================================

    Future<void> executarEdesk({
      required BuildContext dialogContext,
      required StateSetter setDialogState,
      required bool enviar,
    }) async {
      final texto = montarTextoOrdenado();
      final textoEdesk = montarHtmlEdesk();

      final imagensParaEnvio = imagensBase64.isNotEmpty
          ? List<String>.from(imagensBase64)
          : (imagemBase64 != null ? <String>[imagemBase64!] : <String>[]);

      // O EdeskService continua recebendo String. Quando há mais de uma
      // imagem, enviamos a lista codificada em JSON; o Python atualizado
      // abaixo entende os dois formatos.
      final String? imagemPayload = imagensParaEnvio.isEmpty
          ? null
          : (imagensParaEnvio.length == 1
              ? imagensParaEnvio.first
              : jsonEncode(imagensParaEnvio));

      if (texto.isEmpty && imagensParaEnvio.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Digite um comentário ou adicione um print.',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );

        return;
      }

      final task = obterTaskEdesk();

      if (task == null) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Este projeto não possui uma etapa com E-Desk configurado.',
            ),
            backgroundColor: CoresApp.erro,
            duration: const Duration(seconds: 5),
          ),
        );

        return;
      }

      var edeskUrl = task.edeskUrl?.trim() ?? '';
      final idTrabalho = task.edeskIdTrabalho?.trim() ?? '';
      final solicitacao = project.id.trim();

      if (edeskUrl.isEmpty) {
        edeskUrl = 'https://promob.e-desk.com.br';
      }

      if (!edeskUrl.startsWith('http://') && !edeskUrl.startsWith('https://')) {
        edeskUrl = 'https://$edeskUrl';
      }

      final edeskUri = Uri.tryParse(edeskUrl);

      if (edeskUri == null || edeskUri.host.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('URL do E-Desk inválida.')),
        );

        return;
      }

      if (idTrabalho.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível identificar o ID do trabalho E-Desk.',
            ),
          ),
        );

        return;
      }

      if (solicitacao.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text(
              'A solicitação E-Desk não foi informada na tarefa.',
            ),
          ),
        );

        return;
      }

      if (enviar) {
        setDialogState(() {
          enviandoEdesk = true;
        });
      } else {
        setDialogState(() {
          testandoEdesk = true;
        });
      }

      String? comentarioId = comentarioSelecionadoId;
      EdeskService? service;

      try {
        final firebaseUser = FirebaseAuth.instance.currentUser;

        if (firebaseUser == null) {
          throw Exception('Usuário não autenticado no Firebase.');
        }

        final ref = comentariosRef();
        final statusInicial = enviar ? 'Enviando' : 'Teste';

        if (comentarioId == null) {
          final dados = <String, dynamic>{
            'comentario': texto,
            'imagemBase64': imagemBase64,
            'imagensBase64': List<String>.from(imagensParaEnvio),
            'blocosComentario': blocosParaPersistir(),
            'tipoComentario': tipoComentario,
            'tipoComentarioEdesk': _tipoComentarioEdesk(tipoComentario),
            'status': statusInicial,
            'modoExecucao': enviar ? 'Envio' : 'Teste',
            'projetoId': project.id.trim(),
            'usuarioId': firebaseUser.uid,
            'usuario':
                firebaseUser.displayName ?? firebaseUser.email ?? 'Usuário',
            'dataHora': FieldValue.serverTimestamp(),
            'tentativas': 1,
          };

          final documento = await ref.add(dados);
          comentarioId = documento.id;

          setDialogState(() {
            comentarioSelecionadoId = documento.id;
          });
        } else {
          final documentoRef = ref.doc(comentarioId);

          await documentoRef.update({
            'comentario': texto,
            'imagemBase64': imagemBase64,
            'imagensBase64': List<String>.from(imagensParaEnvio),
            'blocosComentario': blocosParaPersistir(),
            'tipoComentario': tipoComentario,
            'tipoComentarioEdesk': _tipoComentarioEdesk(tipoComentario),
            'status': statusInicial,
            'modoExecucao': enviar ? 'Envio' : 'Teste',
            'projetoId': project.id.trim(),
            'usuarioId': firebaseUser.uid,
            'usuario':
                firebaseUser.displayName ?? firebaseUser.email ?? 'Usuário',
            'ultimaTentativa': FieldValue.serverTimestamp(),
            'tentativas': FieldValue.increment(1),
            'erroEnvio': FieldValue.delete(),
          });
        }

        service = EdeskService();

        final resultado = await service.executarComentarioViaPython(
          pageUri: edeskUri,
          solicitacao: solicitacao,
          idTrabalho: idTrabalho,
          tipoComentario: tipoComentario,
          texto: textoEdesk,
          imagemBase64: imagemPayload,
          enviar: enviar,
        );

        final docRef = comentariosRef().doc(comentarioId);

        if (!enviar) {
          await docRef.update({
            'status': resultado.confirmed ? 'Teste' : 'Erro',
            'resultadoTeste': resultado.message,
            'testadoEm': FieldValue.serverTimestamp(),
            if (!resultado.confirmed) 'erroEnvio': resultado.message,
            if (!resultado.confirmed) 'erroEm': FieldValue.serverTimestamp(),
          });
        } else {
          if (resultado.confirmed) {
            await docRef.update({
              'status': 'Enviado',
              'enviadoEm': FieldValue.serverTimestamp(),
              'erroEnvio': FieldValue.delete(),
            });
          } else {
            await docRef.update({
              'status': 'Erro',
              'erroEnvio': resultado.message,
              'erroEm': FieldValue.serverTimestamp(),
            });
          }
        }

        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(resultado.message),
            backgroundColor:
                resultado.confirmed ? CoresApp.sucesso : CoresApp.erro,
            duration: const Duration(seconds: 5),
          ),
        );

        if (enviar && resultado.confirmed) {
          comentarioController.clear();
          comentarioFocusNode.unfocus();
          carregarDocumentoComentario();

          setDialogState(() {
            comentarioSelecionadoId = null;
            imagensBase64.clear();
            blocosComentario.clear();
            controllersBlocosTexto.clear();
            focosBlocosTexto.clear();

            imagensExcelBase64.clear();
            intervalosExcelAdicionados.clear();
            imagemBase64 = null;
            imagemExcelBase64 = null;
            campoExcelSelecionado = null;
            tipoComentario = 'Interno';
          });
        }
      } catch (e) {
        if (comentarioId != null) {
          try {
            await comentariosRef().doc(comentarioId).update({
              'status': 'Erro',
              'erroEnvio': e.toString(),
              'erroEm': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }

        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(
              content: Text('Erro E-Desk: $e'),
              backgroundColor: CoresApp.erro,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } finally {
        try {
          service?.dispose();
        } catch (_) {}

        if (dialogContext.mounted) {
          setDialogState(() {
            testandoEdesk = false;
            enviandoEdesk = false;
          });
        }
      }
    }

    // ===============================================================
    // MODAL SEPARADO — HISTÓRICO DE COMENTÁRIOS
    // ===============================================================

    Future<void> abrirHistoricoComentarios(
      BuildContext parentContext,
      StateSetter setDialogStatePrincipal,
    ) async {
      String buscaHistoricoModal = '';
      Offset offsetHistorico = Offset.zero;
      double? larguraHistoricoCustom;
      double? alturaHistoricoCustom;

      await showDialog<void>(
        context: parentContext,
        barrierDismissible: true,
        builder: (historicoContext) {
          return StatefulBuilder(
            builder: (context, setHistoricoState) {
              final tamanhoTela = MediaQuery.of(historicoContext).size;

              final double margem = tamanhoTela.width < 700 ? 8 : 16;
              final double larguraPadrao = (tamanhoTela.width - (margem * 2))
                  .clamp(320.0, 950.0)
                  .toDouble();
              final double alturaPadrao = (tamanhoTela.height - (margem * 2))
                  .clamp(420.0, 850.0)
                  .toDouble();

              final double larguraFinal =
                  larguraHistoricoCustom ?? larguraPadrao;
              final double alturaFinal = alturaHistoricoCustom ?? alturaPadrao;

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.zero,
                child: Transform.translate(
                  offset: offsetHistorico,
                  child: Center(
                    child: Stack(
                      children: [
                        Container(
                          width: larguraFinal,
                          height: alturaFinal,
                          decoration: BoxDecoration(
                            color: CoresTelas.fundoModal,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CoresApp.borda),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onPanUpdate: (details) {
                                  setHistoricoState(() {
                                    offsetHistorico += details.delta;
                                  });
                                },
                                child: Container(
                                  height: 76,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  decoration: BoxDecoration(
                                    color: CoresTelas.fundoModal,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(14),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(color: CoresApp.borda),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      MouseRegion(
                                        cursor: SystemMouseCursors.move,
                                        child: Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: CoresApp.destaque
                                                .withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(9),
                                          ),
                                          child: Icon(
                                            Icons.open_with_rounded,
                                            color: CoresApp.destaque,
                                            size: 21,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Histórico de comentários',
                                              style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${project.id} - ${project.client}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: CoresApp.textoSecundario,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Fechar',
                                        onPressed: () {
                                          Navigator.of(historicoContext).pop();
                                        },
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: CoresApp.textoSecundario,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                child: SizedBox(
                                  height: 42,
                                  child: TextField(
                                    onChanged: (value) {
                                      setHistoricoState(() {
                                        buscaHistoricoModal =
                                            value.trim().toLowerCase();
                                      });
                                    },
                                    style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 11,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Pesquisar comentários...',
                                      hintStyle: TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 11,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        color: CoresApp.textoSecundario,
                                        size: 18,
                                      ),
                                      filled: true,
                                      fillColor: CoresApp.fundoSecundario,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: CoresApp.borda,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: CoresApp.borda,
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
                              ),
                              Expanded(
                                child: StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: comentariosRef()
                                      .orderBy('dataHora', descending: true)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: CoresApp.destaque,
                                        ),
                                      );
                                    }

                                    if (snapshot.hasError) {
                                      return Center(
                                        child: Text(
                                          'Erro ao carregar comentários.',
                                          style: TextStyle(
                                            color: CoresApp.erro,
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    }

                                    final todosComentarios =
                                        snapshot.data?.docs ?? [];
                                    final comentarios =
                                        todosComentarios.where((doc) {
                                      if (buscaHistoricoModal.isEmpty) {
                                        return true;
                                      }
                                      final dados = doc.data();
                                      final texto = dados['comentario']
                                              ?.toString()
                                              .toLowerCase() ??
                                          '';
                                      final tipo = dados['tipoComentario']
                                              ?.toString()
                                              .toLowerCase() ??
                                          '';
                                      final usuario = dados['usuario']
                                              ?.toString()
                                              .toLowerCase() ??
                                          '';

                                      return texto
                                              .contains(buscaHistoricoModal) ||
                                          tipo.contains(buscaHistoricoModal) ||
                                          usuario.contains(buscaHistoricoModal);
                                    }).toList();

                                    if (comentarios.isEmpty) {
                                      return Center(
                                        child: Text(
                                          buscaHistoricoModal.isEmpty
                                              ? 'Nenhum comentário salvo.'
                                              : 'Nenhum comentário encontrado.',
                                          style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 11,
                                          ),
                                        ),
                                      );
                                    }

                                    return ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 4, 16, 16),
                                      itemCount: comentarios.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final doc = comentarios[index];
                                        final dados = doc.data();
                                        final texto =
                                            dados['comentario']?.toString() ??
                                                '';
                                        final status =
                                            dados['status']?.toString() ??
                                                'Pendente';
                                        final usuario =
                                            dados['usuario']?.toString() ?? '';
                                        final imagem =
                                            dados['imagemBase64']?.toString();
                                        final imagensSalvas =
                                            (dados['imagensBase64'] as List?)
                                                    ?.map((e) => e.toString())
                                                    .where((e) => e.isNotEmpty)
                                                    .toList() ??
                                                <String>[];
                                        final blocosSalvos =
                                            (dados['blocosComentario'] as List?)
                                                    ?.whereType<Map>()
                                                    .map((e) => e.map((k, v) =>
                                                        MapEntry(k.toString(),
                                                            v.toString())))
                                                    .toList() ??
                                                <Map<String, String>>[];
                                        final tipoSalvo =
                                            dados['tipoComentario']?.toString();
                                        final timestamp =
                                            dados['dataHora'] as Timestamp?;
                                        final dataHora = timestamp?.toDate();
                                        final enviado = status == 'Enviado';
                                        final erro = status == 'Erro';

                                        void carregar({required bool editar}) {
                                          comentarioController.clear();
                                          comentarioFocusNode.unfocus();

                                          setDialogStatePrincipal(() {
                                            comentarioSelecionadoId =
                                                editar ? doc.id : null;
                                            controllersBlocosTexto.clear();
                                            focosBlocosTexto.clear();

                                            blocosComentario
                                              ..clear()
                                              ..addAll(blocosSalvos.map((e) =>
                                                  Map<String, String>.from(e)));
                                            imagensBase64
                                              ..clear()
                                              ..addAll(imagensSalvas);
                                            if (imagensBase64.isEmpty &&
                                                imagem != null &&
                                                imagem.isNotEmpty) {
                                              imagensBase64.add(imagem);
                                            }
                                            imagemBase64 =
                                                imagensBase64.isNotEmpty
                                                    ? imagensBase64.last
                                                    : imagem;
                                            carregarDocumentoComentario(
                                              blocos: blocosSalvos,
                                              texto: texto,
                                              imagens: [
                                                ...imagensSalvas,
                                                if (imagensSalvas.isEmpty &&
                                                    imagem != null &&
                                                    imagem.isNotEmpty)
                                                  imagem,
                                              ],
                                            );
                                            if (tipoSalvo != null &&
                                                [
                                                  'Interno',
                                                  'Externo',
                                                  'Padrão',
                                                  'Padrão (Interno)',
                                                ].contains(tipoSalvo)) {
                                              tipoComentario = tipoSalvo;
                                            } else {
                                              tipoComentario = 'Interno';
                                            }
                                          });

                                          Navigator.of(historicoContext).pop();
                                        }

                                        final linhas = texto
                                            .split('\n')
                                            .where((l) => l.trim().isNotEmpty)
                                            .toList();
                                        final titulo = linhas.isNotEmpty
                                            ? linhas.first
                                            : 'Comentário com imagem';

                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: CoresApp.fundoSecundario,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: CoresApp.borda),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (imagem != null &&
                                                      imagem.isNotEmpty)
                                                    Container(
                                                      width: 95,
                                                      height: 62,
                                                      margin:
                                                          const EdgeInsets.only(
                                                        right: 10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: CoresTelas
                                                            .fundoModal,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(7),
                                                        border: Border.all(
                                                          color: CoresApp.borda,
                                                        ),
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        child: Image.memory(
                                                          base64Decode(imagem),
                                                          fit: BoxFit.contain,
                                                          errorBuilder:
                                                              (_, __, ___) =>
                                                                  const SizedBox
                                                                      .shrink(),
                                                        ),
                                                      ),
                                                    ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          titulo,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: CoresApp
                                                                .textoPrincipal,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        if (dataHora !=
                                                            null) ...[
                                                          const SizedBox(
                                                              height: 5),
                                                          Text(
                                                            _formatarDataComentario(
                                                              dataHora,
                                                            ),
                                                            style: TextStyle(
                                                              color: CoresApp
                                                                  .textoSecundario,
                                                              fontSize: 9,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    tooltip: 'Opções',
                                                    color:
                                                        CoresTelas.fundoModal,
                                                    icon: Icon(
                                                      Icons.more_vert_rounded,
                                                      color: CoresApp
                                                          .textoSecundario,
                                                      size: 18,
                                                    ),
                                                    onSelected: (opcao) async {
                                                      if (opcao == 'editar') {
                                                        carregar(editar: true);
                                                        return;
                                                      }
                                                      if (opcao ==
                                                          'reutilizar') {
                                                        carregar(editar: false);
                                                        return;
                                                      }
                                                      if (opcao == 'excluir') {
                                                        await excluirComentario(
                                                          historicoContext,
                                                          setHistoricoState,
                                                          doc.id,
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (context) =>
                                                        const [
                                                      PopupMenuItem<String>(
                                                        value: 'editar',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .edit_outlined,
                                                              size: 17,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text('Editar'),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem<String>(
                                                        value: 'reutilizar',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .content_copy_outlined,
                                                              size: 17,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text('Reutilizar'),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem<String>(
                                                        value: 'excluir',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .delete_outline_rounded,
                                                              size: 17,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text('Excluir'),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 5,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: enviado
                                                          ? CoresApp.sucesso
                                                              .withValues(
                                                                  alpha: 0.10)
                                                          : erro
                                                              ? CoresApp.erro
                                                                  .withValues(
                                                                      alpha:
                                                                          0.10)
                                                              : CoresApp
                                                                  .destaque
                                                                  .withValues(
                                                                      alpha:
                                                                          0.08),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              5),
                                                    ),
                                                    child: Text(
                                                      status,
                                                      style: TextStyle(
                                                        color: enviado
                                                            ? CoresApp.sucesso
                                                            : erro
                                                                ? CoresApp.erro
                                                                : CoresApp
                                                                    .destaque,
                                                        fontSize: 8,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  if (tipoSalvo != null &&
                                                      tipoSalvo.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 7,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                          color: CoresApp.borda,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                      ),
                                                      child: Text(
                                                        tipoSalvo,
                                                        style: TextStyle(
                                                          color: CoresApp
                                                              .textoSecundario,
                                                          fontSize: 8,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              if (texto.trim().isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  texto,
                                                  maxLines: 5,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: CoresApp
                                                        .textoSecundario,
                                                    fontSize: 10,
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ],
                                              if (usuario.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  usuario,
                                                  style: TextStyle(
                                                    color: CoresApp
                                                        .textoSecundario,
                                                    fontSize: 8,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeDownRight,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                setHistoricoState(() {
                                  final novaLargura =
                                      larguraFinal + details.delta.dx;
                                  final novaAltura =
                                      alturaFinal + details.delta.dy;
                                  larguraHistoricoCustom = novaLargura.clamp(
                                      320.0, tamanhoTela.width);
                                  alturaHistoricoCustom = novaAltura.clamp(
                                      350.0, tamanhoTela.height);
                                });
                              },
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color:
                                      CoresApp.destaque.withValues(alpha: 0.3),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(14),
                                  ),
                                ),
                                child: Icon(
                                  Icons.signal_cellular_null,
                                  size: 12,
                                  color: CoresApp.textoPrincipal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // ===============================================================
// MODAL — CONFIGURAÇÕES DOS COMENTÁRIOS E-DESK
// ===============================================================

    Future<void> abrirConfiguracoesComentariosEdesk(
      BuildContext parentContext,
      StateSetter setDialogStatePrincipal,
    ) async {
      // Trabalhamos com cópias para que "Cancelar" não altere
      // as configurações atualmente utilizadas pelo modal principal.
      final etiquetasTemp = List<String>.from(etiquetasComentario);

      final camposTemp = <String, List<Map<String, String>>>{
        for (final entry in camposExcelPorEtiqueta.entries)
          entry.key: entry.value
              .map(
                (campo) => <String, String>{
                  'nome': campo['nome'] ?? '',
                  'intervalo': campo['intervalo'] ?? '',
                },
              )
              .toList(),
      };

      final modelosTemp = modelosDescricao
          .map(
            (modelo) => <String, String>{
              'nome': modelo['nome'] ?? '',
              'conteudo': modelo['conteudo'] ?? '',
            },
          )
          .toList();

      // Garante uma lista de campos para todas as etiquetas.
      for (final etiqueta in etiquetasTemp) {
        camposTemp.putIfAbsent(
          etiqueta,
          () => <Map<String, String>>[],
        );
      }

      int abaSelecionada = 0;

      String etiquetaConfiguracaoSelecionada =
          etiquetasTemp.contains(etiquetaSelecionada)
              ? etiquetaSelecionada
              : (etiquetasTemp.isNotEmpty ? etiquetasTemp.first : '');

      bool salvandoConfiguracoes = false;

      Offset offsetConfiguracoes = Offset.zero;

      void adicionarModeloDescricao(StateSetter setConfigState) {
        var numero = modelosTemp.length + 1;
        var nome = 'Novo modelo $numero';
        while (modelosTemp.any(
          (modelo) =>
              (modelo['nome'] ?? '').toLowerCase() == nome.toLowerCase(),
        )) {
          numero++;
          nome = 'Novo modelo $numero';
        }

        setConfigState(() {
          modelosTemp.add({
            'nome': nome,
            'conteudo': '',
          });
        });
      }

      // ---------------------------------------------------------------
      // ADICIONAR ETIQUETA
      // ---------------------------------------------------------------

      Future<void> adicionarEtiqueta(
        BuildContext modalContext,
        StateSetter setConfigState,
      ) async {
        final controller = TextEditingController();

        final nome = await showDialog<String>(
          context: modalContext,
          builder: (contextNome) {
            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              title: Text(
                'Nova etiqueta',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
                decoration: InputDecoration(
                  hintText: 'Nome da etiqueta',
                  hintStyle: TextStyle(
                    color: CoresApp.textoSecundario,
                  ),
                  filled: true,
                  fillColor: CoresTelas.fundoModal,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.borda,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.borda,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.destaque,
                    ),
                  ),
                ),
                onSubmitted: (value) {
                  Navigator.of(contextNome).pop(value.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(contextNome).pop();
                  },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(contextNome).pop(
                      controller.text.trim(),
                    );
                  },
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 17,
                  ),
                  label: const Text('Adicionar'),
                ),
              ],
            );
          },
        );

        controller.dispose();

        if (nome == null || nome.trim().isEmpty) return;

        final nomeLimpo = nome.trim();

        final jaExiste = etiquetasTemp.any(
          (item) => item.toLowerCase() == nomeLimpo.toLowerCase(),
        );

        if (jaExiste) {
          if (!modalContext.mounted) return;

          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Já existe uma etiqueta com esse nome.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );

          return;
        }

        setConfigState(() {
          etiquetasTemp.add(nomeLimpo);

          camposTemp[nomeLimpo] = <Map<String, String>>[];

          etiquetaConfiguracaoSelecionada = nomeLimpo;
        });
      }

      // ---------------------------------------------------------------
      // RENOMEAR ETIQUETA
      // ---------------------------------------------------------------

      Future<void> editarEtiqueta(
        BuildContext modalContext,
        StateSetter setConfigState,
        String etiquetaAtual,
      ) async {
        final controller = TextEditingController(
          text: etiquetaAtual,
        );

        final novoNome = await showDialog<String>(
          context: modalContext,
          builder: (contextNome) {
            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              title: Text(
                'Editar etiqueta',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
                decoration: InputDecoration(
                  labelText: 'Nome da etiqueta',
                  labelStyle: TextStyle(
                    color: CoresApp.textoSecundario,
                  ),
                  filled: true,
                  fillColor: CoresTelas.fundoModal,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.borda,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.destaque,
                    ),
                  ),
                ),
                onSubmitted: (value) {
                  Navigator.of(contextNome).pop(value.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(contextNome).pop();
                  },
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
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(contextNome).pop(
                      controller.text.trim(),
                    );
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );

        controller.dispose();

        if (novoNome == null || novoNome.trim().isEmpty) return;

        final nomeLimpo = novoNome.trim();

        if (nomeLimpo == etiquetaAtual) return;

        final jaExiste = etiquetasTemp.any(
          (item) =>
              item != etiquetaAtual &&
              item.toLowerCase() == nomeLimpo.toLowerCase(),
        );

        if (jaExiste) {
          if (!modalContext.mounted) return;

          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Já existe uma etiqueta com esse nome.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );

          return;
        }

        setConfigState(() {
          final indice = etiquetasTemp.indexOf(etiquetaAtual);

          if (indice >= 0) {
            etiquetasTemp[indice] = nomeLimpo;
          }

          final camposAntigos =
              camposTemp.remove(etiquetaAtual) ?? <Map<String, String>>[];

          camposTemp[nomeLimpo] = camposAntigos;

          if (etiquetaConfiguracaoSelecionada == etiquetaAtual) {
            etiquetaConfiguracaoSelecionada = nomeLimpo;
          }
        });
      }

      // ---------------------------------------------------------------
      // EXCLUIR ETIQUETA
      // ---------------------------------------------------------------

      Future<void> excluirEtiqueta(
        BuildContext modalContext,
        StateSetter setConfigState,
        String etiqueta,
      ) async {
        final confirmar = await showDialog<bool>(
          context: modalContext,
          builder: (confirmContext) {
            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              title: Text(
                'Excluir etiqueta',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                'Deseja excluir a etiqueta "$etiqueta" e todos os campos do Excel configurados para ela?',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(confirmContext).pop(false);
                  },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.erro,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(confirmContext).pop(true);
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                  ),
                  label: const Text('Excluir'),
                ),
              ],
            );
          },
        );

        if (confirmar != true) return;

        setConfigState(() {
          etiquetasTemp.remove(etiqueta);
          camposTemp.remove(etiqueta);

          if (etiquetaConfiguracaoSelecionada == etiqueta) {
            etiquetaConfiguracaoSelecionada =
                etiquetasTemp.isNotEmpty ? etiquetasTemp.first : '';
          }
        });
      }

      // ---------------------------------------------------------------
      // ADICIONAR CAMPO DO EXCEL
      // ---------------------------------------------------------------

      void adicionarCampoExcel(
        StateSetter setConfigState,
      ) {
        if (etiquetaConfiguracaoSelecionada.isEmpty) return;

        setConfigState(() {
          camposTemp.putIfAbsent(
            etiquetaConfiguracaoSelecionada,
            () => <Map<String, String>>[],
          );

          camposTemp[etiquetaConfiguracaoSelecionada]!.add({
            'nome': '',
            'intervalo': '',
          });
        });
      }

      // ---------------------------------------------------------------
      // SALVAR CONFIGURAÇÕES
      // ---------------------------------------------------------------

      Future<void> salvarConfiguracoes(
        BuildContext modalContext,
        StateSetter setConfigState,
      ) async {
        if (etiquetasTemp.isEmpty) {
          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Cadastre pelo menos uma etiqueta.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );
          return;
        }

        final nomesModelos = <String>{};
        for (final modelo in modelosTemp) {
          final nome = (modelo['nome'] ?? '').trim();
          final conteudo = (modelo['conteudo'] ?? '').trim();
          if (nome.isEmpty || conteudo.isEmpty) {
            ScaffoldMessenger.of(modalContext).showSnackBar(
              const SnackBar(
                content: Text(
                  'Preencha o nome e o conteúdo de todos os modelos antes de salvar.',
                ),
                backgroundColor: CoresApp.erro,
              ),
            );
            return;
          }
          if (!nomesModelos.add(nome.toLowerCase())) {
            ScaffoldMessenger.of(modalContext).showSnackBar(
              SnackBar(
                content: Text('Já existe um modelo chamado "$nome".'),
                backgroundColor: CoresApp.erro,
              ),
            );
            return;
          }
        }

        // Validação dos campos.
        for (final etiqueta in etiquetasTemp) {
          final campos = camposTemp[etiqueta] ?? const [];

          for (final campo in campos) {
            final nome = campo['nome']?.trim() ?? '';
            final intervalo = campo['intervalo']?.trim() ?? '';

            if (nome.isEmpty || intervalo.isEmpty) {
              ScaffoldMessenger.of(modalContext).showSnackBar(
                SnackBar(
                  content: Text(
                    'Preencha o nome e o intervalo de todos os campos da etiqueta "$etiqueta".',
                  ),
                  backgroundColor: CoresApp.erro,
                ),
              );

              return;
            }
          }
        }

        setConfigState(() {
          salvandoConfiguracoes = true;
        });

        try {
          await salvarConfiguracoesComentariosEdesk(
            etiquetas: etiquetasTemp,
            campos: camposTemp,
            modelos: modelosTemp,
          );

          configuracoesEdeskCarregadas = true;

          setDialogStatePrincipal(() {
            etiquetasComentario = List<String>.from(etiquetasTemp);

            camposExcelPorEtiqueta = {
              for (final entry in camposTemp.entries)
                entry.key: entry.value
                    .map(
                      (campo) => <String, String>{
                        'nome': campo['nome']?.trim() ?? '',
                        'intervalo':
                            campo['intervalo']?.trim().toUpperCase() ?? '',
                      },
                    )
                    .toList(),
            };
            modelosDescricao = modelosTemp
                .map(
                  (modelo) => <String, String>{
                    'nome': modelo['nome']!.trim(),
                    'conteudo': modelo['conteudo']!,
                  },
                )
                .toList();
            if (!modelosDescricao.any(
              (modelo) => modelo['nome'] == modeloDescricaoSelecionado,
            )) {
              modeloDescricaoSelecionado = null;
            }

            if (!etiquetasComentario.contains(etiquetaSelecionada)) {
              etiquetaSelecionada = etiquetasComentario.isNotEmpty
                  ? etiquetasComentario.first
                  : '';
            }

            campoExcelSelecionado = null;
            imagemExcelBase64 = null;
          });

          if (!modalContext.mounted) return;

          Navigator.of(modalContext).pop();

          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Configurações dos comentários E-Desk salvas.',
              ),
              backgroundColor: CoresApp.sucesso,
            ),
          );
        } catch (e) {
          if (!modalContext.mounted) return;

          setConfigState(() {
            salvandoConfiguracoes = false;
          });

          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao salvar configurações: $e',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );
        }
      }

      // ===============================================================
      // ABRE O MODAL
      // ===============================================================

      await showDialog<void>(
        context: parentContext,
        barrierDismissible: false,
        builder: (configContext) {
          return StatefulBuilder(
            builder: (context, setConfigState) {
              final tamanhoTela = MediaQuery.of(configContext).size;

              final largura =
                  (tamanhoTela.width - 32).clamp(320.0, 760.0).toDouble();

              final altura =
                  (tamanhoTela.height - 32).clamp(480.0, 720.0).toDouble();

              final camposEtiqueta =
                  camposTemp[etiquetaConfiguracaoSelecionada] ??
                      <Map<String, String>>[];

              // =========================================================
              // CONTEÚDO — ETIQUETAS
              // =========================================================

              Widget construirAbaEtiquetas() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Etiquetas do chamado',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Estas etiquetas serão exibidas no dropdown do modal de comentários E-Desk.',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: etiquetasTemp.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final etiqueta = etiquetasTemp[index];

                          return Container(
                            height: 46,
                            padding: const EdgeInsets.only(left: 12),
                            decoration: BoxDecoration(
                              color: CoresTelas.fundoModal,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: CoresApp.borda,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 17,
                                  color: CoresApp.textoSecundario,
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.sell_outlined,
                                  size: 17,
                                  color: CoresApp.destaque,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    etiqueta,
                                    style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Editar etiqueta',
                                  onPressed: () {
                                    editarEtiqueta(
                                      configContext,
                                      setConfigState,
                                      etiqueta,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 17,
                                    color: CoresApp.textoSecundario,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Excluir etiqueta',
                                  onPressed: () {
                                    excluirEtiqueta(
                                      configContext,
                                      setConfigState,
                                      etiqueta,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: CoresApp.erro,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          adicionarEtiqueta(
                            configContext,
                            setConfigState,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CoresApp.textoPrincipal,
                          side: BorderSide(
                            color: CoresApp.destaque,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 17,
                        ),
                        label: const Text(
                          'Adicionar etiqueta',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // =========================================================
              // CONTEÚDO — CAMPOS DO EXCEL
              // =========================================================

              Widget construirAbaCamposExcel() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CoresApp.destaque.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: CoresApp.destaque.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: CoresApp.destaque,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Configure quais células ou áreas do Excel serão copiadas como imagem para cada etiqueta. Esses campos serão usados ao clicar em "Usar imagem do Excel".',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Selecione a etiqueta para configurar',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 42,
                      child: DropdownButtonFormField<String>(
                        initialValue: etiquetaConfiguracaoSelecionada.isEmpty
                            ? null
                            : etiquetaConfiguracaoSelecionada,
                        isExpanded: true,
                        dropdownColor: CoresTelas.fundoModal,
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            Icons.sell_outlined,
                            size: 17,
                            color: CoresApp.destaque,
                          ),
                          filled: true,
                          fillColor: CoresTelas.fundoModal,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: CoresApp.borda,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 11,
                        ),
                        items: etiquetasTemp.map((etiqueta) {
                          return DropdownMenuItem<String>(
                            value: etiqueta,
                            child: Text(etiqueta),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;

                          setConfigState(() {
                            etiquetaConfiguracaoSelecionada = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Campos do Excel para esta etiqueta',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: camposEtiqueta.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum campo configurado para esta etiqueta.',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: camposEtiqueta.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 7),
                              itemBuilder: (context, index) {
                                final campo = camposEtiqueta[index];

                                return Row(
                                  key: ObjectKey(campo),
                                  children: [
                                    Icon(
                                      Icons.drag_indicator_rounded,
                                      color: CoresApp.textoSecundario,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 5,
                                      child: TextFormField(
                                        key: ObjectKey(campo),
                                        initialValue: campo['nome'] ?? '',
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 11,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Ex.: Capa do projeto',
                                          hintStyle: TextStyle(
                                            color: CoresApp.textoSecundario,
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: CoresTelas.fundoModal,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            borderSide: BorderSide(
                                              color: CoresApp.borda,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          campo['nome'] = value;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        key: ValueKey(
                                          'intervalo-${identityHashCode(campo)}',
                                        ),
                                        initialValue: campo['intervalo'] ?? '',
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'A1:D20',
                                          hintStyle: TextStyle(
                                            color: CoresApp.textoSecundario,
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: CoresTelas.fundoModal,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            borderSide: BorderSide(
                                              color: CoresApp.borda,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          campo['intervalo'] =
                                              value.toUpperCase();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: 'Duplicar campo',
                                      onPressed: () {
                                        setConfigState(() {
                                          camposEtiqueta.insert(
                                            index + 1,
                                            {
                                              'nome':
                                                  '${campo['nome'] ?? ''} cópia',
                                              'intervalo':
                                                  campo['intervalo'] ?? '',
                                            },
                                          );
                                        });
                                      },
                                      icon: Icon(
                                        Icons.copy_outlined,
                                        size: 17,
                                        color: CoresApp.textoSecundario,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Excluir campo',
                                      onPressed: () {
                                        setConfigState(() {
                                          camposEtiqueta.removeAt(index);
                                        });
                                      },
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: CoresApp.erro,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: etiquetaConfiguracaoSelecionada.isEmpty
                            ? null
                            : () {
                                adicionarCampoExcel(
                                  setConfigState,
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CoresApp.textoPrincipal,
                          side: BorderSide(
                            color: CoresApp.destaque,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.add_circle_rounded,
                          size: 17,
                        ),
                        label: const Text(
                          'Adicionar campo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              Widget construirAbaModelosDescricao() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Modelos de descritivo',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cadastre, edite ou exclua os textos que poderão ser inseridos abaixo da imagem da planilha.',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: modelosTemp.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum modelo cadastrado.',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: modelosTemp.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final modelo = modelosTemp[index];
                                final chave = identityHashCode(modelo);
                                return Container(
                                  key: ObjectKey(modelo),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: CoresTelas.fundoModal,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: CoresApp.borda),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: 17,
                                            color: CoresApp.destaque,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              key: ValueKey(
                                                'modelo-nome-$chave',
                                              ),
                                              initialValue:
                                                  modelo['nome'] ?? '',
                                              style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              decoration: InputDecoration(
                                                labelText: 'Nome do modelo',
                                                labelStyle: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontSize: 10,
                                                ),
                                                isDense: true,
                                                filled: true,
                                                fillColor:
                                                    CoresTelas.fundoModal,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(7),
                                                ),
                                              ),
                                              onChanged: (value) {
                                                modelo['nome'] = value;
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Excluir modelo',
                                            onPressed: () {
                                              setConfigState(() {
                                                modelosTemp.removeAt(index);
                                              });
                                            },
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              color: CoresApp.erro,
                                              size: 19,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        key: ValueKey(
                                          'modelo-conteudo-$chave',
                                        ),
                                        initialValue: modelo['conteudo'] ?? '',
                                        minLines: 4,
                                        maxLines: 8,
                                        keyboardType: TextInputType.multiline,
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 11,
                                          height: 1.4,
                                        ),
                                        decoration: InputDecoration(
                                          labelText: 'Conteúdo do descritivo',
                                          alignLabelWithHint: true,
                                          labelStyle: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 10,
                                          ),
                                          hintText:
                                              'Digite o texto que será inserido no comentário...',
                                          hintStyle: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 10,
                                          ),
                                          filled: true,
                                          fillColor: CoresTelas.fundoModal,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          modelo['conteudo'] = value;
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            adicionarModeloDescricao(setConfigState),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CoresApp.textoPrincipal,
                          side: BorderSide(color: CoresApp.destaque),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 17,
                        ),
                        label: const Text(
                          'Adicionar modelo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: Transform.translate(
                  offset: offsetConfiguracoes,
                  child: Center(
                    child: Container(
                      width: largura,
                      height: altura,
                      decoration: BoxDecoration(
                        color: CoresTelas.fundoModal,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: CoresApp.borda,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.40),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // =================================================
                          // CABEÇALHO
                          // =================================================

                          GestureDetector(
                            onPanUpdate: (details) {
                              setConfigState(() {
                                offsetConfiguracoes += details.delta;
                              });
                            },
                            child: Container(
                              height: 74,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: CoresApp.borda,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: CoresApp.sucesso
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(
                                      Icons.settings_outlined,
                                      color: CoresApp.sucesso,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Configurações - Comentários E-Desk',
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Gerencie etiquetas, campos do Excel e modelos de descritivo.',
                                          style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Fechar',
                                    onPressed: salvandoConfiguracoes
                                        ? null
                                        : () {
                                            Navigator.of(configContext).pop();
                                          },
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: CoresApp.textoSecundario,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // =================================================
                          // ABAS
                          // =================================================

                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              18,
                              14,
                              18,
                              0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setConfigState(() {
                                          abaSelecionada = 0;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: abaSelecionada == 0
                                            ? CoresApp.destaque
                                            : CoresApp.textoPrincipal,
                                        side: BorderSide(
                                          color: abaSelecionada == 0
                                              ? CoresApp.destaque
                                              : CoresApp.borda,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.sell_outlined,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Etiquetas',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setConfigState(() {
                                          abaSelecionada = 1;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: abaSelecionada == 1
                                            ? CoresApp.destaque
                                            : CoresApp.textoPrincipal,
                                        side: BorderSide(
                                          color: abaSelecionada == 1
                                              ? CoresApp.destaque
                                              : CoresApp.borda,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.table_view_outlined,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Excel',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setConfigState(() {
                                          abaSelecionada = 2;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: abaSelecionada == 2
                                            ? CoresApp.destaque
                                            : CoresApp.textoPrincipal,
                                        side: BorderSide(
                                          color: abaSelecionada == 2
                                              ? CoresApp.destaque
                                              : CoresApp.borda,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.description_outlined,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Modelos',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // =================================================
                          // CONTEÚDO
                          // =================================================

                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: switch (abaSelecionada) {
                                0 => construirAbaEtiquetas(),
                                1 => construirAbaCamposExcel(),
                                _ => construirAbaModelosDescricao(),
                              },
                            ),
                          ),

                          // =================================================
                          // RODAPÉ
                          // =================================================

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: CoresApp.borda,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                OutlinedButton(
                                  onPressed: salvandoConfiguracoes
                                      ? null
                                      : () {
                                          Navigator.of(configContext).pop();
                                        },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: CoresApp.textoPrincipal,
                                    side: BorderSide(
                                      color: CoresApp.borda,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 13,
                                    ),
                                  ),
                                  child: const Text('Cancelar'),
                                ),
                                const Spacer(),
                                ElevatedButton.icon(
                                  onPressed: salvandoConfiguracoes
                                      ? null
                                      : () {
                                          salvarConfiguracoes(
                                            configContext,
                                            setConfigState,
                                          );
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: CoresApp.sucesso,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 13,
                                    ),
                                  ),
                                  icon: salvandoConfiguracoes
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    salvandoConfiguracoes
                                        ? 'Salvando...'
                                        : 'Salvar configurações',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

// ===============================================================
// MODAL — COMENTÁRIOS E-DESK (Móvel e Redimensionável)
// ===============================================================

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialogState) {
            void setDialogState(VoidCallback callback) {
              if (context.mounted) updateDialogState(callback);
            }
            // =========================================================
            // CARREGA CONFIGURAÇÕES SALVAS NO FIREBASE
            // =========================================================
            //
            // Executa somente uma vez ao abrir o modal.
            // Depois do carregamento, o Firebase passa a definir
            // quais etiquetas e campos do Excel serão exibidos.
            // =========================================================

            if (!configuracoesEdeskCarregadas &&
                !carregandoConfiguracoesEdesk) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!dialogContext.mounted) return;

                await carregarConfiguracoesComentariosEdesk(
                  dialogContext,
                  setDialogState,
                );

                if (!dialogContext.mounted) return;

                await carregarEtiquetaProjeto(
                  dialogContext,
                  setDialogState,
                );
              });
            }

            final tamanhoTela = MediaQuery.of(dialogContext).size;

            final double larguraFinal = (larguraCustomizada ??
                    (tamanhoTela.width * 0.90).clamp(320.0, 1296.0))
                .clamp(0.0, tamanhoTela.width - 24);
            final double alturaFinal =
                (alturaCustomizada ?? tamanhoTela.height - 96)
                    .clamp(0.0, tamanhoTela.height - 24);

            Widget seletorTipoComentario() {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TIPO',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 166,
                    height: 42,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('type-$tipoComentario'),
                      initialValue: tipoComentario,
                      isDense: true,
                      isExpanded: true,
                      dropdownColor: ComentarioDialogPalette.input,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: ComentarioDialogPalette.input,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: ComentarioDialogPalette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: ComentarioDialogPalette.border),
                        ),
                      ),
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 12,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Interno',
                          child: Text('Comentário interno'),
                        ),
                        DropdownMenuItem(
                          value: 'Externo',
                          child: Text('Comentário externo'),
                        ),
                        DropdownMenuItem(
                          value: 'Padrão',
                          child: Text('Padrão'),
                        ),
                        DropdownMenuItem(
                          value: 'Padrão (Interno)',
                          child: Text('Padrão (Interno)'),
                        ),
                      ],
                      onChanged: (salvando || testandoEdesk || enviandoEdesk)
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                tipoComentario = value;
                              });
                            },
                    ),
                  ),
                ],
              );
            }

            Widget seletorImagemExcelAnexo() {
              return PopupMenuButton<Map<String, String>>(
                tooltip: 'Selecionar área da planilha para inserir',
                enabled: !(salvando ||
                    testandoEdesk ||
                    enviandoEdesk ||
                    carregandoExcel),
                color: ComentarioDialogPalette.input,
                onSelected: (campo) async {
                  final intervalo =
                      campo['intervalo']?.trim().toUpperCase() ?? '';
                  if (intervalo.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Este campo não possui um intervalo do Excel configurado.',
                        ),
                        backgroundColor: CoresApp.erro,
                      ),
                    );
                    return;
                  }

                  setDialogState(() {
                    campoExcelSelecionado = intervalo;
                  });
                  await carregarExcelProjeto(dialogContext, setDialogState);
                },
                itemBuilder: (context) {
                  final campos = camposExcelEtiquetaAtual();
                  if (campos.isEmpty) {
                    return [
                      PopupMenuItem<Map<String, String>>(
                        enabled: false,
                        child: Text(
                          'Nenhum campo do Excel configurado para "$etiquetaSelecionada".',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ];
                  }
                  return campos
                      .map(
                        (campo) => PopupMenuItem<Map<String, String>>(
                          value: campo,
                          child: SizedBox(
                            width: 220,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.table_view_outlined,
                                  size: 17,
                                  color: ComentarioDialogPalette.blue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        campo['nome']?.trim().isNotEmpty == true
                                            ? campo['nome']!.trim()
                                            : 'Campo sem nome',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        campo['intervalo']
                                                ?.trim()
                                                .toUpperCase() ??
                                            '',
                                        style: TextStyle(
                                          color: CoresApp.textoSecundario,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList();
                },
                child: ComentarioAttachmentTile(
                  width: 190,
                  icon: Icons.table_view_outlined,
                  title: 'Tabela do Excel',
                  subtitle: campoExcelSelecionado ?? 'Selecionar intervalo',
                  loading: carregandoExcel,
                ),
              );
            }

            Widget construirPainelHistoricoIntegrado() {
              return ComentarioHistoryPanel(
                onSearch: (value) => setDialogState(() {
                  buscaHistorico = value.trim().toLowerCase();
                }),
                onOpenHistory: () =>
                    abrirHistoricoComentarios(dialogContext, setDialogState),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: comentariosRef()
                      .orderBy('dataHora', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ComentarioDialogPalette.blue,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Erro ao carregar comentários.',
                          style: TextStyle(
                            color: CoresApp.erro,
                            fontSize: 11,
                          ),
                        ),
                      );
                    }

                    final docs = (snapshot.data?.docs ?? []).where((doc) {
                      if (buscaHistorico.isEmpty) return true;
                      final dados = doc.data();
                      final texto =
                          dados['comentario']?.toString().toLowerCase() ?? '';
                      final usuario =
                          dados['usuario']?.toString().toLowerCase() ?? '';
                      final tipo =
                          dados['tipoComentario']?.toString().toLowerCase() ??
                              '';
                      return texto.contains(buscaHistorico) ||
                          usuario.contains(buscaHistorico) ||
                          tipo.contains(buscaHistorico);
                    }).toList();

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          buscaHistorico.isEmpty
                              ? 'Nenhum comentário salvo.'
                              : 'Nenhum comentário encontrado.',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 11,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final dados = doc.data();
                        final texto = dados['comentario']?.toString() ?? '';
                        final usuario =
                            dados['usuario']?.toString() ?? 'Usuário';
                        final status =
                            dados['status']?.toString() ?? 'Pendente';
                        final timestamp = dados['dataHora'] as Timestamp?;
                        final dataHora = timestamp?.toDate();
                        final imagem = dados['imagemBase64']?.toString();
                        final imagensSalvas = (dados['imagensBase64'] as List?)
                                ?.map((e) => e.toString())
                                .where((e) => e.isNotEmpty)
                                .toList() ??
                            <String>[];
                        final blocosSalvos =
                            (dados['blocosComentario'] as List?)
                                    ?.whereType<Map>()
                                    .map((e) => e.map((k, v) =>
                                        MapEntry(k.toString(), v.toString())))
                                    .toList() ??
                                <Map<String, String>>[];
                        final tipoSalvo = dados['tipoComentario']?.toString();

                        void carregarComentario({required bool editar}) {
                          comentarioController.clear();
                          comentarioFocusNode.unfocus();
                          setDialogState(() {
                            comentarioSelecionadoId = editar ? doc.id : null;
                            controllersBlocosTexto.clear();
                            focosBlocosTexto.clear();

                            blocosComentario
                              ..clear()
                              ..addAll(blocosSalvos
                                  .map((e) => Map<String, String>.from(e)));
                            imagensBase64
                              ..clear()
                              ..addAll(imagensSalvas);
                            if (imagensBase64.isEmpty &&
                                imagem != null &&
                                imagem.isNotEmpty) {
                              imagensBase64.add(imagem);
                            }
                            imagemBase64 = imagensBase64.isNotEmpty
                                ? imagensBase64.last
                                : imagem;
                            carregarDocumentoComentario(
                              blocos: blocosSalvos,
                              texto: texto,
                              imagens: [
                                ...imagensSalvas,
                                if (imagensSalvas.isEmpty &&
                                    imagem != null &&
                                    imagem.isNotEmpty)
                                  imagem,
                              ],
                            );
                            if (tipoSalvo != null &&
                                [
                                  'Interno',
                                  'Externo',
                                  'Padrão',
                                  'Padrão (Interno)'
                                ].contains(tipoSalvo)) {
                              tipoComentario = tipoSalvo;
                            }
                          });
                          comentarioFocusNode.requestFocus();
                        }

                        return ComentarioHistoryCard(
                          author: usuario,
                          date: dataHora == null
                              ? ''
                              : _formatarDataResumo(dataHora),
                          text: texto,
                          status: status,
                          highlighted: comentarioSelecionadoId == doc.id ||
                              (comentarioSelecionadoId == null && index == 0),
                          onTap: () => carregarComentario(editar: false),
                          actions: PopupMenuButton<String>(
                            tooltip: 'Opções',
                            color: ComentarioDialogPalette.input,
                            icon: Icon(Icons.more_vert_rounded,
                                size: 17, color: CoresApp.textoSecundario),
                            onSelected: (opcao) async {
                              if (opcao == 'editar') {
                                carregarComentario(editar: true);
                              } else if (opcao == 'reutilizar') {
                                carregarComentario(editar: false);
                              } else if (opcao == 'excluir') {
                                await excluirComentario(
                                    dialogContext, setDialogState, doc.id);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'editar', child: Text('Editar')),
                              PopupMenuItem(
                                  value: 'reutilizar',
                                  child: Text('Reutilizar')),
                              PopupMenuItem(
                                  value: 'excluir', child: Text('Excluir')),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            }

            final controls = LayoutBuilder(
              builder: (context, constraints) {
                final seletorEtiqueta = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ETIQUETA DO CHAMADO',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 202,
                          height: 42,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('tag-$etiquetaSelecionada'),
                            initialValue: etiquetaSelecionada,
                            isExpanded: true,
                            isDense: true,
                            dropdownColor: ComentarioDialogPalette.input,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: ComentarioDialogPalette.input,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: ComentarioDialogPalette.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: ComentarioDialogPalette.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: ComentarioDialogPalette.blue,
                                ),
                              ),
                            ),
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            items: etiquetasComentario.map((etiqueta) {
                              return DropdownMenuItem<String>(
                                value: etiqueta,
                                child: Text(etiqueta),
                              );
                            }).toList(),
                            onChanged:
                                (salvando || testandoEdesk || enviandoEdesk)
                                    ? null
                                    : (value) async {
                                        if (value == null) {
                                          return;
                                        }

                                        setDialogState(() {
                                          etiquetaSelecionada = value;
                                          campoExcelSelecionado = null;
                                          imagemExcelBase64 = null;
                                        });

                                        try {
                                          await salvarEtiquetaProjeto(
                                            value,
                                          );
                                        } catch (e) {
                                          debugPrint(
                                            'Erro ao salvar etiqueta E-Desk do projeto: $e',
                                          );
                                        }
                                      },
                          ),
                        ),
                        const SizedBox(
                          width: 4,
                        ),
                        SizedBox(
                          width: 42,
                          height: 42,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: ComentarioDialogPalette.input,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: ComentarioDialogPalette.border),
                            ),
                            child: IconButton(
                              tooltip:
                                  'Cadastrar e gerenciar etiquetas e modelos',
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: (salvando ||
                                      testandoEdesk ||
                                      enviandoEdesk ||
                                      carregandoConfiguracoesEdesk)
                                  ? null
                                  : () => abrirConfiguracoesComentariosEdesk(
                                        dialogContext,
                                        setDialogState,
                                      ),
                              icon: Icon(
                                Icons.sell_outlined,
                                size: 18,
                                color: CoresApp.textoSecundario,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text('Configurar etiquetas',
                          style: TextStyle(
                            color: ComentarioDialogPalette.muted,
                            fontSize: 9,
                          )),
                    ),
                  ],
                );

                final nomesModelos = modelosDescricao
                    .map((modelo) => modelo['nome'] ?? '')
                    .where((nome) => nome.isNotEmpty)
                    .toSet()
                    .toList();

                final modeloSelecionadoValido = nomesModelos.contains(
                  modeloDescricaoSelecionado,
                )
                    ? modeloDescricaoSelecionado
                    : null;

                final seletorModeloDescricao = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MODELO DO DESCRITIVO',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 320,
                      height: 42,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('model-$modeloSelecionadoValido'),
                        initialValue: modeloSelecionadoValido,
                        isExpanded: true,
                        isDense: true,
                        hint: Text(
                          nomesModelos.isEmpty
                              ? 'Cadastre um modelo'
                              : 'Selecione um modelo',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                        dropdownColor: ComentarioDialogPalette.input,
                        decoration: InputDecoration(
                          prefixIconConstraints:
                              const BoxConstraints(minWidth: 42, minHeight: 20),
                          prefixIcon: const Icon(Icons.article_rounded,
                              color: ComentarioDialogPalette.blue, size: 20),
                          filled: true,
                          fillColor: ComentarioDialogPalette.input,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: ComentarioDialogPalette.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: ComentarioDialogPalette.border,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        items: nomesModelos
                            .map((nome) => DropdownMenuItem<String>(
                                  value: nome,
                                  child: Text(
                                    nome,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (salvando ||
                                testandoEdesk ||
                                enviandoEdesk ||
                                nomesModelos.isEmpty)
                            ? null
                            : (nome) {
                                if (nome == null) {
                                  return;
                                }
                                inserirModeloDescricao(
                                  nome,
                                  dialogContext,
                                  setDialogState,
                                );
                              },
                      ),
                    ),
                  ],
                );

                return ComentarioControlsRow(
                  type: seletorTipoComentario(),
                  tag: seletorEtiqueta,
                  model: seletorModeloDescricao,
                );
              },
            );
            final editor = Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: ComentarioDialogPalette.editor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ComentarioDialogPalette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // =================================================
                  // BARRA DE FORMATAÇÃO RICA
                  // A formatação é aplicada ao bloco de texto atual.
                  // Ao inserir uma tabela/imagem, o bloco é consolidado
                  // mantendo fonte, tamanho e estilos escolhidos.
                  // =================================================
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: ComentarioDialogPalette.input,
                      border: Border(
                          bottom: BorderSide(
                              color: ComentarioDialogPalette.border)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 112,
                            child: DropdownButton<String>(
                              value: fonteComentario,
                              isExpanded: true,
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              dropdownColor: ComentarioDialogPalette.input,
                              style: TextStyle(
                                  color: CoresApp.textoPrincipal, fontSize: 11),
                              items: const [
                                'Segoe UI',
                                'Arial',
                                'Calibri',
                                'Verdana',
                                'Tahoma',
                                'Times New Roman',
                                'Georgia',
                                'Courier New'
                              ]
                                  .map((fonte) => DropdownMenuItem(
                                      value: fonte, child: Text(fonte)))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) {
                                  return;
                                }
                                setDialogState(() => fonteComentario = v);
                                aplicarFormatacaoNaSelecao();
                                focarEditorRicoAtivo();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 62,
                            child: DropdownButton<double>(
                              value: tamanhoFonteComentario,
                              isExpanded: true,
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              dropdownColor: ComentarioDialogPalette.input,
                              style: TextStyle(
                                  color: CoresApp.textoPrincipal, fontSize: 11),
                              items: const [
                                9.0,
                                10.0,
                                11.0,
                                12.0,
                                14.0,
                                16.0,
                                18.0,
                                20.0,
                                24.0
                              ]
                                  .map((t) => DropdownMenuItem(
                                      value: t, child: Text('${t.toInt()}')))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) {
                                  return;
                                }
                                setDialogState(
                                    () => tamanhoFonteComentario = v);
                                aplicarFormatacaoNaSelecao();
                                focarEditorRicoAtivo();
                              },
                            ),
                          ),
                          const VerticalDivider(
                              width: 12, indent: 8, endIndent: 8),
                          PopupMenuButton<Color>(
                            tooltip: 'Cor da fonte',
                            initialValue: corFonteComentario,
                            onSelected: (cor) {
                              setDialogState(() => corFonteComentario = cor);
                              aplicarFormatacaoNaSelecao();
                              focarEditorRicoAtivo();
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: Color(0xFFF5F7FA),
                                  child: _CorFonteItem(
                                      cor: Color(0xFFF5F7FA), nome: 'Branco')),
                              PopupMenuItem(
                                  value: Color(0xFF000000),
                                  child: _CorFonteItem(
                                      cor: Color(0xFF000000), nome: 'Preto')),
                              PopupMenuItem(
                                  value: Color(0xFFE53935),
                                  child: _CorFonteItem(
                                      cor: Color(0xFFE53935),
                                      nome: 'Vermelho')),
                              PopupMenuItem(
                                  value: Color(0xFFFFB300),
                                  child: _CorFonteItem(
                                      cor: Color(0xFFFFB300), nome: 'Amarelo')),
                              PopupMenuItem(
                                  value: Color(0xFF43A047),
                                  child: _CorFonteItem(
                                      cor: Color(0xFF43A047), nome: 'Verde')),
                              PopupMenuItem(
                                  value: Color(0xFF1E88E5),
                                  child: _CorFonteItem(
                                      cor: Color(0xFF1E88E5), nome: 'Azul')),
                              PopupMenuItem(
                                  value: Color(0xFF8E24AA),
                                  child: _CorFonteItem(
                                      cor: Color(0xFF8E24AA), nome: 'Roxo')),
                              PopupMenuItem(
                                  value: Color(0xFF00ACC1),
                                  child: _CorFonteItem(
                                      cor: Color(0xFF00ACC1), nome: 'Ciano')),
                              PopupMenuItem(
                                  value: Color(0xFFFF7043),
                                  child: _CorFonteItem(
                                      cor: Color(0xFFFF7043), nome: 'Laranja')),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 7),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.format_color_text,
                                      size: 17,
                                      color: CoresApp.textoSecundario),
                                  Container(
                                      width: 17,
                                      height: 3,
                                      color: corFonteComentario),
                                ],
                              ),
                            ),
                          ),
                          const VerticalDivider(
                              width: 12, indent: 8, endIndent: 8),
                          IconButton(
                            tooltip: 'Negrito',
                            icon: Icon(Icons.format_bold,
                                size: 17,
                                color: negritoComentario
                                    ? ComentarioDialogPalette.blue
                                    : CoresApp.textoSecundario),
                            onPressed: () {
                              setDialogState(
                                  () => negritoComentario = !negritoComentario);
                              aplicarFormatacaoNaSelecao();
                              focarEditorRicoAtivo();
                            },
                          ),
                          IconButton(
                            tooltip: 'Itálico',
                            icon: Icon(Icons.format_italic,
                                size: 17,
                                color: italicoComentario
                                    ? ComentarioDialogPalette.blue
                                    : CoresApp.textoSecundario),
                            onPressed: () {
                              setDialogState(
                                  () => italicoComentario = !italicoComentario);
                              aplicarFormatacaoNaSelecao();
                              focarEditorRicoAtivo();
                            },
                          ),
                          IconButton(
                            tooltip: 'Sublinhado',
                            icon: Icon(Icons.format_underlined,
                                size: 17,
                                color: sublinhadoComentario
                                    ? ComentarioDialogPalette.blue
                                    : CoresApp.textoSecundario),
                            onPressed: () {
                              setDialogState(() =>
                                  sublinhadoComentario = !sublinhadoComentario);
                              aplicarFormatacaoNaSelecao();
                              focarEditorRicoAtivo();
                            },
                          ),
                          IconButton(
                            tooltip: 'Tachado',
                            icon: Icon(Icons.format_strikethrough,
                                size: 17,
                                color: tachadoComentario
                                    ? ComentarioDialogPalette.blue
                                    : CoresApp.textoSecundario),
                            onPressed: () {
                              setDialogState(
                                  () => tachadoComentario = !tachadoComentario);
                              aplicarFormatacaoNaSelecao();
                              focarEditorRicoAtivo();
                            },
                          ),
                          const VerticalDivider(
                              width: 12, indent: 8, endIndent: 8),
                          IconButton(
                            tooltip: 'Lista com marcadores',
                            icon: Icon(Icons.format_list_bulleted,
                                size: 17, color: CoresApp.textoSecundario),
                            onPressed: () {
                              editorController.formatSelection(
                                quill.Attribute.ul,
                              );
                              focarEditorRicoAtivo();
                            },
                          ),
                          IconButton(
                            tooltip: 'Lista numerada',
                            icon: Icon(Icons.format_list_numbered,
                                size: 17, color: CoresApp.textoSecundario),
                            onPressed: () {
                              editorController.formatSelection(
                                quill.Attribute.ol,
                              );
                              focarEditorRicoAtivo();
                            },
                          ),
                          const VerticalDivider(
                              width: 12, indent: 8, endIndent: 8),
                          IconButton(
                              tooltip: 'Alinhar à esquerda',
                              icon: Icon(Icons.format_align_left,
                                  size: 17,
                                  color: alinhamentoComentario == TextAlign.left
                                      ? ComentarioDialogPalette.blue
                                      : CoresApp.textoSecundario),
                              onPressed: () {
                                setDialogState(
                                  () => alinhamentoComentario = TextAlign.left,
                                );
                                aplicarAlinhamentoComentario(
                                  TextAlign.left,
                                );
                                focarEditorRicoAtivo();
                              }),
                          IconButton(
                              tooltip: 'Centralizar',
                              icon: Icon(Icons.format_align_center,
                                  size: 17,
                                  color:
                                      alinhamentoComentario == TextAlign.center
                                          ? ComentarioDialogPalette.blue
                                          : CoresApp.textoSecundario),
                              onPressed: () {
                                setDialogState(
                                  () =>
                                      alinhamentoComentario = TextAlign.center,
                                );
                                aplicarAlinhamentoComentario(
                                  TextAlign.center,
                                );
                                focarEditorRicoAtivo();
                              }),
                          IconButton(
                              tooltip: 'Alinhar à direita',
                              icon: Icon(Icons.format_align_right,
                                  size: 17,
                                  color:
                                      alinhamentoComentario == TextAlign.right
                                          ? ComentarioDialogPalette.blue
                                          : CoresApp.textoSecundario),
                              onPressed: () {
                                setDialogState(
                                  () => alinhamentoComentario = TextAlign.right,
                                );
                                aplicarAlinhamentoComentario(
                                  TextAlign.right,
                                );
                                focarEditorRicoAtivo();
                              }),
                          IconButton(
                              tooltip: 'Justificar',
                              icon: Icon(Icons.format_align_justify,
                                  size: 17,
                                  color:
                                      alinhamentoComentario == TextAlign.justify
                                          ? ComentarioDialogPalette.blue
                                          : CoresApp.textoSecundario),
                              onPressed: () {
                                setDialogState(
                                  () =>
                                      alinhamentoComentario = TextAlign.justify,
                                );
                                aplicarAlinhamentoComentario(
                                  TextAlign.justify,
                                );
                                focarEditorRicoAtivo();
                              }),
                          const VerticalDivider(
                              width: 12, indent: 8, endIndent: 8),
                          IconButton(
                            tooltip: 'Inserir imagem',
                            icon: Icon(Icons.image_outlined,
                                size: 17, color: CoresApp.textoSecundario),
                            onPressed: () =>
                                selecionarImagem(dialogContext, setDialogState),
                          ),
                          const VerticalDivider(
                            width: 8,
                            indent: 8,
                            endIndent: 8,
                          ),
                          for (final indicador in const [
                            (
                              nome: 'amarelo',
                              dica: 'Inserir indicador amarelo',
                            ),
                            (
                              nome: 'vermelho',
                              dica: 'Inserir indicador vermelho',
                            ),
                            (
                              nome: 'verde',
                              dica: 'Inserir indicador verde',
                            ),
                          ])
                            IconButton(
                              tooltip: indicador.dica,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.circle,
                                size: 13,
                                color: corIndicador(
                                  indicador.nome,
                                ),
                              ),
                              onPressed:
                                  (salvando || testandoEdesk || enviandoEdesk)
                                      ? null
                                      : () async {
                                          await inserirIndicador(
                                            indicador.nome,
                                            setDialogState,
                                          );
                                        },
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          if (carregandoExcel)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Adicionando nova tabela...'),
                                ],
                              ),
                            ),
                          if (!carregandoExcel && erroExcel != null)
                            Text(
                              erroExcel!,
                              style: TextStyle(
                                color: CoresApp.erro,
                                fontSize: 10,
                              ),
                            ),
                          if (blocosComentario.isNotEmpty &&
                              editorController.document
                                  .toDelta()
                                  .toJson()
                                  .isEmpty) ...[
                            ...List.generate(
                              blocosComentario.length,
                              (index) {
                                final bloco = blocosComentario[index];
                                final tipo = bloco['tipo'] ?? '';
                                final valor = bloco['valor'] ?? '';

                                if (tipo == 'texto') {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: TextField(
                                          key: ValueKey(
                                            'bloco_texto_$index',
                                          ),
                                          controller:
                                              controllerParaBlocoTexto(bloco),
                                          focusNode: focoParaBlocoTexto(bloco),
                                          enabled:
                                              !testandoEdesk && !enviandoEdesk,
                                          maxLines: null,
                                          minLines: 1,
                                          textAlign: alinhamentoDoBloco(bloco),
                                          style: estiloDoBloco(bloco),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                          ),
                                          onTap: () {
                                            setDialogState(() {
                                              controllerParaBlocoTexto(bloco);
                                              focoParaBlocoTexto(bloco);
                                              fonteComentario =
                                                  bloco['fonte'] ?? 'Segoe UI';
                                              tamanhoFonteComentario =
                                                  double.tryParse(
                                                          bloco['tamanho'] ??
                                                              '') ??
                                                      11;
                                              negritoComentario =
                                                  bloco['negrito'] == 'true';
                                              italicoComentario =
                                                  bloco['italico'] == 'true';
                                              sublinhadoComentario =
                                                  bloco['sublinhado'] == 'true';
                                              tachadoComentario =
                                                  bloco['tachado'] == 'true';
                                              corFonteComentario =
                                                  corDoBloco(bloco);
                                            });
                                          },
                                          onChanged: (novoValor) {
                                            bloco['valor'] = novoValor;
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                // Indicador criado pelo próprio editor.
                                // Fica na mesma linha do texto e possui
                                // controles independentes de tamanho.
                                if (bloco['indicador'] == 'true') {
                                  final rotuloInline =
                                      bloco['rotuloInline'] ?? '';
                                  final largura = double.tryParse(
                                          bloco['larguraIndicador'] ?? '') ??
                                      90.0;
                                  final altura = double.tryParse(
                                          bloco['alturaIndicador'] ?? '') ??
                                      18.0;

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 2,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        if (rotuloInline.isNotEmpty)
                                          SizedBox(
                                            width: 160,
                                            child: TextFormField(
                                              key: ValueKey(
                                                'rotulo_indicador_$index',
                                              ),
                                              initialValue: rotuloInline,
                                              enabled: !testandoEdesk &&
                                                  !enviandoEdesk,
                                              maxLines: null,
                                              minLines: 1,
                                              style: estiloDoBloco(
                                                bloco,
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                              ),
                                              onChanged: (novoValor) {
                                                bloco['rotuloInline'] =
                                                    novoValor;
                                              },
                                            ),
                                          ),
                                        if (rotuloInline.isNotEmpty)
                                          const SizedBox(width: 5),
                                        Image.memory(
                                          base64Decode(valor),
                                          width: largura,
                                          height: altura,
                                          fit: BoxFit.fill,
                                        ),
                                        const SizedBox(width: 5),
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Diminuir indicador',
                                            icon: Icon(
                                              Icons.remove_circle_outline,
                                              size: 16,
                                              color: CoresApp.textoSecundario,
                                            ),
                                            onPressed: () async {
                                              await redimensionarIndicador(
                                                index,
                                                0.85,
                                                setDialogState,
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Aumentar indicador',
                                            icon: Icon(
                                              Icons.add_circle_outline,
                                              size: 16,
                                              color:
                                                  ComentarioDialogPalette.blue,
                                            ),
                                            onPressed: () async {
                                              await redimensionarIndicador(
                                                index,
                                                1.15,
                                                setDialogState,
                                              );
                                            },
                                          ),
                                        ),
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Remover indicador',
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16,
                                              color: CoresApp.erro,
                                            ),
                                            onPressed: () {
                                              setDialogState(() {
                                                final removida = valor;
                                                blocosComentario
                                                    .removeAt(index);
                                                imagensBase64.remove(removida);
                                                imagemBase64 =
                                                    imagensBase64.isNotEmpty
                                                        ? imagensBase64.last
                                                        : null;
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                // Imagem que veio do Ctrl+V da linha
                                // "Situação do Projeto:". Ela é exibida
                                // pequena e na mesma linha do rótulo.
                                if (bloco['inline'] == 'true') {
                                  final rotuloInline =
                                      bloco['rotuloInline'] ?? '';

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          rotuloInline,
                                          style: estiloDoBloco(
                                            bloco,
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 5,
                                        ),
                                        Container(
                                          constraints: const BoxConstraints(
                                            maxWidth: 120,
                                            maxHeight: 26,
                                          ),
                                          child: Image.memory(
                                            base64Decode(
                                              valor,
                                            ),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        const SizedBox(
                                          width: 4,
                                        ),
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Remover esta imagem',
                                            icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16,
                                              color: CoresApp.erro,
                                            ),
                                            onPressed: () {
                                              setDialogState(() {
                                                final removida = valor;
                                                blocosComentario
                                                    .removeAt(index);
                                                imagensBase64.remove(removida);
                                                imagemBase64 =
                                                    imagensBase64.isNotEmpty
                                                        ? imagensBase64.last
                                                        : null;
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                // Imagem/tabela comum do descritivo.
                                // A largura é ajustável somente na interface.
                                // A altura acompanha automaticamente a proporção
                                // real da imagem, sem reservar espaço vazio acima
                                // ou abaixo.
                                final larguraImagem = double.tryParse(
                                      bloco['larguraImagemEditor'] ?? '',
                                    ) ??
                                    760.0;

                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 2,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Image.memory(
                                            base64Decode(valor),
                                            width: larguraImagem,
                                            fit: BoxFit.contain,
                                            gaplessPlayback: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),

                                      // Controles locais do editor.
                                      // Não são persistidos como conteúdo e não
                                      // seguem para o comentário do E-Desk.
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              tooltip: 'Diminuir imagem',
                                              icon: Icon(
                                                Icons.remove_circle_outline,
                                                size: 16,
                                                color: CoresApp.textoSecundario,
                                              ),
                                              onPressed: () {
                                                redimensionarImagemEditor(
                                                  index,
                                                  0.85,
                                                  setDialogState,
                                                );
                                              },
                                            ),
                                          ),
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              tooltip: 'Aumentar imagem',
                                              icon: Icon(
                                                Icons.add_circle_outline,
                                                size: 16,
                                                color: ComentarioDialogPalette
                                                    .blue,
                                              ),
                                              onPressed: () {
                                                redimensionarImagemEditor(
                                                  index,
                                                  1.15,
                                                  setDialogState,
                                                );
                                              },
                                            ),
                                          ),
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              tooltip: 'Remover esta imagem',
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                size: 16,
                                                color: CoresApp.erro,
                                              ),
                                              onPressed: () {
                                                setDialogState(() {
                                                  final removida = valor;
                                                  blocosComentario
                                                      .removeAt(index);
                                                  imagensBase64
                                                      .remove(removida);
                                                  final indiceExcel =
                                                      imagensExcelBase64
                                                          .indexOf(removida);
                                                  if (indiceExcel >= 0) {
                                                    imagensExcelBase64
                                                        .removeAt(indiceExcel);
                                                    if (indiceExcel <
                                                        intervalosExcelAdicionados
                                                            .length) {
                                                      intervalosExcelAdicionados
                                                          .removeAt(
                                                              indiceExcel);
                                                    }
                                                  }
                                                  imagemBase64 =
                                                      imagensBase64.isNotEmpty
                                                          ? imagensBase64.last
                                                          : null;
                                                  imagemExcelBase64 =
                                                      imagensExcelBase64
                                                              .isNotEmpty
                                                          ? imagensExcelBase64
                                                              .last
                                                          : null;
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                          Expanded(
                            child: Shortcuts(
                              shortcuts: const {
                                SingleActivator(
                                  LogicalKeyboardKey.keyV,
                                  control: true,
                                ): _ColarComentarioIntent(),
                              },
                              child: Actions(
                                actions: {
                                  _ColarComentarioIntent:
                                      CallbackAction<_ColarComentarioIntent>(
                                    onInvoke: (intent) {
                                      colarConteudoRicoDoClipboard(
                                        setDialogState,
                                      );
                                      return null;
                                    },
                                  ),
                                },
                                child: quill.QuillEditor.basic(
                                  controller: editorController,
                                  focusNode: editorFocusNode,
                                  scrollController: editorScrollController,
                                  config: quill.QuillEditorConfig(
                                    placeholder:
                                        'Digite sua resposta ou atualização para o E-Desk...',
                                    customStyles: quill.DefaultStyles(
                                      placeHolder: quill.DefaultStyles
                                              .getInstance(context)
                                          .placeHolder
                                          ?.copyWith(
                                              style: const TextStyle(
                                            color:
                                                ComentarioDialogPalette.muted,
                                            fontSize: 12,
                                            height: 1.5,
                                          )),
                                    ),
                                    padding: const EdgeInsets.all(24),
                                    embedBuilders:
                                        quill_extensions.FlutterQuillEmbeds
                                            .defaultEditorBuilders(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
            final busy = salvando || testandoEdesk || enviandoEdesk;
            final modalTheme = Theme.of(context);
            return Theme(
              data: modalTheme.copyWith(
                textTheme: modalTheme.textTheme.apply(fontFamily: 'Segoe UI'),
                iconButtonTheme: IconButtonThemeData(
                    style: IconButton.styleFrom(
                  minimumSize: const Size(28, 28),
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )),
              ),
              child: Dialog(
                insetPadding: const EdgeInsets.all(12),
                backgroundColor: Colors.transparent,
                child: Transform.translate(
                  offset: offsetModal,
                  child: SizedBox(
                    width: larguraFinal,
                    height: alturaFinal,
                    child: ComentarioDialogLayout(
                      title: comentarioSelecionadoId == null
                          ? 'Novo comentário'
                          : 'Editar comentário',
                      project: 'E-Desk · ${project.id} · ${project.client}',
                      linked: obterTaskEdesk() != null,
                      controls: controls,
                      editor: editor,
                      history: construirPainelHistoricoIntegrado(),
                      attachments: Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          ComentarioAttachmentTile(
                            icon: Icons.image_outlined,
                            title: 'Imagem',
                            subtitle: imagensBase64.isEmpty
                                ? 'Adicionar arquivo'
                                : '${imagensBase64.length} arquivo(s)',
                            onTap: busy
                                ? null
                                : () => selecionarImagem(
                                    dialogContext, setDialogState),
                          ),
                          seletorImagemExcelAnexo(),
                        ],
                      ),
                      characterCount: contadorCaracteresComentario,
                      testing: testandoEdesk,
                      sending: enviandoEdesk,
                      saving: salvando,
                      onClose: () => Navigator.of(dialogContext).pop(),
                      onOpenHistory: () => abrirHistoricoComentarios(
                          dialogContext, setDialogState),
                      onTest: () => executarEdesk(
                          dialogContext: dialogContext,
                          setDialogState: setDialogState,
                          enviar: false),
                      onSend: () => executarEdesk(
                          dialogContext: dialogContext,
                          setDialogState: setDialogState,
                          enviar: true),
                      onDrag: (details) => setDialogState(() {
                        offsetModal += details.delta;
                      }),
                      onResize: (details) => setDialogState(() {
                        larguraCustomizada = (larguraFinal + details.delta.dx)
                            .clamp(320.0, tamanhoTela.width - 24);
                        alturaCustomizada = (alturaFinal + details.delta.dy)
                            .clamp(320.0, tamanhoTela.height - 24);
                      }),
                      headerAction: PopupMenuButton<String>(
                        tooltip: 'Mais ações',
                        enabled: !busy,
                        color: ComentarioDialogPalette.input,
                        icon: const Icon(Icons.more_horiz_rounded,
                            color: ComentarioDialogPalette.muted, size: 20),
                        onSelected: (action) {
                          if (action == 'save') {
                            salvarComentario(dialogContext, setDialogState);
                          }
                          if (action == 'clear') {
                            limparFormulario(setDialogState);
                          }
                          if (action == 'history') {
                            abrirHistoricoComentarios(
                                dialogContext, setDialogState);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'save',
                              child: Text('Salvar no histórico')),
                          PopupMenuItem(
                              value: 'clear', child: Text('Limpar comentário')),
                          PopupMenuItem(
                              value: 'history',
                              child: Text('Ver histórico completo')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      modalFechado = true;
      editorController.removeListener(sincronizarEstadoEditor);
      comentarioController.dispose();
      comentarioFocusNode.dispose();
      editorFocusNode.dispose();
      editorScrollController.dispose();
      editorController.dispose();
      contadorCaracteresComentario.dispose();
    });
  }

  static String _formatarDataResumo(DateTime value) {
    final date = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'Hoje, $time';
    if (day == DateTime(now.year, now.month, now.day - 1)) {
      return 'Ontem, $time';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}, $time';
  }

  static String _formatarDataComentario(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();

    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano $hora:$minuto';
  }

  static int _tipoComentarioEdesk(String tipo) {
    switch (tipo) {
      case 'Interno':
        return 0;

      case 'Externo':
        return 1;

      case 'Padrão':
        return 3;

      case 'Padrão (Interno)':
        return 4;

      default:
        return 0;
    }
  }
}

class _ComentarioRichTextController extends TextEditingController {
  final List<_ComentarioFormatoRange> _formatacoes =
      <_ComentarioFormatoRange>[];

  // Formatação ativa para a próxima digitação, no mesmo comportamento do Word.
  // Quando o cursor está apenas posicionado (sem texto selecionado), clicar em
  // Negrito/Itálico/Sublinhado/etc. altera este formato. O texto digitado a
  // partir dali recebe automaticamente a formatação ativa.
  _ComentarioFormato? _formatoDigitacao;

  @override
  set value(TextEditingValue newValue) {
    final textoAnterior = text;
    final textoNovo = newValue.text;

    if (textoAnterior != textoNovo) {
      // Descobre a faixa efetivamente inserida antes de reajustar os ranges.
      var prefixo = 0;
      final limitePrefixo = textoAnterior.length < textoNovo.length
          ? textoAnterior.length
          : textoNovo.length;
      while (prefixo < limitePrefixo &&
          textoAnterior.codeUnitAt(prefixo) == textoNovo.codeUnitAt(prefixo)) {
        prefixo++;
      }

      var sufixo = 0;
      while (sufixo < textoAnterior.length - prefixo &&
          sufixo < textoNovo.length - prefixo &&
          textoAnterior.codeUnitAt(textoAnterior.length - 1 - sufixo) ==
              textoNovo.codeUnitAt(textoNovo.length - 1 - sufixo)) {
        sufixo++;
      }

      final fimInserido = textoNovo.length - sufixo;

      if (_formatacoes.isNotEmpty) {
        _ajustarFormatacoesAposEdicao(textoAnterior, textoNovo);
      }

      // Aplica a formatação ativa somente ao conteúdo novo digitado/colado.
      if (_formatoDigitacao != null && fimInserido > prefixo) {
        _formatacoes.add(
          _ComentarioFormatoRange(
            inicio: prefixo,
            fim: fimInserido,
            formato: _formatoDigitacao!,
          ),
        );
        _normalizarFormatacoes();
      }
    }

    super.value = newValue;
  }

  void aplicarFormatacaoNaSelecao({
    required String fonte,
    required double tamanho,
    required bool negrito,
    required bool italico,
    required bool sublinhado,
    required bool tachado,
    required Color cor,
  }) {
    final selecao = selection;

    final formato = _ComentarioFormato(
      fonte: fonte,
      tamanho: tamanho,
      negrito: negrito,
      italico: italico,
      sublinhado: sublinhado,
      tachado: tachado,
      cor: cor,
    );

    // Comportamento estilo Word:
    // sem seleção, guarda a formatação para tudo que for digitado em seguida.
    if (!selecao.isValid || selecao.isCollapsed) {
      _formatoDigitacao = formato;
      notifyListeners();
      return;
    }

    // Com seleção, aplica imediatamente ao trecho selecionado e também mantém
    // esse formato ativo caso o usuário continue digitando depois da seleção.
    _formatoDigitacao = formato;

    final inicio = selecao.start < selecao.end ? selecao.start : selecao.end;
    final fim = selecao.start < selecao.end ? selecao.end : selecao.start;

    if (inicio < 0 || fim > text.length || inicio >= fim) return;

    // Divide/remaneja intervalos antigos que cruzam a nova seleção.
    final novas = <_ComentarioFormatoRange>[];

    for (final range in _formatacoes) {
      if (range.fim <= inicio || range.inicio >= fim) {
        novas.add(range);
        continue;
      }

      if (range.inicio < inicio) {
        novas.add(
          _ComentarioFormatoRange(
            inicio: range.inicio,
            fim: inicio,
            formato: range.formato,
          ),
        );
      }

      if (range.fim > fim) {
        novas.add(
          _ComentarioFormatoRange(
            inicio: fim,
            fim: range.fim,
            formato: range.formato,
          ),
        );
      }
    }

    novas.add(
      _ComentarioFormatoRange(
        inicio: inicio,
        fim: fim,
        formato: formato,
      ),
    );

    _formatacoes
      ..clear()
      ..addAll(novas);

    _normalizarFormatacoes();
    notifyListeners();
  }

  List<Map<String, String>> criarBlocosParaPersistir({
    required String fontePadrao,
    required double tamanhoPadrao,
    required TextAlign alinhamento,
    required Color corPadrao,
  }) {
    if (text.trim().isEmpty) return <Map<String, String>>[];

    final formatoPadrao = _ComentarioFormato(
      fonte: fontePadrao,
      tamanho: tamanhoPadrao,
      negrito: false,
      italico: false,
      sublinhado: false,
      tachado: false,
      cor: corPadrao,
    );

    final pontos = <int>{0, text.length};
    for (final range in _formatacoes) {
      pontos.add(range.inicio.clamp(0, text.length).toInt());
      pontos.add(range.fim.clamp(0, text.length).toInt());
    }

    final ordenados = pontos.toList()..sort();
    final blocos = <Map<String, String>>[];

    for (var i = 0; i < ordenados.length - 1; i++) {
      final inicio = ordenados[i];
      final fim = ordenados[i + 1];
      if (inicio >= fim) continue;

      final trecho = text.substring(inicio, fim);
      final formato = _formatoNoIndice(inicio) ?? formatoPadrao;

      blocos.add({
        'tipo': 'texto',
        'valor': trecho,
        'fonte': formato.fonte,
        'tamanho': formato.tamanho.toString(),
        'negrito': formato.negrito.toString(),
        'italico': formato.italico.toString(),
        'sublinhado': formato.sublinhado.toString(),
        'tachado': formato.tachado.toString(),
        'alinhamento': alinhamento.name,
        'cor': formato.cor.toARGB32().toRadixString(16).padLeft(8, '0'),
      });
    }

    return blocos;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty || _formatacoes.isEmpty) {
      return TextSpan(style: style, text: text);
    }

    final children = <InlineSpan>[];
    var cursor = 0;
    final ranges = List<_ComentarioFormatoRange>.from(_formatacoes)
      ..sort((a, b) => a.inicio.compareTo(b.inicio));

    for (final range in ranges) {
      final inicio = range.inicio.clamp(0, text.length).toInt();
      final fim = range.fim.clamp(0, text.length).toInt();

      if (inicio >= fim) continue;

      if (cursor < inicio) {
        children.add(TextSpan(text: text.substring(cursor, inicio)));
      }

      children.add(
        TextSpan(
          text: text.substring(inicio, fim),
          style: range.formato.toTextStyle(),
        ),
      );

      cursor = fim;
    }

    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: style, children: children);
  }

  _ComentarioFormato? _formatoNoIndice(int indice) {
    for (final range in _formatacoes.reversed) {
      if (indice >= range.inicio && indice < range.fim) {
        return range.formato;
      }
    }
    return null;
  }

  void _ajustarFormatacoesAposEdicao(String anterior, String novo) {
    var prefixo = 0;
    final limitePrefixo =
        anterior.length < novo.length ? anterior.length : novo.length;

    while (prefixo < limitePrefixo &&
        anterior.codeUnitAt(prefixo) == novo.codeUnitAt(prefixo)) {
      prefixo++;
    }

    var sufixo = 0;
    while (sufixo < anterior.length - prefixo &&
        sufixo < novo.length - prefixo &&
        anterior.codeUnitAt(anterior.length - 1 - sufixo) ==
            novo.codeUnitAt(novo.length - 1 - sufixo)) {
      sufixo++;
    }

    final fimAlteradoAnterior = anterior.length - sufixo;
    final fimAlteradoNovo = novo.length - sufixo;
    final delta = fimAlteradoNovo - fimAlteradoAnterior;
    final ajustadas = <_ComentarioFormatoRange>[];

    for (final range in _formatacoes) {
      if (range.fim <= prefixo) {
        ajustadas.add(range);
        continue;
      }

      if (range.inicio >= fimAlteradoAnterior) {
        ajustadas.add(
          _ComentarioFormatoRange(
            inicio: range.inicio + delta,
            fim: range.fim + delta,
            formato: range.formato,
          ),
        );
        continue;
      }

      // Mantém a parte formatada que ficou antes da edição.
      if (range.inicio < prefixo) {
        ajustadas.add(
          _ComentarioFormatoRange(
            inicio: range.inicio,
            fim: prefixo,
            formato: range.formato,
          ),
        );
      }

      // Mantém a parte formatada que ficou depois da edição.
      if (range.fim > fimAlteradoAnterior) {
        ajustadas.add(
          _ComentarioFormatoRange(
            inicio: fimAlteradoNovo,
            fim: range.fim + delta,
            formato: range.formato,
          ),
        );
      }
    }

    _formatacoes
      ..clear()
      ..addAll(
        ajustadas.where(
          (range) =>
              range.inicio >= 0 &&
              range.fim <= novo.length &&
              range.inicio < range.fim,
        ),
      );

    _normalizarFormatacoes();
  }

  void _normalizarFormatacoes() {
    _formatacoes.sort((a, b) => a.inicio.compareTo(b.inicio));

    if (_formatacoes.length < 2) return;

    final normalizadas = <_ComentarioFormatoRange>[];

    for (final atual in _formatacoes) {
      if (normalizadas.isEmpty) {
        normalizadas.add(atual);
        continue;
      }

      final anterior = normalizadas.last;
      if (anterior.fim == atual.inicio && anterior.formato == atual.formato) {
        normalizadas[normalizadas.length - 1] = _ComentarioFormatoRange(
          inicio: anterior.inicio,
          fim: atual.fim,
          formato: anterior.formato,
        );
      } else {
        normalizadas.add(atual);
      }
    }

    _formatacoes
      ..clear()
      ..addAll(normalizadas);
  }

  @override
  void clear() {
    _formatacoes.clear();
    _formatoDigitacao = null;
    super.clear();
  }
}

class _ComentarioFormatoRange {
  final int inicio;
  final int fim;
  final _ComentarioFormato formato;

  const _ComentarioFormatoRange({
    required this.inicio,
    required this.fim,
    required this.formato,
  });
}

class _ComentarioFormato {
  final String fonte;
  final double tamanho;
  final bool negrito;
  final bool italico;
  final bool sublinhado;
  final bool tachado;
  final Color cor;

  const _ComentarioFormato({
    required this.fonte,
    required this.tamanho,
    required this.negrito,
    required this.italico,
    required this.sublinhado,
    required this.tachado,
    required this.cor,
  });

  TextStyle toTextStyle() {
    return TextStyle(
      color: cor,
      fontSize: tamanho,
      fontFamily: fonte,
      fontWeight: negrito ? FontWeight.bold : FontWeight.normal,
      fontStyle: italico ? FontStyle.italic : FontStyle.normal,
      decoration: TextDecoration.combine([
        if (sublinhado) TextDecoration.underline,
        if (tachado) TextDecoration.lineThrough,
      ]),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _ComentarioFormato &&
        other.fonte == fonte &&
        other.tamanho == tamanho &&
        other.negrito == negrito &&
        other.italico == italico &&
        other.sublinhado == sublinhado &&
        other.tachado == tachado &&
        other.cor.toARGB32() == cor.toARGB32();
  }

  @override
  int get hashCode => Object.hash(
        fonte,
        tamanho,
        negrito,
        italico,
        sublinhado,
        tachado,
        cor.toARGB32(),
      );
}

class _CorFonteItem extends StatelessWidget {
  final Color cor;
  final String nome;

  const _CorFonteItem({required this.cor, required this.nome});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(width: 10),
        Text(nome),
      ],
    );
  }
}
