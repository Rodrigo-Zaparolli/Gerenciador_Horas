import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

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
  String _search = '';
  String _filter = 'Todas';
  DateTime? _startDate;
  DateTime? _endDate;

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
    if (mounted) setState(() {});
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)), end: now),
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

  List<TimeLog> get _registeredLogs {
    final query = _search.trim().toLowerCase();
    return widget.timeLogStore.logs.where((log) {
      if (!log.isRegistered) return false;

      if (_filter == 'Hoje') {
        final now = DateTime.now();
        if (log.date.year != now.year ||
            log.date.month != now.month ||
            log.date.day != now.day) {
          return false;
        }
      } else if (_filter == 'Esta semana') {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final end = start.add(const Duration(days: 7));
        if (log.date.isBefore(start) || !log.date.isBefore(end)) return false;
      } else if (_filter == 'Período' &&
          _startDate != null &&
          _endDate != null) {
        final normalizedLogDate =
            DateTime(log.date.year, log.date.month, log.date.day);
        final normalizedStart =
            DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final normalizedEnd = DateTime(
            _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);

        if (normalizedLogDate.isBefore(normalizedStart) ||
            normalizedLogDate.isAfter(normalizedEnd)) {
          return false;
        }
      }

      if (query.isEmpty) return true;
      return log.targetId.toLowerCase().contains(query) ||
          (log.projectName ?? '').toLowerCase().contains(query) ||
          (log.taskName ?? '').toLowerCase().contains(query) ||
          (log.description ?? '').toLowerCase().contains(query) ||
          log.dateFormatted.contains(query);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  String _date(TimeLog log) =>
      '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year.toString().substring(2)}';

  String _formatShortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  void _abrirModalEdicao(TimeLog log) {
    final descController = TextEditingController(text: log.description ?? '');
    final taskController = TextEditingController(text: log.taskName ?? '');

    String startTime = log.startTime;
    String endTime = log.endTime;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickTime(bool isStart) async {
              final parts = (isStart ? startTime : endTime).split(':');
              int initHour =
                  parts.length == 2 ? int.tryParse(parts[0]) ?? 8 : 8;
              int initMinute =
                  parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;

              final pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: initHour, minute: initMinute),
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

              if (pickedTime != null) {
                final formattedTime =
                    '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
                setModalState(() {
                  if (isStart) {
                    startTime = formattedTime;
                  } else {
                    endTime = formattedTime;
                  }
                });
              }
            }

            return AlertDialog(
              backgroundColor: CoresApp.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: CoresApp.borda.withOpacity(0.6)),
              ),
              title: const Text('Editar Apontamento e Horários',
                  style: TextStyle(
                      color: CoresApp.destaque, fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: taskController,
                        style: const TextStyle(color: CoresApp.textoPrincipal),
                        decoration: InputDecoration(
                          labelText: 'Nome da Tarefa',
                          labelStyle:
                              const TextStyle(color: CoresApp.textoSecundario),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: CoresApp.borda),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: CoresApp.primaria),
                          ),
                          filled: true,
                          fillColor: CoresApp.fundo,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => pickTime(true),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Início',
                                  labelStyle: const TextStyle(
                                      color: CoresApp.textoSecundario),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        const BorderSide(color: CoresApp.borda),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: CoresApp.primaria),
                                  ),
                                  filled: true,
                                  fillColor: CoresApp.fundo,
                                ),
                                child: Text(startTime,
                                    style: const TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 15)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: InkWell(
                              onTap: () => pickTime(false),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Término',
                                  labelStyle: const TextStyle(
                                      color: CoresApp.textoSecundario),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        const BorderSide(color: CoresApp.borda),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: CoresApp.primaria),
                                  ),
                                  filled: true,
                                  fillColor: CoresApp.fundo,
                                ),
                                child: Text(endTime,
                                    style: const TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 15)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: descController,
                        style: const TextStyle(color: CoresApp.textoPrincipal),
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Descrição / Descritivo',
                          labelStyle:
                              const TextStyle(color: CoresApp.textoSecundario),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: CoresApp.borda),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: CoresApp.primaria),
                          ),
                          filled: true,
                          fillColor: CoresApp.fundo,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(color: CoresApp.textoSecundario)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      final startParts = startTime.split(':');
                      final endParts = endTime.split(':');

                      final startMinutes = int.parse(startParts[0]) * 60 +
                          int.parse(startParts[1]);
                      final endMinutes =
                          int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

                      int diffMinutes = endMinutes - startMinutes;
                      if (diffMinutes < 0) {
                        diffMinutes += 24 * 60;
                      }

                      final totalHours = diffMinutes / 60.0;
                      final hoursInt = diffMinutes ~/ 60;
                      final minsInt = diffMinutes % 60;
                      final durationFormatted =
                          '${hoursInt.toString().padLeft(2, '0')}:${minsInt.toString().padLeft(2, '0')}';

                      log.taskName = taskController.text;
                      log.description = descController.text;
                      log.startTime = startTime;
                      log.endTime = endTime;
                      log.hours = totalHours;
                      log.durationFormatted = durationFormatted;

                      await widget.timeLogStore.updateFirebaseLog(log);
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Erro ao atualizar horários: $e'),
                            backgroundColor: CoresApp.erro),
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

  // Modal para escolher o filtro antes de gerar o PDF
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
                side: BorderSide(color: CoresApp.borda.withOpacity(0.6)),
              ),
              title: const Text(
                'Configurar Relatório PDF',
                style: TextStyle(
                  color: CoresApp.destaque,
                  fontWeight: FontWeight.bold,
                ),
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
                          color: CoresApp.textoSecundario, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: filtroSelecionado == 'Período'
                          ? 'Período'
                          : filtroSelecionado,
                      dropdownColor: CoresApp.superficie,
                      style: const TextStyle(
                          color: CoresApp.textoPrincipal, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Filtro',
                        labelStyle:
                            const TextStyle(color: CoresApp.textoSecundario),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: CoresApp.primaria),
                        ),
                        filled: true,
                        fillColor: CoresApp.fundo,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Todas', child: Text('Todas as tarefas')),
                        DropdownMenuItem(
                            value: 'Hoje', child: Text('Apenas Hoje')),
                        DropdownMenuItem(
                            value: 'Esta semana', child: Text('Esta Semana')),
                        DropdownMenuItem(
                            value: 'Período',
                            child: Text('Intervalo de Datas (Período)')),
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
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: CoresApp.borda),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.date_range_rounded,
                            color: CoresApp.primaria),
                        label: Text(
                          inicioTemp != null && fimTemp != null
                              ? '${_formatShortDate(inicioTemp!)} até ${_formatShortDate(fimTemp!)}'
                              : 'Selecionar Datas',
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            initialDateRange:
                                inicioTemp != null && fimTemp != null
                                    ? DateTimeRange(
                                        start: inicioTemp!, end: fimTemp!)
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
                  child: const Text('Cancelar',
                      style: TextStyle(color: CoresApp.textoSecundario)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _gerarPdfComFiltroEspecifico(
                        filtroSelecionado, inicioTemp, fimTemp);
                  },
                  child: const Text('Gerar PDF'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _gerarPdfComFiltroEspecifico(
      String filtroEscolhido, DateTime? inicio, DateTime? fim) async {
    try {
      final logsFiltrados = widget.timeLogStore.logs.where((log) {
        if (!log.isRegistered) return false;

        if (filtroEscolhido == 'Hoje') {
          final now = DateTime.now();
          if (log.date.year != now.year ||
              log.date.month != now.month ||
              log.date.day != now.day) {
            return false;
          }
        } else if (filtroEscolhido == 'Esta semana') {
          final now = DateTime.now();
          final start = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          final end = start.add(const Duration(days: 7));
          if (log.date.isBefore(start) || !log.date.isBefore(end)) return false;
        } else if (filtroEscolhido == 'Período' &&
            inicio != null &&
            fim != null) {
          final normalizedLogDate =
              DateTime(log.date.year, log.date.month, log.date.day);
          final normalizedStart =
              DateTime(inicio.year, inicio.month, inicio.day);
          final normalizedEnd =
              DateTime(fim.year, fim.month, fim.day, 23, 59, 59);

          if (normalizedLogDate.isBefore(normalizedStart) ||
              normalizedLogDate.isAfter(normalizedEnd)) {
            return false;
          }
        }
        return true;
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      if (logsFiltrados.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Nenhum registro encontrado para o filtro selecionado.'),
              backgroundColor: CoresApp.erro,
            ),
          );
        }
        return;
      }

      final pdf = pw.Document();

      // Cores personalizadas para o PDF
      const corPrimariaPdf = PdfColor.fromInt(0xFF3F51B5); // Indigo vibrante
      const corFundoCabecalho = PdfColor.fromInt(0xFF303F9F);
      const corLinhaAlternada = PdfColor.fromInt(0xFFF5F5F7);
      const corBordaPdf = PdfColor.fromInt(0xFFE0E0E0);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: corPrimariaPdf, width: 2),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 6,
                        height: 20,
                        decoration: pw.BoxDecoration(
                          color: corPrimariaPdf,
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        'Relatório de Tarefas Executadas',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(0xFF212121),
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Emitido em: ${_formatShortDate(DateTime.now())}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColor.fromInt(0xFF757575),
                    ),
                  ),
                ],
              ),
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 14),
              padding: const pw.EdgeInsets.only(top: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: corBordaPdf, width: 0.5),
                ),
              ),
              child: pw.Text(
                'Página ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColor.fromInt(0xFF757575),
                ),
              ),
            );
          },
          build: (pw.Context context) {
            return [
              pw.SizedBox(height: 14),
              // Bloco de informações do filtro com cantos arredondados
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFEEF2F6),
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: corBordaPdf),
                ),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      'Filtro aplicado: ',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: corPrimariaPdf,
                      ),
                    ),
                    pw.Text(
                      filtroEscolhido,
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColor.fromInt(0xFF424242),
                      ),
                    ),
                    if (filtroEscolhido == 'Período' &&
                        inicio != null &&
                        fim != null)
                      pw.Text(
                        ' (${_formatShortDate(inicio)} até ${_formatShortDate(fim)})',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColor.fromInt(0xFF424242),
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Tabela Moderna com Cantos Arredondados
              pw.Container(
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(10),
                  border: pw.Border.all(color: corBordaPdf, width: 1),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 10,
                  verticalRadius: 10,
                  child: pw.Table.fromTextArray(
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                    headerDecoration: const pw.BoxDecoration(
                      color: corFundoCabecalho,
                    ),
                    rowDecoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: corBordaPdf, width: 0.5),
                      ),
                    ),
                    oddRowDecoration: const pw.BoxDecoration(
                      color: corLinhaAlternada,
                    ),
                    cellStyle: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColor.fromInt(0xFF333333),
                    ),
                    cellHeight: 32,
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.center,
                      3: pw.Alignment.center,
                      4: pw.Alignment.center,
                    },
                    headers: <String>[
                      'Projeto',
                      'Tarefa / Descrição',
                      'Data',
                      'Horário',
                      'Duração',
                    ],
                    data: logsFiltrados.map((log) {
                      final tarefaOuDescricao = (log.description != null &&
                              log.description!.trim().isNotEmpty)
                          ? '${log.taskName ?? log.targetId} - ${log.description}'
                          : (log.taskName ?? log.targetId);

                      return [
                        log.projectName ?? 'Não identificado',
                        tarefaOuDescricao,
                        _date(log),
                        '${log.startTime} - ${log.endTime}',
                        log.durationFormatted,
                      ];
                    }).toList(),
                  ),
                ),
              ),
              pw.SizedBox(height: 16),

              // Rodapé de Totalização com cantos arredondados
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFE8EAF6),
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColor.fromInt(0xC5C5E1)),
                    ),
                    child: pw.Text(
                      'Total de registros listados: ${logsFiltrados.length}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: corPrimariaPdf,
                      ),
                    ),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'relatorio_tarefas.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao gerar PDF: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = _registeredLogs;
    return Scaffold(
      backgroundColor: CoresApp.fundo,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: _search,
          onSearchChanged: (value) => setState(() => _search = value),
          userName: '',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.task_alt_rounded,
                    color: CoresApp.destaque, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tarefas Executadas',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (_filter == 'Período' &&
                    _startDate != null &&
                    _endDate != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: CoresApp.primaria.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_formatShortDate(_startDate!)} até ${_formatShortDate(_endDate!)}',
                          style: const TextStyle(
                              color: CoresApp.secundaria,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => setState(() {
                            _filter = 'Todas';
                            _startDate = null;
                            _endDate = null;
                          }),
                          child: const Icon(Icons.close_rounded,
                              color: CoresApp.secundaria, size: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  tooltip: 'Gerar PDF com opções de filtro',
                  style: IconButton.styleFrom(
                    backgroundColor: CoresApp.superficie,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: CoresApp.borda),
                    ),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_rounded,
                      color: CoresApp.destaque, size: 20),
                  onPressed: widget.timeLogStore.logs.isEmpty
                      ? null
                      : () => _abrirModalFiltroPdf(),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: CoresApp.superficie,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CoresApp.borda),
                  ),
                  child: Text(
                    '${logs.length} cadastrada(s)',
                    style: const TextStyle(
                      color: CoresApp.destaque,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: CoresApp.textoPrincipal),
                    decoration: InputDecoration(
                      hintText: 'Buscar tarefa, projeto ou ID...',
                      hintStyle:
                          const TextStyle(color: CoresApp.textoSecundario),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: CoresApp.textoSecundario, size: 20),
                      filled: true,
                      fillColor: CoresApp.superficie,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: CoresApp.borda),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: CoresApp.borda),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: CoresApp.primaria),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: CoresApp.superficie,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CoresApp.borda),
                    ),
                    child: DropdownButton<String>(
                      value: _filter == 'Período' ? 'Todas' : _filter,
                      dropdownColor: CoresApp.superficie,
                      style: const TextStyle(
                          color: CoresApp.textoPrincipal, fontSize: 14),
                      items: const [
                        DropdownMenuItem(value: 'Todas', child: Text('Todas')),
                        DropdownMenuItem(value: 'Hoje', child: Text('Hoje')),
                        DropdownMenuItem(
                            value: 'Esta semana', child: Text('Esta semana')),
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
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Filtrar por Período (Intervalo de Datas)',
                  style: IconButton.styleFrom(
                    backgroundColor: CoresApp.superficie,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: CoresApp.borda),
                    ),
                  ),
                  icon: const Icon(Icons.date_range_rounded,
                      color: CoresApp.destaque, size: 22),
                  onPressed: () => _pickDateRange(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CoresApp.superficie,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CoresApp.borda.withOpacity(0.6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: logs.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhum apontamento cadastrado encontrado.',
                          style: TextStyle(
                              color: CoresApp.textoSecundario, fontSize: 14),
                        ),
                      )
                    : GridView.builder(
                        itemCount: logs.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 5.5,
                        ),
                        itemBuilder: (context, index) {
                          final log = logs[index];

                          return Container(
                            key: ValueKey(log.id),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: CoresApp.fundo,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: CoresApp.borda.withOpacity(0.4)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: CoresApp.sucesso.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.check_circle_rounded,
                                      color: CoresApp.sucesso, size: 15),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  log.taskName ?? log.targetId,
                                  style: const TextStyle(
                                    color: CoresApp.textoPrincipal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${log.projectName ?? 'Projeto não identificado'} • ${_date(log)} • ${log.startTime} - ${log.endTime}',
                                        style: const TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 10),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        log.description?.isNotEmpty == true
                                            ? log.description!
                                            : 'Descritivo',
                                        style: TextStyle(
                                          color: log.description?.isNotEmpty ==
                                                  true
                                              ? CoresApp.textoPrincipal
                                              : CoresApp.textoFraco,
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: CoresApp.primaria.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color:
                                            CoresApp.primaria.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    log.durationFormatted,
                                    style: const TextStyle(
                                      color: CoresApp.secundaria,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Editar registro e horários',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: const Icon(Icons.edit_outlined,
                                      color: CoresApp.secundaria, size: 15),
                                  onPressed: () => _abrirModalEdicao(log),
                                ),
                                IconButton(
                                  tooltip: 'Excluir registro',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  icon: const Icon(Icons.delete_outline,
                                      color: CoresApp.erro, size: 15),
                                  onPressed: () async {
                                    if (log.id != null && log.id!.isNotEmpty) {
                                      await widget.timeLogStore
                                          .deleteFirebaseLog(log);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on TimeLog {
  String get dateFormatted =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
