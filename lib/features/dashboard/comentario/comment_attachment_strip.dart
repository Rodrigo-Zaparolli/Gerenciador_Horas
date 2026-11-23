import 'package:flutter/material.dart';

class CommentAttachmentStrip extends StatelessWidget {
  const CommentAttachmentStrip({super.key, required this.count, required this.child});
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) => ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: 32,
      leading: const Icon(Icons.attach_file, size: 18),
      title: Text('Imagens anexadas ($count)', style: const TextStyle(fontSize: 12)),
      children: [child]);
}
