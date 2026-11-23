import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'products_image_field_test.dart' show png;

void main() {
  testWidgets('Pending fields stay highlighted while directly editable',
      (tester) async {
    final controller =
        TextEditingController(text: 'Nome: [PREENCHER: Nome do sistema]');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmailBodyPreview(
                body: controller.text, controller: controller))));
    final finder = find.byKey(const ValueKey('email-inline-body-0'));
    final field = tester.widget<TextField>(finder);
    final span = field.controller!
        .buildTextSpan(context: tester.element(finder), withComposing: false);
    expect(
        span.children!.whereType<TextSpan>().any((s) =>
            s.text == '[PREENCHER: Nome do sistema]' &&
            s.style?.backgroundColor == const Color(0xFFFFE4AA)),
        isTrue);
    await tester.enterText(finder, 'Nome: Cliente');
    await tester.pump();
    expect(controller.text, 'Nome: Cliente');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('Edits directly around inline image and keeps canonical body',
      (tester) async {
    final controller = TextEditingController(
        text: 'Produtos:\n$productsImageMarker\nDados do cliente');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, refresh) => SingleChildScrollView(
                    child: EmailBodyPreview(
                        body: controller.text,
                        controller: controller,
                        productsImage: png,
                        onChanged: () => refresh(() {})))))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('email-inline-body-0')),
        'Produtos revisados:\n');
    await tester.pump();
    expect(controller.text,
        'Produtos revisados:\n$productsImageMarker\nDados do cliente');
    await tester.enterText(find.byKey(const ValueKey('email-inline-body-1')),
        'Cliente atualizado');
    await tester.pump();
    expect(controller.text,
        'Produtos revisados:\n${productsImageMarker}Cliente atualizado');
    expect(find.byKey(const ValueKey('email-products-image-preview')),
        findsOneWidget);
    expect(find.textContaining(productsImageMarker), findsNothing);
    controller.text = 'Texto recarregado';
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('email-inline-body-0')))
            .controller!
            .text,
        contains('Texto recarregado'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('proposal appears at marker between products and system data',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmailBodyPreview(
                body:
                    'Produtos adquiridos pelo cliente:\n$productsImageMarker\nDados gerais do sistema',
                productsImage: png))));
    await tester.pumpAndSettle();
    final image = find.byKey(const ValueKey('email-products-image-preview'));
    final before = find.text('Produtos adquiridos pelo cliente:\n');
    final after = find.text('\nDados gerais do sistema');
    expect(
        tester.getBottomLeft(before).dy, lessThan(tester.getTopLeft(image).dy));
    expect(
        tester.getBottomLeft(image).dy, lessThan(tester.getTopLeft(after).dy));
    expect(find.textContaining(productsImageMarker), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
