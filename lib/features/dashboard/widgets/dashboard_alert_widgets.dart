import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';

class AlertSummaryCard extends StatelessWidget {
  const AlertSummaryCard(
      {super.key,
      required this.title,
      required this.count,
      required this.description,
      required this.icon,
      required this.color,
      required this.onTap,
      this.selected = false,
      this.compact = false});
  final String title, count, description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    color.withValues(alpha: .24),
                    color.withValues(alpha: .065)
                  ]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: color.withValues(alpha: selected ? 1 : .7),
                      width: selected ? 2 : 1.3),
                ),
                child: Row(children: [
                  Icon(icon, color: color, size: compact ? 23 : 28),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(title,
                            style: TextStyle(
                                color: AppPalette.text,
                                fontSize: compact ? 12 : 14,
                                fontWeight: FontWeight.w700)),
                        Text(count,
                            style: TextStyle(
                                color: AppPalette.text,
                                fontSize: compact ? 22 : 24,
                                height: 1.15,
                                fontWeight: FontWeight.w800)),
                        if (!compact)
                          Text(description,
                              style: TextStyle(
                                  color: AppPalette.secondary,
                                  fontSize:
                                      MediaQuery.sizeOf(context).width >= 1000
                                          ? 11
                                          : 11)),
                      ])),
                ]),
              ),
            )),
      );
}

class AlertListEntry extends StatelessWidget {
  const AlertListEntry(
      {super.key,
      required this.title,
      required this.description,
      required this.badge,
      required this.overdue,
      required this.label,
      required this.onAction,
      required this.accent,
      this.onRecordExternal});
  final String title, description, badge, label;
  final bool overdue;
  final VoidCallback onAction;
  final VoidCallback? onRecordExternal;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final status = overdue ? AppPalette.danger : AppPalette.warning;
    final detail = Row(children: [
      Container(
          width: 4,
          height: MediaQuery.sizeOf(context).width >= 1000 ? 34 : 34,
          decoration: BoxDecoration(
              color: status, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 14),
      Icon(overdue ? Icons.error_outline : Icons.schedule,
          color: status, size: 23),
      const SizedBox(width: 12),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
            Tooltip(
                message: title,
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppPalette.text,
                        fontSize:
                            MediaQuery.sizeOf(context).width >= 1000 ? 15 : 14,
                        fontWeight: FontWeight.w700))),
            const SizedBox(height: 4),
            Text(description,
                style: TextStyle(
                    color: AppPalette.secondary,
                    fontSize:
                        MediaQuery.sizeOf(context).width >= 1000 ? 12 : 11.5)),
          ])),
    ]);
    final badgeWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: status.withValues(alpha: .1),
            border: Border.all(color: status.withValues(alpha: .7)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(overdue ? Icons.event_busy_outlined : Icons.schedule,
              color: status, size: 16),
          const SizedBox(width: 6),
          Flexible(
              child: Text(badge,
                  style: TextStyle(
                      color: status,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
        ]));
    final primaryAction = OutlinedButton.icon(
        onPressed: onAction,
        style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withValues(alpha: .8)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7)),
        icon: Icon(
            label == 'Comentar' ? Icons.chat_bubble_outline : Icons.open_in_new,
            size: 17),
        label: Text(label,
            style: TextStyle(
                fontSize: MediaQuery.sizeOf(context).width >= 1000 ? 13 : 12,
                fontWeight: FontWeight.w700)));
    final action = onRecordExternal == null ? primaryAction : Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: primaryAction),
      IconButton(onPressed: onRecordExternal, tooltip: 'Já comentei no E-Desk', icon: Icon(Icons.event_available_outlined, color: accent, size: 20)),
    ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            status.withValues(alpha: overdue ? .18 : .045),
            AppPalette.field.withValues(alpha: .65)
          ]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: .22))),
      child: LayoutBuilder(builder: (context, size) {
        if (size.maxWidth >= 850)
          return Row(children: [
            Expanded(child: detail),
            const SizedBox(width: 14),
            SizedBox(
                width: 185,
                child:
                    Align(alignment: Alignment.centerLeft, child: badgeWidget)),
            const SizedBox(width: 12),
            SizedBox(width: 150, child: action),
          ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          detail,
          const SizedBox(height: 8),
          Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [badgeWidget, action]),
        ]);
      }),
    );
  }
}

class AlertCategory extends StatelessWidget {
  const AlertCategory(
      {super.key,
      required this.title,
      required this.count,
      required this.icon,
      required this.color,
      required this.expanded,
      required this.onToggle,
      required this.children});
  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: .65)),
            borderRadius: BorderRadius.circular(15)),
        clipBehavior: Clip.antiAlias,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Material(
              color: color.withValues(alpha: .08),
              child: InkWell(
                onTap: onToggle,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(children: [
                      Icon(icon, color: color, size: 21),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('$title ($count)',
                              style: TextStyle(
                                  color: AppPalette.text,
                                  fontSize:
                                      MediaQuery.sizeOf(context).width >= 1000
                                          ? 16
                                          : 15,
                                  fontWeight: FontWeight.w700))),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more,
                          color: color),
                    ])),
              )),
          if (expanded)
            Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: Column(children: children)),
        ]),
      );
}

class AlertHeaderWaves extends CustomPainter {
  const AlertHeaderWaves(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 18; i++) {
      final offset = i * 3.0;
      final path = Path()
        ..moveTo(size.width * .45, size.height + offset)
        ..cubicTo(size.width * .65, -size.height + offset, size.width * .76,
            size.height * 1.7 + offset, size.width, -size.height * .7 + offset);
      canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: .04 + i * .005)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8);
    }
  }

  @override
  bool shouldRepaint(AlertHeaderWaves oldDelegate) =>
      oldDelegate.color != color;
}
