import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/edesk_python_io.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/features/edesk/screens/edesk_webview_test_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/features/edesk/screens/edesk_webview_test_screen.dart';

class TarefasScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final TimeLogStore timeLogStore;

  const TarefasScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.timeLogStore,
    required String userName,
  });

  @override
  State<TarefasScreen> createState() => _TarefasScreenState();
}

class _TarefasScreenState extends State<TarefasScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _enviandoEdesk = false;

  String _search = '';
  String _filter = 'Todas';

  DateTime? _startDate;
  DateTime? _endDate;

  final Set<String> _semanasExpandidas = {};

  @override
  void initState() {
    super.initState();
    widget.timeLogStore.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.timeLogStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // FILTRO DE DATA
  // ============================================================

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(
              start: _startDate!,
              end: _endDate!,
            )
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: CoresApp.primaria,
              onPrimary: CoresApp.textoPrincipal,
              surface: CoresApp.superficie,
              onSurface: CoresApp.textoPrincipal,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _filter = 'Período';
      });
    }
  }

  // ============================================================
  // REGISTROS
  // ============================================================

  List<TimeLog> get _registeredLogs {
    final query = _search.trim().toLowerCase();

    return widget.timeLogStore.logs.where((log) {
      if (!log.isRegistered) {
        return false;
      }

      if (_filter == 'Hoje') {
        final now = DateTime.now();

        if (log.date.year != now.year ||
            log.date.month != now.month ||
            log.date.day != now.day) {
          return false;
        }
      } else if (_filter == 'Esta semana') {
        final now = DateTime.now();

        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(
          Duration(days: now.weekday - 1),
        );

        final end = start.add(
          const Duration(days: 7),
        );

        if (log.date.isBefore(start) || !log.date.isBefore(end)) {
          return false;
        }
      } else if (_filter == 'Período' &&
          _startDate != null &&
          _endDate != null) {
        final normalizedLogDate = DateTime(
          log.date.year,
          log.date.month,
          log.date.day,
        );

        final normalizedStart = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
        );

        final normalizedEnd = DateTime(
          _endDate!.year,
          _endDate!.month,
          _endDate!.day,
          23,
          59,
          59,
        );

        if (normalizedLogDate.isBefore(normalizedStart) ||
            normalizedLogDate.isAfter(normalizedEnd)) {
          return false;
        }
      }

      if (query.isEmpty) {
        return true;
      }

      return log.targetId.toLowerCase().contains(query) ||
          (log.projectName ?? '').toLowerCase().contains(query) ||
          (log.taskName ?? '').toLowerCase().contains(query) ||
          (log.description ?? '').toLowerCase().contains(query) ||
          log.dateFormatted.contains(query);
    }).toList()
      ..sort(
        (a, b) => b.date.compareTo(a.date),
      );
  }

  Map<String, List<TimeLog>> get _groupedLogsByDate {
    final logs = _registeredLogs;
    final Map<String, List<TimeLog>> grouped = {};

    for (final log in logs) {
      final key = '${log.date.year}-${log.date.month}-${log.date.day}';

      grouped
          .putIfAbsent(
            key,
            () => [],
          )
          .add(log);
    }

    return grouped;
  }

  Map<String, List<TimeLog>> _groupLogsByWeek(
    List<TimeLog> logs,
  ) {
    final Map<String, List<TimeLog>> grouped = {};

    for (final log in logs) {
      final date = DateTime(
        log.date.year,
        log.date.month,
        log.date.day,
      );

      final weekStart = date.subtract(
        Duration(days: date.weekday - 1),
      );

      final key = '${weekStart.year}-${weekStart.month}-${weekStart.day}';

      grouped
          .putIfAbsent(
            key,
            () => [],
          )
          .add(log);
    }

    for (final list in grouped.values) {
      list.sort(
        (a, b) => b.date.compareTo(a.date),
      );
    }

    return grouped;
  }

  // ============================================================
  // DATAS
  // ============================================================

  DateTime _weekStart(DateTime date) {
    final normalized = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return normalized.subtract(
      Duration(days: normalized.weekday - 1),
    );
  }

  String _weekKey(DateTime date) {
    final start = _weekStart(date);

    return '${start.year}-${start.month}-${start.day}';
  }

  String _formatWeekTitle(DateTime date) {
    final start = _weekStart(date);
    final end = start.add(
      const Duration(days: 6),
    );

    if (start.year == end.year && start.month == end.month) {
      return 'SEMANA '
          '${start.day.toString().padLeft(2, '0')}'
          ' — '
          '${end.day.toString().padLeft(2, '0')} '
          '${_monthShort(start.month)}';
    }

    if (start.year == end.year) {
      return 'SEMANA '
          '${start.day.toString().padLeft(2, '0')} '
          '${_monthShort(start.month)}'
          ' — '
          '${end.day.toString().padLeft(2, '0')} '
          '${_monthShort(end.month)}';
    }

    return 'SEMANA '
        '${_formatShortDate(start)}'
        ' — '
        '${_formatShortDate(end)}';
  }

  String _formatWeekRange(DateTime date) {
    final start = _weekStart(date);
    final end = start.add(
      const Duration(days: 6),
    );

    return '${_formatShortDate(start)} até '
        '${_formatShortDate(end)}';
  }

  String _formatShortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatDateHeader(DateTime date) {
    const diasSemana = [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${diasSemana[date.weekday - 1]}';
  }

  String _dayNameShort(int weekday) {
    const dias = [
      'SEG',
      'TER',
      'QUA',
      'QUI',
      'SEX',
      'SÁB',
      'DOM',
    ];

    return dias[weekday - 1];
  }

  String _formatarMinutos(int minutos) {
    final horas = minutos ~/ 60;
    final mins = minutos % 60;

    return '${horas.toString().padLeft(2, '0')}:'
        '${mins.toString().padLeft(2, '0')}';
  }

  int _duracaoEmMinutos(TimeLog log) {
    if (log.durationMinutes > 0) {
      return log.durationMinutes;
    }

    try {
      final parts = log.durationFormatted.split(':');

      if (parts.length == 2) {
        return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
      }
    } catch (_) {}

    return 0;
  }

  int _totalMinutos(List<TimeLog> logs) {
    int total = 0;

    for (final log in logs) {
      total += _duracaoEmMinutos(log);
    }

    return total;
  }

  Set<String> _projetosUnicos(List<TimeLog> logs) {
    return logs
        .map(
          (log) => (log.projectName ?? log.targetId).trim(),
        )
        .where(
          (name) => name.isNotEmpty,
        )
        .toSet();
  }

  String _monthShort(int month) {
    const months = [
      'JAN',
      'FEV',
      'MAR',
      'ABR',
      'MAI',
      'JUN',
      'JUL',
      'AGO',
      'SET',
      'OUT',
      'NOV',
      'DEZ',
    ];

    return months[month - 1];
  }

  // ============================================================
  // CABEÇALHO UNIFICADO
  // ============================================================

  Widget _buildUnifiedHeader({
    required int totalRegistros,
    required int totalProjetos,
    required String totalHoras,
    required int totalDias,
  }) {
    final stats = [
      _buildSummaryCard(
        icon: Icons.checklist_rounded,
        label: 'Tarefas',
        value: '$totalRegistros',
        description: 'registros',
        color: CoresApp.destaque,
      ),
      _buildSummaryCard(
        icon: Icons.folder_rounded,
        label: 'Projetos',
        value: '$totalProjetos',
        description: 'envolvidos',
        color: CoresApp.primaria,
      ),
      _buildSummaryCard(
        icon: Icons.schedule_rounded,
        label: 'Horas',
        value: totalHoras,
        description: 'registradas',
        color: CoresApp.secundaria,
      ),
      _buildSummaryCard(
        icon: Icons.calendar_month_rounded,
        label: 'Dias',
        value: '$totalDias',
        description: 'trabalhados',
        color: CoresApp.destaque,
      ),
    ];

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CoresApp.superficie.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CoresApp.borda.withOpacity(0.75),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  CoresApp.primaria,
                  CoresApp.destaque,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                final bool wide = width >= 1250;
                final bool medium = width >= 800 && width < 1250;

                // ==================================================
                // DESKTOP LARGO
                // ==================================================

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildUnifiedTitle(),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 7,
                        child: Row(
                          children: [
                            for (int i = 0; i < stats.length; i++) ...[
                              Expanded(
                                child: stats[i],
                              ),
                              if (i < stats.length - 1)
                                const SizedBox(width: 8),
                            ],
                            const SizedBox(width: 10),
                            _buildPdfActionButton(
                              compact: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                // ==================================================
                // TAMANHO MÉDIO
                // ==================================================

                if (medium) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildUnifiedTitle(),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          for (int i = 0; i < stats.length; i++) ...[
                            Expanded(
                              child: stats[i],
                            ),
                            if (i < stats.length - 1) const SizedBox(width: 8),
                          ],
                          const SizedBox(width: 8),
                          _buildPdfActionButton(
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  );
                }

                // ==================================================
                // TELA COMPACTA
                // ==================================================

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUnifiedTitle(),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final stat in stats)
                          SizedBox(
                            width: _getResponsiveStatWidth(width),
                            child: stat,
                          ),
                        _buildPdfActionButton(
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TÍTULO
  // ============================================================

  Widget _buildUnifiedTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 56,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CoresApp.primaria,
                CoresApp.destaque,
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.primaria.withOpacity(0.11),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: CoresApp.primaria.withOpacity(0.22),
            ),
          ),
          child: const Icon(
            Icons.task_alt_rounded,
            color: CoresApp.destaque,
            size: 24,
          ),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tarefas Executadas',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Histórico dos apontamentos organizados por semana',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CARD DE MÉTRICA
  // ============================================================

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required String description,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 120,
        minHeight: 70,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withOpacity(0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BOTÃO PDF
  // ============================================================

  Widget _buildPdfActionButton({
    required bool compact,
  }) {
    final enabled = widget.timeLogStore.logs.isNotEmpty;

    return Tooltip(
      message: 'Gerar relatório PDF',
      child: InkWell(
        onTap: enabled ? _abrirModalFiltroPdf : null,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: compact ? 68 : 70,
          constraints: const BoxConstraints(
            minWidth: 70,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: enabled
                ? CoresApp.primaria.withOpacity(0.10)
                : CoresApp.fundo.withOpacity(0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled
                  ? CoresApp.primaria.withOpacity(0.30)
                  : CoresApp.borda.withOpacity(0.45),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: enabled
                      ? CoresApp.primaria.withOpacity(0.12)
                      : CoresApp.borda.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.picture_as_pdf_rounded,
                  color: enabled
                      ? CoresApp.destaque
                      : CoresApp.textoSecundario.withOpacity(0.5),
                  size: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PDF',
                style: TextStyle(
                  color: enabled
                      ? CoresApp.textoPrincipal
                      : CoresApp.textoSecundario.withOpacity(0.5),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _getResponsiveStatWidth(double width) {
    if (width >= 700) {
      return 170;
    }

    if (width >= 500) {
      return 160;
    }

    if (width >= 360) {
      return 145;
    }

    return width;
  }

  // ============================================================
  // BARRA DE FILTROS
  // ============================================================

  Widget _buildFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: CoresApp.superficie.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CoresApp.borda.withOpacity(0.7),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool compact = constraints.maxWidth < 760;

          if (compact) {
            return Column(
              children: [
                SizedBox(
                  height: 40,
                  child: TextField(
                    style: const TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar tarefa, projeto ou ID...',
                      hintStyle: const TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: CoresApp.textoSecundario,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: CoresApp.fundo,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: CoresApp.borda.withOpacity(0.6),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(8),
                        ),
                        borderSide: BorderSide(
                          color: CoresApp.primaria,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      setState(() => _search = value);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterDropdown(),
                      const SizedBox(width: 8),
                      _buildFilterButton(
                        icon: Icons.date_range_rounded,
                        label: 'Período',
                        active: _filter == 'Período',
                        onPressed: () => _pickDateRange(context),
                      ),
                      if (_filter == 'Período' &&
                          _startDate != null &&
                          _endDate != null) ...[
                        const SizedBox(width: 8),
                        _buildPeriodBadge(),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    style: const TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar tarefa, projeto ou ID...',
                      hintStyle: const TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: CoresApp.textoSecundario,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: CoresApp.fundo,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: CoresApp.borda.withOpacity(0.6),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(8),
                        ),
                        borderSide: BorderSide(
                          color: CoresApp.primaria,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) {
                      setState(() => _search = value);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterDropdown(),
              const SizedBox(width: 8),
              _buildFilterButton(
                icon: Icons.date_range_rounded,
                label: 'Período',
                active: _filter == 'Período',
                onPressed: () => _pickDateRange(context),
              ),
              if (_filter == 'Período' &&
                  _startDate != null &&
                  _endDate != null) ...[
                const SizedBox(width: 8),
                _buildPeriodBadge(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.fundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CoresApp.borda.withOpacity(0.6),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filter == 'Período' ? 'Todas' : _filter,
          dropdownColor: CoresApp.superficie,
          borderRadius: BorderRadius.circular(9),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: CoresApp.textoSecundario,
            size: 18,
          ),
          style: const TextStyle(
            color: CoresApp.textoPrincipal,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            DropdownMenuItem(
              value: 'Todas',
              child: Text('Todas'),
            ),
            DropdownMenuItem(
              value: 'Hoje',
              child: Text('Hoje'),
            ),
            DropdownMenuItem(
              value: 'Esta semana',
              child: Text('Esta semana'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _filter = value ?? 'Todas';

              if (_filter != 'Período') {
                _startDate = null;
                _endDate = null;
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildFilterButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    final color = active ? CoresApp.primaria : CoresApp.textoSecundario;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
        ),
        decoration: BoxDecoration(
          color: active ? CoresApp.primaria.withOpacity(0.12) : CoresApp.fundo,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? CoresApp.primaria.withOpacity(0.4) : CoresApp.borda,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color:
                    active ? CoresApp.textoPrincipal : CoresApp.textoSecundario,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodBadge() {
    if (_filter != 'Período' || _startDate == null || _endDate == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.primaria.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CoresApp.primaria.withOpacity(0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.date_range_rounded,
            color: CoresApp.destaque,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            '${_formatShortDate(_startDate!)} — '
            '${_formatShortDate(_endDate!)}',
            style: const TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () {
              setState(() {
                _filter = 'Todas';
                _startDate = null;
                _endDate = null;
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                color: CoresApp.textoSecundario,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MODAL DETALHES DO DIA
  // ============================================================

  void _abrirModalDetalhesDia(
    String tituloData,
    String duracaoTotal,
    List<TimeLog> logsDoDia,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda.withOpacity(0.6),
            ),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: CoresApp.destaque,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tituloData,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${logsDoDia.length} tarefa(s) registrada(s)',
                      style: const TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  duracaoTotal,
                  style: const TextStyle(
                    color: CoresApp.destaque,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 420,
            child: ListView.builder(
              itemCount: logsDoDia.length,
              itemBuilder: (context, index) {
                final log = logsDoDia[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CoresApp.fundo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: CoresApp.borda.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CoresApp.primaria.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: CoresApp.destaque,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${log.taskName ?? log.targetId} '
                              '(${log.projectName ?? 'Proj'})',
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            if (log.description != null &&
                                log.description!.trim().isNotEmpty) ...[
                              Text(
                                log.description!,
                                style: const TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 11.5,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                            ],
                            Text(
                              '${log.startTime} até ${log.endTime}   •   '
                              '${log.durationFormatted}',
                              style: const TextStyle(
                                color: CoresApp.destaque,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: CoresApp.destaque,
                          size: 18,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _abrirModalEdicao(log);
                        },
                      ),
                      IconButton(
                        tooltip: 'Excluir',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: CoresApp.erro,
                          size: 18,
                        ),
                        onPressed: () async {
                          if (log.id != null && log.id!.isNotEmpty) {
                            await widget.timeLogStore.deleteFirebaseLog(log);

                            if (mounted) {
                              Navigator.pop(context);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.fundo,
                foregroundColor: CoresApp.textoPrincipal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: const BorderSide(
                    color: CoresApp.borda,
                  ),
                ),
                elevation: 0,
              ),
              onPressed: logsDoDia.isEmpty
                  ? null
                  : () {
                      Navigator.pop(context);

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _abrirModalEdesk(logsDoDia);
                        }
                      });
                    },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.send_rounded,
                    size: 15,
                  ),
                  SizedBox(width: 6),
                  Text('E-Desk'),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: CoresApp.textoPrincipal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

// ============================================================
// MODAL E-DESK
// ============================================================

  String _referenciaEdesk(TimeLog log) {
    final targetId = log.targetId.trim();

    if (targetId.isEmpty) {
      return 'Não identificada';
    }

    if (targetId.contains('_')) {
      final partes = targetId.split('_');

      if (partes.length >= 2) {
        final solicitacao = partes.first.trim();
        final idTrabalho = partes.sublist(1).join('_').trim();

        if (solicitacao.isNotEmpty && idTrabalho.isNotEmpty) {
          return '$solicitacao/$idTrabalho';
        }
      }
    }

    return targetId;
  }

// ============================================================
// EXTRAI SOLICITAÇÃO / ID DO TRABALHO
// ============================================================

  Map<String, String> _extrairReferenciaEdesk(TimeLog log) {
    final targetId = log.targetId.trim();

    if (targetId.isEmpty) {
      throw const EdeskException(
        'Não foi possível identificar o projeto/trabalho.',
      );
    }

    final partes = targetId.split('_');

    if (partes.length < 2) {
      throw EdeskException(
        'Referência E-Desk inválida: $targetId',
      );
    }

    final solicitacao = partes.first.trim();
    final idTrabalho = partes.sublist(1).join('_').trim();

    if (solicitacao.isEmpty || idTrabalho.isEmpty) {
      throw const EdeskException(
        'Não foi possível identificar a solicitação e o trabalho.',
      );
    }

    return {
      'solicitacao': solicitacao,
      'idTrabalho': idTrabalho,
    };
  }

// ============================================================
// MODAL PRINCIPAL DE CONFERÊNCIA E-DESK
// ============================================================

  void _abrirModalEdesk(List<TimeLog> logsDoDia) {
    final drafts = logsDoDia.map((log) {
      return _EdeskDraft(
        log: log,
        taskName: log.taskName ?? '',
        description: log.description ?? '',
        startTime: log.startTime,
        endTime: log.endTime,
      );
    }).toList();

    final taskControllers = <String, TextEditingController>{
      for (final draft in drafts)
        draft.log.id: TextEditingController(
          text: draft.taskName,
        ),
    };

    final descriptionControllers = <String, TextEditingController>{
      for (final draft in drafts)
        draft.log.id: TextEditingController(
          text: draft.description,
        ),
    };

    final dialogFuture = showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            int totalMinutes = 0;

            for (final draft in drafts) {
              totalMinutes += _calcularMinutos(
                draft.startTime,
                draft.endTime,
              );
            }

            final totalFormatted =
                '${(totalMinutes ~/ 60).toString().padLeft(2, '0')}:'
                '${(totalMinutes % 60).toString().padLeft(2, '0')}';

            // ==========================================================
            // SELECIONAR HORÁRIO
            // ==========================================================

            Future<void> pickTime(
              _EdeskDraft draft,
              bool isStart,
            ) async {
              final current = isStart ? draft.startTime : draft.endTime;

              final parts = current.split(':');

              final parsedHour =
                  parts.length == 2 ? int.tryParse(parts[0]) : null;

              final parsedMinute =
                  parts.length == 2 ? int.tryParse(parts[1]) : null;

              final hour =
                  parsedHour == null ? 8 : parsedHour.clamp(0, 23).toInt();

              final minute =
                  parsedMinute == null ? 0 : parsedMinute.clamp(0, 59).toInt();

              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: hour,
                  minute: minute,
                ),
                initialEntryMode: TimePickerEntryMode.input,
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: CoresApp.primaria,
                        onPrimary: CoresApp.textoPrincipal,
                        surface: CoresApp.superficie,
                        onSurface: CoresApp.textoPrincipal,
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                final normalized = '${picked.hour.toString().padLeft(2, '0')}:'
                    '${picked.minute.toString().padLeft(2, '0')}';

                setModalState(() {
                  if (isStart) {
                    draft.startTime = normalized;
                  } else {
                    draft.endTime = normalized;
                  }
                });
              }
            }

            // ==========================================================
            // SALVAR ALTERAÇÕES NO FIREBASE
            // ==========================================================

            Future<void> salvarAlteracoes() async {
              try {
                for (final draft in drafts) {
                  draft.taskName = taskControllers[draft.log.id]?.text.trim() ??
                      draft.taskName.trim();

                  draft.description =
                      descriptionControllers[draft.log.id]?.text.trim() ??
                          draft.description.trim();

                  final minutes = _calcularMinutos(
                    draft.startTime,
                    draft.endTime,
                  );

                  final hours = minutes / 60.0;

                  final duration =
                      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
                      '${(minutes % 60).toString().padLeft(2, '0')}';

                  draft.log.taskName = draft.taskName.trim();

                  draft.log.description = draft.description.trim();

                  draft.log.startTime = draft.startTime;

                  draft.log.endTime = draft.endTime;

                  draft.log.durationMinutes = minutes;

                  draft.log.durationFormatted = duration;

                  draft.log.hours = hours;

                  await widget.timeLogStore.updateFirebaseLog(draft.log);
                }

                if (!mounted) return;

                setModalState(() {});

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${drafts.length} trabalho(s) '
                      'salvo(s) no Firebase.',
                    ),
                    backgroundColor: CoresApp.primaria,
                  ),
                );
              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Erro ao salvar alterações: $e',
                    ),
                    backgroundColor: CoresApp.erro,
                  ),
                );
              }
            }

// ==========================================================
// ENVIAR HORAS PARA O E-DESK
// ==========================================================

            Future<void> enviarParaEdesk() async {
              try {
                // ------------------------------------------------------
                // 1. ATUALIZA E VALIDA OS DADOS
                // ------------------------------------------------------

                for (final draft in drafts) {
                  draft.taskName = taskControllers[draft.log.id]?.text.trim() ??
                      draft.taskName.trim();

                  draft.description =
                      descriptionControllers[draft.log.id]?.text.trim() ??
                          draft.description.trim();

                  if (draft.taskName.isEmpty) {
                    throw EdeskException(
                      'A tarefa de '
                      '${_referenciaEdesk(draft.log)} '
                      'não pode ficar vazia.',
                    );
                  }

                  final minutos = _calcularMinutos(
                    draft.startTime,
                    draft.endTime,
                  );

                  if (minutos <= 0) {
                    throw EdeskException(
                      'O horário de '
                      '${_referenciaEdesk(draft.log)} '
                      'é inválido.',
                    );
                  }

                  draft.log.taskName = draft.taskName;
                  draft.log.description = draft.description;
                  draft.log.startTime = draft.startTime;
                  draft.log.endTime = draft.endTime;
                  draft.log.durationMinutes = minutos;
                  draft.log.durationFormatted = _formatarMinutos(minutos);
                  draft.log.hours = minutos / 60.0;

                  // ----------------------------------------------------
                  // Salva a alteração no Firebase ANTES do envio
                  // ----------------------------------------------------

                  await widget.timeLogStore.updateFirebaseLog(
                    draft.log,
                  );
                }

                // ------------------------------------------------------
                // 2. AGRUPA OS TRABALHOS POR SOLICITAÇÃO / TRABALHO
                // ------------------------------------------------------

                final Map<String, List<_EdeskDraft>> grupos = {};

                for (final draft in drafts) {
                  final referencia = _extrairReferenciaEdesk(
                    draft.log,
                  );

                  final chave = '${referencia['solicitacao']}_'
                      '${referencia['idTrabalho']}';

                  grupos.putIfAbsent(
                    chave,
                    () => <_EdeskDraft>[],
                  );

                  grupos[chave]!.add(draft);
                }

                if (grupos.isEmpty) {
                  throw const EdeskException(
                    'Nenhum trabalho válido foi encontrado.',
                  );
                }

                // ------------------------------------------------------
                // 3. MONTA TODOS OS TRABALHOS
                //
                // IMPORTANTE:
                // NÃO executamos o Python dentro do for.
                //
                // Todos os trabalhos serão enviados em UM único payload.
                // ------------------------------------------------------

                final trabalhos = <Map<String, dynamic>>[];

                for (final grupo in grupos.values) {
                  if (grupo.isEmpty) continue;

                  final primeiro = grupo.first;

                  final referencia = _extrairReferenciaEdesk(
                    primeiro.log,
                  );

                  final solicitacao = referencia['solicitacao']!;
                  final idTrabalho = referencia['idTrabalho']!;

                  // ----------------------------------------------------
                  // Monta as horas deste trabalho
                  // ----------------------------------------------------

                  final horas = <Map<String, dynamic>>[];

                  for (final draft in grupo) {
                    final minutos = _calcularMinutos(
                      draft.startTime,
                      draft.endTime,
                    );

                    horas.add({
                      'data': _formatarDataEdesk(
                        draft.log.date,
                      ),

                      'inicio': draft.startTime,

                      'fim': draft.endTime,

                      // Tipo de registro do E-Desk.
                      'tipo': _normalizarTipoEdesk(
                        draft.log.typeHs,
                      ),

                      'tarefa': draft.taskName.trim(),

                      'descricao': draft.description.trim(),

                      // Dados adicionais.
                      'projeto': draft.log.projectName ?? '',

                      'targetId': draft.log.targetId,

                      'duracaoMinutos': minutos,

                      'horas': minutos / 60.0,
                    });
                  }

                  // ----------------------------------------------------
                  // Adiciona este trabalho à lista geral
                  // ----------------------------------------------------

                  trabalhos.add({
                    'solicitacao': solicitacao,
                    'idTrabalho': idTrabalho,
                    'horas': horas,
                  });
                }

                if (trabalhos.isEmpty) {
                  throw const EdeskException(
                    'Nenhum trabalho válido foi preparado para envio.',
                  );
                }

                // ------------------------------------------------------
                // 4. MONTA UM ÚNICO PAYLOAD
                // ------------------------------------------------------
                //
                // Antes:
                //
                // {
                //   "solicitacao": "...",
                //   "idTrabalho": "...",
                //   "horas": [...]
                // }
                //
                // Agora:
                //
                // {
                //   "url": "...",
                //   "trabalhos": [
                //     {
                //       "solicitacao": "...",
                //       "idTrabalho": "...",
                //       "horas": [...]
                //     },
                //     {
                //       "solicitacao": "...",
                //       "idTrabalho": "...",
                //       "horas": [...]
                //     }
                //   ]
                // }

                final payload = {
                  'url': 'https://promob.e-desk.com.br',
                  'trabalhos': trabalhos,
                };

                final requestJson = jsonEncode(payload);

                // ------------------------------------------------------
                // 5. CHAMA O PYTHON UMA ÚNICA VEZ
                // ------------------------------------------------------
                //
                // É aqui que está a correção principal.
                //
                // O Python receberá todos os trabalhos de uma vez e
                // poderá reutilizar a mesma sessão/browser autenticado.
                // ------------------------------------------------------

                final resultado = await executarPythonEdesk(
                  requestJson: requestJson,
                  enviar: true,
                  script: 'edesk_horas.py',
                );

                if (!resultado.confirmed) {
                  throw EdeskException(
                    resultado.message.isNotEmpty
                        ? resultado.message
                        : 'O Python não conseguiu '
                            'registrar as horas no E-Desk.',
                  );
                }

                // ------------------------------------------------------
                // 6. QUANTIDADE DE TRABALHOS ENVIADOS
                // ------------------------------------------------------

                final enviados = trabalhos.length;

                // ------------------------------------------------------
                // 7. FINALIZA
                // ------------------------------------------------------

                if (!mounted) return;

                setModalState(() {
                  _enviandoEdesk = false;
                });

                Navigator.of(dialogContext).pop();

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$enviados trabalho(s) '
                      'enviado(s) para o E-Desk.',
                    ),
                    backgroundColor: CoresApp.primaria,
                    duration: const Duration(seconds: 6),
                  ),
                );
              } catch (e) {
                if (!mounted) return;

                setModalState(() {
                  _enviandoEdesk = false;
                });

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Erro ao enviar horas para o E-Desk: $e',
                    ),
                    backgroundColor: CoresApp.erro,
                    duration: const Duration(seconds: 8),
                  ),
                );
              }
            }
            // ==========================================================
            // INTERFACE
            // ==========================================================

            return Dialog(
              backgroundColor: CoresApp.superficie,
              insetPadding: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda.withOpacity(0.7),
                ),
              ),
              child: SizedBox(
                width: 900,
                height: 700,
                child: Column(
                  children: [
                    // ==================================================
                    // CABEÇALHO
                    // ==================================================

                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: CoresApp.superficie,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: CoresApp.borda.withOpacity(0.7),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: CoresApp.primaria.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(
                                10,
                              ),
                            ),
                            child: const Icon(
                              Icons.access_time_rounded,
                              color: CoresApp.destaque,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Conferência para E-Desk',
                                  style: TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${drafts.length} trabalho(s) • '
                                  'Total: $totalFormatted',
                                  style: const TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fechar',
                            onPressed: _enviandoEdesk
                                ? null
                                : () => Navigator.of(
                                      dialogContext,
                                    ).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: CoresApp.textoSecundario,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ==================================================
                    // LISTA
                    // ==================================================

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: drafts.length,
                        itemBuilder: (context, index) {
                          final draft = drafts[index];

                          final minutes = _calcularMinutos(
                            draft.startTime,
                            draft.endTime,
                          );

                          final duration =
                              '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
                              '${(minutes % 60).toString().padLeft(2, '0')}';

                          return Container(
                            margin: const EdgeInsets.only(
                              bottom: 12,
                            ),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: CoresApp.fundo,
                              borderRadius: BorderRadius.circular(
                                12,
                              ),
                              border: Border.all(
                                color: CoresApp.borda.withOpacity(0.6),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: CoresApp.primaria.withOpacity(
                                          0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          7,
                                        ),
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: CoresApp.secundaria,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        draft.log.projectName
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? draft.log.projectName!
                                            : 'Projeto não informado',
                                        style: const TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Duração: $duration',
                                      style: const TextStyle(
                                        color: CoresApp.secundaria,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.link_rounded,
                                      color: CoresApp.destaque,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Referência E-Desk:',
                                      style: TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _referenciaEdesk(
                                        draft.log,
                                      ),
                                      style: const TextStyle(
                                        color: CoresApp.destaque,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller:
                                            taskControllers[draft.log.id],
                                        enabled: !_enviandoEdesk,
                                        style: const TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 13,
                                        ),
                                        decoration: _edeskInputDecoration(
                                          'Tarefa',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: InkWell(
                                              onTap: _enviandoEdesk
                                                  ? null
                                                  : () => pickTime(
                                                        draft,
                                                        true,
                                                      ),
                                              child: InputDecorator(
                                                decoration:
                                                    _edeskInputDecoration(
                                                  'Início',
                                                ),
                                                child: Text(
                                                  draft.startTime,
                                                  style: const TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: InkWell(
                                              onTap: _enviandoEdesk
                                                  ? null
                                                  : () => pickTime(
                                                        draft,
                                                        false,
                                                      ),
                                              child: InputDecorator(
                                                decoration:
                                                    _edeskInputDecoration(
                                                  'Término',
                                                ),
                                                child: Text(
                                                  draft.endTime,
                                                  style: const TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller:
                                      descriptionControllers[draft.log.id],
                                  enabled: !_enviandoEdesk,
                                  minLines: 2,
                                  maxLines: 4,
                                  style: const TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontSize: 13,
                                  ),
                                  decoration: _edeskInputDecoration(
                                    'Descrição / Descritivo',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text(
                                      'Tipo: '
                                      '${draft.log.typeHs?.trim().isNotEmpty == true ? draft.log.typeHs! : 'Não informado'}',
                                      style: const TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _formatShortDate(
                                        draft.log.date,
                                      ),
                                      style: const TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // ==================================================
                    // RODAPÉ
                    // ==================================================

                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        16,
                      ),
                      decoration: BoxDecoration(
                        color: CoresApp.superficie,
                        border: Border(
                          top: BorderSide(
                            color: CoresApp.borda.withOpacity(0.7),
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _enviandoEdesk
                                ? null
                                : () => Navigator.of(
                                      dialogContext,
                                    ).pop(),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.fundo,
                              foregroundColor: CoresApp.textoPrincipal,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  10,
                                ),
                                side: const BorderSide(
                                  color: CoresApp.borda,
                                ),
                              ),
                            ),
                            onPressed: _enviandoEdesk ? null : salvarAlteracoes,
                            icon: const Icon(
                              Icons.save_outlined,
                              size: 18,
                            ),
                            label: const Text(
                              'Salvar alterações',
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.primaria,
                              foregroundColor: CoresApp.textoPrincipal,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  10,
                                ),
                              ),
                            ),
                            onPressed: _enviandoEdesk
                                ? null
                                : () {
                                    setModalState(
                                      () {
                                        _enviandoEdesk = true;
                                      },
                                    );

                                    enviarParaEdesk();
                                  },
                            icon: _enviandoEdesk
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: CoresApp.textoPrincipal,
                                    ),
                                  )
                                : const Icon(
                                    Icons.cloud_upload_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              _enviandoEdesk
                                  ? 'Enviando horas...'
                                  : 'Registrar horas no E-Desk',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    dialogFuture.whenComplete(() {
      for (final controller in taskControllers.values) {
        controller.dispose();
      }

      for (final controller in descriptionControllers.values) {
        controller.dispose();
      }
    });
  }

// ============================================================
// FORMATA DATA PARA O E-DESK
// ============================================================

  String _formatarDataEdesk(dynamic date) {
    if (date == null) {
      return '';
    }

    if (date is DateTime) {
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    final texto = date.toString().trim();

    if (texto.isEmpty) {
      return '';
    }

    // Já está no padrão do E-Desk.
    if (RegExp(
      r'^\d{2}/\d{2}/\d{4}$',
    ).hasMatch(texto)) {
      return texto;
    }

    // Tenta ISO: 2026-09-19
    final iso = DateTime.tryParse(texto);

    if (iso != null) {
      return '${iso.day.toString().padLeft(2, '0')}/'
          '${iso.month.toString().padLeft(2, '0')}/'
          '${iso.year}';
    }

    return texto;
  }

// ============================================================
// NORMALIZA TIPO PARA O E-DESK
// ============================================================

  String _normalizarTipoEdesk(String? tipo) {
    final valor = tipo?.trim() ?? '';

    if (valor.isEmpty) {
      return '0';
    }

    // Se já for um código numérico do E-Desk.
    if (RegExp(r'^\d+$').hasMatch(valor)) {
      return valor;
    }

    // Mantém compatibilidade com possíveis nomes usados no app.
    switch (valor.toLowerCase()) {
      case 'interno':
        return '0';

      case 'externo':
        return '1';

      case 'padrão':
      case 'padrao':
        return '3';

      default:
        return '0';
    }
  }

// ============================================================
// CALCULA MINUTOS
// ============================================================

  int _calcularMinutos(
    String inicio,
    String fim,
  ) {
    try {
      final iParts = inicio.split(':');
      final fParts = fim.split(':');

      if (iParts.length != 2 || fParts.length != 2) {
        return 0;
      }

      final iMins = int.parse(iParts[0]) * 60 + int.parse(iParts[1]);

      final fMins = int.parse(fParts[0]) * 60 + int.parse(fParts[1]);

      var diff = fMins - iMins;

      if (diff < 0) {
        diff += 24 * 60;
      }

      return diff;
    } catch (_) {
      return 0;
    }
  }

// ============================================================
// DECORAÇÃO DOS CAMPOS
// ============================================================

  InputDecoration _edeskInputDecoration(
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: CoresApp.textoSecundario,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(
          color: CoresApp.borda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(
          color: CoresApp.primaria,
        ),
      ),
      filled: true,
      fillColor: CoresApp.superficie,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
    );
  }
  // ============================================================
  // MODAL DE EDIÇÃO
  // ============================================================

  void _abrirModalEdicao(TimeLog log) {
    final descController = TextEditingController(
      text: log.description ?? '',
    );

    final taskController = TextEditingController(
      text: log.taskName ?? '',
    );

    String startTime = log.startTime;
    String endTime = log.endTime;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickTime(
              bool isStart,
            ) async {
              final parts = (isStart ? startTime : endTime).split(':');

              final h = parts.length == 2 ? int.tryParse(parts[0]) ?? 8 : 8;

              final m = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;

              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: h,
                  minute: m,
                ),
                initialEntryMode: TimePickerEntryMode.input,
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.dark().copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: CoresApp.primaria,
                        onPrimary: CoresApp.textoPrincipal,
                        surface: CoresApp.superficie,
                        onSurface: CoresApp.textoPrincipal,
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                final formatted = '${picked.hour.toString().padLeft(2, '0')}:'
                    '${picked.minute.toString().padLeft(2, '0')}';

                setModalState(() {
                  if (isStart) {
                    startTime = formatted;
                  } else {
                    endTime = formatted;
                  }
                });
              }
            }

            return AlertDialog(
              backgroundColor: CoresApp.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda.withOpacity(0.6),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.edit_calendar_rounded,
                      color: CoresApp.destaque,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Editar Apontamento',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: taskController,
                        style: const TextStyle(
                          color: CoresApp.textoPrincipal,
                        ),
                        decoration: _edeskInputDecoration(
                          'Nome da Tarefa',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => pickTime(true),
                              child: InputDecorator(
                                decoration: _edeskInputDecoration(
                                  'Início',
                                ),
                                child: Text(
                                  startTime,
                                  style: const TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => pickTime(false),
                              child: InputDecorator(
                                decoration: _edeskInputDecoration(
                                  'Término',
                                ),
                                child: Text(
                                  endTime,
                                  style: const TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descController,
                        style: const TextStyle(
                          color: CoresApp.textoPrincipal,
                        ),
                        maxLines: 3,
                        decoration: _edeskInputDecoration(
                          'Descrição / Descritivo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      final diffMinutes = _calcularMinutos(
                        startTime,
                        endTime,
                      );

                      log.taskName = taskController.text;

                      log.description = descController.text;

                      log.startTime = startTime;

                      log.endTime = endTime;

                      log.hours = diffMinutes / 60.0;

                      log.durationMinutes = diffMinutes;

                      log.durationFormatted = _formatarMinutos(
                        diffMinutes,
                      );

                      await widget.timeLogStore.updateFirebaseLog(log);

                      if (mounted) {
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao atualizar: $e',
                          ),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                    }
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // MODAL FILTRO PDF
  // ============================================================

  void _abrirModalFiltroPdf() {
    String filtroSelecionado = _filter;
    DateTime? inicioTemp = _startDate;
    DateTime? fimTemp = _endDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: CoresApp.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda.withOpacity(0.6),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: CoresApp.destaque,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Configurar Relatório PDF',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selecione o filtro base para o relatório:',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: filtroSelecionado == 'Período'
                          ? 'Período'
                          : filtroSelecionado,
                      dropdownColor: CoresApp.superficie,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 14,
                      ),
                      decoration: _edeskInputDecoration(
                        'Filtro',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Todas',
                          child: Text(
                            'Todas as tarefas',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hoje',
                          child: Text(
                            'Apenas Hoje',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Esta semana',
                          child: Text(
                            'Esta Semana',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Período',
                          child: Text(
                            'Intervalo de Datas (Período)',
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setModalState(() {
                          filtroSelecionado = val ?? 'Todas';
                        });
                      },
                    ),
                    if (filtroSelecionado == 'Período') ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CoresApp.fundo,
                          foregroundColor: CoresApp.textoPrincipal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ),
                            side: const BorderSide(
                              color: CoresApp.borda,
                            ),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(
                          Icons.date_range_rounded,
                          color: CoresApp.destaque,
                        ),
                        label: Text(
                          inicioTemp != null && fimTemp != null
                              ? '${_formatShortDate(inicioTemp!)} '
                                  'até '
                                  '${_formatShortDate(fimTemp!)}'
                              : 'Selecionar Datas',
                          style: const TextStyle(
                            fontSize: 13,
                          ),
                        ),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            initialDateRange:
                                inicioTemp != null && fimTemp != null
                                    ? DateTimeRange(
                                        start: inicioTemp!,
                                        end: fimTemp!,
                                      )
                                    : null,
                            builder: (context, child) {
                              return Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: CoresApp.primaria,
                                    onPrimary: CoresApp.textoPrincipal,
                                    surface: CoresApp.superficie,
                                    onSurface: CoresApp.textoPrincipal,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );

                          if (picked != null) {
                            setModalState(() {
                              inicioTemp = picked.start;
                              fimTemp = picked.end;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        10,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 17,
                  ),
                  onPressed: () {
                    Navigator.pop(context);

                    _gerarPdfComFiltroEspecifico(
                      filtroSelecionado,
                      inicioTemp,
                      fimTemp,
                    );
                  },
                  label: const Text('Gerar PDF'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // PDF
  // ============================================================

  Future<void> _gerarPdfComFiltroEspecifico(
    String filtroEscolhido,
    DateTime? inicio,
    DateTime? fim,
  ) async {
    try {
      final logsFiltrados = widget.timeLogStore.logs.where((log) {
        if (!log.isRegistered) {
          return false;
        }

        if (filtroEscolhido == 'Hoje') {
          final now = DateTime.now();

          if (log.date.year != now.year ||
              log.date.month != now.month ||
              log.date.day != now.day) {
            return false;
          }
        } else if (filtroEscolhido == 'Esta semana') {
          final now = DateTime.now();

          final start = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(
            Duration(days: now.weekday - 1),
          );

          final end = start.add(
            const Duration(days: 7),
          );

          if (log.date.isBefore(start) || !log.date.isBefore(end)) {
            return false;
          }
        } else if (filtroEscolhido == 'Período' &&
            inicio != null &&
            fim != null) {
          final nLog = DateTime(
            log.date.year,
            log.date.month,
            log.date.day,
          );

          final nStart = DateTime(
            inicio.year,
            inicio.month,
            inicio.day,
          );

          final nEnd = DateTime(
            fim.year,
            fim.month,
            fim.day,
            23,
            59,
            59,
          );

          if (nLog.isBefore(nStart) || nLog.isAfter(nEnd)) {
            return false;
          }
        }

        return true;
      }).toList()
        ..sort(
          (a, b) => b.date.compareTo(a.date),
        );

      if (logsFiltrados.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Nenhum registro encontrado para o filtro selecionado.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );
        }

        return;
      }

      final pdf = pw.Document();

      const corPrimariaPdf = PdfColor.fromInt(0xFF3F51B5);

      const corPrimariaEscuraPdf = PdfColor.fromInt(0xFF303F9F);

      const corFundoCabecalho = PdfColor.fromInt(0xFF303F9F);

      const corLinhaAlternada = PdfColor.fromInt(0xFFF7F8FA);

      const corBordaPdf = PdfColor.fromInt(0xFFE0E3E7);

      const corTextoPdf = PdfColor.fromInt(0xFF263238);

      const corTextoSecundarioPdf = PdfColor.fromInt(0xFF687078);

      const corFundoResumo = PdfColor.fromInt(0xFFF1F4F8);

      // Evita warning de constante declarada
      // para manter a paleta do relatório.
      // ignore: unused_local_variable
      const _ = corPrimariaEscuraPdf;

      final totalMinutos = _totalMinutos(logsFiltrados);

      final totalHoras = _formatarMinutos(totalMinutos);

      final totalProjetos = _projetosUnicos(logsFiltrados).length;

      String periodoDescricao;

      switch (filtroEscolhido) {
        case 'Hoje':
          periodoDescricao = 'Hoje: ${_formatShortDate(DateTime.now())}';
          break;

        case 'Esta semana':
          final now = DateTime.now();

          final semanaInicio = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(
            Duration(days: now.weekday - 1),
          );

          final semanaFim = semanaInicio.add(
            const Duration(days: 6),
          );

          periodoDescricao = 'Esta semana: '
              '${_formatShortDate(semanaInicio)} até '
              '${_formatShortDate(semanaFim)}';

          break;

        case 'Período':
          periodoDescricao = inicio != null && fim != null
              ? '${_formatShortDate(inicio)} até '
                  '${_formatShortDate(fim)}'
              : 'Período selecionado';
          break;

        default:
          periodoDescricao = 'Todos os registros';
      }

      final Map<String, List<TimeLog>> registrosPorData = {};

      for (final log in logsFiltrados) {
        final chave = '${log.date.year}-${log.date.month}-${log.date.day}';

        registrosPorData
            .putIfAbsent(
              chave,
              () => [],
            )
            .add(log);
      }

      final datasOrdenadas = registrosPorData.entries.toList()
        ..sort(
          (a, b) => b.key.compareTo(a.key),
        );

      final hoje = DateTime.now();

      final nomeArquivo = 'relatorio_tarefas_'
          '${hoje.day}-${hoje.month}-${hoje.year}.pdf';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(
            32,
            28,
            32,
            32,
          ),
          build: (pw.Context context) {
            final List<pw.Widget> conteudo = [];

            conteudo.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: corFundoResumo,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(
                    color: corBordaPdf,
                  ),
                ),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 4,
                      height: 38,
                      decoration: pw.BoxDecoration(
                        color: corPrimariaPdf,
                        borderRadius: pw.BorderRadius.circular(
                          2,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'PERÍODO DO RELATÓRIO',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: corTextoSecundarioPdf,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            periodoDescricao,
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: corTextoPdf,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );

            conteudo.add(
              pw.SizedBox(height: 14),
            );

            for (int index = 0; index < datasOrdenadas.length; index++) {
              final entry = datasOrdenadas[index];

              final logsDoDia = entry.value;

              final dataRef = logsDoDia.first.date;

              final totalDia = _formatarMinutos(
                _totalMinutos(logsDoDia),
              );

              conteudo.add(
                pw.Container(
                  margin: pw.EdgeInsets.only(
                    top: index == 0 ? 0 : 12,
                    bottom: 8,
                  ),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(
                      0xFFE9EDF7,
                    ),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          _formatDateHeader(
                            dataRef,
                          ),
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: corTextoPdf,
                          ),
                        ),
                      ),
                      pw.Text(
                        'Total: $totalDia',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: corPrimariaPdf,
                        ),
                      ),
                    ],
                  ),
                ),
              );

              conteudo.add(
                pw.Table(
                  border: pw.TableBorder.all(
                    color: corBordaPdf,
                    width: 0.5,
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(
                      1.8,
                    ),
                    1: const pw.FlexColumnWidth(
                      3.1,
                    ),
                    2: const pw.FlexColumnWidth(
                      1.0,
                    ),
                    3: const pw.FlexColumnWidth(
                      1.35,
                    ),
                    4: const pw.FlexColumnWidth(
                      0.9,
                    ),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: corFundoCabecalho,
                      ),
                      children: [
                        _pdfHeaderCell(
                          'PROJETO',
                        ),
                        _pdfHeaderCell(
                          'TAREFA / DESCRIÇÃO',
                        ),
                        _pdfHeaderCell(
                          'TIPO',
                        ),
                        _pdfHeaderCell(
                          'HORÁRIO',
                        ),
                        _pdfHeaderCell(
                          'DURAÇÃO',
                        ),
                      ],
                    ),
                    ...List.generate(
                      logsDoDia.length,
                      (i) {
                        final log = logsDoDia[i];

                        return pw.TableRow(
                          decoration: pw.BoxDecoration(
                            color:
                                i.isOdd ? corLinhaAlternada : PdfColors.white,
                          ),
                          children: [
                            _pdfBodyCell(
                              (log.projectName ?? log.targetId).trim(),
                              bold: true,
                            ),
                            _pdfBodyCell(
                              (log.taskName ?? log.targetId).trim(),
                            ),
                            _pdfBodyCell(
                              log.typeHs ?? '',
                              center: true,
                            ),
                            _pdfBodyCell(
                              '${log.startTime} até '
                              '${log.endTime}',
                              center: true,
                            ),
                            _pdfBodyCell(
                              log.durationFormatted,
                              center: true,
                              bold: true,
                              color: corPrimariaPdf,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }

            return conteudo;
          },
        ),
      );

      if (!mounted) {
        return;
      }

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: CoresApp.superficie,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: 1000,
              height: 750,
              child: Column(
                children: [
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Pré-visualização do Relatório',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(
                            dialogContext,
                          ).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: CoresApp.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PdfPreview(
                      build: (format) async => pdf.save(),
                      allowPrinting: true,
                      allowSharing: true,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      pdfFileName: nomeArquivo,
                      actions: const [],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao gerar PDF: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  pw.Widget _pdfHeaderCell(
    String text,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 7,
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  pw.Widget _pdfBodyCell(
    String text, {
    bool bold = false,
    bool center = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 7,
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? corTextoPdfLocal,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  static const PdfColor corTextoPdfLocal = PdfColor.fromInt(0xFF263238);

  static const PdfColor corTextoSecundarioPdfLocal =
      PdfColor.fromInt(0xFF687078);

  // ============================================================
  // ESTADO VAZIO
  // ============================================================

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 480,
        ),
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: CoresApp.primaria.withOpacity(0.1),
                borderRadius: BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color: CoresApp.primaria.withOpacity(0.2),
                ),
              ),
              child: const Icon(
                Icons.task_alt_rounded,
                color: CoresApp.destaque,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Nenhum apontamento encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Não existem tarefas cadastradas para os filtros selecionados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LINHA DO DIA
  // ============================================================

  Widget _buildDayRow({
    required DateTime dataReferencia,
    required List<TimeLog> logsDoDia,
  }) {
    final totalDia = _formatarMinutos(
      _totalMinutos(logsDoDia),
    );

    final now = DateTime.now();

    final isToday = now.year == dataReferencia.year &&
        now.month == dataReferencia.month &&
        now.day == dataReferencia.day;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _abrirModalDetalhesDia(
          _formatDateHeader(
            dataReferencia,
          ),
          totalDia,
          logsDoDia,
        ),
        child: Container(
          height: 50,
          margin: const EdgeInsets.only(
            bottom: 4,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          decoration: BoxDecoration(
            color: isToday
                ? CoresApp.primaria.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? CoresApp.primaria.withOpacity(0.25)
                  : CoresApp.borda.withOpacity(0.4),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dayNameShort(
                        dataReferencia.weekday,
                      ),
                      style: TextStyle(
                        color: isToday
                            ? CoresApp.destaque
                            : CoresApp.textoSecundario,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${dataReferencia.day.toString().padLeft(2, '0')} '
                      '${_monthShort(dataReferencia.month)}',
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 26,
                color: CoresApp.borda.withOpacity(0.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${logsDoDia.length} '
                  '${logsDoDia.length == 1 ? 'tarefa' : 'tarefas'}',
                  style: const TextStyle(
                    color: CoresApp.textoSecundario,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(
                    6,
                  ),
                ),
                child: Text(
                  totalDia,
                  style: const TextStyle(
                    color: CoresApp.destaque,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: CoresApp.textoSecundario,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CARD DA SEMANA
  // ============================================================

  Widget _buildWeekCard({
    required DateTime weekStart,
    required List<TimeLog> logsDaSemana,
    required bool expanded,
  }) {
    final weekKey = _weekKey(weekStart);

    final totalSemana = _formatarMinutos(
      _totalMinutos(logsDaSemana),
    );

    final projetosSemana = _projetosUnicos(
      logsDaSemana,
    ).length;

    final groupedDays = <String, List<TimeLog>>{};

    for (final log in logsDaSemana) {
      final key = '${log.date.year}-${log.date.month}-${log.date.day}';

      groupedDays
          .putIfAbsent(
            key,
            () => [],
          )
          .add(log);
    }

    final dayKeys = groupedDays.keys.toList()
      ..sort(
        (a, b) => b.compareTo(a),
      );

    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      decoration: BoxDecoration(
        color: CoresApp.superficie.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: expanded
              ? CoresApp.primaria.withOpacity(0.3)
              : CoresApp.borda.withOpacity(0.6),
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(
                12,
              ),
              onTap: () {
                setState(() {
                  if (_semanasExpandidas.contains(weekKey)) {
                    _semanasExpandidas.remove(weekKey);
                  } else {
                    _semanasExpandidas.add(weekKey);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(
                        milliseconds: 180,
                      ),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: expanded
                            ? CoresApp.primaria.withOpacity(
                                0.12,
                              )
                            : CoresApp.fundo,
                        borderRadius: BorderRadius.circular(
                          8,
                        ),
                      ),
                      child: Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        color: expanded
                            ? CoresApp.destaque
                            : CoresApp.textoSecundario,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _formatWeekTitle(
                                  weekStart,
                                ),
                                style: const TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (_weekKey(
                                    DateTime.now(),
                                  ) ==
                                  weekKey) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CoresApp.destaque.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(
                                      4,
                                    ),
                                  ),
                                  child: const Text(
                                    'ATUAL',
                                    style: TextStyle(
                                      color: CoresApp.destaque,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatWeekRange(
                              weekStart,
                            ),
                            style: const TextStyle(
                              color: CoresApp.textoSecundario,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildWeekInfo(
                      value: totalSemana,
                      label: 'horas',
                      color: CoresApp.destaque,
                    ),
                    const SizedBox(width: 16),
                    _buildWeekInfo(
                      value: '${logsDaSemana.length}',
                      label: 'tarefas',
                      color: CoresApp.primaria,
                    ),
                    const SizedBox(width: 16),
                    _buildWeekInfo(
                      value: '$projetosSemana',
                      label: 'projetos',
                      color: CoresApp.secundaria,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                10,
                0,
                10,
                10,
              ),
              child: Column(
                children: [
                  Divider(
                    height: 1,
                    color: CoresApp.borda.withOpacity(0.4),
                  ),
                  const SizedBox(height: 6),
                  for (final dayKey in dayKeys)
                    _buildDayRow(
                      dataReferencia: groupedDays[dayKey]!.first.date,
                      logsDoDia: groupedDays[dayKey]!,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWeekInfo({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: CoresApp.textoSecundario,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final registeredLogs = _registeredLogs;

    final groupedWeeks = _groupLogsByWeek(
      registeredLogs,
    );

    final sortedWeekKeys = groupedWeeks.keys.toList()
      ..sort(
        (a, b) => b.compareTo(a),
      );

    final int totalRegistros = registeredLogs.length;

    final int totalMinutos = _totalMinutos(
      registeredLogs,
    );

    final String totalHoras = _formatarMinutos(
      totalMinutos,
    );

    final int totalProjetos = _projetosUnicos(
      registeredLogs,
    ).length;

    final int totalDias = _groupedLogsByDate.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: _search,
          onSearchChanged: (value) {
            setState(
              () => _search = value,
            );
          },
          userName: '',
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              AppTheme.caminhoFundo,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox.shrink();
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(
                AppTheme.opacidadeFundo,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              14,
              12,
              14,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==================================================
                // CABEÇALHO UNIFICADO
                // ==================================================

                _buildUnifiedHeader(
                  totalRegistros: totalRegistros,
                  totalProjetos: totalProjetos,
                  totalHoras: totalHoras,
                  totalDias: totalDias,
                ),

                const SizedBox(height: 12),

                // ==================================================
                // FILTROS
                // ==================================================

                _buildFiltersBar(),

                const SizedBox(height: 12),

                // ==================================================
                // HISTÓRICO
                // ==================================================

                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(
                      12,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.superficie.withOpacity(
                        0.95,
                      ),
                      borderRadius: BorderRadius.circular(
                        14,
                      ),
                      border: Border.all(
                        color: CoresApp.borda.withOpacity(
                          0.7,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(
                            0.06,
                          ),
                          blurRadius: 10,
                          offset: const Offset(
                            0,
                            3,
                          ),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: CoresApp.sucesso.withOpacity(
                                    0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    8,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.history_rounded,
                                  color: CoresApp.sucesso,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Histórico de apontamentos',
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 1),
                                    Text(
                                      'Organizado por semana',
                                      style: TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (sortedWeekKeys.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CoresApp.fundo,
                                    borderRadius: BorderRadius.circular(
                                      7,
                                    ),
                                    border: Border.all(
                                      color: CoresApp.borda,
                                    ),
                                  ),
                                  child: Text(
                                    '${sortedWeekKeys.length} '
                                    '${sortedWeekKeys.length == 1 ? 'semana' : 'semanas'}',
                                    style: const TextStyle(
                                      color: CoresApp.textoSecundario,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: sortedWeekKeys.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: sortedWeekKeys.length,
                                  itemBuilder: (context, index) {
                                    final weekKey = sortedWeekKeys[index];

                                    final logsDaSemana = groupedWeeks[weekKey]!;

                                    final weekStart = _weekStart(
                                      logsDaSemana.first.date,
                                    );

                                    final currentWeekKey = _weekKey(
                                      DateTime.now(),
                                    );

                                    final isCurrentWeek =
                                        weekKey == currentWeekKey;

                                    final expanded =
                                        _semanasExpandidas.contains(
                                              weekKey,
                                            ) ||
                                            isCurrentWeek;

                                    if (isCurrentWeek &&
                                        !_semanasExpandidas.contains(
                                          weekKey,
                                        )) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                        (_) {
                                          if (mounted) {
                                            setState(
                                              () => _semanasExpandidas.add(
                                                weekKey,
                                              ),
                                            );
                                          }
                                        },
                                      );
                                    }

                                    return _buildWeekCard(
                                      weekStart: weekStart,
                                      logsDaSemana: logsDaSemana,
                                      expanded: expanded,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// MODELO TEMPORÁRIO DO E-DESK
// ================================================================

class _EdeskDraft {
  final TimeLog log;

  String taskName;
  String description;
  String startTime;
  String endTime;

  _EdeskDraft({
    required this.log,
    required this.taskName,
    required this.description,
    required this.startTime,
    required this.endTime,
  });
}

// ================================================================
// EXTENSION
// ================================================================

extension on TimeLog {
  String get dateFormatted {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }
}
