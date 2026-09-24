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
  // ============================================================
  // ESTADO DO DASHBOARD
  // ============================================================

  bool _onlyActive = true;
  bool _agrupar = true;
  bool _ordenarPrioridade = false;
  String _searchQuery = '';

  // ============================================================
  // FOTO DE PERFIL
  // ============================================================

  ImageProvider? _fotoPerfilProvider;
  bool _carregandoFoto = true;

  // ============================================================
  // FILTROS
  // ============================================================

  String? _tipoServicoSelecionado;
  String _filtroProjetos = '';
  DateTime? _dataInicioFiltro;
  DateTime? _dataFimFiltro;
  String? _statusFiltroDashboard;
  bool _filtroApenasAtivos = false;
  bool _filtroTodosProjetos = false;

  // ============================================================
  // PROJETOS
  // ============================================================

  final Set<String> _expandedProjectIds = {};

  bool _showPostStopButton = false;
  bool _isLoadingProjects = true;

  // ============================================================
  // SCROLLS
  // ============================================================

  final ScrollController _verticalTableScroll = ScrollController();
  final ScrollController _horizontalTableScroll = ScrollController();

  // ============================================================
  // FILTROS AVANÇADOS
  // ============================================================

  final FilterOptions _filterOptions = FilterOptions();

  String? _selectedTargetId;

  final List<String> _statusList = [
    'INI_PRO',
    'TRAB',
    'EA',
    'TRAB_STOP',
    'TRAB_FIM',
  ];

  // ============================================================
  // DADOS
  // ============================================================

  List<ProjectModel> _projects = [];
  List<WorkFormat> _workFormatsFirebase = [];

  final FirebaseService _firebaseService = FirebaseService();

  List<TimeLog> get _timeLogs => widget.timeLogStore.logs;

  // ============================================================
  // CRONÔMETRO
  // ============================================================

  String? _activeTimerTargetId;
  DateTime? _activeStartTime;

  // Momento em que o segmento atual de trabalho começou.
  //
  // Exemplo:
  // 14:00 começa
  // 15:00 pausa
  // 15:30 retoma
  // 16:00 para
  //
  // O primeiro segmento é 14:00 -> 15:00.
  // O segundo é 15:30 -> 16:00.
  DateTime? _segmentStartTime;

  // Total de segundos efetivamente trabalhados antes
  // do segmento atual.
  //
  // O tempo em pausa nunca entra aqui.
  int _accumulatedWorkedSeconds = 0;

  TimerState _timerState = TimerState.stopped;

  Timer? _timer;
  int _secondsElapsed = 0;

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: CoresApp.textoSecundario,
      ),
      filled: true,
      fillColor: CoresDashboard.fundoSecundario,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: CoresApp.borda,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: CoresApp.borda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: CoresApp.primaria,
          width: 1.5,
        ),
      ),
      isDense: true,
    );
  }

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
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _carregarFotoDoFirestore();
    _loadDataFromFirebase(showLoader: true);
  }

  // ============================================================
  // FOTO DE PERFIL
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

    if (image == null) {
      return;
    }

    try {
      final User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final bytes = await image.readAsBytes();
        final String base64Image = base64Encode(bytes);

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'photoBase64': base64Image,
          },
          SetOptions(merge: true),
        );

        if (mounted) {
          setState(() {
            _fotoPerfilProvider = MemoryImage(bytes);
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto alterada com sucesso!'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao alterar foto: $e'),
          ),
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

    super.dispose();
  }

  // ============================================================
  // FIREBASE
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ============================================================
  // LOCALIZAR PROJETO/TAREFA PELO TARGET ID
  // ============================================================

  ProjectModel? _findProjectByTargetId(String targetId) {
    final projectId = targetId.split('_').first;

    for (final project in _projects) {
      if (project.id == projectId) {
        return project;
      }
    }

    return null;
  }

  TaskModel? _findTaskByTargetId(
    String targetId,
    ProjectModel project,
  ) {
    if (!targetId.contains('_')) {
      return null;
    }

    final projectId = targetId.split('_').first;

    if (project.id != projectId) {
      return null;
    }

    final subId = targetId.substring(projectId.length + 1);

    for (final task in project.subTasks ?? <TaskModel>[]) {
      if (task.subId == subId) {
        return task;
      }
    }

    return null;
  }

  // ============================================================
  // ATUALIZAR STATUS DO ALVO DO CRONÔMETRO
  // ============================================================

  Future<void> _setTimerTargetStatus(
    String targetId,
    String status,
  ) async {
    final project = _findProjectByTargetId(targetId);

    if (project == null) {
      return;
    }

    if (targetId == project.id) {
      project.status = status;
    } else {
      final task = _findTaskByTargetId(
        targetId,
        project,
      );

      if (task == null) {
        return;
      }

      task.status = status;
    }

    await _firebaseService.saveProject(project);
  }

  // ============================================================
  // CRONÔMETRO
  // ============================================================

  void _startTimer(String targetId) {
    // ----------------------------------------------------------
    // NOVO TRABALHO
    // ----------------------------------------------------------

    if (_activeTimerTargetId != targetId) {
      if (_activeTimerTargetId != null) {
        unawaited(_stopTimer());
      }

      final now = DateTime.now();

      _activeTimerTargetId = targetId;
      _activeStartTime = now;
      _segmentStartTime = now;
      _accumulatedWorkedSeconds = 0;
      _secondsElapsed = 0;
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

          if (_timerState != TimerState.running || _segmentStartTime == null) {
            return;
          }

          final now = DateTime.now();

          final currentSegmentSeconds =
              now.difference(_segmentStartTime!).inSeconds;

          setState(() {
            _secondsElapsed = _accumulatedWorkedSeconds + currentSegmentSeconds;
          });
        },
      );

      unawaited(
        _setTimerTargetStatus(
          targetId,
          'TRAB',
        ),
      );

      setState(() {});

      return;
    }

    // ----------------------------------------------------------
    // MESMO TRABALHO — RETOMAR APÓS PAUSA
    // ----------------------------------------------------------

    if (_timerState == TimerState.paused) {
      final now = DateTime.now();

      _segmentStartTime = now;
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

          if (_timerState != TimerState.running || _segmentStartTime == null) {
            return;
          }

          final now = DateTime.now();

          final currentSegmentSeconds =
              now.difference(_segmentStartTime!).inSeconds;

          setState(() {
            _secondsElapsed = _accumulatedWorkedSeconds + currentSegmentSeconds;
          });
        },
      );

      unawaited(
        _setTimerTargetStatus(
          targetId,
          'TRAB',
        ),
      );

      setState(() {});

      return;
    }

    // ----------------------------------------------------------
    // JÁ ESTÁ RODANDO
    // ----------------------------------------------------------

    if (_timerState == TimerState.running) {
      return;
    }

    // ----------------------------------------------------------
    // CASO GERAL — INICIAR
    // ----------------------------------------------------------

    final now = DateTime.now();

    _activeTimerTargetId = targetId;
    _activeStartTime ??= now;
    _segmentStartTime = now;
    _accumulatedWorkedSeconds = 0;
    _secondsElapsed = 0;
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

        if (_timerState != TimerState.running || _segmentStartTime == null) {
          return;
        }

        final now = DateTime.now();

        final currentSegmentSeconds =
            now.difference(_segmentStartTime!).inSeconds;

        setState(() {
          _secondsElapsed = _accumulatedWorkedSeconds + currentSegmentSeconds;
        });
      },
    );

    unawaited(
      _setTimerTargetStatus(
        targetId,
        'TRAB',
      ),
    );

    setState(() {});
  }

  // ============================================================
  // PAUSAR CRONÔMETRO
  // ============================================================

  void _pauseTimer() {
    if (_activeTimerTargetId == null) {
      return;
    }

    if (_timerState != TimerState.running) {
      return;
    }

    final now = DateTime.now();

    // ----------------------------------------------------------
    // FECHA O SEGMENTO ATUAL
    // ----------------------------------------------------------

    if (_segmentStartTime != null) {
      final currentSegmentSeconds =
          now.difference(_segmentStartTime!).inSeconds;

      if (currentSegmentSeconds > 0) {
        _accumulatedWorkedSeconds += currentSegmentSeconds;
      }
    }

    // O valor exibido passa a representar somente o tempo
    // realmente trabalhado.
    _secondsElapsed = _accumulatedWorkedSeconds;

    _segmentStartTime = null;

    _timer?.cancel();
    _timer = null;

    _timerState = TimerState.paused;

    final targetId = _activeTimerTargetId!;

    setState(() {});

    // ----------------------------------------------------------
    // PERSISTIR TRAB_STOP NO FIRESTORE
    // ----------------------------------------------------------

    unawaited(
      _setTimerTargetStatus(
        targetId,
        'TRAB_STOP',
      ),
    );
  }

  // ============================================================
  // FINALIZAR CRONÔMETRO
  // ============================================================

  Future<void> _stopTimer() async {
    _timer?.cancel();
    _timer = null;

    if (_activeTimerTargetId != null) {
      final targetId = _activeTimerTargetId!;
      final endTime = DateTime.now();

      final startTime = _activeStartTime ?? endTime;

      // --------------------------------------------------------
      // CALCULAR O TEMPO REALMENTE TRABALHADO
      // --------------------------------------------------------

      int totalSeconds = _accumulatedWorkedSeconds;

      // Se ainda estava trabalhando, fecha o último segmento.
      //
      // Se estava pausado, _segmentStartTime é null e nenhum
      // segundo do período pausado será contabilizado.
      if (_timerState == TimerState.running && _segmentStartTime != null) {
        final currentSegmentSeconds =
            endTime.difference(_segmentStartTime!).inSeconds;

        if (currentSegmentSeconds > 0) {
          totalSeconds += currentSegmentSeconds;
        }
      }

      // Segurança para impedir valores negativos.
      if (totalSeconds < 0) {
        totalSeconds = 0;
      }

      // --------------------------------------------------------
      // HORÁRIOS
      // --------------------------------------------------------

      final startFormatted = '${startTime.hour.toString().padLeft(2, '0')}:'
          '${startTime.minute.toString().padLeft(2, '0')}';

      final endFormatted = '${endTime.hour.toString().padLeft(2, '0')}:'
          '${endTime.minute.toString().padLeft(2, '0')}';

      // --------------------------------------------------------
      // NÃO CRIAR APONTAMENTO VAZIO
      // --------------------------------------------------------

      if (totalSeconds > 0) {
        final durationFormatted = _formatDuration(
          totalSeconds,
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
                content: Text(
                  'Tempo de trabalho salvo: $durationFormatted.',
                ),
                backgroundColor: CoresApp.sucesso,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      }

      // --------------------------------------------------------
      // IMPORTANTE:
      //
      // Ao parar definitivamente, não deixamos TRAB_STOP
      // como estado do projeto caso o trabalho tenha sido
      // encerrado.
      //
      // Voltamos para TRAB somente se o item estava pausado.
      // Isso evita deixar um projeto permanentemente marcado
      // como pausado depois que o apontamento foi encerrado.
      // --------------------------------------------------------

      if (_timerState == TimerState.paused) {
        unawaited(
          _setTimerTargetStatus(
            targetId,
            'TRAB',
          ),
        );
      }
    }

    // ----------------------------------------------------------
    // RESET DO CRONÔMETRO
    // ----------------------------------------------------------

    if (!mounted) {
      return;
    }

    setState(() {
      _timerState = TimerState.stopped;
      _activeTimerTargetId = null;
      _activeStartTime = null;
      _segmentStartTime = null;
      _accumulatedWorkedSeconds = 0;
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

    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}';
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
        totalHours += _parseTimeToHours(
          log.durationFormatted,
        );
      }
    }

    return totalHours;
  }

  // ============================================================
  // HORAS DO DIA
  // ============================================================

  Future<void> _abrirHorasDoDia(DateTime data) async {
    final logsDoDia = _timeLogs.where((log) {
      if (!log.isRegistered) {
        return false;
      }

      return log.date.year == data.year &&
          log.date.month == data.month &&
          log.date.day == data.day;
    }).toList();

    logsDoDia.sort((a, b) {
      int minutos(TimeLog log) {
        final partes = log.startTime.split(':');

        if (partes.length != 2) {
          return 0;
        }

        final hora = int.tryParse(partes[0]) ?? 0;
        final minuto = int.tryParse(partes[1]) ?? 0;

        return hora * 60 + minuto;
      }

      return minutos(a).compareTo(minutos(b));
    });

    int totalMinutos = 0;

    for (final log in logsDoDia) {
      final partes = log.durationFormatted.split(':');

      if (partes.length == 2) {
        final horas = int.tryParse(partes[0]) ?? 0;
        final minutos = int.tryParse(partes[1]) ?? 0;

        totalMinutos += (horas * 60) + minutos;
      }
    }

    final totalHoras = _formatHours(totalMinutos / 60.0);

    final dataFormatada = '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: CoresApp.borda,
            ),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            10,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            20,
            4,
            20,
            12,
          ),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF0099FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: Color(0xFF0099FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Horas cadastradas',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dataFormatada,
                      style: const TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
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
                  color: const Color(0xFF0099FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF0099FF).withOpacity(0.25),
                  ),
                ),
                child: Text(
                  totalHoras,
                  style: const TextStyle(
                    color: Color(0xFF33BBFF),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            height: 430,
            child: logsDoDia.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.access_time_outlined,
                            color: Colors.white38,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Nenhum apontamento cadastrado',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Não existem horas registradas para este dia.',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: CoresApp.borda.withOpacity(0.7),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.list_alt_rounded,
                              color: CoresApp.destaque,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${logsDoDia.length} apontamento(s)',
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Total: $totalHoras',
                              style: const TextStyle(
                                color: Color(0xFF33BBFF),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.separated(
                          itemCount: logsDoDia.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final log = logsDoDia[index];

                            final projeto = (log.projectName ?? '').trim();
                            final tarefa = (log.taskName ?? '').trim();
                            final descricao = (log.description ?? '').trim();
                            final tipo = (log.typeHs ?? '').trim();

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: CoresDashboard.fundoSecundario,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: CoresApp.borda.withOpacity(0.7),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0099FF)
                                          .withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(
                                      Icons.schedule_rounded,
                                      color: Color(0xFF0099FF),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tarefa.isNotEmpty
                                              ? tarefa
                                              : 'Tarefa não informada',
                                          style: const TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          projeto.isNotEmpty
                                              ? projeto
                                              : 'Projeto não informado',
                                          style: const TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (descricao.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            descricao,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 7),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.access_time_rounded,
                                              color: Color(0xFF33BBFF),
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${log.startTime} até ${log.endTime}',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF0099FF,
                                                ).withOpacity(0.10),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                log.durationFormatted,
                                                style: const TextStyle(
                                                  color: Color(0xFF33BBFF),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (tipo.isNotEmpty) ...[
                                              const SizedBox(width: 7),
                                              Text(
                                                tipo,
                                                style: const TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  PopupMenuButton<String>(
                                    tooltip: 'Opções',
                                    color: CoresDashboard.card,
                                    icon: const Icon(
                                      Icons.more_vert_rounded,
                                      color: CoresApp.textoSecundario,
                                      size: 19,
                                    ),
                                    onSelected: (value) async {
                                      Navigator.of(dialogContext).pop();

                                      if (value == 'editar') {
                                        await _editLogDialog(log);
                                        await _abrirHorasDoDia(data);
                                      } else if (value == 'excluir') {
                                        await _confirmDeleteLog(log);
                                        await _abrirHorasDoDia(data);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<String>(
                                        value: 'editar',
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.edit_outlined,
                                              color: CoresApp.destaque,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Editar',
                                              style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'excluir',
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.delete_outline,
                                              color: CoresApp.erro,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Excluir',
                                              style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                              ),
                                            ),
                                          ],
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
                    ],
                  ),
          ),
          actions: [
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
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'Fechar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SELEÇÃO DE DATA
  // ============================================================

  Future<DateTime?> _selectCustomDate(DateTime initialDate) async {
    int day = initialDate.day;
    int month = initialDate.month;
    int year = initialDate.year;

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1B1B2A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withOpacity(0.16),
                ),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    color: Color(0xFF35D27F),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Selecionar Data',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
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
                    _buildDateDropdown(
                      label: 'Dia',
                      value: day,
                      values: List.generate(31, (index) => index + 1),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => day = value);
                        }
                      },
                      padLeft: true,
                    ),
                    const Text(
                      '/',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                    _buildDateDropdown(
                      label: 'Mês',
                      value: month,
                      values: List.generate(12, (index) => index + 1),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => month = value);
                        }
                      },
                      padLeft: true,
                    ),
                    const Text(
                      '/',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                    _buildDateDropdown(
                      label: 'Ano',
                      value: year,
                      values: List.generate(11, (index) => 2020 + index),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => year = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: Color(0xFFBDBDC7),
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF35D27F),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () {
                    final novaData = DateTime(
                      year,
                      month,
                      day,
                    );

                    Navigator.of(dialogContext).pop(novaData);
                  },
                  child: const Text(
                    'Confirmar',
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

  Widget _buildDateDropdown({
    required String label,
    required int value,
    required List<int> values,
    required ValueChanged<int?> onChanged,
    bool padLeft = false,
  }) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          DropdownButton<int>(
            value: value,
            dropdownColor: const Color(0xFF1B1B2A),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
            items: values.map((item) {
              return DropdownMenuItem<int>(
                value: item,
                child: Text(
                  padLeft ? item.toString().padLeft(2, '0') : item.toString(),
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EDITAR SUBTRABALHO
  // ============================================================

  void _editSubTaskDialog(
    ProjectModel project,
    TaskModel task,
  ) {
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
                side: const BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Editar Subtrabalho (Etapa ${task.subId})',
                style: const TextStyle(
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
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Número (Nº)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: serviceTypeController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Tipo de Serviço'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stageController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Trabalho / Etapa'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Horas Estimadas (ex: 10:00)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hourTypeController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Tipo de Horas (ex: Hs Cobradas)',
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
                                side: const BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Início: ${_formatDateShort(startDate)}',
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final DateTime? picked =
                                  await _selectCustomDate(endDate);

                              if (picked != null) {
                                setDialogState(() {
                                  endDate = picked;
                                });
                              }

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
                                side: const BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Fim: ${_formatDateShort(endDate)}',
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              // CORREÇÃO APLICADA AQUI:
                              // Passa e atualiza a endDate em vez da startDate
                              final DateTime? picked = await _selectCustomDate(
                                endDate,
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  endDate = picked;
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
                      task.planEnd = endDate; // Salva o fim corretamente
                    });

                    await _firebaseService.saveProject(
                      project,
                    );

                    if (context.mounted) {
                      Navigator.of(context).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Subtrabalho atualizado com sucesso!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                side: const BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: Text(
                'Adicionar Nova Etapa ao Projeto ${project.id}',
                style: const TextStyle(
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
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Número da Etapa (Nº)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stageController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Trabalho / Etapa'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: serviceTypeController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Tipo de Serviço'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hoursController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Horas Estimadas (ex: 10:00)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: hourTypeController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Tipo de Horas'),
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
                                side: const BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Início: ${_formatDateShort(startDate)}',
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final DateTime? picked = await _selectCustomDate(
                                startDate,
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
                                side: const BorderSide(
                                  color: CoresApp.bordaSuave,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.calendar_today,
                              color: CoresApp.destaque,
                              size: 16,
                            ),
                            label: Text(
                              'Fim: ${_formatDateShort(endDate)}',
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 11,
                              ),
                            ),
                            onPressed: () async {
                              final DateTime? picked = await _selectCustomDate(
                                startDate,
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

                    await _firebaseService.saveProject(
                      project,
                    );

                    if (context.mounted) {
                      Navigator.of(context).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Etapa "$stageName" adicionada com sucesso!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: Text(
            'Adicionar Horas Manualmente\n($itemTitle)',
            style: const TextStyle(
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
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Horas'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: minutesController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Minutos'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Apontado manualmente ${h}h ${m}m e salvo no Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao salvar apontamento manual: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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

    hoursController.dispose();
    minutesController.dispose();
  }

  // ============================================================
// EDITAR APONTAMENTO (CORRIGIDO)
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
                side: const BorderSide(
                  color: CoresApp.borda,
                ),
              ),
              title: const Text(
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
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Hora Início (ex: 14:00)',
                      ),
                      onChanged: (_) {
                        calculateDuration();
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration(
                        'Hora Fim (ex: 15:30)',
                      ),
                      onChanged: (_) {
                        calculateDuration();
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: durationController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      decoration: _inputDecoration('Duração (ex: 01:30)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      style: const TextStyle(
                        color: CoresApp.textoPrincipal,
                      ),
                      maxLines: 2,
                      decoration: _inputDecoration(
                        'Descrição / Comentário',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    // Atualiza os valores locais da instância do log
                    log.startTime = startController.text.trim();
                    log.endTime = endController.text.trim();
                    log.durationFormatted = durationController.text.trim();
                    log.description = descriptionController.text.trim().isEmpty
                        ? null
                        : descriptionController.text.trim();

                    if (_activeTimerTargetId == log.targetId) {
                      final durationParts = log.durationFormatted.split(':');

                      if (durationParts.length >= 2) {
                        final h = int.tryParse(durationParts[0]) ?? 0;
                        final m = int.tryParse(durationParts[1]) ?? 0;

                        _secondsElapsed = (h * 3600) + (m * 60);
                        _accumulatedWorkedSeconds = _secondsElapsed;

                        if (_timerState == TimerState.running) {
                          _segmentStartTime = DateTime.now();
                        }
                      }

                      final startParts = log.startTime.split(':');
                      if (startParts.length == 2) {
                        final sh = int.tryParse(startParts[0]) ?? log.date.hour;
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

                    try {
                      // Garante a persistência e atualização correta no Firebase e na Store
                      await widget.timeLogStore.updateFirebaseLog(log);

                      if (!mounted) return;

                      setState(
                          () {}); // Força a reconstrução do Dashboard para refletir as horas atualizadas

                      if (!dialogContext.mounted) {
                        return;
                      }

                      Navigator.of(dialogContext).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Apontamento atualizado e salvo no Firebase!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!dialogContext.mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao atualizar apontamento: $e',
                          ),
                          backgroundColor: CoresApp.erro,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
            side: const BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: const Text(
            'Excluir Apontamento',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Deseja realmente remover esta linha de apontamento?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
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
                      content: const Text(
                        'Apontamento excluído do Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir apontamento: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              child: const Text(
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
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: const Text(
            'Excluir Projeto',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente excluir o projeto '
            '"${project.client}" (${project.id})?',
            style: const TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
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

                  _expandedProjectIds.remove(
                    project.id,
                  );

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
                      content: Text(
                        'Projeto ${project.id} removido do Firebase!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir projeto: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              child: const Text(
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
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: CoresApp.borda,
            ),
          ),
          title: const Text(
            'Excluir Subtrabalho (Etapa)',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Deseja realmente excluir a etapa '
            '"${task.stage}" (Nº ${task.subId})?',
            style: const TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
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
                  await _firebaseService.saveProject(project);

                  if (!dialogContext.mounted) {
                    return;
                  }

                  Navigator.of(dialogContext).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Subtrabalho excluído com sucesso!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) {
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao excluir subtrabalho: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
              child: const Text(
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
        firebaseService: null,
      ),
    );

    if (newProject == null) {
      return;
    }

    // ============================================================
    // IMPORTANTE:
    //
    // O ProjectFormDialog já cria as subtarefas contendo exatamente
    // as datas escolhidas pelo usuário.
    //
    // Portanto, NÃO devemos recriar as tarefas aqui.
    //
    // Antes havia uma lógica que fazia:
    //
    // planEnd: newProject.startDate.add(
    //   const Duration(days: 30),
    // ),
    //
    // Isso fazia a data final escolhida pelo usuário ser perdida.
    // ============================================================

    final List<TaskModel>? projectSubTasks = newProject.subTasks;

    final ProjectModel projectWithSubtasks = ProjectModel(
      id: newProject.id,
      id2: newProject.id2,
      client: newProject.client,
      serviceType: newProject.serviceType,
      stage: newProject.stage,
      task: newProject.task,
      status: newProject.status,

      // Mantém exatamente a data inicial que veio do formulário.
      startDate: newProject.startDate,

      estimatedHours: newProject.estimatedHours,
      leader: newProject.leader,
      hourType: newProject.hourType,

      // ==========================================================
      // Mantém as subtarefas criadas pelo ProjectFormDialog.
      //
      // Isso preserva as datas:
      //   - startDate
      //   - planStart
      //   - planEnd
      //
      // sem alterar para +15 ou +30 dias.
      // ==========================================================
      subTasks: projectSubTasks,

      checklist: newProject.checklist,
      observacao: newProject.observacao,
      excelLink: newProject.excelLink,
      folderPath: newProject.folderPath,
    );

    // ============================================================
    // SALVAR NO FIREBASE
    // ============================================================

    await _firebaseService.saveProject(
      projectWithSubtasks,
    );

    // ============================================================
    // ATUALIZAR O DASHBOARD
    // ============================================================

    if (!mounted) {
      return;
    }

    setState(() {
      _projects.add(projectWithSubtasks);

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

    // ============================================================
    // MENSAGEM DE SUCESSO
    // ============================================================

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Projeto salvo no Firebase com sucesso!',
        ),
        backgroundColor: CoresApp.sucesso,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
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
        Duration(days: i),
      );

      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

      points.add(
        DailyHoursPoint(
          label: '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')}',
          date: date,
          hours: _getHoursForDate(date),
          isWeekend: isWeekend,
          isHighlighted: i == 0,
        ),
      );
    }

    return points;
  }

  // ============================================================
  // PREPARAÇÃO DOS DADOS DO DASHBOARD
  // ============================================================

  List<ProjectModel> _buildFilteredProjects() {
    return _projects.where((p) {
      final query = _searchQuery.toLowerCase().trim();

      final matchesSearch = query.isEmpty ||
          p.client.toLowerCase().contains(query) ||
          p.id.toLowerCase().contains(query) ||
          p.serviceType.toLowerCase().contains(query);

      final filtroProjeto = _filtroProjetos.toLowerCase().trim();

      final matchesProjectFilter = filtroProjeto.isEmpty ||
          p.id.toLowerCase().contains(filtroProjeto) ||
          p.client.toLowerCase().contains(filtroProjeto);

      final matchesServiceType = _tipoServicoSelecionado == null ||
          _tipoServicoSelecionado!.trim().isEmpty ||
          p.serviceType.trim().toLowerCase() ==
              _tipoServicoSelecionado!.trim().toLowerCase();

      final matchesStartDate = _dataInicioFiltro == null ||
          (p.startDate.year == _dataInicioFiltro!.year &&
              p.startDate.month == _dataInicioFiltro!.month &&
              p.startDate.day == _dataInicioFiltro!.day);

      final matchesEndDate = _dataFimFiltro == null ||
          p.startDate.isBefore(
            _dataFimFiltro!.add(const Duration(days: 1)),
          );

      final matchesDateOption = _filterOptions.selectedDate == null ||
          (p.startDate.year == _filterOptions.selectedDate!.year &&
              p.startDate.month == _filterOptions.selectedDate!.month &&
              p.startDate.day == _filterOptions.selectedDate!.day);

// ============================================================
// FILTRO DOS CARDS DO DASHBOARD
// ============================================================
//
// PROJETOS CADASTRADOS:
//   Todos os projetos.
//
// PROJETOS ATIVOS:
//   Somente projetos que não estão finalizados
//   e não estão pausados.
//
// PROJETOS PAUSADOS:
//   Somente TRAB_STOP.
//
// O filtro do card tem prioridade sobre "_onlyActive".
// ============================================================

      bool matchesStatus = true;

      if (_filtroApenasAtivos) {
        // ATIVOS = tudo que não está finalizado
        // e não está pausado.
        matchesStatus = p.status != 'TRAB_FIM' && p.status != 'TRAB_STOP';
      } else if (_statusFiltroDashboard != null) {
        // PAUSADOS ou qualquer outro status específico.
        matchesStatus = p.status == _statusFiltroDashboard;
      } else {
        matchesStatus = _onlyActive
            ? p.status != 'TRAB_FIM' && p.status != 'TRAB_STOP'
            : true;
      }

      // ============================================================
      // FILTRO POR TURNO
      // ============================================================

      bool matchesShift = true;

      if (_filterOptions.shift == 'Manhã') {
        final logs = _timeLogs.where(
          (l) => l.targetId.split('_').first == p.id,
        );

        matchesShift = logs.any((l) {
          final hour = int.tryParse(
                l.startTime.split(':').first,
              ) ??
              0;

          return hour < 12;
        });
      } else if (_filterOptions.shift == 'Tarde') {
        final logs = _timeLogs.where(
          (l) => l.targetId.split('_').first == p.id,
        );

        matchesShift = logs.any((l) {
          final hour = int.tryParse(
                l.startTime.split(':').first,
              ) ??
              0;

          return hour >= 12 && hour < 18;
        });
      }

      return matchesSearch &&
          matchesProjectFilter &&
          matchesServiceType &&
          matchesStartDate &&
          matchesEndDate &&
          matchesDateOption &&
          matchesStatus &&
          matchesShift;
    }).toList();
  }

  ProjectModel _getActiveProject() {
    final defaultTargetId = _projects.isNotEmpty ? _projects.first.id : '';

    return _projects.firstWhere(
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
  }

  // ============================================================
  // CABEÇALHO VISUAL
  // ============================================================

  Widget _buildDashboardHeader({
    required int activeProjects,
    required int totalProjects,
    required int pausedProjects,
    required int totalTasks,
    required String totalHours,
  }) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CoresDashboard.card.withOpacity(0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CoresApp.borda.withOpacity(0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 9,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                final stats = [
                  _buildDashboardStat(
                    icon: Icons.folder_open_rounded,
                    label: 'Projetos ativos',
                    value: '$activeProjects',
                    description: 'em andamento',
                    color: CoresApp.destaque,
                    filterApenasAtivos: true,
                  ),
                  _buildDashboardStat(
                    icon: Icons.folder_rounded,
                    label: 'Projetos',
                    value: '$totalProjects',
                    description: 'cadastrados',
                    color: CoresApp.primaria,
                  ),
                  _buildDashboardStat(
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Projetos pausados',
                    value: '$pausedProjects',
                    description: 'parados',
                    color: CoresApp.aviso,
                    filterStatus: 'TRAB_STOP',
                  ),
                  _buildDashboardStat(
                    icon: Icons.task_alt_rounded,
                    label: 'Tarefas',
                    value: '$totalTasks',
                    description: 'etapas',
                    color: CoresApp.secundaria,
                  ),
                  _buildDashboardStat(
                    icon: Icons.schedule_rounded,
                    label: 'Horas',
                    value: totalHours,
                    description: 'registradas',
                    color: CoresApp.destaque,
                  ),
                ];

                if (width >= 1250) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildDashboardTitle(),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 8,
                        child: Row(
                          children: [
                            for (int i = 0; i < stats.length; i++) ...[
                              Expanded(
                                child: stats[i],
                              ),
                              if (i < stats.length - 1)
                                const SizedBox(width: 7),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                }

                if (width >= 800) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDashboardTitle(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (int i = 0; i < stats.length; i++) ...[
                            Expanded(
                              child: stats[i],
                            ),
                            if (i < stats.length - 1) const SizedBox(width: 7),
                          ],
                        ],
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDashboardTitle(),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final stat in stats)
                          SizedBox(
                            width: _responsiveStatWidth(width),
                            child: stat,
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

  Widget _buildDashboardTitle() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 42,
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
        const SizedBox(width: 11),
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CoresApp.primaria.withOpacity(0.12),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: CoresApp.primaria.withOpacity(0.24),
            ),
          ),
          child: const Icon(
            Icons.dashboard_rounded,
            color: CoresApp.destaque,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestão de Horas e Projetos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Acompanhe projetos, etapas, horas e produtividade em um único painel.',
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

  Widget _buildDashboardStat({
    required IconData icon,
    required String label,
    required String value,
    required String description,
    required Color color,
    String? filterStatus,
    bool filterApenasAtivos = false,
  }) {
    final isSelected = (filterApenasAtivos && _filtroApenasAtivos) ||
        (filterStatus != null &&
            _statusFiltroDashboard == filterStatus &&
            !_filtroApenasAtivos);
    final isClickable = filterStatus != null || filterApenasAtivos;
    return InkWell(
      onTap: !isClickable
          ? null
          : () {
              _toggleDashboardStatusFilter(
                status: filterStatus,
                apenasAtivos: filterApenasAtivos,
              );
            },
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(
          minHeight: 62,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.18)
              : CoresDashboard.fundoSecundario,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color:
                isSelected ? color.withOpacity(0.75) : color.withOpacity(0.22),
            width: isSelected ? 1.3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.16),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(
                  isSelected ? 0.22 : 0.11,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                isSelected ? Icons.filter_alt_rounded : icon,
                color: color,
                size: 17,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.35,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          color: color,
                          size: 13,
                        ),
                    ],
                  ),
                  const SizedBox(height: 1),
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
                    isSelected ? 'filtro aplicado' : description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color.withOpacity(0.9),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _responsiveStatWidth(double width) {
    if (width >= 700) {
      return 175;
    }

    if (width >= 500) {
      return 160;
    }

    if (width >= 360) {
      return 150;
    }

    return width;
  }

  // ============================================================
  // PAINEL SUPERIOR
  // ============================================================

  Widget _buildTopDashboardPanels({
    required ProjectModel activeProject,
    required List<DailyHoursPoint> dailyHoursPoints,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 1000) {
          return Column(
            children: [
              _buildDashboardPanel(
                child: ControleProjetosWidget(
                  agrupar: _agrupar,
                  ordenarPrioridade: _ordenarPrioridade,
                  somenteAtivos: _onlyActive,
                  filtroAtivo: _filterOptions.hasFilter ||
                      (_tipoServicoSelecionado != null &&
                          _tipoServicoSelecionado!.isNotEmpty) ||
                      _filtroProjetos.isNotEmpty ||
                      _dataInicioFiltro != null ||
                      _dataFimFiltro != null ||
                      _statusFiltroDashboard != null ||
                      _filtroApenasAtivos,
                  expandedProjectIds: _expandedProjectIds,
                  onNewProject: _createNewProject,
                  onSynchronize: () {
                    _loadDataFromFirebase(
                      showLoader: false,
                    );
                  },
                  onFilter: () {},
                  onManual: () {
                    final target = _selectedTargetId ??
                        (_projects.isNotEmpty ? _projects.first.id : 'Geral');

                    _showManualTimeDialog(target);
                  },
                  onStart: () {
                    final target = _selectedTargetId ??
                        (_projects.isNotEmpty ? _projects.first.id : null);

                    if (target != null) {
                      _startTimer(target);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Selecione um trabalho na tabela para iniciar!',
                          ),
                          backgroundColor: CoresApp.aviso,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                  filtroProjetos: _filtroProjetos,
                  tipoServicoSelecionado: _tipoServicoSelecionado ?? '',
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
                  tiposServicoOpcoes: _getServiceTypeNames(),
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
              const SizedBox(height: 12),
              _buildDashboardPanel(
                child: ProgressoProjetoWidget(
                  activeProject: activeProject,
                  timeLogs: _timeLogs,
                  parseTimeToHours: _parseTimeToHours,
                  formatHours: _formatHours,
                  formatDateShort: _formatDateShort,
                ),
              ),
              const SizedBox(height: 12),
              _buildDashboardPanel(
                child: GraficoHorasWidget(
                  points: dailyHoursPoints,
                  formatHours: _formatHours,
                  onDayTap: _abrirHorasDoDia,
                ),
              ),
            ],
          );
        }

        return SizedBox(
          height: 190,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ========================================================
              // CONTROLE DE PROJETOS
              // ========================================================

              Expanded(
                flex: 3,
                child: _buildDashboardPanel(
                  child: ControleProjetosWidget(
                    agrupar: _agrupar,
                    ordenarPrioridade: _ordenarPrioridade,
                    somenteAtivos: _onlyActive,
                    filtroAtivo: _filterOptions.hasFilter ||
                        (_tipoServicoSelecionado != null &&
                            _tipoServicoSelecionado!.isNotEmpty) ||
                        _filtroProjetos.isNotEmpty ||
                        _dataInicioFiltro != null ||
                        _dataFimFiltro != null,
                    expandedProjectIds: _expandedProjectIds,
                    onNewProject: _createNewProject,
                    onSynchronize: () {
                      _loadDataFromFirebase(
                        showLoader: false,
                      );
                    },
                    onFilter: () {},
                    onManual: () {
                      final target = _selectedTargetId ??
                          (_projects.isNotEmpty ? _projects.first.id : 'Geral');

                      _showManualTimeDialog(target);
                    },
                    onStart: () {
                      final target = _selectedTargetId ??
                          (_projects.isNotEmpty ? _projects.first.id : null);

                      if (target != null) {
                        _startTimer(target);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Selecione um trabalho na tabela para iniciar!',
                            ),
                            backgroundColor: CoresApp.aviso,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
                    filtroProjetos: _filtroProjetos,
                    tipoServicoSelecionado: _tipoServicoSelecionado ?? '',
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
                    tiposServicoOpcoes: _getServiceTypeNames(),
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

              const SizedBox(width: 12),

              // ========================================================
              // ETAPAS DO PROJETO
              // ========================================================

              Expanded(
                flex: 6,
                child: _buildDashboardPanel(
                  child: ProgressoProjetoWidget(
                    activeProject: activeProject,
                    timeLogs: _timeLogs,
                    parseTimeToHours: _parseTimeToHours,
                    formatHours: _formatHours,
                    formatDateShort: _formatDateShort,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // ========================================================
              // EVOLUÇÃO DE HORAS
              // ========================================================

              Expanded(
                flex: 4,
                child: _buildDashboardPanel(
                  child: GraficoHorasWidget(
                    points: dailyHoursPoints,
                    formatHours: _formatHours,
                    onDayTap: _abrirHorasDoDia,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDashboardPanel({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CoresDashboard.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CoresApp.borda.withOpacity(0.75),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }

  List<String> _getServiceTypeNames() {
    final availableWorkFormats = _workFormatsFirebase.isNotEmpty
        ? _workFormatsFirebase
        : widget.workFormats;

    return availableWorkFormats.map((wf) => wf.name).toList();
  }

  // ============================================================
  // TABELA
  // ============================================================

  Widget _buildProjectsTable(
    List<ProjectModel> filteredProjects,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CoresDashboard.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CoresApp.borda.withOpacity(0.75),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
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
          onProjectStatusChanged: _handleProjectStatusChanged,
          onSubTaskStatusChanged: _handleSubTaskStatusChanged,
          onEditSubTask: _editSubTaskDialog,
          onDeleteSubTask: _confirmDeleteSubTask,
          onStartTimer: _startTimer,
          onPauseTimer: _pauseTimer,
          onStopTimer: _stopTimer,
          onManualTime: _showManualTimeDialog,
          onEditLog: _editLogDialog,
          onDeleteLog: _confirmDeleteLog,
          onRegisterLog: _handleRegisterLog,
          onMarkTaskCompleted: _handleMarkTaskCompleted,
          formatDuration: _formatDuration,
          firebaseService: _firebaseService,
        ),
      ),
    );
  }

  // ============================================================
  // CALLBACKS DA TABELA
  // ============================================================

  Future<void> _handleProjectStatusChanged(
    ProjectModel project,
    String newStatus,
  ) async {
    setState(() {
      project.status = newStatus;
    });

    try {
      if (newStatus == 'TRAB_FIM') {
        await widget.timeLogStore.registerProjectLogs(
          project.id,
        );
      }

      await _firebaseService.saveProject(
        project,
      );

      if (newStatus == 'TRAB_FIM') {
        widget.onProjectCompleted?.call(
          project,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Projeto ${project.id} finalizado e movido!',
              ),
              backgroundColor: CoresApp.sucesso,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao atualizar status: $e',
            ),
            backgroundColor: CoresApp.erro,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleSubTaskStatusChanged(
    TaskModel task,
    String newStatus,
  ) async {
    setState(() {
      task.status = newStatus;
    });

    final parent = _projects.firstWhere(
      (p) => p.subTasks?.contains(task) ?? false,
      orElse: () => _projects.first,
    );

    await _firebaseService.saveProject(
      parent,
    );
  }

  Future<void> _handleRegisterLog(
    TimeLog log,
  ) async {
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Tempo cadastrado e salvo no Firebase com sucesso!',
          ),
          backgroundColor: CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao cadastrar tempo no Firebase: $e',
          ),
          backgroundColor: CoresApp.erro,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _handleMarkTaskCompleted(
    TaskModel task,
  ) async {
    setState(() {
      task.status = 'TRAB';
    });

    final parent = _projects.firstWhere(
      (p) => p.subTasks?.contains(task) ?? false,
      orElse: () => _projects.first,
    );

    await _firebaseService.saveProject(
      parent,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Etapa ${task.subId} marcada como realizada!',
          ),
          backgroundColor: CoresApp.sucesso,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ============================================================
  // ALERTAS
  // ============================================================

  Widget _buildAlerts() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CoresDashboard.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CoresApp.borda.withOpacity(0.75),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CentralAlertasWidget(
          projects: _projects,
          formatDateShort: _formatDateShort,
        ),
      ),
    );
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 28,
          vertical: 24,
        ),
        decoration: BoxDecoration(
          color: CoresDashboard.card.withOpacity(
            0.96,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CoresApp.borda.withOpacity(0.7),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: CoresApp.destaque,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Carregando projetos...',
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sincronizando dados com o Firebase',
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final filteredProjects = _buildFilteredProjects();

    final activeProject = _getActiveProject();

    final dailyHoursPoints = _buildDailyHoursPoints();

    final totalProjects = _projects.length;

    final activeProjects = _projects
        .where(
          (p) => p.status != 'TRAB_FIM' && p.status != 'TRAB_STOP',
        )
        .length;

    final pausedProjects = _projects
        .where(
          (p) => p.status == 'TRAB_STOP',
        )
        .length;

    final totalTasks = _projects.fold<int>(
      0,
      (total, project) => total + (project.subTasks?.length ?? 0),
    );

    final totalRegisteredMinutes = _timeLogs
        .where(
      (log) => log.isRegistered,
    )
        .fold<int>(
      0,
      (total, log) {
        final parts = log.durationFormatted.split(':');

        if (parts.length != 2) {
          return total;
        }

        final hours = int.tryParse(parts[0]) ?? 0;

        final minutes = int.tryParse(parts[1]) ?? 0;

        return total + (hours * 60) + minutes;
      },
    );

    final totalHours = _formatHours(
      totalRegisteredMinutes / 60.0,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Cabecalho(
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
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/fundo.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(
                0.42,
              ),
            ),
          ),
          _isLoadingProjects
              ? _buildLoadingState()
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDashboardHeader(
                          activeProjects: activeProjects,
                          totalProjects: totalProjects,
                          pausedProjects: pausedProjects,
                          totalTasks: totalTasks,
                          totalHours: totalHours,
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        _buildTopDashboardPanels(
                          activeProject: activeProject,
                          dailyHoursPoints: dailyHoursPoints,
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        _buildProjectsTable(
                          filteredProjects,
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        _buildAlerts(),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  void _toggleDashboardStatusFilter({
    String? status,
    bool apenasAtivos = false,
  }) {
    setState(() {
      final alreadySelected = _statusFiltroDashboard == status &&
          _filtroApenasAtivos == apenasAtivos;

      if (alreadySelected) {
        // Ao clicar novamente no card selecionado,
        // remove o filtro do card.
        _statusFiltroDashboard = null;
        _filtroApenasAtivos = false;
      } else {
        // Aplica o filtro selecionado.
        _statusFiltroDashboard = status;
        _filtroApenasAtivos = apenasAtivos;
      }
    });
  }
}
