import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/shared/widgets/movable_document_dialog.dart';

void main() {
  testWidgets('resizes and moves without losing unsaved text', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:MovableDocumentDialog(child:TextField())));
    await tester.enterText(find.byType(TextField),'Pendente');
    final before=tester.getSize(find.byType(Material).last);
    await tester.drag(find.byKey(const ValueKey('document-resize-handle')),const Offset(-140,-100));
    await tester.pumpAndSettle();
    final after=tester.getSize(find.byType(Material).last);
    expect(after.width,lessThan(before.width));
    final position=tester.getTopLeft(find.byKey(const ValueKey('document-drag-handle')));
    await tester.drag(find.byKey(const ValueKey('document-drag-handle')),const Offset(50,40));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('document-drag-handle'))).dx,greaterThan(position.dx));
    expect(find.text('Pendente'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
