import 'package:flutter/material.dart';

/// Keeps the full table, including trailing actions, inside the available width.
/// Height follows the rows so projects do not scroll inside a clipped viewport.
class ProjectTableViewport extends StatelessWidget {
  final Widget child;
  const ProjectTableViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: child,
            ),
          ),
        ),
      );
}
