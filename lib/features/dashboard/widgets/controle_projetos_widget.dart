import 'dart:async';

import 'package:flutter/material.dart';

class ControleProjetosWidget extends StatefulWidget {
  final bool agrupar;
  final bool ordenarPrioridade;
  final bool somenteAtivos;
  final bool filtroAtivo;

// Tipo de serviço selecionado
  final String tipoServicoSelecionado;

// Lista dinâmica vinda do cadastro de trabalho
  final List<String> tiposServicoOpcoes;

// Período
  final DateTime? dataInicio;
  final DateTime? dataFim;

  final Set<String>? expandedProjectIds;

  final VoidCallback onNewProject;
  final VoidCallback onSynchronize;
  final VoidCallback onFilter;
  final VoidCallback onManual;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback? onFolder;

  final ValueChanged<bool?> onAgruparChanged;
  final ValueChanged<bool?> onOrdenarPrioridadeChanged;
  final ValueChanged<bool?> onSomenteAtivosChanged;

// Callbacks dos filtros
  final ValueChanged<String?> onTipoServicoChanged;
  final ValueChanged<DateTime?> onDataInicioChanged;
  final ValueChanged<DateTime?> onDataFimChanged;

  const ControleProjetosWidget({
    super.key,
    required this.agrupar,
    required this.ordenarPrioridade,
    required this.somenteAtivos,
    required this.filtroAtivo,
    required this.tipoServicoSelecionado,
    required this.tiposServicoOpcoes,
    this.dataInicio,
    this.dataFim,
    this.expandedProjectIds,
    required this.onNewProject,
    required this.onSynchronize,
    required this.onFilter,
    required this.onManual,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    this.onFolder,
    required this.onAgruparChanged,
    required this.onOrdenarPrioridadeChanged,
    required this.onSomenteAtivosChanged,
    required this.onTipoServicoChanged,
    required this.onDataInicioChanged,
    required this.onDataFimChanged,

// Mantidos para compatibilidade com a chamada existente.
    required String filtroProjetos,
    required Null Function(String? value) onFiltroProjetosChanged,
  });

  @override
  State<ControleProjetosWidget> createState() => _ControleProjetosWidgetState();
}

class _ControleProjetosWidgetState extends State<ControleProjetosWidget> {
  late Timer _timer;
  late DateTime _now;

// Mantém a resposta visual imediata do dropdown.
  late String _tipoServicoLocal;

  static const Color _background = Color(0xFF1B1B2A);
  static const Color _fieldBackground = Color(0xFF101019);
  static const Color _buttonBackground = Color(0xFF3B3B4D);
  static const Color _green = Color(0xFF35D27F);
  static const Color _yellow = Color(0xFFFFC400);
  static const Color _textPrimary = Color(0xFFE5E5EA);
  static const Color _textSecondary = Color(0xFFBDBDC7);

  @override
  void initState() {
    super.initState();

    _now = DateTime.now();
    _tipoServicoLocal = widget.tipoServicoSelecionado;

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) return;

