import 'package:gerenciador_horas/shared/widgets/redesign_components.dart';
import 'task_log_query.dart';
import 'task_log_search.dart';
import 'task_hours_filter.dart';
import 'task_work_picker.dart';
import 'task_filters_bar.dart';
import 'task_overview_header.dart';
import 'task_workspace_panel.dart';
import 'task_period_summary.dart';
import 'task_logs_table.dart';
import '../../data/services/firebase_service.dart';
import '../../domain/models/hours_overlap.dart';
import 'hours_send_selection.dart';
import '../assistant/beta_access.dart';
import 'task_history_month.dart';
import 'dart:async';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/domain/models/work_duration.dart';
import 'task_pdf_report.dart';
import 'task_log_edit_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_palette.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/edesk_python.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:printing/printing.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/data/services/edesk_credentials_service.dart';

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
  State<TarefasScreen> createState() => TarefasScreenState();
}

class TarefasScreenState extends State<TarefasScreen> {
  Future<String?> sendForBeta(List<TimeLog> logs) {
    final user = FirebaseAuth.instance.currentUser;
    if (!BetaAccess.allows(uid: user?.uid, email: user?.email))
      throw StateError('BETA indisponível para esta conta.');
    return _enviarHorasDireto(logs, reviewed: true);
  }

  String? _filterOwner;
  String _lastFilterState = '';
  final _searchController = TextEditingController();
  String _lastQueryPeriod = '';
  bool _loadingPeriod = false;
  Object? _periodError;
  int _periodGeneration = 0;
  bool _showHistory = true;
  bool _showPending = false;
  VoidCallback? _refreshHistoryDialog;
  final Set<String> _selectedLogs = {};
  void _applyQueryPeriod() {
    if (widget.selectedIndex != 5) return;
    final now = DateTime.now();
    DateTime? start, end;
    if (_filter == 'Hoje') {
      start = DateTime(now.year, now.month, now.day);
      end = start;
    }
    if (_filter == 'Esta semana') {
      start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      end = start.add(const Duration(days: 6));
    }
    if (_filter == 'Per\u00edodo') {
      start = _startDate;
      end = _endDate;
    }
    if (_filter == 'Todas') {
      final year = _anoHistoricoSelecionado ?? now.year;
      final month = _mesHistoricoSelecionado ?? now.month;
      if (_nivelHistoricoSelecionado == 'ano') {
        start = DateTime(year);
        end = DateTime(year, 12, 31);
      } else if (_nivelHistoricoSelecionado != 'todos') {
        // Keep the month's history available beside a selected day/week.
        start = DateTime(year, month);
        end = DateTime(year, month + 1, 0);
      }
    }
    final signature = '${start?.toIso8601String()}/${end?.toIso8601String()}';
    if (_lastQueryPeriod == signature) return;
    _lastQueryPeriod = signature;
    final generation = ++_periodGeneration;
    _loadingPeriod = true;
    _periodError = null;
    unawaited(widget.timeLogStore
        .setHistoryPeriod(start, end)
        .catchError((Object error) {
      if (mounted && generation == _periodGeneration) {
        super.setState(() => _periodError = error);
      }
    }).whenComplete(() {
      if (mounted && generation == _periodGeneration) {
        super.setState(() => _loadingPeriod = false);
      }
    }));
  }

