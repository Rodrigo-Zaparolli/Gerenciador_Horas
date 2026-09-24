import 'package:flutter/material.dart';

class DailyHoursPoint {
  final String label;
  final double hours;

  /// Data real representada pela barra.
  ///
  /// É opcional para não quebrar pontos antigos.
  final DateTime? date;

  final bool isWeekend;
  final bool isHighlighted;

  const DailyHoursPoint({
    required this.label,
    required this.hours,
    this.date,
    this.isWeekend = false,
    this.isHighlighted = false,
  });
}

class GraficoHorasWidget extends StatelessWidget {
  final List<DailyHoursPoint> points;
  final String Function(double) formatHours;

  /// Chamado quando o usuário clica em um dia do gráfico.
  ///
  /// Recebe a data correspondente à barra clicada.
  final ValueChanged<DateTime>? onDayTap;

  const GraficoHorasWidget({
    super.key,
    required this.points,
    required this.formatHours,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    // ==============================================================
    // TOTAL DE HORAS EXIBIDAS NO GRÁFICO
    // ==============================================================

    final double totalHours = points.fold(
      0,
      (sum, point) => sum + point.hours,
    );

    // ==============================================================
    // TOTAL DA SEMANA ATUAL
    //
    // Considera:
    // segunda-feira 00:00
    // até
    // domingo 23:59:59
    // ==============================================================

    final DateTime now = DateTime.now();

    final DateTime today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    // DateTime.weekday:
    // segunda = 1
    // terça   = 2
    // ...
    // domingo = 7

    final DateTime startOfWeek = today.subtract(
      Duration(days: today.weekday - 1),
    );

    final DateTime startOfNextWeek = startOfWeek.add(
      const Duration(days: 7),
    );

    final double weeklyHours = points.fold(
      0,
      (sum, point) {
        final DateTime? date = point.date;

        if (date == null) {
          return sum;
        }

        final DateTime pointDay = DateTime(
          date.year,
          date.month,
          date.day,
        );

        final bool belongsToCurrentWeek = !pointDay.isBefore(startOfWeek) &&
            pointDay.isBefore(startOfNextWeek);

        if (!belongsToCurrentWeek) {
          return sum;
        }

        return sum + point.hours;
      },
    );

    // ==============================================================
    // MAIOR PONTO
    // ==============================================================

    final DailyHoursPoint? highestPoint = points.isEmpty
        ? null
        : points.reduce(
            (a, b) => a.hours >= b.hours ? a : b,
          );

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          14,
          12,
          14,
          9,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF15171E),
              Color(0xFF101116),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withOpacity(0.065),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.42),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: const Color(0xFF0099FF).withOpacity(0.035),
              blurRadius: 30,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            // ======================================================
            // CABEÇALHO
            // ======================================================

            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Ícone
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF0099FF).withOpacity(0.18),
                        const Color(0xFF0099FF).withOpacity(0.055),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF0099FF).withOpacity(0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: Color(0xFF35B4FF),
                    size: 18,
                  ),
                ),

                const SizedBox(width: 10),

                // ==================================================
                // TÍTULO
                // ==================================================

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Evolução de Horas',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.05,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Acompanhamento diário',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.38),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ==================================================
                // RESUMOS DE HORAS
                // ==================================================

                if (points.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ------------------------------------------------
                      // TOTAL
                      // ------------------------------------------------

                      _HoursSummary(
                        value: formatHours(totalHours),
                        label: 'TOTAL',
                        color: const Color(0xFF55C4FF),
                      ),

                      const SizedBox(width: 5),

                      // ------------------------------------------------
                      // SEMANA
                      // ------------------------------------------------

                      _HoursSummary(
                        value: formatHours(weeklyHours),
                        label: 'SEMANA',
                        color: const Color(0xFF36D6A0),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 9),

            // ======================================================
            // LINHA INFORMATIVA
            // ======================================================

            Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF21A9FF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Clique em um dia para ver os apontamentos',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.34),
                    fontSize: 7.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (highestPoint != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.trending_up_rounded,
                        color: const Color(0xFF55C4FF).withOpacity(0.75),
                        size: 11,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Pico ${formatHours(highestPoint.hours)}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.38),
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 6),

            // ======================================================
            // SEPARADOR
            // ======================================================

            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.00),
                    Colors.white.withOpacity(0.055),
                    Colors.white.withOpacity(0.00),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 5),

            // ======================================================
            // GRÁFICO
            // ======================================================

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
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }

                  return Stack(
                    children: [
                      // ==================================================
                      // LINHAS HORIZONTAIS
                      // ==================================================

                      Positioned.fill(
                        child: IgnorePointer(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildGridLine(
                                opacity: 0.035,
                              ),
                              _buildGridLine(
                                opacity: 0.025,
                              ),
                              _buildGridLine(
                                opacity: 0.025,
                              ),
                              _buildGridLine(
                                opacity: 0.035,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ==================================================
                      // INDICADOR BASE
                      // ==================================================

                      Positioned(
                        left: 2,
                        right: 2,
                        bottom: 17,
                        child: Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.055),
                        ),
                      ),

                      // ==================================================
                      // BARRAS
                      // ==================================================

                      Positioned.fill(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: points
                              .map(
                                (point) => Expanded(
                                  child: _InteractiveBarItem(
                                    point: point,
                                    formatHours: formatHours,
                                    onTap: onDayTap,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridLine({
    double opacity = 0.025,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
      ),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.00),
              Colors.white.withOpacity(opacity),
              Colors.white.withOpacity(0.00),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// RESUMO DE HORAS
// ==================================================================

class _HoursSummary extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _HoursSummary({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 54,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.065),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.14),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 6.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// ITEM INDIVIDUAL DA BARRA
// ==================================================================

class _InteractiveBarItem extends StatefulWidget {
  final DailyHoursPoint point;
  final String Function(double) formatHours;
  final ValueChanged<DateTime>? onTap;

  const _InteractiveBarItem({
    required this.point,
    required this.formatHours,
    this.onTap,
  });

  @override
  State<_InteractiveBarItem> createState() => _InteractiveBarItemState();
}

class _InteractiveBarItemState extends State<_InteractiveBarItem> {
  bool _isHovered = false;
  bool _isPressed = false;

  void _handleTap() {
    final date = widget.point.date;

    if (date == null) {
      return;
    }

    widget.onTap?.call(date);
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;

    final bool isZero = point.hours <= 0;

    // Mantém o mesmo limite visual de 10 horas.
    final double heightPct = (point.hours / 10.0).clamp(
      0.0,
      1.0,
    );

    final Color baseColor =
        point.isHighlighted ? const Color(0xFFFFC400) : const Color(0xFF0099FF);

    final Color hoverColor =
        point.isHighlighted ? const Color(0xFFFFD95A) : const Color(0xFF38BBFF);

    final Color currentBarColor = _isHovered ? hoverColor : baseColor;

    final double barWidth = _isHovered || _isPressed ? 15.0 : 10.0;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _isHovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _isHovered = false;
          _isPressed = false;
        });
      },
      cursor: point.date != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        onTapDown: point.date == null
            ? null
            : (_) {
                setState(() {
                  _isPressed = true;
                });
              },
        onTapUp: point.date == null
            ? null
            : (_) {
                setState(() {
                  _isPressed = false;
                });
              },
        onTapCancel: point.date == null
            ? null
            : () {
                setState(() {
                  _isPressed = false;
                });
              },
        child: Tooltip(
          message: point.date != null
              ? '${point.label}: '
                  '${widget.formatHours(point.hours)} hrs\n'
                  'Clique para ver os apontamentos'
              : '${point.label}: '
                  '${widget.formatHours(point.hours)} hrs',
          waitDuration: const Duration(
            milliseconds: 180,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF20232B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.40),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 1.5,
            ),
            child: Column(
              children: [
                // ==================================================
                // VALOR DAS HORAS
                // ==================================================

                AnimatedDefaultTextStyle(
                  duration: const Duration(
                    milliseconds: 160,
                  ),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    color: _isHovered
                        ? Colors.white
                        : (point.isHighlighted
                            ? const Color(0xFFFFC400)
                            : Colors.white.withOpacity(0.62)),
                    fontSize: _isHovered ? 9.5 : 8.5,
                    fontWeight: _isHovered ? FontWeight.w800 : FontWeight.w600,
                    height: 1,
                  ),
                  child: Text(
                    widget.formatHours(point.hours),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ),

                const SizedBox(height: 5),

                // ==================================================
                // ÁREA DA BARRA
                // ==================================================

                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double trackHeight = constraints.maxHeight;

                      final double barHeight = isZero
                          ? 5.0
                          : (trackHeight * heightPct).clamp(
                              5.0,
                              trackHeight,
                            );

                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            // ==================================================
                            // TRILHA DA BARRA
                            // ==================================================

                            AnimatedContainer(
                              duration: const Duration(
                                milliseconds: 180,
                              ),
                              curve: Curves.easeOut,
                              width: _isHovered ? 13 : 9,
                              height: trackHeight,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(
                                  _isHovered ? 0.05 : 0.022,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(
                                    _isHovered ? 0.055 : 0.018,
                                  ),
                                ),
                              ),
                            ),

                            // ==================================================
                            // BARRA PRINCIPAL
                            // ==================================================

                            AnimatedContainer(
                              duration: const Duration(
                                milliseconds: 220,
                              ),
                              curve: Curves.easeOutCubic,
                              width: barWidth,
                              height: barHeight,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: isZero
                                    ? null
                                    : LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: point.isHighlighted
                                            ? [
                                                const Color(
                                                  0xFFFFE97A,
                                                ),
                                                const Color(
                                                  0xFFFFC400,
                                                ),
                                                const Color(
                                                  0xFFE0A500,
                                                ),
                                              ]
                                            : [
                                                _isHovered
                                                    ? const Color(
                                                        0xFF8DDBFF,
                                                      )
                                                    : const Color(
                                                        0xFF42B8FF,
                                                      ),
                                                const Color(
                                                  0xFF0099FF,
                                                ),
                                                const Color(
                                                  0xFF006CB5,
                                                ),
                                              ],
                                      ),
                                color: isZero
                                    ? Colors.white.withOpacity(
                                        0.10,
                                      )
                                    : null,
                                border: Border.all(
                                  color: isZero
                                      ? Colors.white.withOpacity(
                                          0.055,
                                        )
                                      : Colors.white.withOpacity(
                                          _isHovered ? 0.32 : 0.11,
                                        ),
                                  width: 0.7,
                                ),
                                boxShadow: _isHovered || point.isHighlighted
                                    ? [
                                        BoxShadow(
                                          color: currentBarColor.withOpacity(
                                            _isHovered ? 0.65 : 0.42,
                                          ),
                                          blurRadius: _isHovered ? 15 : 9,
                                          spreadRadius: _isHovered ? 2 : 1,
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(
                                            0.18,
                                          ),
                                          blurRadius: 3,
                                          offset: const Offset(
                                            0,
                                            1,
                                          ),
                                        ),
                                      ],
                              ),
                            ),

                            // ==================================================
                            // BRILHO NO TOPO
                            // ==================================================

                            if (!isZero)
                              AnimatedContainer(
                                duration: const Duration(
                                  milliseconds: 180,
                                ),
                                width: barWidth * 0.62,
                                height: 2,
                                margin: const EdgeInsets.only(
                                  bottom: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(
                                    _isHovered ? 0.78 : 0.36,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),

                            // ==================================================
                            // MARCADOR DO DIA DESTACADO
                            // ==================================================

                            if (point.isHighlighted)
                              Positioned(
                                bottom: barHeight + 5,
                                child: AnimatedContainer(
                                  duration: const Duration(
                                    milliseconds: 180,
                                  ),
                                  width: _isHovered ? 6 : 5,
                                  height: _isHovered ? 6 : 5,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC400),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.70),
                                      width: 0.7,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFFC400,
                                        ).withOpacity(0.60),
                                        blurRadius: 7,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 4),

                // ==================================================
                // LABEL DO DIA
                // ==================================================

                AnimatedDefaultTextStyle(
                  duration: const Duration(
                    milliseconds: 160,
                  ),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    color: _isHovered
                        ? Colors.white
                        : (point.isHighlighted
                            ? Colors.white
                            : point.isWeekend
                                ? Colors.white38
                                : Colors.white54),
                    fontSize: _isHovered ? 8.5 : 8,
                    fontWeight: _isHovered || point.isHighlighted
                        ? FontWeight.w700
                        : FontWeight.normal,
                    height: 1,
                  ),
                  child: Text(
                    point.label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