        setState(() {
          _now = DateTime.now();
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant ControleProjetosWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.tipoServicoSelecionado != _tipoServicoLocal) {
      _tipoServicoLocal = widget.tipoServicoSelecionado;
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

// ==============================================================
// FORMATAÇÃO
// ==============================================================

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatClock(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
  }

// ==============================================================
// SELEÇÃO DE DATA
// ==============================================================

  Future<void> _selecionarData(
    BuildContext context,
    bool isInicio,
  ) async {
    final DateTime initialDate =
        (isInicio ? widget.dataInicio : widget.dataFim) ?? DateTime.now();

    int diaTemp = initialDate.day;
    int mesTemp = initialDate.month;
    int anoTemp = initialDate.year;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: _background,
              elevation: 18,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.calendar_today_outlined,
                      color: _green,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isInicio
                          ? 'Selecionar Data Inicial'
                          : 'Selecionar Data Final',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 300,
                height: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // DIA
                    Expanded(
                      child: _dateDropdown(
                        label: 'Dia',
                        value: diaTemp,
                        items: List.generate(
                          31,
                          (index) => index + 1,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setStateDialog(() {
                              diaTemp = value;
                            });
                          }
                        },
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: Text(
                        '/',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // MÊS
                    Expanded(
                      child: _dateDropdown(
                        label: 'Mês',
                        value: mesTemp,
                        items: List.generate(
                          12,
                          (index) => index + 1,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setStateDialog(() {
                              mesTemp = value;
                            });
                          }
                        },
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: Text(
                        '/',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // ANO
                    Expanded(
                      child: _dateDropdown(
                        label: 'Ano',
                        value: anoTemp,
                        items: List.generate(
                          16,
                          (index) => 2020 + index,
                        ),
                        onChanged: (value) {
                          if (value != null) {
                            setStateDialog(() {
                              anoTemp = value;
                            });
                          }
                        },
                        formatValue: (value) => value.toString(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(null);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: _textSecondary,
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    try {
                      final novaData = DateTime(
                        anoTemp,
                        mesTemp,
                        diaTemp,
                      );

                      Navigator.of(dialogContext).pop(novaData);
                    } catch (_) {
                      Navigator.of(dialogContext).pop(null);
                    }
                  },
                  child: const Text(
                    'Confirmar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null) {
      if (isInicio) {
        widget.onDataInicioChanged(picked);
      } else {
        widget.onDataFimChanged(picked);
      }

      widget.onFilter();
    }
  }

// ==============================================================
// DROPDOWN DE DATA DO MODAL
// ==============================================================

  Widget _dateDropdown({
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int?> onChanged,
    String Function(int value)? formatValue,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        DropdownButton<int>(
          value: value,
          dropdownColor: _background,
          underline: const SizedBox.shrink(),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: _textSecondary,
            size: 16,
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          items: items.map((item) {
            return DropdownMenuItem<int>(
              value: item,
              child: Text(
                formatValue?.call(item) ?? item.toString().padLeft(2, '0'),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

// ==============================================================
// BUILD
// ==============================================================

  @override
  Widget build(BuildContext context) {
    final List<String> listaServicos = [
      'Todos os Serviços',
      ...widget.tiposServicoOpcoes.where(
        (item) => item != 'Todos os Serviços',
      ),
    ];

    if (!listaServicos.contains(_tipoServicoLocal)) {
      _tipoServicoLocal =
          listaServicos.isNotEmpty ? listaServicos.first : 'Todos os Serviços';
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========================================================
          // DATA + RELÓGIO
          // ========================================================

          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: _fieldBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Container(
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.calendar_today_outlined,
                          color: _green,
                          size: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _formatDate(_now),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(
                          color: _yellow.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.access_time,
                          color: _yellow,
                          size: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _formatClock(_now),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ========================================================
          // TÍTULO + LIMPAR
          // ========================================================

          Row(
            children: [
              const Icon(
                Icons.tune,
                color: _textSecondary,
                size: 13,
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'Filtrar Projetos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
              if (widget.filtroAtivo)
                InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () {
                    setState(() {
                      _tipoServicoLocal = 'Todos os Serviços';
                    });

                    widget.onTipoServicoChanged(
                      'Todos os Serviços',
                    );

                    widget.onDataInicioChanged(null);
                    widget.onDataFimChanged(null);

                    widget.onFilter();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      'Limpar',
                      style: TextStyle(
                        color: _green,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 4),

          // ========================================================
          // FILTRO: TIPO DE SERVIÇO
          // ========================================================

          _dropdown<String>(
            value: _tipoServicoLocal,
            items: listaServicos.map((tipo) {
              return DropdownMenuItem<String>(
                value: tipo,
                child: Text(
                  tipo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;

              setState(() {
                _tipoServicoLocal = value;
              });

              widget.onTipoServicoChanged(value);
              widget.onFilter();
            },
          ),

          const SizedBox(height: 4),

          // ========================================================
          // FILTRO POR PERÍODO
          // ========================================================

          Row(
            children: [
              Expanded(
                child: _dataField(
                  label: widget.dataInicio != null
                      ? _formatDate(widget.dataInicio!)
                      : 'Data Inicial',
                  onTap: () => _selecionarData(
                    context,
                    true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _dataField(
                  label: widget.dataFim != null
                      ? _formatDate(widget.dataFim!)
                      : 'Data Final',
                  onTap: () => _selecionarData(
                    context,
                    false,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ========================================================
          // BOTÕES
          // ========================================================

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ElevatedButton.icon(
                    onPressed: widget.onNewProject,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _buttonBackground,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(
                      Icons.add,
                      size: 15,
                    ),
                    label: const Flexible(
                      child: Text(
                        'Novo Trabalho',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 30,
                height: 30,
                child: IconButton(
                  onPressed: () {
                    widget.expandedProjectIds?.clear();
                    widget.onSynchronize();
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: _buttonBackground,
                    foregroundColor: _textSecondary,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(
                    Icons.sync,
                    size: 15,
                  ),
                  tooltip: 'Sincronizar',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

// ==============================================================
// DROPDOWN PRINCIPAL
// ==============================================================

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _fieldBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: _background,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: _textSecondary,
            size: 17,
          ),
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

// ==============================================================
// CAMPO DE DATA
// ==============================================================

  Widget _dataField({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: _fieldBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textPrimary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.calendar_today_outlined,
              color: _textSecondary,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
