import '../../core/theme/app_visuals.dart';
import '../../core/theme/app_palette.dart';
import 'dart:math' as math;
import 'annual_performance_chart.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/work_duration.dart';

String monthlyDayLabel(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  if (date.weekday == DateTime.saturday) return '$day\nSáb';
  if (date.weekday == DateTime.sunday) return '$day\nDom';
  return day;
}

class MonthlyPerformanceData {
  MonthlyPerformanceData(DateTime month, Iterable<TimeLog> logs) {
    charged = List.filled(DateTime(month.year, month.month + 1, 0).day, 0);
    other = List.filled(charged.length, 0);
    for (final log in logs) {
      if (log.date.year != month.year || log.date.month != month.month) {
        continue;
      }
      final kind = (log.typeHs ?? '')
          .toLowerCase()
          .replaceAll('ã', 'a')
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ç', 'c')
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final bucket =
          kind.contains('cobradas') && !kind.contains('nao') ? charged : other;
      bucket[log.date.day - 1] += WorkDuration.minutes(log);
    }
  }
  late final List<int> charged, other;
  int get billed => charged.fold(0, (sum, value) => sum + value);
  int get worked => billed + other.fold(0, (sum, value) => sum + value);
  int get activeDays =>
      List.generate(charged.length, (i) => charged[i] + other[i])
          .where((v) => v > 0)
          .length;
  int get dailyAverage => activeDays == 0 ? 0 : (worked / activeDays).round();
}

class MonthlyPerformance extends StatefulWidget {
  const MonthlyPerformance(
      {super.key,
      required this.year,
      required this.logs,
      required this.goals,
      required this.chargedColor,
      required this.otherColor,
      this.settings});
  final int year;
  final List<TimeLog> logs;
  final List<int> goals;
  final Color chargedColor, otherColor;
  final Widget? settings;
  @override
  State<MonthlyPerformance> createState() => _MonthlyPerformanceState();
}

class _MonthlyPerformanceState extends State<MonthlyPerformance> {
  int month = DateTime.now().month;
  static const names = [
    'Janeiro',
    'Fevereiro',
    'Março',
    'Abril',
    'Maio',
    'Junho',
    'Julho',
    'Agosto',
    'Setembro',
    'Outubro',
    'Novembro',
    'Dezembro'
  ];
  String time(int minutes) => WorkDuration.format(minutes);
  Widget surface(Widget child, {double padding = 12}) => Container(
      padding: EdgeInsets.all(padding),
      decoration: AppVisuals.panel(prominent: true),
      child: child);

