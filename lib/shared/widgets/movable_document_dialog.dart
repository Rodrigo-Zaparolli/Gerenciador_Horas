import 'package:flutter/material.dart';

/// Keeps the editor mounted while moving or resizing its surface.
class MovableDocumentDialog extends StatefulWidget {
  const MovableDocumentDialog({super.key, required this.child});
  final Widget child;
  @override
  State<MovableDocumentDialog> createState() => _MovableDocumentDialogState();
}

class _MovableDocumentDialogState extends State<MovableDocumentDialog> {
  Offset offset = const Offset(16, 16);
  Size? size;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final maxWidth = bounds.maxWidth - 16;
    final maxHeight = bounds.maxHeight - 16;
    final width = (size?.width ?? maxWidth).clamp(320.0.clamp(0, maxWidth), maxWidth).toDouble();
    final height = (size?.height ?? maxHeight).clamp(320.0.clamp(0, maxHeight), maxHeight).toDouble();
    final left = offset.dx.clamp(0, bounds.maxWidth - width).toDouble();
    final top = offset.dy.clamp(0, bounds.maxHeight - height).toDouble();
    return Stack(children: [Positioned(left:left,top:top,width:width,height:height,
      child:Material(elevation:24,borderRadius:BorderRadius.circular(16),clipBehavior:Clip.antiAlias,
        color:Theme.of(context).dialogTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
        child:Column(children:[
          GestureDetector(key:const ValueKey('document-drag-handle'),behavior:HitTestBehavior.opaque,
            onPanUpdate:(event)=>setState(()=>offset=Offset(left,top)+event.delta),
            child:MouseRegion(cursor:SystemMouseCursors.move,child:SizedBox(height:24,
              child:Row(mainAxisAlignment:MainAxisAlignment.center,children:const[
                Icon(Icons.drag_handle,size:18),SizedBox(width:6),Text('Arraste para mover',style:TextStyle(fontSize:11))])))),
          Expanded(child:widget.child),
          Align(alignment:Alignment.centerRight,child:GestureDetector(
            key:const ValueKey('document-resize-handle'),behavior:HitTestBehavior.opaque,
            onPanUpdate:(event)=>setState(()=>size=Size(width+event.delta.dx,height+event.delta.dy)),
            child:const MouseRegion(cursor:SystemMouseCursors.resizeUpLeftDownRight,
              child:Padding(padding:EdgeInsets.all(5),child:Icon(Icons.open_in_full,size:16))))),
        ])),
    )]);
  });
}
