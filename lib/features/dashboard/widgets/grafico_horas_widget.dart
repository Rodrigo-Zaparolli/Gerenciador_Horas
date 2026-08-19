import 'package:flutter/material.dart';

class DailyHoursPoint {
  final String label;
  final double hours;
  final bool isWeekend;
  final bool isHighlighted;

  const DailyHoursPoint({
    required this.label,
    required this.hours,
    this.isWeekend = false,
    this.isHighlighted = false,
  });
}

class GraficoHorasWidget extends StatelessWidget {
  final List<DailyHoursPoint> points;
  final String Function(double) formatHours;

  const GraficoHorasWidget({
    super.key,
    required this.points,
    required this.formatHours,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 7),
        decoration: BoxDecoration(
          color: const Color(0xFF13131A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bar_chart_rounded,
                  color: Color(0xFF0099FF),
                  size: 17,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Evolução de Horas (Diárias)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0099FF).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: const Color(0xFF0099FF).withOpacity(0.3),
                    ),
                  ),
                  child: const Text(
                    'Interativo',
                    style: TextStyle(
                      color: Color(0xFF0099FF),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (points.isEmpty) {
                    return const Center(
                      child: Text(
                        'Nenhum registro de horas',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: points
                        .map((point) => Expanded(
                              child: _InteractiveBarItem(
                                point: point,
                                formatHours: formatHours,
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveBarItem extends StatefulWidget {
  final DailyHoursPoint point;
  final String Function(double) formatHours;

  const _InteractiveBarItem({
    required this.point,
    required this.formatHours,
  });

  @override
  State<_InteractiveBarItem> createState() => _InteractiveBarItemState();
}

class _InteractiveBarItemState extends State<_InteractiveBarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    final isZero = point.hours <= 0;
    final heightPct = (point.hours / 10.0).clamp(0.0, 1.0);

    final baseColor =
        point.isHighlighted ? const Color(0xFFFFC400) : const Color(0xFF0099FF);
    final hoverColor =
        point.isHighlighted ? const Color(0xFFFFD54F) : const Color(0xFF33BBFF);
    final currentBarColor = _isHovered ? hoverColor : baseColor;
    final double barWidth = _isHovered ? 14.0 : 10.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: '${point.label}: ${widget.formatHours(point.hours)} hrs',
        waitDuration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Column(
            children: [
              Text(
                widget.formatHours(point.hours),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: _isHovered
                      ? Colors.white
                      : (point.isHighlighted
                          ? const Color(0xFFFFC400)
                          : Colors.white60),
                  fontSize: 8.5,
                  fontWeight: _isHovered ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackHeight = constraints.maxHeight;
                    final barHeight = isZero
                        ? 5.0
                        : (trackHeight * heightPct).clamp(5.0, trackHeight);

                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            width: 10,
                            height: trackHeight,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            width: barWidth,
                            height: barHeight,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: isZero
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: point.isHighlighted
                                          ? [
                                              const Color(0xFFFFD740),
                                              const Color(0xFFE3A900),
                                            ]
                                          : [
                                              _isHovered
                                                  ? const Color(0xFF66CCFF)
                                                  : const Color(0xFF26A9F5),
                                              const Color(0xFF0077CC),
                                            ],
                                    ),
                              color: isZero
                                  ? Colors.white.withOpacity(0.10)
                                  : null,
                              boxShadow: _isHovered || point.isHighlighted
                                  ? [
                                      BoxShadow(
                                        color: currentBarColor.withOpacity(
                                            _isHovered ? 0.6 : 0.42),
                                        blurRadius: _isHovered ? 12 : 8,
                                        spreadRadius: _isHovered ? 2 : 1,
                                      ),
                                    ]
                                  : [],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 3),
              Text(
                point.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isHovered
                      ? Colors.white
                      : (point.isHighlighted
                          ? Colors.white
                          : point.isWeekend
                              ? Colors.white38
                              : Colors.white54),
                  fontSize: 8,
                  fontWeight: _isHovered || point.isHighlighted
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
