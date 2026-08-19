import 'dart:async';

import 'package:flutter/material.dart';

class ControleProjetosWidget extends StatefulWidget {
  final bool agrupar;
  final bool ordenarPrioridade;
  final bool somenteAtivos;
  final bool filtroAtivo;
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

  const ControleProjetosWidget({
    super.key,
    required this.agrupar,
    required this.ordenarPrioridade,
    required this.somenteAtivos,
    required this.filtroAtivo,
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
  });

  @override
  State<ControleProjetosWidget> createState() => _ControleProjetosWidgetState();

  void somenteAtivosChanged(bool bool) {}
}

class _ControleProjetosWidgetState extends State<ControleProjetosWidget> {
  late Timer _timer;
  late DateTime _now;

  // Lista de tipos de horas solicitada
  final List<String> _tiposHsOpcoes = const [
    'Todos os Tipos',
    'Horas Cobradas',
    'Horas Investimento',
    'Horas Não Cobradas',
    'Horas Internas',
    'Outras',
    'Horas Não Informadas',
  ];

  String _tipoSelecionado = 'Todos os Tipos';

  @override
  void initState() {
    super.initState();

    _now = DateTime.now();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (mounted) {
          setState(() {
            _now = DateTime.now();
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        10,
        8,
        10,
        6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========================================================
          // DATA + RELÓGIO
          // ========================================================
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF101019),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.16),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: Color(0xFF35D27F),
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _formatDate(_now),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Color(0xFFFFC400),
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _formatClock(_now),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // ========================================================
          // TÍTULO
          // ========================================================
          const Text(
            'Filtrar Projetos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),

          const SizedBox(height: 4),

          // ========================================================
          // PROJETOS ATIVOS
          // ========================================================
          _dropdown<String>(
            value:
                widget.somenteAtivos ? 'Projetos Ativos' : 'Todos os Projetos',
            items: const [
              DropdownMenuItem(
                value: 'Projetos Ativos',
                child: Text('Projetos Ativos'),
              ),
              DropdownMenuItem(
                value: 'Todos os Projetos',
                child: Text('Todos os Projetos'),
              ),
            ],
            onChanged: (value) {
              widget.onSomenteAtivosChanged(
                value == 'Projetos Ativos',
              );
            },
          ),

          const SizedBox(height: 4),

          // ========================================================
          // TIPO DE HORAS (ATUALIZADO)
          // ========================================================
          _dropdown<String>(
            value: _tiposHsOpcoes.contains(_tipoSelecionado)
                ? _tipoSelecionado
                : 'Todos os Tipos',
            items: _tiposHsOpcoes.map((tipo) {
              return DropdownMenuItem<String>(
                value: tipo,
                child: Text(
                  tipo,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _tipoSelecionado = value;
                });
                widget.onFilter();
              }
            },
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
                      backgroundColor: const Color(0xFF3B3B4D),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(
                      Icons.add,
                      size: 15,
                    ),
                    label: const Text(
                      'Novo Trabalho',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
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
                    backgroundColor: const Color(0xFF3B3B4D),
                    foregroundColor: const Color(0xFFB8B8C4),
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

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF101019),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.16),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: const Color(0xFF1B1B2A),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFFBDBDC7),
            size: 17,
          ),
          style: const TextStyle(
            color: Color(0xFFE5E5EA),
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
