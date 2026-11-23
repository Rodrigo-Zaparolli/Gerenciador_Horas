import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_stage_panel.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_stage.dart';
import 'package:gerenciador_horas/features/dashboard/comentario/comment_attachment_strip.dart';

void main() {
  testWidgets('compact stage keeps selection in one row and attachments start collapsed', (tester) async {
    CommentStage? selected;
    final stage = CommentStage('Implantação',DateTime(2026,12,5),.67);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 700,
      child: Column(children: [
        CommentStagePanel(compact:true, autoLoad:true,
          load:() async => [stage], allowed:()=>true, onSelected:(s)=>selected=s),
        const Expanded(child: TextField(key:ValueKey('writing'), expands:true, maxLines:null)),
        const CommentAttachmentStrip(count:2,child:SizedBox(height:70,child:Text('Miniaturas'))),
      ])))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CommentStagePanel)).height,lessThanOrEqualTo(64));
    expect(tester.getSize(find.byKey(const ValueKey('writing'))).height,greaterThan(400));
    expect(find.text('Miniaturas').hitTestable(),findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Implantação').last);
    await tester.pumpAndSettle();
    expect(selected,stage);
    await tester.tap(find.text('Imagens anexadas (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Miniaturas').hitTestable(),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
