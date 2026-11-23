import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_stage.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_stage_panel.dart';

void main() {
  test('rounds displayed stage percentage like the Excel table', () {
    final stage = CommentStage('Implantação', DateTime(2026, 11, 11), .6666667);
    expect(stage.percent, '67%');
    expect(stage.percentage, .6666667);
    final editor = QuillController.basic();
    editor.document.insert(0, 'Etapa atual do projeto: Implantação\nPercentual: 66,7%\n');
    applyCommentStage(editor, stage);
    expect(editor.document.toPlainText(), contains('Percentual: 67%'));
    expect(editor.document.toPlainText(), isNot(contains('66,7%')));
    editor.dispose();
  });
  final implant = CommentStage('Implantação', DateTime(2026, 9, 28), 1);
  final post = CommentStage('Pós-Implantação', DateTime(2026, 11, 5), .8);
  test('updates finalization variants in place without duplicating the date', () {
    for (final label in ['Finalização até dia:', 'Finalizaçao até dia:',
      'Finalização até o dia -', 'Finalização até dia: -']) {
      final editor = QuillController.basic();
      editor.document.insert(0, 'Etapa atual do projeto: Implantação\n$label 15/10/2026\nPercentual: 43%\nAgenda: manter\n');
      applyCommentStage(editor, post);
      final text = editor.document.toPlainText();
      expect(text, contains('$label 05/11/2026'));
      expect(text, isNot(contains('15/10/2026')));
      expect('05/11/2026'.allMatches(text).length, 1);
      expect(text, contains('Agenda: manter'));
      editor.dispose();
    }
  });

  testWidgets('auto-load follows stage written in the comment and its own end date', (tester) async {
    final editor = QuillController.basic();
    editor.document.insert(0, 'Etapa atual do projeto: Implantação\nFinalização até dia: 15/10/2026\nPercentual: 43%\n');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CommentStagePanel(
      autoLoad: true, editorChanges: editor,
      currentStageName: () => commentStageNameFromText(editor.document.toPlainText()),
      load: () async => [implant, post], allowed: () => true,
      onSelected: (stage) => applyCommentStage(editor, stage),
    ))));
    await tester.pumpAndSettle();
    expect(editor.document.toPlainText(), contains('28/09/2026'));
    final text = editor.document.toPlainText();
    final offset = text.indexOf('Implantação');
    editor.replaceText(offset, 'Implantação'.length, 'Pós-Implantação', null);
    await tester.pumpAndSettle();
    expect(editor.document.toPlainText(), contains('Finalização até dia: 05/11/2026'));
    expect(editor.document.toPlainText(), contains('Percentual: 80%'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
  });
  test('uses stage percentage and end, never project total or weight', () {
    final rows = CommentStage.fromStatus({
      'statusPreview': {
        'total': .94,
        'rows': [
          {
            'label': 'Pós-Implantação',
            'percentage': .8,
            'weight': .3,
            'end': '2026-11-05'
          }
        ]
      }
    });
    expect(rows.single.percent, '80%');
    expect(rows.single.date, '05/11/2026');
    expect(
        () => CommentStage.fromStatus({
              'statusPreview': {
                'rows': [
                  {'label': 'Implantação', 'percentage': 1, 'end': null}
                ]
              }
            }),
        throwsFormatException);
    expect(
        () => CommentStage.fromStatus({
              'statusPreview': {
                'rows': [
                  {
                    'label': 'Implantação',
                    'percentage': 43,
                    'end': '2026-11-05'
                  }
                ]
              }
            }),
        throwsFormatException);
  });
  test('changes three values, preserves embeds, agenda, styles and idempotence',
      () {
    final editor = QuillController.basic();
    editor.document = Document.fromJson([
      {'insert': 'Qual o progresso deste projeto:\n'},
      {'insert': 'Etapa atual do projeto: Implantação\n'},
      {
        'insert':
            '     Finalização até o dia - 15/10/2026\n     Percentual: 43%\n'
      },
      {
        'insert': {'image': 'data:image/png;base64,example'}
      },
      {'insert': '\n'},
      {
        'insert': 'Contato: Fernando\nAgenda: 13/10 - Relatórios\n',
        'attributes': {'bold': true, 'font': 'Times New Roman'}
      },
    ]);
    applyCommentStage(editor, implant);
    expect(editor.document.toPlainText(), contains('Percentual: 100%'));
    applyCommentStage(editor, post);
    expect(editor.document.toPlainText(),
        contains('Etapa atual do projeto: Pós-Implantação'));
    expect(editor.document.toPlainText(), contains('dia - 05/11/2026'));
    expect(editor.document.toPlainText(), contains('Percentual: 80%'));
    final delta = editor.document.toDelta().toJson();
    expect(delta.any((op) => op['insert'] is Map), isTrue);
    expect(
        delta.any((op) =>
            op['insert'].toString().contains('Contato: Fernando') &&
            (op['attributes'] as Map?)?['bold'] == true),
        isTrue);
    applyCommentStage(editor, post);
    expect(editor.document.toDelta().toJson(), delta);
    editor.dispose();
  });
  test(
      'supports nonbreaking spaces, tokens, and missing fields without deleting text',
      () {
    final editor = QuillController.basic();
    editor.document.insert(
        0,
        'Etapa\u00a0atual\u00a0do\u00a0projeto: Implantação\n'
        'Finalização até o dia - {{fim_etapa}}\nPercentual: {{percentual_etapa}}\nAgenda: manter\n');
    applyCommentStage(editor, post);
    expect(editor.document.toPlainText(), contains('80%'));
    expect(editor.document.toPlainText(), contains('Agenda: manter'));
    expect(editor.document.toPlainText(), isNot(contains('{{')));
    editor.document = Document()..insert(0, 'Texto sem modelo\n');
    applyCommentStage(editor, implant);
    expect(editor.document.toPlainText(), contains('Texto sem modelo'));
    expect(editor.document.toPlainText(), contains('Percentual: 100%'));
    editor.dispose();
  });
  testWidgets('explicit load and selection apply only chosen stage',
      (tester) async {
    var loads = 0;
    CommentStage? chosen;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommentStagePanel(
                load: () async {
                  loads++;
                  return [implant, post];
                },
                allowed: () => true,
                onSelected: (s) => chosen = s))));
    expect(loads, 0);
    await tester.tap(find.text('Carregar etapas'));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(chosen, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pós-Implantação').last);
    await tester.pumpAndSettle();
    expect(chosen, post);
    expect(find.textContaining('05/11/2026'), findsOneWidget);
  });
  testWidgets('read failure never replaces comment values', (tester) async {
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CommentStagePanel(
                load: () async => throw StateError('Integração ocupada'),
                allowed: () => true,
                onSelected: (_) => changes++))));
    await tester.tap(find.text('Carregar etapas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Integração ocupada'), findsOneWidget);
    expect(changes, 0);
  });
}
