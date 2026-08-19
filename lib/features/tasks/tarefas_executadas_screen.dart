import 'package:flutter/material.dart';
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
              primary: Colors.cyanAccent,
              onPrimary: Colors.black,
              surface: Color(0xFF1A1A2E),
              onSurface: Colors.white,
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
          log.dateFormatted.contains(query);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  String _date(TimeLog log) =>
      '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year.toString().substring(2)}';

  String _formatShortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final logs = _registeredLogs;
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Cabecalho(
          selectedIndex: widget.selectedIndex,
          onSelectTab: widget.onSelectTab,
          searchQuery: _search,
          onSearchChanged: (value) => setState(() => _search = value),
          userName: '',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.task_alt, color: Colors.cyanAccent, size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tarefas Executadas',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                if (_filter == 'Período' &&
                    _startDate != null &&
                    _endDate != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_formatShortDate(_startDate!)} até ${_formatShortDate(_endDate!)}',
                          style: const TextStyle(
                              color: Colors.cyanAccent,
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
                          child: const Icon(Icons.close,
                              color: Colors.cyanAccent, size: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.cyanAccent.withOpacity(0.25)),
                  ),
                  child: Text('${logs.length} cadastrada(s)',
                      style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar tarefa, projeto ou ID...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF151522),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF151522),
                        borderRadius: BorderRadius.circular(10)),
                    child: DropdownButton<String>(
                      value: _filter == 'Período' ? 'Todas' : _filter,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Colors.white),
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
                    backgroundColor: const Color(0xFF151522),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.white.withOpacity(0.06)),
                    ),
                  ),
                  icon: const Icon(Icons.date_range,
                      color: Colors.cyanAccent, size: 22),
                  onPressed: () => _pickDateRange(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF151522),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: logs.isEmpty
                    ? const Center(
                        child: Text('Nenhum apontamento cadastrado encontrado.',
                            style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => Divider(
                            color: Colors.white.withOpacity(0.05), height: 1),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.check_circle,
                                  color: Colors.greenAccent),
                            ),
                            title: Text(log.taskName ?? log.targetId,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${log.projectName ?? 'Projeto não identificado'}  •  ${_date(log)}  •  ${log.startTime} - ${log.endTime}',
                                style: const TextStyle(color: Colors.white54)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(log.durationFormatted,
                                    style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.cloud_upload,
                                      color: Colors.cyanAccent, size: 20),
                                  tooltip: 'Enviar para o Banco de Dados',
                                  onPressed: () async {
                                    try {
                                      await _firebaseService
                                          .saveCompletedProject(
                                        log.id,
                                        {
                                          'name': log.projectName ??
                                              'Projeto não identificado',
                                          'titulo':
                                              log.taskName ?? log.targetId,
                                          'description':
                                              'Data: ${_date(log)} | Horário: ${log.startTime} - ${log.endTime} | Duração: ${log.durationFormatted}',
                                          'date': log.date.toIso8601String(),
                                          'duration': log.durationFormatted,
                                        },
                                      );

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Tarefa enviada para o banco de dados com sucesso!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text('Erro ao enviar: $e'),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
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
