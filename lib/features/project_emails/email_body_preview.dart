import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'email_document.dart';
import 'sharepoint_email_links.dart';

class EmailBodyPreview extends StatelessWidget {
  final String body;
  final Uint8List? productsImage;
  final Map<String, String> linkLabels;
  final TextEditingController? controller;
  final VoidCallback? onChanged;
  final bool enabled;
  const EmailBodyPreview(
      {super.key,
      required this.body,
      this.productsImage,
      this.linkLabels = const {},
      this.controller,
      this.onChanged,
      this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return _InlineEmailEditor(
          controller: controller!,
          productsImage: productsImage,
          enabled: enabled,
          onChanged: onChanged);
    }
    final parts = (productsImage == null
            ? body.replaceAll(
                productsImageMarker, '[PREENCHER: Produtos adquiridos]')
            : emailBodyWithProductsImage(body))
        .split(productsImageMarker);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < parts.length; i++) ...[
        if (parts[i].isNotEmpty)
          EmailPendingText(emailLinkDisplayText(parts[i], linkLabels)),
        if (i < parts.length - 1 && productsImage != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.memory(productsImage!,
                key: i == 0
                    ? const ValueKey('email-products-image-preview')
                    : null,
                height: 220,
                fit: BoxFit.contain),
          ),
      ],
    ]);
  }
}

class _InlineEmailEditor extends StatefulWidget {
  const _InlineEmailEditor(
      {required this.controller,
      required this.enabled,
      this.productsImage,
      this.onChanged});
  final TextEditingController controller;
  final Uint8List? productsImage;
  final bool enabled;
  final VoidCallback? onChanged;
  @override
  State<_InlineEmailEditor> createState() => _InlineEmailEditorState();
}

class _InlineEmailEditorState extends State<_InlineEmailEditor> {
  final editors = <_PendingTextController>[];
  int count = 0;
  bool writing = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(sync);
    sync();
  }

  void sync() {
    if (writing) return;
    final source = widget.productsImage == null
        ? widget.controller.text
        : emailBodyWithProductsImage(widget.controller.text);
    final parts = source.split(productsImageMarker);
    while (editors.length < parts.length) {
      editors.add(_PendingTextController());
    }
    for (var i = 0; i < parts.length; i++) {
      if (editors[i].text != parts[i]) {
        final offset =
            editors[i].selection.baseOffset.clamp(0, parts[i].length);
        editors[i].value = TextEditingValue(
            text: parts[i], selection: TextSelection.collapsed(offset: offset));
      }
    }
    if (count != parts.length) setState(() => count = parts.length);
  }

  void changed() {
    writing = true;
    try {
      widget.controller.text =
          editors.take(count).map((c) => c.text).join(productsImageMarker);
    } finally {
      writing = false;
    }
    widget.onChanged?.call();
  }

  @override
  void didUpdateWidget(covariant _InlineEmailEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(sync);
      widget.controller.addListener(sync);
    }
    sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(sync);
    for (final controller in editors) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++) ...[
            TextField(
                key: ValueKey('email-inline-body-$i'),
                controller: editors[i],
                enabled: widget.enabled,
                minLines: 1,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                    labelText: i == 0 ? 'Mensagem — editável' : null,
                    hintText: 'Escreva diretamente no corpo do e-mail…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8)),
                onChanged: (_) => changed()),
            if (i < count - 1 && widget.productsImage != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Image.memory(widget.productsImage!,
                      key: i == 0
                          ? const ValueKey('email-products-image-preview')
                          : null,
                      height: 220,
                      fit: BoxFit.contain)),
          ],
        ],
      );
}

class _PendingTextController extends TextEditingController {
  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in RegExp(r'\[PREENCHER: [^\]]+\]').allMatches(text)) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(
              color: Color(0xFF823900),
              backgroundColor: Color(0xFFFFE4AA),
              fontWeight: FontWeight.bold)));
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}

class EmailPendingText extends StatelessWidget {
  const EmailPendingText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final matches = RegExp(r'\[PREENCHER: [^\]]+\]').allMatches(text).toList();
    if (matches.isEmpty) return SelectableText(text);
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in matches) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      spans.add(TextSpan(
          text: match.group(0),
          style: const TextStyle(
              color: Color(0xFF823900),
              backgroundColor: Color(0xFFFFE4AA),
              fontWeight: FontWeight.bold)));
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return SelectableText.rich(
        TextSpan(style: DefaultTextStyle.of(context).style, children: spans));
  }
}
