import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comentario_dialog_layout.dart';

Widget _field(String label, String value, double width) => SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ComentarioSectionLabel(label),
        const SizedBox(height: 9),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
              color: ComentarioDialogPalette.input,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: ComentarioDialogPalette.border)),
          child: Row(children: [
            Expanded(
                child: Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: ComentarioDialogPalette.text, fontSize: 12))),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: ComentarioDialogPalette.muted, size: 18),
          ]),
        ),
      ]),
    );

Widget _editor() => Container(
      decoration: BoxDecoration(
          color: ComentarioDialogPalette.editor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ComentarioDialogPalette.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 42,
          color: ComentarioDialogPalette.input,
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                const SizedBox(width: 12),
                const Text('Segoe UI',
                    style: TextStyle(
                        color: ComentarioDialogPalette.text, fontSize: 12)),
                const SizedBox(width: 20),
                for (final icon in [
                  Icons.format_bold,
                  Icons.format_italic,
                  Icons.format_underlined,
                  Icons.format_strikethrough,
                  Icons.format_align_left,
                  Icons.format_align_center,
                  Icons.format_align_right,
                  Icons.image_outlined
                ])
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Icon(icon,
                          size: 20, color: ComentarioDialogPalette.muted)),
                for (final color in [
                  Colors.amber,
                  Colors.redAccent,
                  ComentarioDialogPalette.green
                ])
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.circle, size: 15, color: color)),
              ])),
        ),
        const Expanded(
            child: SingleChildScrollView(
                padding: EdgeInsets.all(27),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ComentarioSectionLabel(
                          'IMAGEM DA PLANILHA · PRÉVIA GERADA DO EXCEL'),
                      SizedBox(height: 12),
                      SizedBox(
                          height: 100,
                          width: double.infinity,
                          child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: Color(0xFFE5ECF5),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(8))),
                              child: Center(
                                  child: Icon(Icons.table_chart_outlined,
                                      size: 60, color: Color(0xFF5C83B3))))),
                      SizedBox(height: 18),
                      ComentarioSectionLabel(
                          'MODELO INSERIDO ABAIXO DA IMAGEM'),
                      SizedBox(height: 10),
                      Text('Atualização do projeto',
                          style: TextStyle(
                              color: ComentarioDialogPalette.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 10),
                      Text(
                          'Olá equipe. Segue o resumo das atividades e dos próximos passos.',
                          style: TextStyle(
                              color: ComentarioDialogPalette.text,
                              fontSize: 12)),
                      SizedBox(height: 16),
                      Text('Situação do Projeto:   Em andamento',
                          style: TextStyle(
                              color: ComentarioDialogPalette.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 14),
                      Text(
                          '• Atividade principal concluída dentro do prazo.\n• Próxima etapa inicia na segunda-feira.',
                          style: TextStyle(
                              color: ComentarioDialogPalette.text,
                              fontSize: 11,
                              height: 1.8)),
                    ]))),
      ]),
    );

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('SAVE_COMMENT_PREVIEW') &&
        Platform.isWindows) {
      final textFonts = FontLoader('Segoe UI');
      for (final filename in ['segoeui.ttf', 'segoeuib.ttf']) {
        textFonts.addFont(Future.value(ByteData.sublistView(
            await File('C:/Windows/Fonts/$filename').readAsBytes())));
      }
      await textFonts.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(await File(
              'C:/src/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes())));
      await icons.load();
    }
  });
  for (final size in [
    const Size(1440, 900),
    const Size(900, 700),
    const Size(390, 844)
  ]) {
    testWidgets('Composer fits ${size.width} and preserves its actions',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final count = ValueNotifier<int>(486);
      addTearDown(count.dispose);
      var tested = false;
      var sent = false;
      var historyOpened = false;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark().copyWith(
              textTheme:
                  ThemeData.dark().textTheme.apply(fontFamily: 'Segoe UI')),
          home: Scaffold(
            backgroundColor: const Color(0xFF0B1420),
            body: RepaintBoundary(
                key: const ValueKey('preview'),
                child: Center(
                    child: SizedBox(
                  width: size.width >= 1100 ? 1296 : size.width - 24,
                  height: size.height - 96,
                  child: ComentarioDialogLayout(
                    title: 'Novo comentário',
                    project: 'E-Desk · Projeto Atlas',
                    linked: true,
                    controls: ComentarioControlsRow(
                      type: _field('TIPO', 'Comentário externo', 166),
                      tag: _field('ETIQUETA DO CHAMADO', 'Enterprise', 248),
                      model: _field('MODELO DO DESCRITIVO',
                          'Enterprise / Professional', 320),
                    ),
                    editor: KeyedSubtree(
                        key: const ValueKey('comment-editor'),
                        child: _editor()),
                    history: ComentarioHistoryPanel(
                      onSearch: (_) {},
                      onOpenHistory: () {
                        historyOpened = true;
                      },
                      child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          children: const [
                            ComentarioHistoryCard(
                                author: 'Rafael Almeida',
                                date: 'Hoje, 14:32',
                                text: 'Atualização semanal do projeto',
                                status: 'Enviado',
                                highlighted: true),
                            SizedBox(height: 12),
                            ComentarioHistoryCard(
                                author: 'Mariana Costa',
                                date: 'Ontem, 17:08',
                                text: 'Revisão do cronograma concluída',
                                status: 'Enviado'),
                            SizedBox(height: 12),
                            ComentarioHistoryCard(
                                author: 'Lucas Santos',
                                date: '06/10, 11:45',
                                text: 'Aguardando retorno do cliente',
                                status: 'Pendente'),
                          ]),
                    ),
                    attachments:
                        const Wrap(spacing: 12, runSpacing: 10, children: [
                      ComentarioAttachmentTile(
                          icon: Icons.image_outlined,
                          title: 'Imagem',
                          subtitle: '1 arquivo'),
                      ComentarioAttachmentTile(
                          icon: Icons.table_view_outlined,
                          title: 'Tabela do Excel',
                          subtitle: 'Selecionar intervalo',
                          width: 190),
                    ]),
                    characterCount: count,
                    onClose: () {},
                    onTest: () {
                      tested = true;
                    },
                    onSend: () {
                      sent = true;
                    },
                    onOpenHistory: () {
                      historyOpened = true;
                    },
                  ),
                ))),
          )));
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (size.width >= 1100) {
        final type = tester.getTopLeft(find.text('TIPO'));
        final tag = tester.getTopLeft(find.text('ETIQUETA DO CHAMADO'));
        final model = tester.getTopLeft(find.text('MODELO DO DESCRITIVO'));
        expect(tag.dy, type.dy);
        expect(model.dy, type.dy);
        expect(tag.dx, greaterThan(type.dx));
        expect(model.dx, greaterThan(tag.dx));
        expect(
            tester.getSize(find.byKey(const ValueKey('comment-editor'))).height,
            greaterThan(350));
      }
      if (size.width >= 1100 &&
          const bool.fromEnvironment('SAVE_COMMENT_PREVIEW')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('screenshots').createSync(recursive: true);
          File('screenshots/comentario_layout_preview.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester
          .tap(find.text(size.width < 600 ? 'Testar' : 'Testar sem salvar'));
      await tester
          .tap(find.text(size.width < 600 ? 'Enviar' : 'Enviar comentário'));
      expect(tested, isTrue);
      expect(sent, isTrue);
      if (size.width < 1100) {
        final historyButton = find.text('Histórico do projeto');
        await tester.ensureVisible(historyButton);
        await tester.tap(historyButton);
        expect(historyOpened, isTrue);
      } else {
        expect(find.text('Rafael Almeida'), findsOneWidget);
        await tester.tap(find.text('Ver histórico completo'));
        expect(historyOpened, isTrue);
      }
      count.value = 2001;
      await tester.pump();
      expect(find.textContaining('2001 / 2000'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
