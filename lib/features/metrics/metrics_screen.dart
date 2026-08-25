import 'package:flutter/material.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class MetricsScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final TimeLogStore timeLogStore;
  final String userName;

  const MetricsScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.timeLogStore,
    required this.userName,
  });

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  final List<String> _meses = const [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  late TextEditingController _horasDiaController;
  late TextEditingController _dataInicioController;

  late List<int> _diasUteisCalculados;
  late List<TextEditingController> _metaControllers;
  late List<TextEditingController> _cobradasControllers;
  late List<TextEditingController> _investimentoControllers;
  late List<TextEditingController> _naoCobradasControllers;
  late List<TextEditingController> _internasControllers;
  late List<TextEditingController> _outrasControllers;
  late List<TextEditingController> _naoInformadasControllers;

  bool _isLoadingFirebase = true;

  Color _metaColor = CoresApp.secundaria;
  Color _realizadoColor = CoresDashboard.graficoProjetos;

  final List<Color> _paletaCores = const [
    CoresApp.primaria,
    CoresApp.secundaria,
    CoresApp.sucesso,
    CoresApp.aviso,
    CoresApp.erro,
    CoresDashboard.graficoHoras,
    CoresDashboard.graficoProjetos,
    CoresDashboard.graficoConcluidos,
    CoresDashboard.graficoAtrasados,
    CoresDashboard.graficoAndamento,
    CoresApp.destaqueAmarelo,
    CoresApp.destaqueVerde,
  ];

  @override
  void initState() {
    super.initState();

    _dataInicioController = TextEditingController(text: '01/01/2026');

    _horasDiaController = TextEditingController(text: '08:20');

    _diasUteisCalculados = List.generate(12, (i) => 0);

    _recalcularDiasUteis();

    final metasIniciais = [
      '110:00',
      '120:00',
      '137:00',
      '125:00',
      '128:00',
      '128:00',
      '147:00',
      '134:00',
      '134:00',
      '134:00',
      '122:00',
      '90:00',
    ];

    _metaControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: metasIniciais[i],
      ),
    );

    _cobradasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Cobradas',
        ),
      ),
    );

    _investimentoControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Investimento',
        ),
      ),
    );

    _naoCobradasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Não cobradas',
        ),
      ),
    );

    _internasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Internas',
        ),
      ),
    );

    _outrasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Outras',
        ),
      ),
    );

    _naoInformadasControllers = List.generate(
      12,
      (i) => TextEditingController(
        text: _calcularHorasPorTipo(
          i + 1,
          'Hs Não Informadas',
        ),
      ),
    );

    widget.timeLogStore.addListener(
      _atualizarValoresComLogs,
    );

    _carregarMetasDoFirebase();
  }

  Future<void> _carregarMetasDoFirebase() async {
    try {
      final metasMap = await widget.timeLogStore.carregarMetasAnuais(2026);

      if (metasMap != null && mounted) {
        setState(() {
          for (int i = 0; i < 12; i++) {
            final mesKey = (i + 1).toString();

            final valorSalvo = metasMap[mesKey]?.toString();

            if (valorSalvo != null && valorSalvo.isNotEmpty) {
              _metaControllers[i].text = valorSalvo;
            }
          }
        });
      }
    } catch (e) {
      debugPrint(
        'Erro ao carregar metas do Firebase: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFirebase = false;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.timeLogStore.removeListener(
      _atualizarValoresComLogs,
    );

    _dataInicioController.dispose();
    _horasDiaController.dispose();

    for (int i = 0; i < 12; i++) {
      _metaControllers[i].dispose();
      _cobradasControllers[i].dispose();
      _investimentoControllers[i].dispose();
      _naoCobradasControllers[i].dispose();
      _internasControllers[i].dispose();
      _outrasControllers[i].dispose();
      _naoInformadasControllers[i].dispose();
    }

    super.dispose();
  }

  void _atualizarValoresComLogs() {
    if (!mounted) return;

    setState(() {
      for (int i = 1; i <= 12; i++) {
        _cobradasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Cobradas',
        );

        _investimentoControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Investimento',
        );

        _naoCobradasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Não cobradas',
        );

        _internasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Internas',
        );

        _outrasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Outras',
        );

        _naoInformadasControllers[i - 1].text = _calcularHorasPorTipo(
          i,
          'Hs Não Informadas',
        );
      }
    });
  }

  String _calcularHorasPorTipo(
    int mes,
    String tipoHs,
  ) {
    double totalHoras = 0.0;

    for (var log in widget.timeLogStore.logs) {
      if (log.date.month == mes && log.date.year == 2026) {
        String? rawType;

        try {
          rawType = (log as dynamic).hourType ??
              (log as dynamic).typeHs ??
              (log as dynamic).type ??
              (log as dynamic).tipo ??
              (log as dynamic).category;
        } catch (_) {
          rawType = log.typeHs;
        }

        final logType = (rawType ?? '').trim().toLowerCase();

        final targetType = tipoHs.trim().toLowerCase();

        bool match = false;

        String normalize(String s) => s
            .toLowerCase()
            .replaceAll('horas', 'h')
            .replaceAll('hs', 'h')
            .replaceAll('á', 'a')
            .replaceAll('ã', 'a')
            .replaceAll('é', 'e')
            .replaceAll('í', 'i')
            .replaceAll('ó', 'o')
            .replaceAll('ú', 'u')
            .replaceAll('ç', 'c')
            .replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );

        final normLog = normalize(logType);
        final normTarget = normalize(targetType);

        if (normLog.isEmpty) {
          if (normTarget.contains('informadas')) {
            match = true;
          }
        } else {
          if (normTarget.contains('cobradas') && !normTarget.contains('nao')) {
            if (normLog.contains('cobradas') && !normLog.contains('nao')) {
              match = true;
            }
          } else if (normTarget.contains('naocobradas')) {
            if (normLog.contains('naocobradas') ||
                normLog.contains('naocobrada')) {
              match = true;
            }
          } else if (normTarget.contains('investimento')) {
            if (normLog.contains('investimento')) {
              match = true;
            }
          } else if (normTarget.contains('internas')) {
            if (normLog.contains('internas') || normLog.contains('interna')) {
              match = true;
            }
          } else if (normTarget.contains('outras')) {
            if (normLog.contains('outras') || normLog.contains('outra')) {
              match = true;
            }
          } else if (normTarget.contains('informadas')) {
            if (normLog.contains('informadas') ||
                normLog.contains('desconhecido')) {
              match = true;
            }
          }
        }

        if (match) {
          totalHoras += _parseTimeToDouble(
            log.durationFormatted,
          );
        }
      }
    }

    return _formatDoubleToTime(totalHoras);
  }

  void _recalcularDiasUteis() {
    int ano = 2026;

    try {
      final parts = _dataInicioController.text.split('/');

      if (parts.length == 3) {
        ano = int.parse(parts[2]);
      }
    } catch (_) {}

    for (int month = 1; month <= 12; month++) {
      _diasUteisCalculados[month - 1] = _calcularDiasUteis(ano, month);
    }
  }

  int _calcularDiasUteis(
    int year,
    int month,
  ) {
    final totalDays = DateTime(year, month + 1, 0).day;

    int count = 0;

    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(year, month, day);

      if (date.weekday != DateTime.saturday &&
          date.weekday != DateTime.sunday) {
        count++;
      }
    }

    return count;
  }

  double _parseTimeToDouble(
    String timeStr,
  ) {
    try {
      final parts = timeStr.split(':');

      final hours = double.parse(parts[0]);

      final minutes = parts.length > 1 ? double.parse(parts[1]) / 60 : 0.0;

      return hours + minutes;
    } catch (_) {
      return 0.0;
    }
  }

  double _getRealizadoSum(int index) {
    return _parseTimeToDouble(
          _cobradasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _investimentoControllers[index].text,
        ) +
        _parseTimeToDouble(
          _naoCobradasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _internasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _outrasControllers[index].text,
        ) +
        _parseTimeToDouble(
          _naoInformadasControllers[index].text,
        );
  }

  String _formatDoubleToTime(
    double value,
  ) {
    final hours = value.floor();

    final minutes = ((value - hours) * 60).round();

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFirebase) {
      return const Scaffold(
        backgroundColor: CoresDashboard.fundo,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: CoresDashboard.fundo,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: '',
          onSearchChanged: (val) {},
          userName: widget.userName,
        ),
      ),
      body: Stack(
        children: [
          // ========================================================
          // FUNDO DO APLICATIVO
          // ========================================================
          Positioned.fill(
            child: Image.asset(
              AppTheme.caminhoFundo,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: CoresDashboard.fundo,
                );
              },
            ),
          ),

          // ========================================================
          // CAMADA DE PROTEÇÃO PARA MANTER A LEITURA
          // ========================================================
          Positioned.fill(
            child: Container(
              color: CoresApp.fundo.withOpacity(0.72),
            ),
          ),

          // ========================================================
          // CONTEÚDO
          // ========================================================
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CoresDashboard.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Meta vs Horas Realizadas (2026)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: CoresApp.textoPrincipal,
                            ),
                          ),
                          Row(
                            children: [
                              _buildLegendItem(
                                'Meta',
                                _metaColor,
                              ),
                              const SizedBox(
                                width: 20,
                              ),
                              _buildLegendItem(
                                'Realizado',
                                _realizadoColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const double maxValor = 200.0;

                            final double availableHeight =
                                constraints.maxHeight - 30;

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  flex: 16,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Cor da Meta:',
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 2,
                                      ),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: _paletaCores.map(
                                          (color) {
                                            final isSelected =
                                                _metaColor == color;

                                            return GestureDetector(
                                              onTap: () => setState(
                                                () => _metaColor = color,
                                              ),
                                              child: Container(
                                                width: 17,
                                                height: 17,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  border: isSelected
                                                      ? Border.all(
                                                          color: Colors.white,
                                                          width: 2,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                            );
                                          },
                                        ).toList(),
                                      ),
                                      const SizedBox(
                                        height: 6,
                                      ),
                                      Text(
                                        'Cor do Realizado:',
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 2,
                                      ),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: _paletaCores.map(
                                          (color) {
                                            final isSelected =
                                                _realizadoColor == color;

                                            return GestureDetector(
                                              onTap: () => setState(
                                                () => _realizadoColor = color,
                                              ),
                                              child: Container(
                                                width: 17,
                                                height: 17,
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle,
                                                  border: isSelected
                                                      ? Border.all(
                                                          color: Colors.white,
                                                          width: 2,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                            );
                                          },
                                        ).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                                const Expanded(
                                  flex: 8,
                                  child: SizedBox(),
                                ),
                                ...List.generate(
                                  12,
                                  (index) {
                                    final metaVal = _parseTimeToDouble(
                                      _metaControllers[index].text,
                                    );

                                    final realizadoVal = _getRealizadoSum(
                                      index,
                                    );

                                    final realizadoText = _formatDoubleToTime(
                                      realizadoVal,
                                    );

                                    final double metaH =
                                        (metaVal / maxValor) * availableHeight;

                                    final double realizadoH =
                                        (realizadoVal / maxValor) *
                                            availableHeight;

                                    return Expanded(
                                      flex: 10,
                                      child: Tooltip(
                                        message:
                                            '${_meses[index].toUpperCase()}\n'
                                            'Meta: ${_metaControllers[index].text}h\n'
                                            'Realizado: ${realizadoText}h',
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    if (metaVal > 0)
                                                      Text(
                                                        _metaControllers[index]
                                                            .text,
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: CoresApp
                                                              .textoPrincipal,
                                                        ),
                                                      ),
                                                    const SizedBox(
                                                      height: 2,
                                                    ),
                                                    Container(
                                                      width: 18,
                                                      height:
                                                          metaH > 0 ? metaH : 3,
                                                      decoration: BoxDecoration(
                                                        color: _metaColor,
                                                        borderRadius:
                                                            const BorderRadius
                                                                .vertical(
                                                          top: Radius.circular(
                                                              4),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(
                                                  width: 2,
                                                ),
                                                Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    if (realizadoVal > 0)
                                                      Text(
                                                        realizadoText,
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: CoresApp
                                                              .textoSecundario,
                                                        ),
                                                      ),
                                                    const SizedBox(
                                                      height: 2,
                                                    ),
                                                    Container(
                                                      width: 18,
                                                      height: realizadoH > 0
                                                          ? realizadoH
                                                          : 3,
                                                      decoration: BoxDecoration(
                                                        color: _realizadoColor,
                                                        borderRadius:
                                                            const BorderRadius
                                                                .vertical(
                                                          top: Radius.circular(
                                                              4),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(
                                              height: 4,
                                            ),
                                            Text(
                                              _meses[index],
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: CoresApp.textoSecundario,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.8),
                      1: FlexColumnWidth(1.0),
                      2: FlexColumnWidth(1.0),
                      3: FlexColumnWidth(1.0),
                      4: FlexColumnWidth(1.0),
                      5: FlexColumnWidth(1.0),
                      6: FlexColumnWidth(1.0),
                      7: FlexColumnWidth(1.0),
                      8: FlexColumnWidth(1.0),
                      9: FlexColumnWidth(1.0),
                      10: FlexColumnWidth(1.0),
                      11: FlexColumnWidth(1.0),
                      12: FlexColumnWidth(1.0),
                      13: FlexColumnWidth(1.0),
                    },
                    border: TableBorder.all(
                      color: Colors.black12,
                      width: 1,
                    ),
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: CoresDashboard.cabecalhoTabela,
                        ),
                        children: [
                          _buildCellText(
                            'Data Início Ano',
                            isHeader: true,
                            color: Colors.white,
                          ),
                          _buildCellInput(
                            _horasDiaController,
                            isHeader: true,
                            bgColor: const Color(
                              0xFFFFF2CC,
                            ),
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellText(
                              _meses[i],
                              isHeader: true,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        decoration: BoxDecoration(
                          color: CoresDashboard.cabecalhoTabela,
                        ),
                        children: [
                          _buildCellInput(
                            _dataInicioController,
                            bgColor: const Color(
                              0xFFFFF2CC,
                            ),
                            onChanged: (_) {
                              _recalcularDiasUteis();
                              setState(() {});
                            },
                          ),
                          _buildCellText(
                            '',
                            isHeader: true,
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellText(
                              '${i + 1}',
                              isHeader: true,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Dias Úteis',
                            alignLeft: true,
                          ),
                          _buildCellText(
                            '${_diasUteisCalculados.fold<int>(0, (sum, val) => sum + val)}',
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellText(
                              '${_diasUteisCalculados[i]}',
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFF2CC),
                        ),
                        children: [
                          _buildCellText(
                            'Meta',
                            alignLeft: true,
                            isBold: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              _metaControllers.fold<double>(
                                0,
                                (sum, item) =>
                                    sum +
                                    _parseTimeToDouble(
                                      item.text,
                                    ),
                              ),
                            ),
                            isBold: true,
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellInput(
                              _metaControllers[i],
                              isBold: true,
                              onChanged: (val) {
                                final mesKey = (i + 1).toString();

                                widget.timeLogStore.salvarMetaMensal(
                                  2026,
                                  mesKey,
                                  val,
                                );

                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Hs Totais Realizadas',
                            alignLeft: true,
                            isBold: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              List.generate(
                                12,
                                (i) => _getRealizadoSum(
                                  i,
                                ),
                              ).reduce(
                                (a, b) => a + b,
                              ),
                            ),
                            isBold: true,
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellText(
                              _formatDoubleToTime(
                                _getRealizadoSum(
                                  i,
                                ),
                              ),
                              isBold: true,
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Hs Cobradas',
                            alignLeft: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              _cobradasControllers.fold<double>(
                                0,
                                (sum, item) =>
                                    sum +
                                    _parseTimeToDouble(
                                      item.text,
                                    ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellInput(
                              _cobradasControllers[i],
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Hs Investimento',
                            alignLeft: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              _investimentoControllers.fold<double>(
                                0,
                                (sum, item) =>
                                    sum +
                                    _parseTimeToDouble(
                                      item.text,
                                    ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellInput(
                              _investimentoControllers[i],
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Hs Não cobradas',
                            alignLeft: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              _naoCobradasControllers.fold<double>(
                                0,
                                (sum, item) =>
                                    sum +
                                    _parseTimeToDouble(
                                      item.text,
                                    ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellInput(
                              _naoCobradasControllers[i],
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Hs Internas',
                            alignLeft: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              _internasControllers.fold<double>(
                                0,
                                (sum, item) =>
                                    sum +
                                    _parseTimeToDouble(
                                      item.text,
                                    ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellInput(
                              _internasControllers[i],
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Outras',
                            alignLeft: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              _outrasControllers.fold<double>(
                                0,
                                (sum, item) =>
                                    sum +
                                    _parseTimeToDouble(
                                      item.text,
                                    ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellInput(
                              _outrasControllers[i],
                            ),
                          ),
                        ],
                      ),
                      TableRow(
                        children: [
                          _buildCellText(
                            'Hs Não Informadas',
                            alignLeft: true,
                          ),
                          _buildCellText(
                            _formatDoubleToTime(
                              _naoInformadasControllers.fold<double>(
                                0,
                                (sum, item) =>
                                    sum +
                                    _parseTimeToDouble(
                                      item.text,
                                    ),
                              ),
                            ),
                          ),
                          ...List.generate(
                            12,
                            (i) => _buildCellInput(
                              _naoInformadasControllers[i],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCellText(
    String text, {
    bool isHeader = false,
    bool alignLeft = false,
    bool isBold = false,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 4,
      ),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? Colors.black87,
          fontSize: 11,
          fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildCellInput(
    TextEditingController controller, {
    bool isHeader = false,
    Color? bgColor,
    bool isBold = false,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(
        vertical: 2,
        horizontal: 2,
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? Colors.black : Colors.black87,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            vertical: 6,
          ),
        ),
        onChanged: (val) {
          if (onChanged != null) {
            onChanged(val);
          } else {
            setState(() {});
          }
        },
      ),
    );
  }

  Widget _buildLegendItem(
    String label,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: CoresApp.textoSecundario,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
