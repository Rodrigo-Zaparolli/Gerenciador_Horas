import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
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

  // Variáveis de estado para a foto de perfil na tela principal
  ImageProvider? _fotoPerfilProvider;
  bool _carregandoFoto = true;

  // Variáveis de estado para os filtros do ControleProjetosWidget
  String? _tipoServicoSelecionado;
  String _filtroProjetos = '';
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;

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

  List<ProjectModel> _projects = [];
  List<WorkFormat> _workFormatsFirebase = [];

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
    _carregarFotoDoFirestore();
    _loadDataFromFirebase(showLoader: true);
  }

  // ============================================================
  // GERENCIAMENTO DA FOTO DE PERFIL
  // ============================================================

  Future<void> _carregarFotoDoFirestore() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists && doc.data()?['photoBase64'] != null) {
          final String base64Str = doc.data()!['photoBase64'];
          final bytes = base64Decode(base64Str);
          if (mounted) {
            setState(() {
              _fotoPerfilProvider = MemoryImage(bytes);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar foto: $e');
    } finally {
      if (mounted) {
        setState(() {
          _carregandoFoto = false;
        });
      }
    }
  }

  Future<void> _alterarFotoPerfil() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 70,
    );

    if (image == null) return;

    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final bytes = await image.readAsBytes();
        final String base64Image = base64Encode(bytes);

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'photoBase64': base64Image,
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() {
            _fotoPerfilProvider = MemoryImage(bytes);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto alterada com sucesso!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alterar foto: $e')),
        );
      }
    }
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
  // CARREGAR DADOS DO FIREBASE (PROJETOS E WORK FORMATS)
  // ============================================================

  Future<void> _loadDataFromFirebase({
    bool showLoader = false,
  }) async {
    if (showLoader) {
      setState(() {
        _isLoadingProjects = true;
      });
    }

    try {
      final results = await Future.wait([
        _firebaseService.getProjects(),
        _firebaseService.getWorkFormats(),
      ]);

      final loadedProjects = results[0] as List<ProjectModel>;
      final loadedWorkFormats = results[1] as List<WorkFormat>;

      final projectIds = loadedProjects
          .map((project) => project.id.trim())
          .where((id) => id.isNotEmpty)
          .toList();

      await widget.timeLogStore.startListeningToProjects(projectIds);

      if (!mounted) {
        return;
      }

      setState(() {
        _projects = loadedProjects;
        _workFormatsFirebase = loadedWorkFormats;
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
          content: Text('Erro ao carregar dados do Firebase: $e'),
          backgroundColor: CoresApp.erro,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        totalSeconds = endTime.difference(startTime).inSeconds;

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
              content: const Text('Tempo de trabalho salvo no Firebase.'),
              backgroundColor: CoresApp.sucesso,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao salvar o tempo no Firebase: $e'),
              backgroundColor: CoresApp.erro,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
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

  String _formatDuration(int seconds) {
    final hours = (seconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  double _parseTimeToHours(String timeFormatted) {
    final parts = timeFormatted.split(':');

    if (parts.length < 2) {
      return 0.0;
    }

    final hours = double.tryParse(parts[0]) ?? 0.0;
    final minutes = double.tryParse(parts[1]) ?? 0.0;

    return hours + (minutes / 60.0);
  }

  String _formatHours(double hours) {
    int h = hours.toInt();
    int m = ((hours - h) * 60).round();

    if (m >= 60) {
      h++;
      m = 0;
    }

    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formatDateShort(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year.toString().substring(2)}';
  }

  // ============================================================
  // HORAS POR DATA
  // ============================================================

  double _getHoursForDate(DateTime targetDate) {
    double totalHours = 0.0;

    for (final log in _timeLogs.where((l) => l.isRegistered)) {
      if (log.date.year == targetDate.year &&
          log.date.month == targetDate.month &&
          log.date.day == targetDate.day) {
        totalHours += _parseTimeToHours(log.durationFormatted);
      }
    }

    return totalHours;
  }

  // ============================================================
  // EDITAR SUBTRABALHO
  // ============================================================

  void _editSubTaskDialog(ProjectModel project, TaskModel task) {
    final subIdController = TextEditingController(text: task.subId);
    final stageController = TextEditingController(text: task.stage);
    final serviceTypeController =
        TextEditingController(text: project.serviceType);
    final hoursController = TextEditingController(text: task.estimatedHours);
    final hourTypeController = TextEditingController(text: task.hourType);

    DateTime startDate = task.startDate;
    DateTime endDate = task.planEnd ?? task.startDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: CoresApp.borda),
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
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Número (Nº)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: serviceTypeController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Serviço',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stageController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Trabalho / Etapa',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Horas Estimadas (ex: 10:00)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hourTypeController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Horas (ex: Hs Cobradas)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: CoresApp.bordaSuave),
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
                              int diaTemp = startDate.day;
                              int mesTemp = startDate.month;
                              int anoTemp = startDate.year;

                              final DateTime? picked =
                                  await showDialog<DateTime>(
                                context: context,
                                builder: (BuildContext dialogContext) {
                                  return StatefulBuilder(
                                    builder: (context, setStateDialog) {
                                      return AlertDialog(
                                        backgroundColor:
                                            const Color(0xFF1B1B2A),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          side: BorderSide(
                                              color: Colors.white
                                                  .withOpacity(0.16)),
                                        ),
                                        title: const Row(
                                          children: [
                                            Icon(Icons.calendar_today_outlined,
                                                color: Color(0xFF35D27F),
                                                size: 20),
                                            SizedBox(width: 10),
                                            Text(
                                              'Selecionar Data',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15),
                                            ),
                                          ],
                                        ),
                                        content: SizedBox(
                                          width: 300,
                                          height: 110,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              // DIA
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Dia',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: diaTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              31,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              diaTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // MÊS
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Mês',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: mesTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              12,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              mesTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // ANO
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Ano',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: anoTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              11,
                                                              (index) =>
                                                                  2020 + index)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              anoTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(dialogContext)
                                                    .pop(null),
                                            child: const Text('Cancelar',
                                                style: TextStyle(
                                                    color: Color(0xFFBDBDC7))),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF35D27F),
                                              foregroundColor: Colors.black,
                                            ),
                                            onPressed: () {
                                              try {
                                                final novaData = DateTime(
                                                    anoTemp, mesTemp, diaTemp);
                                                Navigator.of(dialogContext)
                                                    .pop(novaData);
                                              } catch (_) {
                                                Navigator.of(dialogContext)
                                                    .pop(null);
                                              }
                                            },
                                            child: const Text('Confirmar',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: CoresApp.bordaSuave),
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
                              int diaTemp = startDate.day;
                              int mesTemp = startDate.month;
                              int anoTemp = startDate.year;

                              final DateTime? picked =
                                  await showDialog<DateTime>(
                                context: context,
                                builder: (BuildContext dialogContext) {
                                  return StatefulBuilder(
                                    builder: (context, setStateDialog) {
                                      return AlertDialog(
                                        backgroundColor:
                                            const Color(0xFF1B1B2A),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          side: BorderSide(
                                              color: Colors.white
                                                  .withOpacity(0.16)),
                                        ),
                                        title: const Row(
                                          children: [
                                            Icon(Icons.calendar_today_outlined,
                                                color: Color(0xFF35D27F),
                                                size: 20),
                                            SizedBox(width: 10),
                                            Text(
                                              'Selecionar Data',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15),
                                            ),
                                          ],
                                        ),
                                        content: SizedBox(
                                          width: 300,
                                          height: 110,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              // DIA
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Dia',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: diaTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              31,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              diaTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // MÊS
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Mês',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: mesTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              12,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              mesTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // ANO
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Ano',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: anoTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              11,
                                                              (index) =>
                                                                  2020 + index)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              anoTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(dialogContext)
                                                    .pop(null),
                                            child: const Text('Cancelar',
                                                style: TextStyle(
                                                    color: Color(0xFFBDBDC7))),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF35D27F),
                                              foregroundColor: Colors.black,
                                            ),
                                            onPressed: () {
                                              try {
                                                final novaData = DateTime(
                                                    anoTemp, mesTemp, diaTemp);
                                                Navigator.of(dialogContext)
                                                    .pop(novaData);
                                              } catch (_) {
                                                Navigator.of(dialogContext)
                                                    .pop(null);
                                              }
                                            },
                                            child: const Text('Confirmar',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: CoresApp.textoSecundario),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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

                    await _firebaseService.saveProject(project);

                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              const Text('Subtrabalho atualizado com sucesso!'),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Salvar',
                    style: TextStyle(fontWeight: FontWeight.bold),
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

  void _addNewTaskDialog(ProjectModel project) {
    final subIdController = TextEditingController(
      text: ((project.subTasks?.length ?? 0) + 1).toString(),
    );
    final stageController = TextEditingController();
    final serviceTypeController =
        TextEditingController(text: project.serviceType);
    final hoursController = TextEditingController(text: '10:00');
    final hourTypeController = TextEditingController(text: project.hourType);

    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 15));

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: CoresApp.borda),
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
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Número da Etapa (Nº)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stageController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Trabalho / Etapa',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: serviceTypeController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Serviço',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Horas Estimadas (ex: 10:00)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hourTypeController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Tipo de Horas',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: CoresApp.bordaSuave),
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
                              int diaTemp = startDate.day;
                              int mesTemp = startDate.month;
                              int anoTemp = startDate.year;

                              final DateTime? picked =
                                  await showDialog<DateTime>(
                                context: context,
                                builder: (BuildContext dialogContext) {
                                  return StatefulBuilder(
                                    builder: (context, setStateDialog) {
                                      return AlertDialog(
                                        backgroundColor:
                                            const Color(0xFF1B1B2A),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          side: BorderSide(
                                              color: Colors.white
                                                  .withOpacity(0.16)),
                                        ),
                                        title: const Row(
                                          children: [
                                            Icon(Icons.calendar_today_outlined,
                                                color: Color(0xFF35D27F),
                                                size: 20),
                                            SizedBox(width: 10),
                                            Text(
                                              'Selecionar Data',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15),
                                            ),
                                          ],
                                        ),
                                        content: SizedBox(
                                          width: 300,
                                          height: 110,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              // DIA
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Dia',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: diaTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              31,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              diaTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // MÊS
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Mês',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: mesTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              12,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              mesTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // ANO
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Ano',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: anoTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              11,
                                                              (index) =>
                                                                  2020 + index)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              anoTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(dialogContext)
                                                    .pop(null),
                                            child: const Text('Cancelar',
                                                style: TextStyle(
                                                    color: Color(0xFFBDBDC7))),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF35D27F),
                                              foregroundColor: Colors.black,
                                            ),
                                            onPressed: () {
                                              try {
                                                final novaData = DateTime(
                                                    anoTemp, mesTemp, diaTemp);
                                                Navigator.of(dialogContext)
                                                    .pop(novaData);
                                              } catch (_) {
                                                Navigator.of(dialogContext)
                                                    .pop(null);
                                              }
                                            },
                                            child: const Text('Confirmar',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor: CoresDashboard.fundoSecundario,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: CoresApp.bordaSuave),
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
                              int diaTemp = startDate.day;
                              int mesTemp = startDate.month;
                              int anoTemp = startDate.year;

                              final DateTime? picked =
                                  await showDialog<DateTime>(
                                context: context,
                                builder: (BuildContext dialogContext) {
                                  return StatefulBuilder(
                                    builder: (context, setStateDialog) {
                                      return AlertDialog(
                                        backgroundColor:
                                            const Color(0xFF1B1B2A),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          side: BorderSide(
                                              color: Colors.white
                                                  .withOpacity(0.16)),
                                        ),
                                        title: const Row(
                                          children: [
                                            Icon(Icons.calendar_today_outlined,
                                                color: Color(0xFF35D27F),
                                                size: 20),
                                            SizedBox(width: 10),
                                            Text(
                                              'Selecionar Data',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15),
                                            ),
                                          ],
                                        ),
                                        content: SizedBox(
                                          width: 300,
                                          height: 110,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              // DIA
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Dia',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: diaTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              31,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              diaTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // MÊS
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Mês',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: mesTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              12,
                                                              (index) =>
                                                                  index + 1)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()
                                                                .padLeft(
                                                                    2, '0')));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              mesTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Text('/',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 20)),
                                              // ANO
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Text('Ano',
                                                        style: TextStyle(
                                                            color: Colors.grey,
                                                            fontSize: 12)),
                                                    const SizedBox(height: 5),
                                                    DropdownButton<int>(
                                                      value: anoTemp,
                                                      dropdownColor:
                                                          const Color(
                                                              0xFF1B1B2A),
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 16),
                                                      items: List.generate(
                                                              11,
                                                              (index) =>
                                                                  2020 + index)
                                                          .map((val) {
                                                        return DropdownMenuItem(
                                                            value: val,
                                                            child: Text(val
                                                                .toString()));
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null)
                                                          setStateDialog(() =>
                                                              anoTemp = val);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(dialogContext)
                                                    .pop(null),
                                            child: const Text('Cancelar',
                                                style: TextStyle(
                                                    color: Color(0xFFBDBDC7))),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFF35D27F),
                                              foregroundColor: Colors.black,
                                            ),
                                            onPressed: () {
                                              try {
                                                final novaData = DateTime(
                                                    anoTemp, mesTemp, diaTemp);
                                                Navigator.of(dialogContext)
                                                    .pop(novaData);
                                              } catch (_) {
                                                Navigator.of(dialogContext)
                                                    .pop(null);
                                              }
                                            },
                                            child: const Text('Confirmar',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: CoresApp.textoSecundario),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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

                      _expandedProjectIds.add(project.id);
                    });

                    await _firebaseService.saveProject(project);

                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Etapa "$stageName" adicionada com sucesso!'),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Adicionar',
                    style: TextStyle(fontWeight: FontWeight.bold),
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
  // HORAS MANUAIS
  // ============================================================

  Future<void> _showManualTimeDialog(String itemTitle) async {
    final hoursController = TextEditingController();
    final minutesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: CoresApp.borda),
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
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Horas',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: minutesController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Minutos',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(color: CoresApp.textoSecundario),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: CoresApp.textoPrincipal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final h = int.tryParse(hoursController.text.trim()) ?? 0;
                final m = int.tryParse(minutesController.text.trim()) ?? 0;

                if (h <= 0 && m <= 0) {
                  return;
                }

                final now = DateTime.now();
                final durationFormatted = '${h.toString().padLeft(2, '0')}:'
                    '${m.toString().padLeft(2, '0')}';

                final startFormatted = '${now.hour.toString().padLeft(2, '0')}:'
                    '${now.minute.toString().padLeft(2, '0')}';

                final endDateTime = now.add(Duration(hours: h, minutes: m));
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

                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Apontado manualmente ${h}h ${m}m e salvo no Firebase!'),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao salvar apontamento manual: $e'),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              child: const Text(
                'Salvar',
                style: TextStyle(fontWeight: FontWeight.bold),
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

  Future<void> _editLogDialog(TimeLog log) async {
    final startController = TextEditingController(text: log.startTime);
    final endController = TextEditingController(text: log.endTime);
    final durationController =
        TextEditingController(text: log.durationFormatted);
    final descriptionController =
        TextEditingController(text: log.description ?? '');

    void calculateDuration() {
      final startParts = startController.text.split(':');
      final endParts = endController.text.split(':');

      if (startParts.length == 2 && endParts.length == 2) {
        final sh = int.tryParse(startParts[0]) ?? 0;
        final sm = int.tryParse(startParts[1]) ?? 0;
        final eh = int.tryParse(endParts[0]) ?? 0;
        final em = int.tryParse(endParts[1]) ?? 0;

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
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: CoresDashboard.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: CoresApp.borda),
              ),
              title: Text(
                'Editar Horário de Apontamento',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: startController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Hora Início (ex: 14:00)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                      onChanged: (_) {
                        calculateDuration();
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Hora Fim (ex: 15:30)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                      onChanged: (_) {
                        calculateDuration();
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: durationController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      decoration: InputDecoration(
                        labelText: 'Duração (ex: 01:30)',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      style: TextStyle(color: CoresApp.textoPrincipal),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Descrição / Comentário',
                        labelStyle: TextStyle(color: CoresApp.textoSecundario),
                        filled: true,
                        fillColor: CoresDashboard.fundoSecundario,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: CoresApp.borda),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: CoresApp.primaria, width: 1.5),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: CoresApp.textoSecundario),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    setState(() {
                      log.startTime = startController.text.trim();
                      log.endTime = endController.text.trim();
                      log.durationFormatted = durationController.text.trim();
                      log.description =
                          descriptionController.text.trim().isEmpty
                              ? null
                              : descriptionController.text.trim();

                      if (_activeTimerTargetId == log.targetId) {
                        final durationParts = log.durationFormatted.split(':');

                        if (durationParts.length >= 2) {
                          final h = int.tryParse(durationParts[0]) ?? 0;
                          final m = int.tryParse(durationParts[1]) ?? 0;
                          _secondsElapsed = (h * 3600) + (m * 60);
                        }

                        final startParts = log.startTime.split(':');

                        if (startParts.length == 2) {
                          final sh =
                              int.tryParse(startParts[0]) ?? log.date.hour;
                          final sm =
                              int.tryParse(startParts[1]) ?? log.date.minute;
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
                      await widget.timeLogStore.updateFirebaseLog(log);

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.of(dialogContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                              'Apontamento atualizado e salvo no Firebase!'),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    } catch (e) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao atualizar apontamento: $e'),
                          backgroundColor: CoresApp.erro,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'Salvar',
                    style: TextStyle(fontWeight: FontWeight.bold),
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
    descriptionController.dispose();
  }

  // ============================================================
  // EXCLUIR APONTAMENTO
  // ============================================================

  Future<void> _confirmDeleteLog(TimeLog log) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: CoresApp.borda),
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
            style: TextStyle(color: CoresApp.textoSecundario),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(color: CoresApp.textoSecundario),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                try {
                  await widget.timeLogStore.deleteFirebaseLog(log);

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Apontamento excluído do Firebase!'),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao excluir apontamento: $e'),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(color: CoresApp.textoPrincipal),
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

  Future<void> _confirmDeleteProject(ProjectModel project) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: CoresApp.borda),
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
            style: TextStyle(color: CoresApp.textoSecundario),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(color: CoresApp.textoSecundario),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                if (_activeTimerTargetId == project.id ||
                    (_activeTimerTargetId?.startsWith('${project.id}_') ??
                        false)) {
                  await _stopTimer();
                }

                setState(() {
                  _projects.removeWhere((p) => p.id == project.id);
                  _expandedProjectIds.remove(project.id);

                  if (_selectedTargetId == project.id) {
                    _selectedTargetId = null;
                  }
                });

                try {
                  await _firebaseService.deleteProject(project.id);

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Projeto ${project.id} removido do Firebase!'),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao excluir projeto: $e'),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(color: CoresApp.textoPrincipal),
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
      ProjectModel project, TaskModel task) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: CoresApp.borda),
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
            style: TextStyle(color: CoresApp.textoSecundario),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancelar',
                style: TextStyle(color: CoresApp.textoSecundario),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final subTargetId = '${project.id}_${task.subId}';

                if (_activeTimerTargetId == subTargetId) {
                  await _stopTimer();
                }

                setState(() {
                  project.subTasks?.removeWhere((t) => t.subId == task.subId);
                  widget.timeLogStore.removeByTargetId(subTargetId);

                  if (_selectedTargetId == subTargetId) {
                    _selectedTargetId = null;
                  }
                });

                try {
                  await _firebaseService.saveProject(project);

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Subtrabalho excluído com sucesso!'),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao excluir subtrabalho: $e'),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              child: Text(
                'Excluir',
                style: TextStyle(color: CoresApp.textoPrincipal),
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

  void _toggleExpand(String id) {
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
        workFormats: _workFormatsFirebase.isNotEmpty
            ? _workFormatsFirebase
            : widget.workFormats,
      ),
    );

    if (newProject == null) {
      return;
    }

    final activeWorkFormats = _workFormatsFirebase.isNotEmpty
        ? _workFormatsFirebase
        : widget.workFormats;
    final matchingFormats = activeWorkFormats.where(
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
            planEnd: newProject.startDate.add(const Duration(days: 30)),
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

    await _firebaseService.saveProject(projectWithSubtasks);

    setState(() {
      _projects.add(projectWithSubtasks);

      if (projectWithSubtasks.subTasks != null &&
          projectWithSubtasks.subTasks!.isNotEmpty) {
        _expandedProjectIds.add(projectWithSubtasks.id);
      }

      if (_selectedTargetId == null) {
        _selectedTargetId = projectWithSubtasks.id;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Projeto salvo no Firebase com sucesso!'),
          backgroundColor: CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      ).subtract(Duration(days: i));

      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

      points.add(
        DailyHoursPoint(
          label: '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}',
          hours: _getHoursForDate(date),
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
  Widget build(BuildContext context) {
    final filteredProjects = _projects.where((p) {
      final matchesActive = _onlyActive ? p.status != 'TRAB_FIM' : true;
      final query = _searchQuery.toLowerCase();

      final matchesSearch = p.client.toLowerCase().contains(query) ||
          p.id.contains(_searchQuery) ||
          p.serviceType.toLowerCase().contains(query);

      final matchesProjectFilter = _filtroProjetos.isEmpty ||
          p.id.toLowerCase().contains(_filtroProjetos.toLowerCase()) ||
          p.client.toLowerCase().contains(_filtroProjetos.toLowerCase());

      final matchesServiceType = _tipoServicoSelecionado == null ||
          _tipoServicoSelecionado!.trim().isEmpty ||
          p.serviceType.trim().toLowerCase() ==
              _tipoServicoSelecionado!.trim().toLowerCase();

      final matchesStartDate = _dataInicioFiltro == null ||
          (p.startDate.year == _dataInicioFiltro!.year &&
              p.startDate.month == _dataInicioFiltro!.month &&
              p.startDate.day == _dataInicioFiltro!.day);

      final matchesDateOption = _filterOptions.selectedDate == null ||
          (p.startDate.year == _filterOptions.selectedDate!.year &&
              p.startDate.month == _filterOptions.selectedDate!.month &&
              p.startDate.day == _filterOptions.selectedDate!.day);

      bool matchesShift = true;

      if (_filterOptions.shift == 'Manhã') {
        final logs = _timeLogs.where(
          (l) => l.targetId.split('_').first == p.id,
        );

        matchesShift = logs.any((l) {
          final hour = int.tryParse(l.startTime.split(':').first) ?? 0;
          return hour < 12;
        });
      } else if (_filterOptions.shift == 'Tarde') {
        final logs = _timeLogs.where(
          (l) => l.targetId.split('_').first == p.id,
        );

        matchesShift = logs.any((l) {
          final hour = int.tryParse(l.startTime.split(':').first) ?? 0;
          return hour >= 12 && hour < 18;
        });
      }

      return matchesActive &&
          matchesSearch &&
          matchesProjectFilter &&
          matchesServiceType &&
          matchesStartDate &&
          matchesDateOption &&
          matchesShift;
    }).toList();

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

    final availableWorkFormats = _workFormatsFirebase.isNotEmpty
        ? _workFormatsFirebase
        : widget.workFormats;
    final List<String> tiposServicoNomes =
        availableWorkFormats.map((wf) => wf.name).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
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
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/fundo.png'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.4),
              BlendMode.darken,
            ),
          ),
        ),
        child: _isLoadingProjects
            ? Center(
                child: CircularProgressIndicator(
                  color: CoresApp.destaque,
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 180,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 3,
                              child: SizedBox.expand(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: CoresDashboard.card,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: CoresApp.borda, width: 0.8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: ControleProjetosWidget(
                                      agrupar: _agrupar,
                                      ordenarPrioridade: _ordenarPrioridade,
                                      somenteAtivos: _onlyActive,
                                      filtroAtivo: _filterOptions.hasFilter ||
                                          (_tipoServicoSelecionado != null &&
                                              _tipoServicoSelecionado!
                                                  .isNotEmpty) ||
                                          _filtroProjetos.isNotEmpty ||
                                          _dataInicioFiltro != null ||
                                          _dataFimFiltro != null,
                                      expandedProjectIds: _expandedProjectIds,
                                      onNewProject: _createNewProject,
                                      onSynchronize: () {
                                        _loadDataFromFirebase(
                                            showLoader: false);
                                      },
                                      onFilter: () {},
                                      onManual: () {
                                        final target = _selectedTargetId ??
                                            (_projects.isNotEmpty
                                                ? _projects.first.id
                                                : 'Geral');
                                        _showManualTimeDialog(target);
                                      },
                                      onStart: () {
                                        final target = _selectedTargetId ??
                                            (_projects.isNotEmpty
                                                ? _projects.first.id
                                                : null);

                                        if (target != null) {
                                          _startTimer(target);
                                        } else {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: const Text(
                                                  'Selecione um trabalho na tabela para iniciar!'),
                                              backgroundColor: CoresApp.aviso,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
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
                                      filtroProjetos: _filtroProjetos,
                                      tipoServicoSelecionado:
                                          _tipoServicoSelecionado ?? '',
                                      onFiltroProjetosChanged: (String? value) {
                                        setState(() {
                                          _filtroProjetos = value ?? '';
                                        });
                                      },
                                      onTipoServicoChanged: (String? value) {
                                        setState(() {
                                          _tipoServicoSelecionado = value;
                                        });
                                      },
                                      tiposServicoOpcoes: tiposServicoNomes,
                                      onDataInicioChanged: (DateTime? value) {
                                        setState(() {
                                          _dataInicioFiltro = value;
                                        });
                                      },
                                      onDataFimChanged: (DateTime? value) {
                                        setState(() {
                                          _dataFimFiltro = value;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 6,
                              child: SizedBox.expand(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: CoresDashboard.card,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: CoresApp.borda, width: 0.8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: ProgressoProjetoWidget(
                                      activeProject: activeProject,
                                      timeLogs: _timeLogs,
                                      parseTimeToHours: _parseTimeToHours,
                                      formatHours: _formatHours,
                                      formatDateShort: _formatDateShort,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: SizedBox.expand(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: CoresDashboard.card,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: CoresApp.borda, width: 0.8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: GraficoHorasWidget(
                                      points: dailyHoursPoints,
                                      formatHours: _formatHours,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Substituído ConstrainedBox por Container simples para ajustar de forma dinâmica
                      Container(
                        decoration: BoxDecoration(
                          color: CoresDashboard.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: CoresApp.borda, width: 0.8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
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
                            onProjectStatusChanged: (project, newStatus) async {
                              setState(() {
                                project.status = newStatus;
                              });

                              try {
                                await _firebaseService.saveProject(project);

                                if (newStatus == 'TRAB_FIM') {
                                  widget.onProjectCompleted?.call(project);

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Projeto ${project.id} finalizado e movido!'),
                                        backgroundColor: CoresApp.sucesso,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Erro ao atualizar status: $e'),
                                      backgroundColor: CoresApp.erro,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                              }
                            },
                            onSubTaskStatusChanged: (task, newStatus) async {
                              setState(() {
                                task.status = newStatus;
                              });

                              final parent = _projects.firstWhere(
                                (p) => p.subTasks?.contains(task) ?? false,
                                orElse: () => _projects.first,
                              );

                              await _firebaseService.saveProject(parent);
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
                                await widget.timeLogStore.register(log);

                                if (!mounted) {
                                  return;
                                }

                                setState(() {
                                  _showPostStopButton = false;
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                        'Tempo cadastrado e salvo no Firebase com sucesso!'),
                                    backgroundColor: CoresApp.sucesso,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) {
                                  return;
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Erro ao cadastrar tempo no Firebase: $e'),
                                    backgroundColor: CoresApp.erro,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                );
                              }
                            },
                            onMarkTaskCompleted: (task) async {
                              setState(() {
                                task.status = 'TRAB';
                              });

                              final parent = _projects.firstWhere(
                                (p) => p.subTasks?.contains(task) ?? false,
                                orElse: () => _projects.first,
                              );

                              await _firebaseService.saveProject(parent);

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Etapa ${task.subId} marcada como realizada!'),
                                    backgroundColor: CoresApp.sucesso,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                );
                              }
                            },
                            formatDuration: _formatDuration,
                            firebaseService: _firebaseService,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CentralAlertasWidget(
                        projects: _projects,
                        formatDateShort: _formatDateShort,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