  @override
  void didUpdateWidget(covariant TarefasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      if (widget.selectedIndex == 5) _selectToday();
      _lastQueryPeriod = '';
      _applyQueryPeriod();
    }
  }

  void _restoreFilters() {
    _filterOwner = FirebaseAuth.instance.currentUser?.uid;
    final data = LocalUserState.read(_filterOwner, 'filters.tasks');
    if (data == null) return;
    _filter = ['Todas', 'Hoje', 'Esta semana', 'Per\u00edodo']
            .contains(data['filter'])
        ? data['filter'] as String
        : 'Todas';
    _startDate = DateTime.tryParse(data['start']?.toString() ?? '');
    _endDate = DateTime.tryParse(data['end']?.toString() ?? '');
    if (_filter == 'Per\u00edodo' && (_startDate == null || _endDate == null))
      _filter = 'Todas';
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _applyQueryPeriod();
    if (_filterOwner == null ||
        FirebaseAuth.instance.currentUser?.uid != _filterOwner) return;
    final data = {
      'filter': _filter,
      'start': _startDate?.toIso8601String(),
      'end': _endDate?.toIso8601String()
    };
    final encoded = jsonEncode(data);
    if (encoded == _lastFilterState) return;
    _lastFilterState = encoded;
    LocalUserState.write(_filterOwner, 'filters.tasks', data);
  }

  void _clearFilters() => setState(() {
        _filter = 'Todas';
        _startDate = null;
        _endDate = null;
        _search = '';
        _hasProjectFilter = false;
        _projectFilterId = null;
        _projectRequests = {};
        _projectFilterLabel = null;
        _hoursFilter = TaskHoursFilter.all;
        _selectedLogs.clear();
        _searchController.clear();
      });

  bool _enviandoEdesk = false;

  bool _hasProjectFilter = false;
  bool _choosingProject = false;
  String? _projectFilterId;
  Set<String> _projectRequests = {};
  String? _projectFilterLabel;
  TaskHoursFilter _hoursFilter = TaskHoursFilter.all;
  String _search = '';
  String _filter = 'Todas';

  DateTime? _startDate;
  DateTime? _endDate;

  final Set<String> _semanasExpandidas = {};
  final Set<int> _anosExpandidos = {};
  final Set<String> _mesesExpandidos = {};
  DateTime? _diaSelecionado;
  String _nivelHistoricoSelecionado = 'mes';
  int? _anoHistoricoSelecionado;
  int? _mesHistoricoSelecionado;
  DateTime? _semanaHistoricoSelecionada;

  @override
  void initState() {
    super.initState();
    _restoreFilters();
    _selectToday();
    _applyQueryPeriod();
    widget.timeLogStore.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    widget.timeLogStore.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted && context.mounted) {
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
        AppAppearance.watch(context);
        return child!;
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

  List<TimeLog> _filteredRegisteredLogs({bool filterHours = true}) {
    final now = DateUtils.dateOnly(DateTime.now());
    DateTime? start, end;
    if (_filter == 'Hoje') {
      start = now;
      end = now;
    }
    if (_filter == 'Esta semana') {
      start = _weekStart(now);
      end = start.add(const Duration(days: 6));
    }
    if (_filter == 'Per\u00edodo') {
      start = _startDate;
      end = _endDate;
    }
    return filterTaskLogs(widget.timeLogStore.logs,
        search: _search,
        projectId: _hasProjectFilter ? _projectFilterId : null,
        projectRequests: _projectRequests,
        start: start,
        end: end,
        includePending: _showPending,
        billing: filterHours ? _hoursFilter : TaskHoursFilter.all);
  }

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

  String _formatarMinutos(int minutos) => WorkDuration.format(minutos);

  int _duracaoEmMinutos(TimeLog log) => WorkDuration.minutes(log);

  int _totalMinutos(List<TimeLog> logs) {
    int total = 0;

    for (final log in logs) {
      total += _duracaoEmMinutos(log);
    }

    return total;
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

  void _abrirModalDetalhesDia(
    String tituloData,
    String duracaoTotal,
    List<TimeLog> logsDoDia,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresApp.borda.withValues(alpha: 0.6),
            ),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CoresApp.primaria.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
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
                      style: TextStyle(
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
                      style: TextStyle(
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
                  color: CoresApp.primaria.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  duracaoTotal,
                  style: TextStyle(
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
                      color: CoresApp.borda.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CoresApp.primaria.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
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
                              style: TextStyle(
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
                                style: TextStyle(
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
                              style: TextStyle(
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
                        icon: Icon(
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
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: CoresApp.erro,
                          size: 18,
                        ),
                        onPressed: () async {
                          final excluido =
                              await _excluirApontamentoComConfirmacao(log);

                          if (excluido && mounted && context.mounted) {
                            Navigator.pop(context);
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
                foregroundColor: AppPalette.foregroundOn(CoresApp.fundo),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(
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
                        if (mounted && context.mounted) {
                          _enviarHorasDireto(logsDoDia);
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
                foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
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

  Future<String?> _enviarHorasDireto(List<TimeLog> logs,
      {bool reviewed = false}) async {
    if (_enviandoEdesk || logs.isEmpty) {
      if (reviewed) throw StateError('Há outro envio em andamento.');
      return null;
    }
    final sendOwner = FirebaseAuth.instance.currentUser?.uid;
    if (sendOwner == null) return null;
    setState(() => _enviandoEdesk = true);
    try {
      if (!reviewed) {
        final selection = await selectHoursForSend(context, logs,
            save: widget.timeLogStore.updateFirebaseLog,
            delete: widget.timeLogStore.deleteFirebaseLog,
            canSend: () =>
                mounted && FirebaseAuth.instance.currentUser?.uid == sendOwner);
        if (!mounted ||
            FirebaseAuth.instance.currentUser?.uid != sendOwner ||
            selection == null ||
            selection.isEmpty) return null;
        logs = selection;
      }
      logs = await verifyHoursForSend(logs,
          loadDay: widget.timeLogStore.loadRegisteredDay,
          authorized: () =>
              mounted && FirebaseAuth.instance.currentUser?.uid == sendOwner);
      final draftsSelecionados = logs
          .map((log) => _EdeskDraft(
                log: log,
                taskName: log.taskName ?? '',
                description: log.description ?? '',
                startTime: log.startTime,
                endTime: log.endTime,
              ))
          .toList();
      for (final draft in draftsSelecionados) {
        if (draft.taskName.trim().isEmpty ||
            draft.description.trim().isEmpty ||
            _calcularMinutos(draft.startTime, draft.endTime) <= 0) {
          throw EdeskException(
              'Revise a tarefa, o descritivo e o horário de ${_referenciaEdesk(draft.log)} antes de enviar.');
        }
      }
      final Map<String, List<_EdeskDraft>> grupos = {};

      for (final draft in draftsSelecionados) {
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

      final trabalhos = <Map<String, dynamic>>[];

      for (final grupo in grupos.values) {
        if (grupo.isEmpty) continue;

        final primeiro = grupo.first;

        final referencia = _extrairReferenciaEdesk(
          primeiro.log,
        );

        final solicitacao = referencia['solicitacao']!;
        final idTrabalho = referencia['idTrabalho']!;

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
            'tipo': _normalizarTipoEdesk(
              draft.log.typeHs,
            ),
            'tarefa': draft.taskName.trim(),
            'descricao': draft.description.trim(),
            'projeto': draft.log.projectName ?? '',
            'targetId': draft.log.targetId,
            'duracaoMinutos': minutos,
            'horas': minutos / 60.0,
          });
        }

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

      final credenciais = await EdeskCredentialsService().ler();

      if (!mounted || FirebaseAuth.instance.currentUser?.uid != sendOwner)
        return null;

      final payload = {
        'url': 'https://promob.e-desk.com.br',
        'enviar': true,
        'trabalhos': trabalhos,
        'edeskCredenciais': credenciais == null
            ? null
            : {
                'email': credenciais['email'],
                'senha': credenciais['senha'],
              },
      };

      final requestJson = jsonEncode(payload);

      final resultado = await executarPythonEdesk(
        requestJson: requestJson,
        enviar: true,
        script: 'edesk_horas.py',
      );

      if (resultado.statusCode == 499) {
        return null;
      }

      if (!resultado.confirmed) {
        throw EdeskException(
          resultado.message.isNotEmpty
              ? resultado.message
              : 'O Python não conseguiu '
                  'registrar as horas no E-Desk.',
        );
      }

      if (!mounted ||
          !context.mounted ||
          FirebaseAuth.instance.currentUser?.uid != sendOwner) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resultado.message),
        backgroundColor: CoresApp.primaria,
        duration: const Duration(seconds: 6),
      ));
      return resultado.message.isNotEmpty
          ? resultado.message
          : 'Envio concluído e confirmado no E-Desk.';
    } catch (e) {
      if (reviewed) rethrow;
      if (!mounted ||
          !context.mounted ||
          FirebaseAuth.instance.currentUser?.uid != sendOwner) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao enviar horas para o E-Desk: $e'),
        backgroundColor: CoresApp.erro,
        duration: const Duration(seconds: 8),
      ));
    } finally {
      if (mounted && context.mounted) setState(() => _enviandoEdesk = false);
    }
    return null;
  }

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

    if (RegExp(
      r'^\d{2}/\d{2}/\d{4}$',
    ).hasMatch(texto)) {
      return texto;
    }

    final iso = DateTime.tryParse(texto);

    if (iso != null) {
      return '${iso.day.toString().padLeft(2, '0')}/'
          '${iso.month.toString().padLeft(2, '0')}/'
          '${iso.year}';
    }

    return texto;
  }

  String _normalizarTipoEdesk(String? tipo) {
    final valor = tipo?.trim() ?? '';

    if (valor.isEmpty) {
      return '0';
    }

    if (RegExp(r'^\d+$').hasMatch(valor)) {
      return valor;
    }

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

  int _calcularMinutos(String inicio, String fim) {
    final start = WorkDuration.clock(inicio), end = WorkDuration.clock(fim);
    return start != null && end != null && end > start ? end - start : 0;
  }

  InputDecoration _edeskInputDecoration(
    String label,
  ) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(
          color: CoresApp.borda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(
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

  // Exclui um apontamento somente após confirmação do usuário.
  Future<bool> _excluirApontamentoComConfirmacao(TimeLog log) async {
    if (log.id.isEmpty) {
      return false;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          title: Text(
            'Excluir apontamento?',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Esta ação excluirá o apontamento do Firebase e não poderá ser desfeita.',
            style: TextStyle(color: CoresApp.textoSecundario),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Excluir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: AppPalette.foregroundOn(CoresApp.erro),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return false;
    }

    await widget.timeLogStore.deleteFirebaseLog(log);
    return true;
  }

  void _abrirModalEdicao(TimeLog log) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskLogEditDialog(
          log: log, save: widget.timeLogStore.updateFirebaseLog),
    );
  }

  void _abrirModalFiltroPdf() {
    String filtroSelecionado = _filter;
    DateTime? inicioTemp = _startDate;
    DateTime? fimTemp = _endDate;
    if (_filter == 'Todas' && _nivelHistoricoSelecionado != 'todos') {
      filtroSelecionado = 'Período';
      final year = _anoHistoricoSelecionado ?? DateTime.now().year;
      final month = _mesHistoricoSelecionado ?? DateTime.now().month;
      inicioTemp = DateTime(year, month);
      fimTemp = DateTime(year, month + 1, 0);
      if (_nivelHistoricoSelecionado == 'ano') {
        inicioTemp = DateTime(year);
        fimTemp = DateTime(year, 12, 31);
      } else if (_nivelHistoricoSelecionado == 'dia') {
        inicioTemp = _diaInicial();
        fimTemp = inicioTemp;
      } else if (_nivelHistoricoSelecionado == 'semana' &&
          _semanaHistoricoSelecionada != null) {
        final week = TaskHistoryMonth(year, month, []).weeks.firstWhere(
            (week) => _sameDay(week.monday, _semanaHistoricoSelecionada!));
        inicioTemp = week.days.first;
        fimTemp = week.days.last;
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        AppAppearance.watch(context);
        return StatefulBuilder(
          builder: (context, setModalState) {
            AppAppearance.watch(context);
            return AlertDialog(
              backgroundColor: CoresApp.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: CoresApp.borda.withValues(alpha: 0.6),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.picture_as_pdf_rounded,
                      color: CoresApp.destaque,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
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
                    Text(
                      'Exporta os registros carregados, mantendo trabalho, pesquisa e cobrança. Para outro período, carregue-o primeiro na tela.',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: filtroSelecionado == 'Período'
                          ? 'Período'
                          : filtroSelecionado,
                      dropdownColor: CoresApp.superficie,
                      style: TextStyle(
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
                          foregroundColor:
                              AppPalette.foregroundOn(CoresApp.fundo),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ),
                            side: BorderSide(
                              color: CoresApp.borda,
                            ),
                          ),
                          elevation: 0,
                        ),
                        icon: Icon(
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
                              AppAppearance.watch(context);
                              return Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: ColorScheme.dark(
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
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: AppPalette.foregroundOn(CoresApp.primaria),
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

        return taskLogMatchesHoursFilter(log, _hoursFilter) &&
            taskLogMatches(log, _search) &&
            taskLogInProject(log, _hasProjectFilter ? _projectFilterId : null,
                requests: _projectRequests);
      }).toList()
        ..sort(
          (a, b) => b.date.compareTo(a.date),
        );

      if (logsFiltrados.isEmpty) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Nenhum registro encontrado para o filtro selecionado.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );
        }

        return;
      }

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

      final hoje = DateTime.now();
      final nomeArquivo =
          'relatorio_atividades_${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}.pdf';
      final user = FirebaseAuth.instance.currentUser;
      final responsible = user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : user?.email ?? 'Conta conectada';
      final pdf = await buildTaskPdfReport(
        data: TaskReportData(logsFiltrados, _duracaoEmMinutos),
        period: periodoDescricao,
        responsible: responsible,
        generatedAt: hoje,
      );

      if (!mounted || !context.mounted) {
        return;
      }

      await showDialog(
        context: context,
        builder: (dialogContext) {
          AppAppearance.watch(dialogContext);

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
                        Text(
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
                          icon: Icon(
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
      if (mounted && context.mounted) {
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

  // ============================================================
  // ESTADO VAZIO
  // ============================================================

  String _monthName(int month) {
    const months = [
      'JANEIRO',
      'FEVEREIRO',
      'MARÇO',
      'ABRIL',
      'MAIO',
      'JUNHO',
      'JULHO',
      'AGOSTO',
      'SETEMBRO',
      'OUTUBRO',
      'NOVEMBRO',
      'DEZEMBRO',
    ];
    return months[month - 1];
  }

  String _monthKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<TimeLog> _logsDoDiaSelecionado(List<TimeLog> logs, DateTime dia) =>
      logs.where((log) => _sameDay(log.date, dia)).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  void _selectToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    _filter = 'Todas';
    _startDate = null;
    _endDate = null;
    _diaSelecionado = today;
    _nivelHistoricoSelecionado = 'dia';
    _anoHistoricoSelecionado = today.year;
    _mesHistoricoSelecionado = today.month;
    _semanaHistoricoSelecionada = null;
    _anosExpandidos.add(today.year);
    _mesesExpandidos.add(_monthKey(today.year, today.month));
    _semanasExpandidas.add('${today.year}-${today.month}-${_weekKey(today)}');
  }

  DateTime _diaInicial() =>
      _diaSelecionado ?? DateUtils.dateOnly(DateTime.now());

  Map<int, Map<int, Map<DateTime, List<TimeLog>>>> _arvoreHistorico(
          List<TimeLog> logs) =>
      taskHistoryCalendar(
          logs, _anoHistoricoSelecionado ?? DateTime.now().year);

  Widget _treeInfo(String horas, int tarefas) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(horas,
              style: TextStyle(
                  color: CoresApp.destaque,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900)),
          Text('$tarefas ${tarefas == 1 ? 'tarefa' : 'tarefas'}',
              style: TextStyle(color: CoresApp.textoSecundario, fontSize: 8.5)),
        ],
      );

  Widget _treeRow({
    required int level,
    required bool expanded,
    required bool expandable,
    required IconData icon,
    required String title,
    required List<TimeLog> logs,
    required VoidCallback onTap,
    bool selected = false,
    bool showTotals = true,
  }) {
    return InkWell(
      onTap: () {
        _filter = 'Todas';
        _selectedLogs.clear();
        onTap();
        _refreshHistoryDialog?.call();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: EdgeInsets.only(left: level * 7.0, bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? CoresApp.destaque.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: CoresApp.destaque.withValues(alpha: .8))
              : null,
        ),
        child: Row(children: [
          SizedBox(
            width: 18,
            child: expandable
                ? Icon(
                    expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    size: 18,
                    color: CoresApp.destaque)
                : const SizedBox.shrink(),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: CoresApp.primaria.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 15, color: CoresApp.destaque),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: level <= 1 ? 11.5 : 10.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700)),
          ),
          showTotals
              ? _treeInfo(_formatarMinutos(_totalMinutos(logs)), logs.length)
              : Text('Consultar',
                  style:
                      TextStyle(color: CoresApp.textoSecundario, fontSize: 9)),
        ]),
      ),
    );
  }

  Widget _buildHistoryTree(List<TimeLog> logs, DateTime selectedDay) {
    final arvore = _arvoreHistorico(logs);
    final anos = arvore.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.only(right: 5),
      children: [
        for (final ano in anos) ...[
          Builder(builder: (_) {
            final mesesMap = arvore[ano]!;
            final logsAno = mesesMap.values
                .expand((semanas) => semanas.values.expand((e) => e))
                .toList();
            final anoAberto = _anosExpandidos.contains(ano);
            return Column(children: [
              _treeRow(
                level: 0,
                expanded: anoAberto,
                expandable: true,
                icon: Icons.calendar_month_rounded,
                title: '$ano',
                logs: logsAno,
                onTap: () => setState(() {
                  _nivelHistoricoSelecionado = 'ano';
                  _anoHistoricoSelecionado = ano;
                  _mesHistoricoSelecionado = null;
                  _semanaHistoricoSelecionada = null;
                  anoAberto
                      ? _anosExpandidos.remove(ano)
                      : _anosExpandidos.add(ano);
                }),
                selected: _nivelHistoricoSelecionado == 'ano' &&
                    _anoHistoricoSelecionado == ano,
              ),
              if (anoAberto)
                for (final mes
                    in (mesesMap.keys.toList()..sort((a, b) => b.compareTo(a))))
                  Builder(builder: (_) {
                    final semanasMap = mesesMap[mes]!;
                    final logsMes = semanasMap.values.expand((e) => e).toList();
                    final mk = _monthKey(ano, mes);
                    final mesAberto = _mesesExpandidos.contains(mk);
                    return Column(children: [
                      _treeRow(
                        level: 1,
                        expanded: mesAberto,
                        expandable: true,
                        icon: Icons.folder_rounded,
                        title: _monthName(mes),
                        logs: logsMes,
                        showTotals: logsMes.isNotEmpty ||
                            (_anoHistoricoSelecionado == ano &&
                                _mesHistoricoSelecionado == mes),
                        onTap: () => setState(() {
                          _nivelHistoricoSelecionado = 'mes';
                          _anoHistoricoSelecionado = ano;
                          _mesHistoricoSelecionado = mes;
                          _semanaHistoricoSelecionada = null;
                          mesAberto
                              ? _mesesExpandidos.remove(mk)
                              : _mesesExpandidos.add(mk);
                        }),
                        selected: _nivelHistoricoSelecionado == 'mes' &&
                            _anoHistoricoSelecionado == ano &&
                            _mesHistoricoSelecionado == mes,
                      ),
                      if (mesAberto)
                        for (final inicio
                            in (semanasMap.keys.toList()
                              ..sort((a, b) => b.compareTo(a))))
                          Builder(builder: (_) {
                            final logsSemana = semanasMap[inicio]!;
                            final wk = '$ano-$mes-${_weekKey(inicio)}';
                            final semanaAberta =
                                _semanasExpandidas.contains(wk);
                            final dias = <String, List<TimeLog>>{};
                            for (final log in logsSemana) {
                              dias
                                  .putIfAbsent(_dayKey(log.date), () => [])
                                  .add(log);
                            }
                            final week = TaskHistoryMonth(ano, mes, [])
                                .weeks
                                .firstWhere(
                                    (week) => _sameDay(week.monday, inicio));
                            final datas = week.days;
                            return Column(children: [
                              _treeRow(
                                level: 2,
                                expanded: semanaAberta,
                                expandable: true,
                                icon: Icons.date_range_rounded,
                                title: week.label,
                                logs: logsSemana,
                                onTap: () => setState(() {
                                  _nivelHistoricoSelecionado = 'semana';
                                  _anoHistoricoSelecionado = ano;
                                  _mesHistoricoSelecionado = mes;
                                  _semanaHistoricoSelecionada = inicio;
                                  semanaAberta
                                      ? _semanasExpandidas.remove(wk)
                                      : _semanasExpandidas.add(wk);
                                }),
                                selected: _nivelHistoricoSelecionado ==
                                        'semana' &&
                                    _anoHistoricoSelecionado == ano &&
                                    _mesHistoricoSelecionado == mes &&
                                    _semanaHistoricoSelecionada != null &&
                                    _sameDay(
                                        _semanaHistoricoSelecionada!, inicio),
                              ),
                              if (semanaAberta)
                                for (final data in datas)
                                  _treeRow(
                                    level: 3,
                                    expanded: false,
                                    expandable: false,
                                    icon: Icons.calendar_today_rounded,
                                    title:
                                        '${_formatShortDate(data).substring(0, 5)} (${_dayNameShort(data.weekday)})',
                                    logs: dias[_dayKey(data)] ?? [],
                                    selected:
                                        _nivelHistoricoSelecionado == 'dia' &&
                                            _sameDay(data, selectedDay),
                                    onTap: () => setState(() {
                                      _nivelHistoricoSelecionado = 'dia';
                                      _diaSelecionado = data;
                                      _anoHistoricoSelecionado = data.year;
                                      _mesHistoricoSelecionado = data.month;
                                      _semanaHistoricoSelecionada =
                                          _weekStart(data);
                                    }),
                                  ),
                            ]);
                          }),
                    ]);
                  }),
            ]);
          }),
        ],
      ],
    );
  }

  List<TimeLog> _logsPeriodoSelecionado(List<TimeLog> logs) {
    final arvore = _arvoreHistorico(logs);

    if (_nivelHistoricoSelecionado == 'ano' &&
        _anoHistoricoSelecionado != null) {
      final meses = arvore[_anoHistoricoSelecionado];
      if (meses == null) return [];
      return meses.values
          .expand((semanas) => semanas.values.expand((e) => e))
          .toList();
    }

    if (_nivelHistoricoSelecionado == 'mes' &&
        _anoHistoricoSelecionado != null &&
        _mesHistoricoSelecionado != null) {
      final semanas =
          arvore[_anoHistoricoSelecionado]?[_mesHistoricoSelecionado];
      if (semanas == null) return [];
      return semanas.values.expand((e) => e).toList();
    }

    if (_nivelHistoricoSelecionado == 'semana' &&
        _semanaHistoricoSelecionada != null) {
      final inicio = _semanaHistoricoSelecionada!;
      final fim = inicio.add(const Duration(days: 6));
      return logs.where((log) {
        final d = DateTime(log.date.year, log.date.month, log.date.day);
        final i = DateTime(inicio.year, inicio.month, inicio.day);
        final f = DateTime(fim.year, fim.month, fim.day);
        return !d.isBefore(i) &&
            !d.isAfter(f) &&
            (_anoHistoricoSelecionado == null ||
                d.year == _anoHistoricoSelecionado) &&
            (_mesHistoricoSelecionado == null ||
                d.month == _mesHistoricoSelecionado);
      }).toList();
    }

    return [];
  }

  String _tituloPeriodoSelecionado() {
    if (_nivelHistoricoSelecionado == 'ano') {
      return '${_anoHistoricoSelecionado ?? ''}';
    }
    if (_nivelHistoricoSelecionado == 'mes') {
      final mes = _mesHistoricoSelecionado;
      final ano = _anoHistoricoSelecionado;
      return mes == null || ano == null ? 'Mês' : '${_monthName(mes)} de $ano';
    }
    final inicio = _semanaHistoricoSelecionada;
    if (inicio == null) return 'Semana';
    final year = _anoHistoricoSelecionado;
    final month = _mesHistoricoSelecionado;
    if (year != null && month != null) {
      return TaskHistoryMonth(year, month, [])
          .weeks
          .firstWhere((week) => _sameDay(week.monday, inicio))
          .label;
    }
    return _formatWeekTitle(inicio);
  }

  void _selecionarMes(DateTime month) => setState(() {
        _filter = 'Todas';
        _selectedLogs.clear();
        _nivelHistoricoSelecionado = 'mes';
        _anoHistoricoSelecionado = month.year;
        _mesHistoricoSelecionado = month.month;
        _semanaHistoricoSelecionada = null;
        _anosExpandidos.add(month.year);
        _mesesExpandidos.add(_monthKey(month.year, month.month));
      });

  void _shiftMonth(int offset) {
    final now = DateTime.now();
    _selecionarMes(DateTime(_anoHistoricoSelecionado ?? now.year,
        (_mesHistoricoSelecionado ?? now.month) + offset));
  }

  List<TimeLog> _contextLogs(List<TimeLog> source) {
    final logs = _filter != 'Todas' || _nivelHistoricoSelecionado == 'todos'
        ? source
        : _nivelHistoricoSelecionado == 'dia'
            ? _logsDoDiaSelecionado(source, _diaInicial())
            : _logsPeriodoSelecionado(source);
    return [...logs]..sort((a, b) {
        final date =
            DateUtils.dateOnly(b.date).compareTo(DateUtils.dateOnly(a.date));
        return date != 0 ? date : b.startTime.compareTo(a.startTime);
      });
  }

  String get _periodLabel {
    if (_filter == 'Período') {
      return '${_formatShortDate(_startDate!)} – ${_formatShortDate(_endDate!)}';
    }
    if (_filter != 'Todas') return _filter;
    if (_nivelHistoricoSelecionado == 'todos') return 'Todo o histórico';
    if (_nivelHistoricoSelecionado == 'dia') {
      return _formatDateHeader(_diaInicial());
    }
    return _tituloPeriodoSelecionado();
  }

  Future<void> _chooseProject() async {
    if (_choosingProject) return;
    final owner = FirebaseAuth.instance.currentUser?.uid;
    if (owner == null) return;
    bool authorized() =>
        mounted && FirebaseAuth.instance.currentUser?.uid == owner;
    _choosingProject = true;
    try {
      final choice = await showDialog<TaskProjectChoice>(
          context: context,
          builder: (_) => TaskProjectPicker(
                authorized: authorized,
                loader: FirebaseService().getProjects,
                logs: widget.timeLogStore.logs,
              ));
      if (!authorized() || choice == null) return;
      setState(() {
        _hasProjectFilter = choice.id.isNotEmpty;
        _projectFilterId = choice.id.isEmpty ? null : choice.id;
        _projectFilterLabel = choice.id.isEmpty ? null : choice.label;
        _projectRequests = choice.requests;
        _selectedLogs.clear();
      });
    } finally {
      _choosingProject = false;
    }
  }

  Future<void> _choosePeriod() async {
    final choice = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
              title: const Text('Selecionar período'),
              children: [
                for (final label in [
                  'Hoje',
                  'Mês atual',
                  'Esta semana',
                  'Ano atual',
                  'Escolher mês',
                  'Escolher ano',
                  'Intervalo de datas',
                  'Todo o histórico'
                ])
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialog, label),
                      child: Text(label)),
              ],
            ));
    if (!mounted || choice == null) return;
    final now = DateTime.now();
    if (choice == 'Escolher ano') {
      final year = await showDialog<int>(
          context: context,
          builder: (dialog) =>
              SimpleDialog(title: const Text('Escolher ano'), children: [
                for (var year = now.year; year >= 2020; year--)
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialog, year),
                      child: Text('$year')),
              ]));
      if (mounted && year != null)
        setState(() {
          _filter = 'Todas';
          _nivelHistoricoSelecionado = 'ano';
          _anoHistoricoSelecionado = year;
          _mesHistoricoSelecionado = null;
          _anosExpandidos.add(year);
          _selectedLogs.clear();
        });
      return;
    }
    if (choice == 'Intervalo de datas') {
      await _pickDateRange(context);
      return;
    }
    if (choice == 'Escolher mês') {
      final date = await showDatePicker(
          context: context,
          initialDate: DateTime(_anoHistoricoSelecionado ?? now.year,
              _mesHistoricoSelecionado ?? now.month),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100));
      if (mounted && date != null) {
        _filter = 'Todas';
        _selecionarMes(date);
      }
      return;
    }
    setState(() {
      _selectedLogs.clear();
      _filter = 'Todas';
      if (choice == 'Hoje') {
        _selectToday();
      }
      if (choice == 'Mês atual') {
        _nivelHistoricoSelecionado = 'mes';
        _anoHistoricoSelecionado = now.year;
        _mesHistoricoSelecionado = now.month;
      }
      if (choice == 'Esta semana') _filter = 'Esta semana';
      if (choice == 'Ano atual') {
        _nivelHistoricoSelecionado = 'ano';
        _anoHistoricoSelecionado = now.year;
        _mesHistoricoSelecionado = null;
      }
      if (choice == 'Todo o histórico') _nivelHistoricoSelecionado = 'todos';
    });
  }

  void _screenAction(TaskScreenAction action) {
    switch (action) {
      case TaskScreenAction.history:
        if (MediaQuery.sizeOf(context).width < 1050) {
          showDialog<void>(
              context: context,
              builder: (dialogContext) =>
                  StatefulBuilder(builder: (context, refresh) {
                    _refreshHistoryDialog = () {
                      if (context.mounted) refresh(() {});
                    };
                    return AlertDialog(
                      content: SizedBox(
                          width: 330,
                          height: MediaQuery.sizeOf(dialogContext).height * .65,
                          child: ListenableBuilder(
                              listenable: widget.timeLogStore,
                              builder: (_, __) => _historyPanel(
                                  _filteredRegisteredLogs(filterHours: false),
                                  _diaInicial()))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Fechar'))
                      ],
                    );
                  })).whenComplete(() => _refreshHistoryDialog = null);
        } else {
          setState(() => _showHistory = !_showHistory);
        }
      case TaskScreenAction.pending:
        setState(() => _showPending = !_showPending);
      case TaskScreenAction.clear:
        _clearFilters();
      case TaskScreenAction.registerHours:
        widget.onSelectTab(0);
    }
  }

  Future<void> _logAction(TimeLog log, TaskLogAction action) async {
    try {
      switch (action) {
        case TaskLogAction.edit:
          _abrirModalEdicao(log);
        case TaskLogAction.delete:
          await _excluirApontamentoComConfirmacao(log);
        case TaskLogAction.send:
          await _enviarHorasDireto([log]);
        case TaskLogAction.register:
          await widget.timeLogStore.register(log);
        case TaskLogAction.reviewDay:
          final logs = widget.timeLogStore.logs
              .where(
                  (item) => item.isRegistered && _sameDay(item.date, log.date))
              .toList();
          _abrirModalDetalhesDia(_formatDateHeader(log.date),
              _formatarMinutos(_totalMinutos(logs)), logs);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível concluir: $error')));
      }
    }
  }

  Widget _historyPanel(List<TimeLog> logs, DateTime day) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: CoresApp.superficie,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CoresApp.borda)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Icon(Icons.history, size: 16),
                const SizedBox(width: 7),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Histórico de apontamentos',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12)),
                      Text('Ano · mês · semana · dia',
                          style: TextStyle(
                              color: CoresApp.textoSecundario, fontSize: 10)),
                    ])),
                IconButton(
                    tooltip: 'Selecionar período ou ano',
                    visualDensity: VisualDensity.compact,
                    onPressed: _choosePeriod,
                    icon: const Icon(Icons.calendar_month_outlined, size: 15)),
              ])),
          Divider(color: CoresApp.borda),
          Expanded(child: _buildHistoryTree(logs, day)),
        ]),
      );

  Widget _workspace(List<TimeLog> contextLogs, List<TimeLog> visible,
          TaskPeriodSummary summary) =>
      TaskWorkspacePanel(
        logs: visible,
        summary: summary,
        workLabel: _projectFilterLabel,
        periodLabel: _periodLabel,
        filter: _hoursFilter,
        onBilling: (value) => setState(() => _hoursFilter = value),
        selected: _selectedLogs,
        sending: _enviandoEdesk,
        loading: _loadingPeriod,
        hasError: _periodError != null || widget.timeLogStore.loadError != null,
        showPending: _showPending,
        onSelect: (log, selected) => setState(() {
          selected
              ? _selectedLogs.add(taskLogKey(log))
              : _selectedLogs.remove(taskLogKey(log));
        }),
        onSelectAll: (selected) => setState(() {
          for (final log in visible) {
            selected
                ? _selectedLogs.add(taskLogKey(log))
                : _selectedLogs.remove(taskLogKey(log));
          }
        }),
        onAction: _logAction,
        onSend: (logs) => _enviarHorasDireto(logs),
        onRegisterHours: () => widget.onSelectTab(0),
        onToggleHistory: () => _screenAction(TaskScreenAction.history),
        onViewMonth: _nivelHistoricoSelecionado == 'dia'
            ? () => _selecionarMes(_diaInicial())
            : null,
        onRetry: () async {
          try {
            await widget.timeLogStore.retryListening();
            if (mounted) setState(() => _periodError = null);
          } catch (error) {
            if (mounted) setState(() => _periodError = error);
          }
        },
      );

  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    final day = _diaInicial();
    final base = _filteredRegisteredLogs(filterHours: false);
    final contextLogs = _contextLogs(base);
    final visible = contextLogs
        .where((log) => taskLogMatchesHoursFilter(log, _hoursFilter))
        .toList();
    final summary = TaskPeriodSummary(contextLogs);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Cabecalho(
              selectedIndex: widget.selectedIndex,
              onSelectTab: widget.onSelectTab,
              searchQuery: _search,
              onSearchChanged: (value) => setState(() {
                    _search = value;
                    _searchController.text = value;
                  }),
              userName: '')),
      body: LayoutBuilder(
          builder: (context, constraints) => Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: constraints.maxHeight * .36),
                    child: SingleChildScrollView(
                        child: Column(children: [
                      TaskOverviewHeader(
                          summary: summary,
                          onPdf: _abrirModalFiltroPdf,
                          filter: _hoursFilter,
                          onBilling: (value) =>
                              setState(() => _hoursFilter = value)),
                      const SizedBox(height: 8),
                      TaskFiltersBar(
                          controller: _searchController,
                          onSearch: (value) => setState(() => _search = value),
                          workLabel: _projectFilterLabel,
                          onWork: _chooseProject,
                          onClearWork: () => setState(() {
                                _hasProjectFilter = false;
                                _projectFilterId = null;
                                _projectRequests = {};
                                _projectFilterLabel = null;
                              }),
                          periodLabel: _periodLabel,
                          onPeriod: _choosePeriod,
                          onPreviousMonth: () => _shiftMonth(-1),
                          onNextMonth: () => _shiftMonth(1),
                          onToday: () => setState(_selectToday),
                          filter: _hoursFilter,
                          onBilling: (value) =>
                              setState(() => _hoursFilter = value),
                          showHistory: _showHistory,
                          showPending: _showPending,
                          onAction: _screenAction),
                    ]))),
                const SizedBox(height: 8),
                Expanded(
                    child: Row(children: [
                  if (_showHistory && constraints.maxWidth >= 1050) ...[
                    SizedBox(width: constraints.maxWidth >= 1400 ? 320 : 225, child: _historyPanel(base, day)),
                    const SizedBox(width: 12)
                  ],
                  Expanded(child: _workspace(contextLogs, visible, summary)),
                ])),
                if (constraints.maxWidth >= 1400 && constraints.maxHeight >= 800) ...[
                  const SizedBox(height: 12),
                  const AppSuggestionsBanner(items: [
                    (Icons.event_outlined, 'Alertas de prazo', 'Confira os apontamentos e o estado do envio.'),
                    (Icons.bar_chart, 'Resumo do período', 'Filtre por projeto, período e cobrança.'),
                    (Icons.checklist, 'Ações em lote', 'Selecione os apontamentos para conferir e enviar.'),
                  ]),
                ],
              ]))),
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