  @override
  Widget build(BuildContext context) {
    final date = DateTime(widget.year, month);
    final data = MonthlyPerformanceData(date, widget.logs);
    final previous =
        MonthlyPerformanceData(DateTime(widget.year, month - 1), widget.logs);
    final goal = widget.goals[month - 1];
    final remaining = math.max(0, goal - data.billed);
    final ratio = goal > 0 ? data.billed / goal : 0.0;
    final variation = previous.billed == 0
        ? 'Sem base de comparação'
        : '${data.billed >= previous.billed ? '+' : ''}${((data.billed - previous.billed) / previous.billed * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
    final scheme = Theme.of(context).colorScheme;
    final stats = [
      ('Meta mensal', goal, Icons.flag_outlined),
      ('Horas trabalhadas', data.worked, Icons.schedule),
      ('Horas cobradas', data.billed, Icons.receipt_long_outlined),
      ('Falta para a meta', remaining, Icons.hourglass_empty)
    ];
    final goalCard =
        surface(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Meta do mês',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Row(children: [
        Text(goal > 0 ? '${(ratio * 100).round()}%' : 'Sem meta',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppPalette.readableText(widget.chargedColor))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 8,
              color: widget.chargedColor,
              borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 6),
          Text('${time(data.billed)} de ${time(goal)}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ])),
      ]),
    ]));
    final annualTotals = List.generate(
        12,
        (i) => MonthlyPerformanceData(DateTime(widget.year, i + 1), widget.logs)
            .billed);
    Widget sidebar(double height) => SizedBox(
        height: height,
        child: Column(children: [
          goalCard,
          const SizedBox(height: 12),
          Expanded(
              child: surface(AnnualPerformanceChart(
            year: widget.year,
            totals: annualTotals,
            goals: widget.goals,
            selectedMonth: month,
            color: widget.chargedColor,
            onMonthSelected: (value) => setState(() => month = value),
          ))),
        ]));
    Widget monthControls() => Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: 'Mês anterior',
              onPressed: month > 1 ? () => setState(() => month--) : null,
              icon: const Icon(Icons.chevron_left)),
          SizedBox(
              width: 158,
              child: DropdownButton<int>(
                  value: month,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('${names[i]} ${widget.year}'))),
                  onChanged: (value) {
                    if (value != null) setState(() => month = value);
                  })),
          IconButton(
              tooltip: 'Próximo mês',
              onPressed: month < 12 ? () => setState(() => month++) : null,
              icon: const Icon(Icons.chevron_right)),
        ]);
    Widget totals(double width) {
      final count = width >= 700
          ? 4
          : width >= 400
              ? 2
              : 1;
      return Wrap(spacing: 10, runSpacing: 8, children: [
        for (final stat in stats)
          SizedBox(
              width: (width - (count - 1) * 10) / count,
              child: surface(
                  Row(children: [
                    Icon(stat.$3, color: scheme.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(stat.$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant)),
                          Text(time(stat.$2),
                              style: const TextStyle(
                                  fontSize: 23, fontWeight: FontWeight.w800)),
                        ])),
                  ]),
                  padding: 8)),
      ]);
    }

    Widget monthly(double plotHeight) => surface(LayoutBuilder(
        builder: (context, box) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    const Text('Desempenho mensal',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    monthControls(),
                    if (widget.settings != null) widget.settings!,
                  ]),
              const SizedBox(height: 6),
              totals(box.maxWidth),
              const SizedBox(height: 8),
              const Text('Horas registradas por dia',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Wrap(spacing: 18, children: [
                legend('Cobradas', widget.chargedColor),
                legend('Demais horas', widget.otherColor)
              ]),
              const SizedBox(height: 8),
              if (data.worked == 0)
                SizedBox(
                    height: plotHeight,
                    child: const Center(
                        child: Text('Nenhuma hora registrada neste mês.')))
              else
                LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                            width: math.max(
                                c.maxWidth, data.charged.length * 23.0 + 50),
                            height: plotHeight,
                            child: chart(data)))),
            ])));
    return LayoutBuilder(
        builder: (context, c) =>
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (c.maxWidth >= 1050)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: monthly(92)),
                  const SizedBox(width: 12),
                  SizedBox(width: c.maxWidth * .32, child: sidebar(272)),
                ])
              else ...[monthly(190), const SizedBox(height: 12), sidebar(280)],
              const SizedBox(height: 8),
              surface(
                  Wrap(spacing: 30, runSpacing: 8, children: [
                    const Text('Comparativo mensal',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('Mês anterior: ${time(previous.billed)} cobradas'),
                    Text('Variação: $variation'),
                    Text(
                        'Média por dia trabalhado: ${time(data.dailyAverage)}'),
                  ]),
                  padding: 8),
            ]));
  }

  Widget legend(String label, Color color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]);
  Widget chart(MonthlyPerformanceData data) {
    final highest = List.generate(
            data.charged.length, (i) => (data.charged[i] + data.other[i]) / 60)
        .reduce(math.max);
    final maxY = math.max(2.0, (highest / 2).ceil() * 2.0);
    final style = TextStyle(
        fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return BarChart(BarChartData(
      maxY: maxY,
      alignment: BarChartAlignment.spaceAround,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
              color: Theme.of(context).colorScheme.outlineVariant,
              strokeWidth: 1)),
      titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  interval: maxY / 4,
                  getTitlesWidget: (value, meta) =>
                      Text(time((value * 60).round()), style: style))),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          monthlyDayLabel(
                              DateTime(widget.year, month, value.toInt() + 1)),
                          textAlign: TextAlign.center,
                          style: style))))),
      barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipColor: (_) =>
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  '${group.x + 1}/${month.toString().padLeft(2, '0')}/${widget.year}\nCobradas ${time(data.charged[group.x])}\nDemais ${time(data.other[group.x])}\nTotal ${time(data.charged[group.x] + data.other[group.x])}',
                  TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600)))),
      barGroups: List.generate(
          data.charged.length,
          (i) => BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: (data.charged[i] + data.other[i]) / 60,
                  width: 12,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                  rodStackItems: [
                    BarChartRodStackItem(
                        0, data.charged[i] / 60, widget.chargedColor),
                    BarChartRodStackItem(
                        data.charged[i] / 60,
                        (data.charged[i] + data.other[i]) / 60,
                        widget.otherColor)
                  ],
                )
              ])),
    ));
  }
}
