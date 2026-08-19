import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/service_type_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/central_alertas_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/controle_projetos_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/grafico_horas_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/progresso_projeto_widget.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/tabela_projetos_widget.dart';
import 'package:gerenciador_horas/features/projects/dialogs/project_form_dialog.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class DashboardScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final List<WorkFormat> workFormats;
  final ValueChanged<ProjectModel>? onProjectCompleted;
  final TimeLogStore timeLogStore;

  const DashboardScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.workFormats,
    required this.timeLogStore,
    this.onProjectCompleted,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _onlyActive = true;
  bool _agrupar = true;
  bool _ordenarPrioridade = false;
  String _searchQuery = '';

  final Set<String> _expandedProjectIds = {};

  bool _showPostStopButton = false;
  bool _isLoadingProjects = true;

  final ScrollController _verticalTableScroll = ScrollController();

  final ScrollController _horizontalTableScroll = ScrollController();

  final FilterOptions _filterOptions = FilterOptions();

  String? _selectedTargetId;

  final List<String> _statusList = [
    'INI_PRO',
    'TRAB',
    'EA',
    'TRAB_FIM',
  ];

  final List<ServiceTypeModel> _serviceTypes = [
    ServiceTypeModel(
      id: '1',
      name: 'Enterprise',
    ),
    ServiceTypeModel(
      id: '2',
      name: 'Professional Produção Completa',
    ),
    ServiceTypeModel(
      id: '3',
      name: 'Worker',
    ),
    ServiceTypeModel(
      id: '4',
      name: 'Atividade Interna',
    ),
    ServiceTypeModel(
      id: '5',
      name: 'Consultoria',
    ),
    ServiceTypeModel(
      id: '6',
      name: 'Implantação Start',
    ),
    ServiceTypeModel(
      id: '7',
      name: 'Teste',
    ),
  ];

  List<ProjectModel> _projects = [];

  final FirebaseService _firebaseService = FirebaseService();

  List<TimeLog> get _timeLogs => widget.timeLogStore.logs;

  // ============================================================
  // CRIAÇÃO DO TIME LOG
  // ============================================================

  TimeLog _createTimeLog({
    required String targetId,
    required DateTime date,
    required String startTime,
    required String endTime,
    required String durationFormatted,
    required bool isRegistered,
  }) {
    String? projectName;
    String? taskName;
    String? typeHs;

    final project = _projects.cast<ProjectModel?>().firstWhere(
          (p) => p!.id == targetId,
          orElse: () => null,
        );

    if (project != null) {
      projectName = project.client;
      taskName = project.stage;
      typeHs = project.hourType;
    } else if (targetId.contains('_')) {
      final parts = targetId.split('_');

      if (parts.length >= 2) {
        final projectId = parts.first;
        final subId = parts.sublist(1).join('_');

        final parent = _projects.cast<ProjectModel?>().firstWhere(
              (p) => p!.id == projectId,
              orElse: () => null,
            );

        if (parent != null) {
          projectName = parent.client;

          final task = parent.subTasks?.cast<TaskModel?>().firstWhere(
                (t) => t!.subId == subId,
                orElse: () => null,
              );

          taskName = task?.stage ?? 'Etapa $subId';

          typeHs = task?.hourType ?? parent.hourType;
        }
      }
    }

    return TimeLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      targetId: targetId,
      date: date,
      startTime: startTime,
      endTime: endTime,
      durationFormatted: durationFormatted,
      isRegistered: isRegistered,
      projectName: projectName,
      taskName: taskName,
      typeHs: typeHs,
      hours: null,
      description: null,
    );
  }

  // ============================================================
  // CRONÔMETRO
  // ============================================================

  String? _activeTimerTargetId;
  DateTime? _activeStartTime;
  TimerState _timerState = TimerState.stopped;

  Timer? _timer;

  int _secondsElapsed = 0;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadProjectsFromFirebase(
      showLoader: true,
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _timer?.cancel();

    _verticalTableScroll.dispose();
    _horizontalTableScroll.dispose();

    widget.timeLogStore.stopListening();

    super.dispose();
  }

  // ============================================================
  // CARREGAR PROJETOS E HORAS
  // ============================================================

  Future<void> _loadProjectsFromFirebase({
    bool showLoader = false,
  }) async {
    if (showLoader) {
      setState(() {
        _isLoadingProjects = true;
      });
    }

    try {
      final loadedProjects = await _firebaseService.getProjects();

      final projectIds = loadedProjects
          .map(
            (project) => project.id.trim(),
          )
          .where(
            (id) => id.isNotEmpty,
          )
          .toList();

      await widget.timeLogStore.startListeningToProjects(
        projectIds,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _projects = loadedProjects;
        _isLoadingProjects = false;

        if (_projects.isNotEmpty && _selectedTargetId == null) {
          _selectedTargetId = _projects.first.id;
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingProjects = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar projetos e horas do Firebase: $e',
          ),
          backgroundColor: CoresApp.erro,
        ),
      );
    }
  }

  // ============================================================
  // INICIAR CRONÔMETRO
  // ============================================================

  void _startTimer(String targetId) {
    if (_activeTimerTargetId != targetId) {
      _stopTimer();

      _activeStartTime = DateTime.now();

      _secondsElapsed = 0;
    } else if (_activeStartTime == null) {
      _activeStartTime = DateTime.now();
    }

    _activeTimerTargetId = targetId;

    _timerState = TimerState.running;

    _showPostStopButton = false;

    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _secondsElapsed++;
        });
      },
    );

    setState(() {});
  }

  // ============================================================
  // PAUSAR
  // ============================================================

  void _pauseTimer() {
    _timer?.cancel();

    setState(() {
      _timerState = TimerState.paused;
    });
  }

  // ============================================================
  // PARAR E SALVAR NO FIREBASE
  // ============================================================

  Future<void> _stopTimer() async {
    _timer?.cancel();

    if (_activeTimerTargetId != null) {
      final targetId = _activeTimerTargetId!;

      final endTime = DateTime.now();

      final startTime = _activeStartTime ?? endTime;

      int totalSeconds = _secondsElapsed;

      if (totalSeconds <= 0) {
        totalSeconds = endTime
            .difference(
              startTime,
            )
            .inSeconds;

        if (totalSeconds < 0) {
          totalSeconds = 0;
        }
      }

      final startFormatted = '${startTime.hour.toString().padLeft(2, '0')}:'
          '${startTime.minute.toString().padLeft(2, '0')}';

      final endFormatted = '${endTime.hour.toString().padLeft(2, '0')}:'
          '${endTime.minute.toString().padLeft(2, '0')}';

      final durationFormatted = _formatDuration(
        totalSeconds > 0 ? totalSeconds : 60,
      );

      final log = _createTimeLog(
        targetId: targetId,
        date: startTime,
        startTime: startFormatted,
        endTime: endFormatted,
        durationFormatted: durationFormatted,
        isRegistered: false,
      );

      try {
        final projectId = targetId.split('_').first;

        final logId = await widget.timeLogStore.addFirebaseLog(
          projectId,
          log,
        );

        log.id = logId;

        widget.timeLogStore.add(log);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Tempo de trabalho salvo no Firebase.',
              ),
              backgroundColor: CoresApp.sucesso,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao salvar o tempo no Firebase: $e',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _timerState = TimerState.stopped;

      _activeTimerTargetId = null;

      _activeStartTime = null;

      _secondsElapsed = 0;

      _showPostStopButton = true;
    });
  }

  // ============================================================
  // FORMATAÇÃO
  // ============================================================

  String _formatDuration(
    int seconds,
  ) {
    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');

    final minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');

    return '$hours:$minutes';
  }

  double _parseTimeToHours(
    String timeFormatted,
  ) {
    final parts = timeFormatted.split(':');

    if (parts.length < 2) {
      return 0.0;
    }

    final hours = double.tryParse(
          parts[0],
        ) ??
        0.0;

    final minutes = double.tryParse(
          parts[1],
        ) ??
        0.0;

    return hours + (minutes / 60.0);
  }

  String _formatHours(
    double hours,
  ) {
    int h = hours.toInt();

    int m = ((hours - h) * 60).round();

    if (m >= 60) {
      h++;
      m = 0;
    }

    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}';
  }

  String _formatDateShort(
    DateTime d,
  ) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year.toString().substring(2)}';
  }

  // ============================================================
  // HORAS POR DATA
  // ============================================================

  double _getHoursForDate(
    DateTime targetDate,
  ) {
    double totalHours = 0.0;

    for (final log in _timeLogs.where(
      (l) => l.isRegistered,
    )) {
      if (log.date.year == targetDate.year &&
          log.date.month == targetDate.month &&
          log.date.day == targetDate.day) {
        totalHours += _parseTimeToHours(
          log.durationFormatted,
        );
      }
    }

    return totalHours;
  }

  // ============================================================
  // EDITAR SUBTRABALHO
  // ============================================================

  void _editSubTaskDialog(
    ProjectModel project,
    TaskModel task,
  ) {
    final subIdController = TextEditingController(
      text: task.subId,
    );

    final stageController = TextEditingController(
      text: task.stage,
    );

    final serviceTypeController = TextEditingController(
      text: project.serviceType,
    );

    final hoursController = TextEditingController(
      text: task.estimatedHours,
    );

    final hourTypeController = TextEditingController(
      text: task.hourType,
    );

    DateTime startDate = task.startDate;

    DateTime endDate = task.planEnd ?? task.startDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  16,
                ),
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Editar Subtrabalho (Etapa ${task.subId})',
                style: TextStyle(
                  fontSize: 16,
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subIdController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Número (Nº)',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: serviceTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Serviço',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: stageController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Trabalho / Etapa',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: hoursController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Horas Estimadas (ex: 10:00)',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: hourTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Horas (ex: Hs Cobradas)',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Início: ${_formatDateShort(startDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(
                                  2020,
                                ),
                                lastDate: DateTime(
                                  2030,
                                ),
                              );

                              if (picked != null) {
                                setDialogState(
                                  () {
                                    startDate = picked;
                                  },
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Fim: ${_formatDateShort(endDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: DateTime(
                                  2020,
                                ),
                                lastDate: DateTime(
                                  2030,
                                ),
                              );

                              if (picked != null) {
                                setDialogState(
                                  () {
                                    endDate = picked;
                                  },
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: CoresApp.fundo,
                  ),
                  onPressed: () async {
                    setState(() {
                      task.subId = subIdController.text.trim();

                      task.stage = stageController.text.trim();

                      task.estimatedHours = hoursController.text.trim();

                      task.hourType = hourTypeController.text.trim();

                      task.startDate = startDate;

                      task.planStart = startDate;

                      task.planEnd = endDate;
                    });

                    await _firebaseService.saveProject(
                      project,
                    );

                    if (context.mounted) {
                      Navigator.of(
                        context,
                      ).pop();

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Subtrabalho atualizado com sucesso!',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Salvar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // ADICIONAR NOVA ETAPA
  // ============================================================

  void _addNewTaskDialog(
    ProjectModel project,
  ) {
    final subIdController = TextEditingController(
      text: ((project.subTasks?.length ?? 0) + 1).toString(),
    );

    final stageController = TextEditingController();

    final serviceTypeController = TextEditingController(
      text: project.serviceType,
    );

    final hoursController = TextEditingController(
      text: '10:00',
    );

    final hourTypeController = TextEditingController(
      text: project.hourType,
    );

    DateTime startDate = DateTime.now();

    DateTime endDate = DateTime.now().add(
      const Duration(
        days: 15,
      ),
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  16,
                ),
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Adicionar Nova Etapa ao Projeto ${project.id}',
                style: TextStyle(
                  fontSize: 16,
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subIdController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Número da Etapa (Nº)',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: stageController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Trabalho / Etapa',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: serviceTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Serviço',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: hoursController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Horas Estimadas (ex: 10:00)',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    TextField(
                      controller: hourTypeController,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Horas',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Início: ${_formatDateShort(startDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(
                                  2020,
                                ),
                                lastDate: DateTime(
                                  2030,
                                ),
                              );

                              if (picked != null) {
                                setDialogState(
                                  () {
                                    startDate = picked;
                                  },
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  8,
                                ),
                              ),
                            ),
                            icon: Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Fim: ${_formatDateShort(endDate)}',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: DateTime(
                                  2020,
                                ),
                                lastDate: DateTime(
                                  2030,
                                ),
                              );

                              if (picked != null) {
                                setDialogState(
                                  () {
                                    endDate = picked;
                                  },
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: CoresApp.fundo,
                  ),
                  onPressed: () async {
                    final stageName = stageController.text.trim();

                    if (stageName.isEmpty) {
                      return;
                    }

                    setState(() {
                      project.subTasks ??= [];

                      project.subTasks!.add(
                        TaskModel(
                          subId: subIdController.text.trim().isNotEmpty
                              ? subIdController.text.trim()
                              : (project.subTasks!.length + 1).toString(),
                          stage: stageName,
                          status: 'INI_PRO',
                          startDate: startDate,
                          planStart: startDate,
                          planEnd: endDate,
                          estimatedHours: hoursController.text.trim(),
                          hourType: hourTypeController.text.trim(),
                        ),
                      );

                      _expandedProjectIds.add(
                        project.id,
                      );
                    });

                    await _firebaseService.saveProject(
                      project,
                    );

                    if (context.mounted) {
                      Navigator.of(
                        context,
                      ).pop();

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Etapa "$stageName" adicionada com sucesso!',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Adicionar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // FILTROS
  // ============================================================

  void _openFilterDialog() {
    DateTime? tempDate = _filterOptions.selectedDate;

    String? tempType = _filterOptions.serviceType;

    String tempShift = _filterOptions.shift;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  16,
                ),
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.filter_alt,
                    color: CoresApp.destaque,
                    size: 20,
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  Text(
                    'Filtrar Projetos',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Data de Início:',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );

                      if (picked != null) {
                        setDialogState(
                          () {
                            tempDate = picked;
                          },
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: CoresDashboard.fundoSecundario,
                        borderRadius: BorderRadius.circular(
                          8,
                        ),
                        border: Border.all(
                          color: CoresApp.borda,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tempDate == null
                                ? 'Selecionar Data'
                                : '${tempDate!.day.toString().padLeft(2, '0')}/'
                                    '${tempDate!.month.toString().padLeft(2, '0')}/'
                                    '${tempDate!.year}',
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 13,
                            ),
                          ),
                          Icon(
                            tempDate != null
                                ? Icons.close
                                : Icons.calendar_today,
                            color: CoresApp.textoSecundario,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Text(
                    'Tipo do Projeto:',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: CoresDashboard.fundoSecundario,
                      borderRadius: BorderRadius.circular(
                        8,
                      ),
                      border: Border.all(
                        color: CoresApp.borda,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: tempType,
                        isExpanded: true,
                        dropdownColor: CoresDashboard.card,
                        hint: Text(
                          'Todos os Tipos',
                          style: TextStyle(
                            color: CoresApp.textoFraco,
                            fontSize: 13,
                          ),
                        ),
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 13,
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Todos os Tipos',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                              ),
                            ),
                          ),
                          ..._serviceTypes.map(
                            (
                              st,
                            ) =>
                                DropdownMenuItem<String?>(
                              value: st.name,
                              child: Text(
                                st.name,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setDialogState(
                            () {
                              tempType = val;
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Text(
                    'Turno de Trabalho:',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(
                    height: 6,
                  ),
                  Row(
                    children: [
                      _buildShiftChip(
                        'Todos',
                        tempShift,
                        (
                          s,
                        ) {
                          setDialogState(
                            () {
                              tempShift = s;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        width: 6,
                      ),
                      _buildShiftChip(
                        'Manhã',
                        tempShift,
                        (
                          s,
                        ) {
                          setDialogState(
                            () {
                              tempShift = s;
                            },
                          );
                        },
                      ),
                      const SizedBox(
                        width: 6,
                      ),
                      _buildShiftChip(
                        'Tarde',
                        tempShift,
                        (
                          s,
                        ) {
                          setDialogState(
                            () {
                              tempShift = s;
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(
                      () {
                        _filterOptions.clear();
                      },
                    );

                    Navigator.pop(
                      context,
                    );
                  },
                  child: Text(
                    'Limpar',
                    style: TextStyle(
                      color: CoresApp.textoFraco,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: CoresApp.fundo,
                  ),
                  onPressed: () {
                    setState(
                      () {
                        _filterOptions.selectedDate = tempDate;

                        _filterOptions.serviceType = tempType;

                        _filterOptions.shift = tempShift;
                      },
                    );

                    Navigator.pop(
                      context,
                    );
                  },
                  child: const Text(
                    'Aplicar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildShiftChip(
    String label,
    String currentSelected,
    ValueChanged<String> onSelect,
  ) {
    final isSelected = currentSelected == label;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? CoresApp.fundo : CoresApp.textoSecundario,
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: CoresApp.destaque,
      backgroundColor: CoresDashboard.fundoSecundario,
      onSelected: (_) => onSelect(label),
    );
  }

  // ============================================================
  // HORAS MANUAIS
  // ============================================================

  Future<void> _showManualTimeDialog(
    String itemTitle,
  ) async {
    final hoursController = TextEditingController();

    final minutesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              16,
            ),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Adicionar Horas Manualmente\n($itemTitle)',
            style: TextStyle(
              fontSize: 16,
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hoursController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Horas',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: TextField(
                      controller: minutesController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Minutos',
                        labelStyle: TextStyle(
                          color: CoresApp.textoSecundario,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.destaque,
                foregroundColor: CoresApp.fundo,
              ),
              onPressed: () async {
                final h = int.tryParse(
                      hoursController.text.trim(),
                    ) ??
                    0;

                final m = int.tryParse(
                      minutesController.text.trim(),
                    ) ??
                    0;

                if (h <= 0 && m <= 0) {
                  return;
                }

                final now = DateTime.now();

                final durationFormatted = '${h.toString().padLeft(2, '0')}:'
                    '${m.toString().padLeft(2, '0')}';

                final startFormatted = '${now.hour.toString().padLeft(2, '0')}:'
                    '${now.minute.toString().padLeft(2, '0')}';

                final endDateTime = now.add(
                  Duration(
                    hours: h,
                    minutes: m,
                  ),
                );

                final endFormatted =
                    '${endDateTime.hour.toString().padLeft(2, '0')}:'
                    '${endDateTime.minute.toString().padLeft(2, '0')}';

                final targetId = _selectedTargetId ??
                    (_projects.isNotEmpty ? _projects.first.id : 'Geral');

                final log = _createTimeLog(
                  targetId: targetId,
                  date: now,
                  startTime: startFormatted,
                  endTime: endFormatted,
                  durationFormatted: durationFormatted,
                  isRegistered: true,
                );

                try {
                  final projectId = targetId.split('_').first;

                  final logId = await widget.timeLogStore.addFirebaseLog(
                    projectId,
                    log,
                  );

                  log.id = logId;

                  widget.timeLogStore.add(log);

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(
                    dialogContext,
                  ).pop();

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Apontado manualmente ${h}h ${m}m e salvo no Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao salvar apontamento manual: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                    ),
                  );
                }
              },
              child: const Text(
                'Salvar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    hoursController.dispose();
    minutesController.dispose();
  }

  // ============================================================
  // EDITAR APONTAMENTO
  // ============================================================

  Future<void> _editLogDialog(
    TimeLog log,
  ) async {
    final startController = TextEditingController(
      text: log.startTime,
    );

    final endController = TextEditingController(
      text: log.endTime,
    );

    final durationController = TextEditingController(
      text: log.durationFormatted,
    );

    void calculateDuration() {
      final startParts = startController.text.split(':');

      final endParts = endController.text.split(':');

      if (startParts.length == 2 && endParts.length == 2) {
        final sh = int.tryParse(
              startParts[0],
            ) ??
            0;

        final sm = int.tryParse(
              startParts[1],
            ) ??
            0;

        final eh = int.tryParse(
              endParts[0],
            ) ??
            0;

        final em = int.tryParse(
              endParts[1],
            ) ??
            0;

        int startTotalMins = (sh * 60) + sm;

        int endTotalMins = (eh * 60) + em;

        int diffMins = endTotalMins - startTotalMins;

        if (diffMins < 0) {
          diffMins += 24 * 60;
        }

        final dh = diffMins ~/ 60;

        final dm = diffMins % 60;

        durationController.text = '${dh.toString().padLeft(2, '0')}:'
            '${dm.toString().padLeft(2, '0')}';
      }
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  16,
                ),
                side: BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Editar Horário de Apontamento',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: startController,
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Hora Início (ex: 14:00)',
                      labelStyle: TextStyle(
                        color: CoresApp.textoSecundario,
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      calculateDuration();

                      setDialogState(
                        () {},
                      );
                    },
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  TextField(
                    controller: endController,
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Hora Fim (ex: 15:30)',
                      labelStyle: TextStyle(
                        color: CoresApp.textoSecundario,
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      calculateDuration();

                      setDialogState(
                        () {},
                      );
                    },
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  TextField(
                    controller: durationController,
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Duração (ex: 01:30)',
                      labelStyle: TextStyle(
                        color: CoresApp.textoSecundario,
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: CoresApp.fundo,
                  ),
                  onPressed: () async {
                    setState(() {
                      log.startTime = startController.text.trim();

                      log.endTime = endController.text.trim();

                      log.durationFormatted = durationController.text.trim();

                      if (_activeTimerTargetId == log.targetId) {
                        final durationParts = log.durationFormatted.split(
                          ':',
                        );

                        if (durationParts.length >= 2) {
                          final h = int.tryParse(
                                durationParts[0],
                              ) ??
                              0;

                          final m = int.tryParse(
                                durationParts[1],
                              ) ??
                              0;

                          _secondsElapsed = (h * 3600) + (m * 60);
                        }

                        final startParts = log.startTime.split(
                          ':',
                        );

                        if (startParts.length == 2) {
                          final sh = int.tryParse(
                                startParts[0],
                              ) ??
                              log.date.hour;

                          final sm = int.tryParse(
                                startParts[1],
                              ) ??
                              log.date.minute;

                          _activeStartTime = DateTime(
                            log.date.year,
                            log.date.month,
                            log.date.day,
                            sh,
                            sm,
                          );
                        }
                      }
                    });

                    try {
                      await widget.timeLogStore.updateFirebaseLog(
                        log,
                      );

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.of(
                        dialogContext,
                      ).pop();

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Apontamento atualizado e salvo no Firebase!',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao atualizar apontamento: $e',
                          ),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Salvar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    startController.dispose();
    endController.dispose();
    durationController.dispose();
  }

  // ============================================================
  // EXCLUIR APONTAMENTO
  // ============================================================

  Future<void> _confirmDeleteLog(
    TimeLog log,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              16,
            ),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Excluir Apontamento',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente remover esta linha de apontamento?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
              ),
              onPressed: () async {
                try {
                  await widget.timeLogStore.deleteFirebaseLog(
                    log,
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(
                    dialogContext,
                  ).pop();

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Apontamento excluído do Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir apontamento: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EXCLUIR PROJETO
  // ============================================================

  Future<void> _confirmDeleteProject(
    ProjectModel project,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              16,
            ),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Excluir Projeto',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente excluir o projeto "${project.client}" (${project.id})?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
              ),
              onPressed: () async {
                if (_activeTimerTargetId == project.id ||
                    (_activeTimerTargetId?.startsWith(
                          '${project.id}_',
                        ) ??
                        false)) {
                  await _stopTimer();
                }

                setState(() {
                  _projects.removeWhere(
                    (p) => p.id == project.id,
                  );

                  _expandedProjectIds.remove(project.id);

                  if (_selectedTargetId == project.id) {
                    _selectedTargetId = null;
                  }
                });

                try {
                  await _firebaseService.deleteProject(
                    project.id,
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(
                    dialogContext,
                  ).pop();

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Projeto ${project.id} removido do Firebase!',
                      ),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir projeto: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EXCLUIR SUBTAREFA
  // ============================================================

  Future<void> _confirmDeleteSubTask(
    ProjectModel project,
    TaskModel task,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              16,
            ),
            side: BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Excluir Subtrabalho (Etapa)',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente excluir a etapa "${task.stage}" (Nº ${task.subId})?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
              ),
              onPressed: () async {
                final subTargetId = '${project.id}_${task.subId}';

                if (_activeTimerTargetId == subTargetId) {
                  await _stopTimer();
                }

                setState(() {
                  project.subTasks?.removeWhere(
                    (t) => t.subId == task.subId,
                  );

                  widget.timeLogStore.removeByTargetId(
                    subTargetId,
                  );

                  if (_selectedTargetId == subTargetId) {
                    _selectedTargetId = null;
                  }
                });

                try {
                  await _firebaseService.saveProject(
                    project,
                  );

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(
                    dialogContext,
                  ).pop();

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Subtrabalho excluído com sucesso!',
                      ),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir subtrabalho: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // EXPANDIR PROJETO
  // ============================================================

  void _toggleExpand(
    String id,
  ) {
    setState(() {
      if (_expandedProjectIds.contains(id)) {
        _expandedProjectIds.remove(id);
      } else {
        _expandedProjectIds.add(id);
      }
    });
  }

  // ============================================================
  // CRIAR NOVO PROJETO
  // ============================================================

  Future<void> _createNewProject() async {
    final ProjectModel? newProject = await showDialog<ProjectModel>(
      context: context,
      builder: (context) => ProjectFormDialog(
        workFormats: widget.workFormats,
      ),
    );

    if (newProject == null) {
      return;
    }

    final matchingFormats = widget.workFormats.where(
      (wf) => wf.name.toLowerCase() == newProject.serviceType.toLowerCase(),
    );

    final matchingFormat =
        matchingFormats.isNotEmpty ? matchingFormats.first : null;

    final List<TaskModel> generatedTasks = [];

    if (matchingFormat != null && matchingFormat.steps.isNotEmpty) {
      int subIdCounter = 1;

      for (final step in matchingFormat.steps) {
        const stepHours = 10;

        generatedTasks.add(
          TaskModel(
            subId: subIdCounter.toString(),
            stage: step,
            status: 'INI_PRO',
            startDate: newProject.startDate,
            planStart: newProject.startDate,
            planEnd: newProject.startDate.add(
              const Duration(
                days: 30,
              ),
            ),
            estimatedHours: '${stepHours.toString().padLeft(2, '0')}:00',
            hourType: newProject.hourType,
          ),
        );

        subIdCounter++;
      }
    }

    final projectWithSubtasks = ProjectModel(
      id: newProject.id,
      id2: newProject.id2,
      client: newProject.client,
      serviceType: newProject.serviceType,
      stage: newProject.stage,
      task: newProject.task,
      status: newProject.status,
      startDate: newProject.startDate,
      estimatedHours: newProject.estimatedHours,
      leader: newProject.leader,
      hourType: newProject.hourType,
      subTasks:
          generatedTasks.isNotEmpty ? generatedTasks : newProject.subTasks,
      checklist: newProject.checklist,
      observacao: newProject.observacao,
      excelLink: newProject.excelLink,
      folderPath: newProject.folderPath,
    );

    await _firebaseService.saveProject(
      projectWithSubtasks,
    );

    setState(() {
      _projects.add(
        projectWithSubtasks,
      );

      if (projectWithSubtasks.subTasks != null &&
          projectWithSubtasks.subTasks!.isNotEmpty) {
        _expandedProjectIds.add(
          projectWithSubtasks.id,
        );
      }

      if (_selectedTargetId == null) {
        _selectedTargetId = projectWithSubtasks.id;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Projeto salvo no Firebase com sucesso!',
          ),
        ),
      );
    }
  }

  // ============================================================
  // HORAS DOS ÚLTIMOS 10 DIAS
  // ============================================================

  List<DailyHoursPoint> _buildDailyHoursPoints() {
    final now = DateTime.now();

    final points = <DailyHoursPoint>[];

    for (int i = 9; i >= 0; i--) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(
        Duration(
          days: i,
        ),
      );

      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

      points.add(
        DailyHoursPoint(
          label: '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}',
          hours: _getHoursForDate(
            date,
          ),
          isWeekend: isWeekend,
          isHighlighted: i == 0,
        ),
      );
    }

    return points;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final filteredProjects = _projects.where(
      (p) {
        final matchesActive = _onlyActive ? p.status != 'TRAB_FIM' : true;

        final query = _searchQuery.toLowerCase();

        final matchesSearch = p.client.toLowerCase().contains(query) ||
            p.id.contains(
              _searchQuery,
            ) ||
            p.serviceType.toLowerCase().contains(query);

        final matchesDate = _filterOptions.selectedDate == null ||
            (p.startDate.year == _filterOptions.selectedDate!.year &&
                p.startDate.month == _filterOptions.selectedDate!.month &&
                p.startDate.day == _filterOptions.selectedDate!.day);

        final matchesServiceType = _filterOptions.serviceType == null ||
            p.serviceType.toLowerCase() ==
                _filterOptions.serviceType!.toLowerCase();

        bool matchesShift = true;

        if (_filterOptions.shift == 'Manhã') {
          final logs = _timeLogs.where(
            (l) => l.targetId.split('_').first == p.id,
          );

          matchesShift = logs.any(
            (l) {
              final hour = int.tryParse(
                    l.startTime.split(':').first,
                  ) ??
                  0;

              return hour < 12;
            },
          );
        } else if (_filterOptions.shift == 'Tarde') {
          final logs = _timeLogs.where(
            (l) => l.targetId.split('_').first == p.id,
          );

          matchesShift = logs.any(
            (l) {
              final hour = int.tryParse(
                    l.startTime.split(':').first,
                  ) ??
                  0;

              return hour >= 12 && hour < 18;
            },
          );
        }

        return matchesActive &&
            matchesSearch &&
            matchesDate &&
            matchesServiceType &&
            matchesShift;
      },
    ).toList();

    final defaultTargetId = _projects.isNotEmpty ? _projects.first.id : '';

    final activeProject = _projects.firstWhere(
      (p) => p.id == (_selectedTargetId?.split('_').first ?? defaultTargetId),
      orElse: () => _projects.isNotEmpty
          ? _projects.first
          : ProjectModel(
              id: '',
              id2: '',
              client: 'Nenhum projeto',
              serviceType: '',
              stage: '',
              task: '',
              status: '',
              startDate: DateTime.now(),
              estimatedHours: '00:00',
              leader: '',
              hourType: '',
            ),
    );

    final dailyHoursPoints = _buildDailyHoursPoints();

    return Scaffold(
      backgroundColor: CoresDashboard.fundo,
      appBar: Cabecalho(
        selectedIndex: widget.selectedIndex,
        onSelectTab: widget.onSelectTab,
        searchQuery: _searchQuery,
        onSearchChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        userName: '',
      ),
      body: _isLoadingProjects
          ? Center(
              child: CircularProgressIndicator(
                color: CoresApp.destaque,
              ),
            )
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 175,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SizedBox.expand(
                              child: ControleProjetosWidget(
                                agrupar: _agrupar,
                                ordenarPrioridade: _ordenarPrioridade,
                                somenteAtivos: _onlyActive,
                                filtroAtivo: _filterOptions.hasFilter,
                                expandedProjectIds: _expandedProjectIds,
                                onNewProject: _createNewProject,
                                onSynchronize: () {
                                  _loadProjectsFromFirebase(
                                    showLoader: false,
                                  );
                                },
                                onFilter: _openFilterDialog,
                                onManual: () {
                                  final target = _selectedTargetId ??
                                      (_projects.isNotEmpty
                                          ? _projects.first.id
                                          : 'Geral');

                                  _showManualTimeDialog(
                                    target,
                                  );
                                },
                                onStart: () {
                                  final target = _selectedTargetId ??
                                      (_projects.isNotEmpty
                                          ? _projects.first.id
                                          : null);

                                  if (target != null) {
                                    _startTimer(
                                      target,
                                    );
                                  } else {
                                    ScaffoldMessenger.of(
                                      context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Selecione um trabalho na tabela para iniciar!',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                onPause: _pauseTimer,
                                onStop: _stopTimer,
                                onAgruparChanged: (value) {
                                  setState(() {
                                    _agrupar = value ?? false;
                                  });
                                },
                                onOrdenarPrioridadeChanged: (value) {
                                  setState(() {
                                    _ordenarPrioridade = value ?? false;
                                  });
                                },
                                onSomenteAtivosChanged: (value) {
                                  setState(() {
                                    _onlyActive = value ?? false;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            flex: 6,
                            child: SizedBox.expand(
                              child: ProgressoProjetoWidget(
                                activeProject: activeProject,
                                timeLogs: _timeLogs,
                                parseTimeToHours: _parseTimeToHours,
                                formatHours: _formatHours,
                                formatDateShort: _formatDateShort,
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            flex: 3,
                            child: SizedBox.expand(
                              child: GraficoHorasWidget(
                                points: dailyHoursPoints,
                                formatHours: _formatHours,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: 350,
                      ),
                      child: TabelaProjetosWidget(
                        projects: filteredProjects,
                        statusList: _statusList,
                        expandedProjectIds: _expandedProjectIds,
                        selectedTargetId: _selectedTargetId,
                        timeLogs: _timeLogs,
                        activeTimerTargetId: _activeTimerTargetId,
                        activeStartTime: _activeStartTime,
                        timerState: _timerState,
                        secondsElapsed: _secondsElapsed,
                        showPostStopButton: _showPostStopButton,
                        horizontalController: _horizontalTableScroll,
                        verticalController: _verticalTableScroll,
                        onSelectTarget: (targetId) {
                          setState(() {
                            _selectedTargetId = targetId;
                          });
                        },
                        onToggleExpand: _toggleExpand,
                        onEditProject: (project) {
                          setState(() {
                            final index = _projects.indexWhere(
                              (p) => p.id == project.id,
                            );

                            if (index != -1) {
                              _projects[index] = project;
                            }
                          });
                        },
                        onDeleteProject: _confirmDeleteProject,
                        onAddSubTask: _addNewTaskDialog,
                        onProjectStatusChanged: (
                          project,
                          newStatus,
                        ) async {
                          setState(() {
                            project.status = newStatus;
                          });

                          try {
                            await _firebaseService.saveProject(
                              project,
                            );

                            if (newStatus == 'TRAB_FIM') {
                              widget.onProjectCompleted?.call(
                                project,
                              );

                              if (context.mounted) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Projeto ${project.id} finalizado e movido!',
                                    ),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Erro ao atualizar status: $e',
                                  ),
                                  backgroundColor: CoresApp.erro,
                                ),
                              );
                            }
                          }
                        },
                        onSubTaskStatusChanged: (
                          task,
                          newStatus,
                        ) async {
                          setState(() {
                            task.status = newStatus;
                          });

                          final parent = _projects.firstWhere(
                            (p) =>
                                p.subTasks?.contains(
                                  task,
                                ) ??
                                false,
                            orElse: () => _projects.first,
                          );

                          await _firebaseService.saveProject(
                            parent,
                          );
                        },
                        onEditSubTask: _editSubTaskDialog,
                        onDeleteSubTask: _confirmDeleteSubTask,
                        onStartTimer: _startTimer,
                        onPauseTimer: _pauseTimer,
                        onStopTimer: _stopTimer,
                        onManualTime: _showManualTimeDialog,
                        onEditLog: _editLogDialog,
                        onDeleteLog: _confirmDeleteLog,
                        onRegisterLog: (log) async {
                          try {
                            await widget.timeLogStore.register(
                              log,
                            );

                            if (!mounted) {
                              return;
                            }

                            setState(() {
                              _showPostStopButton = false;
                            });

                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Tempo cadastrado e salvo no Firebase com sucesso!',
                                ),
                                backgroundColor: CoresApp.sucesso,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) {
                              return;
                            }

                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Erro ao cadastrar tempo no Firebase: $e',
                                ),
                                backgroundColor: CoresApp.erro,
                              ),
                            );
                          }
                        },
                        onMarkTaskCompleted: (task) async {
                          setState(() {
                            task.status = 'TRAB';
                          });

                          final parent = _projects.firstWhere(
                            (p) =>
                                p.subTasks?.contains(
                                  task,
                                ) ??
                                false,
                            orElse: () => _projects.first,
                          );

                          await _firebaseService.saveProject(
                            parent,
                          );

                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Etapa ${task.subId} marcada como realizada!',
                                ),
                              ),
                            );
                          }
                        },
                        formatDuration: _formatDuration,
                        firebaseService: _firebaseService,
                      ),
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    CentralAlertasWidget(
                      projects: _projects,
                      formatDateShort: _formatDateShort,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
