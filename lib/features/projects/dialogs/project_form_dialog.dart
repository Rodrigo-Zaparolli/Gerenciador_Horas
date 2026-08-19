import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:url_launcher/url_launcher.dart';

class ProjectFormDialog extends StatefulWidget {
  final List<WorkFormat> workFormats;
  final ProjectModel? projectToEdit;

  const ProjectFormDialog({
    super.key,
    required this.workFormats,
    this.projectToEdit,
  });

  @override
  State<ProjectFormDialog> createState() => _ProjectFormDialogState();
}

///
/// Formata a entrada de horas:
///
/// 1    -> 00:01
/// 10   -> 00:10
/// 100  -> 01:00
/// 130  -> 01:30
/// 1230 -> 12:30
///
class HoursInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 4) {
      digits = digits.substring(0, 4);
    }

    String formatted = digits;

    if (digits.length >= 3) {
      formatted =
          '${digits.substring(0, digits.length - 2)}:${digits.substring(digits.length - 2)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: formatted.length,
      ),
    );
  }
}

class _ProjectFormDialogState extends State<ProjectFormDialog> {
  final FirebaseService _firebaseService = FirebaseService();

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _clientController = TextEditingController();
  final TextEditingController _leaderController = TextEditingController();
  final TextEditingController _excelLinkController = TextEditingController();
  final TextEditingController _folderPathController = TextEditingController();

  WorkFormat? _selectedWorkFormat;

  String _status = 'INI_PRI';
  String _hourType = 'Hs Cobradas';

  late DateTime _startDate;

  List<Map<String, dynamic>> _internalWorks = [];

  bool _isSaving = false;

  bool get _isEditing => widget.projectToEdit != null;

  @override
  void initState() {
    super.initState();

    final project = widget.projectToEdit;

    // ------------------------------------------------------------
    // VALORES DO PROJETO
    // ------------------------------------------------------------

    if (project != null) {
      _idController.text = project.id;
      _clientController.text = project.client;
      _leaderController.text = project.leader;

      _status = project.status;
      _hourType = project.hourType;

      _excelLinkController.text = project.excelLink ?? '';
      _folderPathController.text = project.folderPath ?? '';

      // ----------------------------------------------------------
      // DATA INICIAL
      // ----------------------------------------------------------

      _startDate = project.startDate;

      if (project.subTasks != null && project.subTasks!.isNotEmpty) {
        final firstTask = project.subTasks!.first;

        _startDate = firstTask.planStart ?? firstTask.startDate;
      }

      debugPrint('====================================');
      debugPrint('EDITANDO PROJETO');
      debugPrint('ID: ${project.id}');
      debugPrint('CLIENTE: ${project.client}');
      debugPrint('DATA PROJETO: ${project.startDate}');
      debugPrint('SUBTASKS: ${project.subTasks?.length}');
      debugPrint('====================================');

      if (project.subTasks != null) {
        for (final task in project.subTasks!) {
          debugPrint(
            'ETAPA: ${task.stage} | '
            'startDate: ${task.startDate} | '
            'planStart: ${task.planStart} | '
            'planEnd: ${task.planEnd}',
          );
        }
      }
    } else {
      // ----------------------------------------------------------
      // NOVO PROJETO
      // ----------------------------------------------------------

      _startDate = DateTime.now();

      _startDate = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      );
    }

    // ------------------------------------------------------------
    // TIPO DE SERVIÇO
    // ------------------------------------------------------------

    if (widget.workFormats.isNotEmpty) {
      if (project != null) {
        _selectedWorkFormat = widget.workFormats.firstWhere(
          (wf) =>
              wf.name.trim().toLowerCase() ==
              project.serviceType.trim().toLowerCase(),
          orElse: () => widget.workFormats.first,
        );
      } else {
        _selectedWorkFormat = widget.workFormats.first;
      }

      _updateInternalWorks(
        _selectedWorkFormat!,
        existingProject: project,
      );
    }
  }

  // ============================================================
  // CONVERTER ETAPA DO WORK FORMAT
  // ============================================================
  //
  // O Firestore pode possuir etapas armazenadas como:
  //
  // String:
  //   "Análise"
  //
  // Map:
  //   {"name": "Análise"}
  //
  // Ou formatos antigos utilizando:
  //   stage / title / description
  //
  // Esta função evita que o app quebre ao abrir
  // o formulário de Novo Trabalho.
  // ============================================================

  String _getWorkName(
    dynamic rawStep,
    int index,
  ) {
    if (rawStep is String) {
      final String value = rawStep.trim();

      if (value.isNotEmpty) {
        return value;
      }
    }

    if (rawStep is Map) {
      final dynamic name = rawStep['name'];

      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }

      final dynamic stage = rawStep['stage'];

      if (stage != null && stage.toString().trim().isNotEmpty) {
        return stage.toString().trim();
      }

      final dynamic title = rawStep['title'];

      if (title != null && title.toString().trim().isNotEmpty) {
        return title.toString().trim();
      }

      final dynamic description = rawStep['description'];

      if (description != null && description.toString().trim().isNotEmpty) {
        return description.toString().trim();
      }
    }

    if (rawStep != null) {
      final String value = rawStep.toString().trim();

      if (value.isNotEmpty && value != 'null') {
        return value;
      }
    }

    return 'Etapa ${index + 1}';
  }

  // ============================================================
  // DATAS
  // ============================================================

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  DateTime _onlyDate(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  Future<DateTime?> _selectDate({
    required DateTime initialDate,
  }) async {
    final DateTime normalizedInitialDate = _onlyDate(initialDate);

    return showDatePicker(
      context: context,
      initialDate: normalizedInitialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00FFCC),
              onPrimary: Colors.black,
              surface: Color(0xFF2D2D44),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  // ============================================================
  // EDITAR DATA DE INÍCIO
  // ============================================================

  Future<void> _editStartDate(
    Map<String, dynamic> work,
  ) async {
    final DateTime currentDate = work['startDate'] as DateTime;

    final DateTime? picked = await _selectDate(
      initialDate: currentDate,
    );

    if (picked == null || !mounted) {
      return;
    }

    final DateTime endDate = work['endDate'] as DateTime;

    if (picked.isAfter(endDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A data de início não pode ser posterior à data de término.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    setState(() {
      work['startDate'] = picked;

      if (_internalWorks.isNotEmpty && identical(work, _internalWorks.first)) {
        _startDate = picked;
      }
    });
  }

  // ============================================================
  // EDITAR DATA DE TÉRMINO
  // ============================================================

  Future<void> _editEndDate(
    Map<String, dynamic> work,
  ) async {
    final DateTime currentDate = work['endDate'] as DateTime;

    final DateTime? picked = await _selectDate(
      initialDate: currentDate,
    );

    if (picked == null || !mounted) {
      return;
    }

    final DateTime startDate = work['startDate'] as DateTime;

    if (picked.isBefore(startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A data de término não pode ser anterior à data de início.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    setState(() {
      work['endDate'] = picked;
    });
  }

  // ============================================================
  // TRABALHOS INTERNOS
  // ============================================================

  void _disposeInternalControllers() {
    for (final work in _internalWorks) {
      final controller = work['controller'];

      if (controller is TextEditingController) {
        controller.dispose();
      }
    }
  }

  void _updateInternalWorks(
    WorkFormat workFormat, {
    ProjectModel? existingProject,
  }) {
    // ============================================================
    // LIBERA CONTROLLERS ANTIGOS
    // ============================================================

    for (final work in _internalWorks) {
      final controller = work['controller'];

      if (controller is TextEditingController) {
        controller.dispose();
      }
    }

    // ============================================================
    // GARANTE DATA BASE
    // ============================================================

    DateTime baseDate = _onlyDate(_startDate);

    // ============================================================
    // SUBTASKS EXISTENTES
    // ============================================================

    final List<TaskModel> existingTasks =
        existingProject?.subTasks ?? <TaskModel>[];

    debugPrint('==========================================');
    debugPrint('CARREGANDO TRABALHOS INTERNOS');
    debugPrint('PROJETO: ${existingProject?.id}');
    debugPrint('ETAPAS DO FORMATO: ${workFormat.steps.length}');
    debugPrint('SUBTASKS DO PROJETO: ${existingTasks.length}');

    for (final task in existingTasks) {
      debugPrint(
        'TASK -> '
        'stage=${task.stage} | '
        'start=${task.startDate} | '
        'planStart=${task.planStart} | '
        'planEnd=${task.planEnd} | '
        'hours=${task.estimatedHours}',
      );
    }

    debugPrint('==========================================');

    // ============================================================
    // MONTA AS ETAPAS
    // ============================================================

    _internalWorks = List.generate(
      workFormat.steps.length,
      (index) {
        // ========================================================
        // CONVERSÃO SEGURA DA ETAPA
        // ========================================================

        final dynamic rawStep = workFormat.steps[index];

        final String workName = _getWorkName(
          rawStep,
          index,
        );

        debugPrint(
          'ETAPA FIRESTORE [$index]: $rawStep',
        );

        debugPrint(
          'NOME NORMALIZADO: $workName',
        );

        // --------------------------------------------------------
        // DATA PADRÃO
        // --------------------------------------------------------

        DateTime stepStart = baseDate;

        DateTime stepEnd = baseDate.add(
          const Duration(days: 15),
        );

        String hoursText = '00:00';

        // --------------------------------------------------------
        // PROCURA A TAREFA EXISTENTE
        //
        // Primeiro pelo nome da etapa.
        // Se não encontrar, usa o índice como fallback.
        // --------------------------------------------------------

        TaskModel? existingTask;

        if (existingTasks.isNotEmpty) {
          // 1º - tenta pelo nome
          for (final task in existingTasks) {
            if (task.stage.trim().toLowerCase() ==
                workName.trim().toLowerCase()) {
              existingTask = task;
              break;
            }
          }

          // 2º - fallback pelo índice
          if (existingTask == null && index < existingTasks.length) {
            existingTask = existingTasks[index];
          }
        }

        // --------------------------------------------------------
        // CARREGA DADOS EXISTENTES
        // --------------------------------------------------------

        if (existingTask != null) {
          // INÍCIO
          stepStart = existingTask.planStart ?? existingTask.startDate;

          // TÉRMINO
          stepEnd = existingTask.planEnd ??
              stepStart.add(
                const Duration(days: 15),
              );

          // HORAS
          hoursText = existingTask.estimatedHours.trim();

          if (hoursText.isEmpty) {
            hoursText = '00:00';
          }

          debugPrint(
            'ETAPA CARREGADA: $workName',
          );

          debugPrint(
            '  INÍCIO: $stepStart',
          );

          debugPrint(
            '  TÉRMINO: $stepEnd',
          );

          debugPrint(
            '  HORAS: $hoursText',
          );
        } else {
          debugPrint(
            'ETAPA SEM DADOS EXISTENTES: $workName',
          );
        }

        // --------------------------------------------------------
        // NORMALIZA DATAS
        // --------------------------------------------------------

        stepStart = _onlyDate(stepStart);
        stepEnd = _onlyDate(stepEnd);

        // --------------------------------------------------------
        // SEGURANÇA
        // --------------------------------------------------------

        if (stepEnd.isBefore(stepStart)) {
          stepEnd = stepStart.add(
            const Duration(days: 15),
          );
        }

        // --------------------------------------------------------
        // CRIA CONTROLLER
        // --------------------------------------------------------

        return <String, dynamic>{
          'name': workName,
          'controller': TextEditingController(
            text: hoursText,
          ),
          'startDate': stepStart,
          'endDate': stepEnd,
        };
      },
    );

    // ============================================================
    // DATA GLOBAL DO PROJETO
    // ============================================================

    if (_internalWorks.isNotEmpty) {
      _startDate = _internalWorks.first['startDate'] as DateTime;
    }

    // ============================================================
    // DEBUG FINAL
    // ============================================================

    debugPrint('==========================================');
    debugPrint('RESULTADO FINAL DO EDITAR');
    debugPrint(
      'TOTAL DE ETAPAS: ${_internalWorks.length}',
    );

    for (final work in _internalWorks) {
      final DateTime start = work['startDate'] as DateTime;

      final DateTime end = work['endDate'] as DateTime;

      debugPrint(
        '${work['name']} -> '
        '${_formatDate(start)} até ${_formatDate(end)}',
      );
    }

    debugPrint('==========================================');
  }

  // ============================================================
  // HORAS
  // ============================================================

  String _calculateTotalEstimatedHours() {
    int totalMinutes = 0;

    for (final work in _internalWorks) {
      final controller = work['controller'] as TextEditingController;

      final String text = controller.text.replaceAll(
        RegExp(r'\D'),
        '',
      );

      if (text.isEmpty) {
        continue;
      }

      final int padded = int.tryParse(text) ?? 0;

      int hours = padded ~/ 100;
      int minutes = padded % 100;

      // Corrige entradas como 00:90.
      hours += minutes ~/ 60;
      minutes %= 60;

      totalMinutes += (hours * 60) + minutes;
    }

    final int finalHours = totalMinutes ~/ 60;

    final int finalMinutes = totalMinutes % 60;

    return '${finalHours.toString().padLeft(2, '0')}:'
        '${finalMinutes.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // ARQUIVO
  // ============================================================

  Future<void> _pickExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'xlsx',
          'xls',
          'csv',
          'docx',
          'pdf',
          'txt',
        ],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _excelLinkController.text = result.files.single.path!;
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar arquivo: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // ABRIR CAMINHO / ARQUIVO
  // ============================================================

  Future<void> _abrirCaminho(
    String? caminho,
  ) async {
    if (caminho == null || caminho.trim().isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum caminho ou arquivo cadastrado para este projeto.',
          ),
        ),
      );

      return;
    }

    try {
      final String path = caminho.trim();

      // ========================================================
      // LINK HTTP / HTTPS
      // ========================================================

      if (path.startsWith('http://') || path.startsWith('https://')) {
        final Uri uri = Uri.parse(path);

        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
        } else {
          throw 'Não foi possível abrir o link.';
        }

        return;
      }

      // ========================================================
      // ARQUIVO
      // ========================================================

      final File file = File(path);

      // ========================================================
      // PASTA
      // ========================================================

      final Directory directory = Directory(path);

      Uri? uri;

      if (await file.exists()) {
        uri = Uri.file(file.path);
      } else if (await directory.exists()) {
        uri = Uri.directory(directory.path);
      } else {
        final Directory parentDir = file.parent;

        if (await parentDir.exists()) {
          uri = Uri.directory(
            parentDir.path,
          );
        }
      }

      if (uri == null) {
        throw 'O arquivo ou pasta não foi encontrado.';
      }

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw 'Não foi possível abrir o arquivo ou pasta.';
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao abrir arquivo/pasta: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // SALVAR PROJETO
  // ============================================================

  Future<void> _saveProject() async {
    if (_isSaving) {
      return;
    }

    final String id = _idController.text.trim();

    final String client = _clientController.text.trim();

    // ==========================================================
    // VALIDA CAMPOS OBRIGATÓRIOS
    // ==========================================================

    if (id.isEmpty || client.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe o ID e o Cliente.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    // ==========================================================
    // VALIDA DATAS
    // ==========================================================

    for (final work in _internalWorks) {
      final DateTime startDate = work['startDate'] as DateTime;

      final DateTime endDate = work['endDate'] as DateTime;

      if (endDate.isBefore(startDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A etapa "${work['name']}" possui término '
              'anterior ao início.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );

        return;
      }
    }

    // ==========================================================
    // CRIA AS SUBTASKS
    // ==========================================================

    final List<TaskModel> customSubTasks = [];

    for (int index = 0; index < _internalWorks.length; index++) {
      final work = _internalWorks[index];

      final TextEditingController controller =
          work['controller'] as TextEditingController;

      final DateTime stepStart = work['startDate'] as DateTime;

      final DateTime stepEnd = work['endDate'] as DateTime;

      customSubTasks.add(
        TaskModel(
          subId: (index + 1).toString(),
          stage: work['name'] as String,
          status: _status,
          startDate: stepStart,
          planStart: stepStart,
          planEnd: stepEnd,
          estimatedHours: controller.text.trim().isNotEmpty
              ? controller.text.trim()
              : '00:00',
          hourType: _hourType,
        ),
      );
    }

    // ==========================================================
    // DATA INICIAL DO PROJETO
    // ==========================================================

    final DateTime globalStartDate = _internalWorks.isNotEmpty
        ? _internalWorks.first['startDate'] as DateTime
        : _startDate;

    // ==========================================================
    // PROJETO
    // ==========================================================

    final ProjectModel savedProject = ProjectModel(
      id: id,

      // Mantém o ID2 existente durante edição.
      id2: widget.projectToEdit?.id2 ?? '0',

      client: client,

      serviceType: _selectedWorkFormat?.name ?? 'Geral',

      stage: _internalWorks.isNotEmpty
          ? _internalWorks.first['name'] as String
          : 'Geral',

      // Mantém a tarefa existente durante edição.
      task: widget.projectToEdit?.task ?? '',

      status: _status,

      startDate: globalStartDate,

      estimatedHours: _calculateTotalEstimatedHours(),

      leader: _leaderController.text.trim().isEmpty
          ? 'Equipe'
          : _leaderController.text.trim(),

      hourType: _hourType,

      excelLink: _excelLinkController.text.trim().isEmpty
          ? null
          : _excelLinkController.text.trim(),

      folderPath: _folderPathController.text.trim().isEmpty
          ? null
          : _folderPathController.text.trim(),

      subTasks: customSubTasks,
    );

    // ==========================================================
    // SALVA NO FIREBASE
    // ==========================================================

    setState(() {
      _isSaving = true;
    });

    try {
      await _firebaseService.saveProject(
        savedProject,
        savedProject.id,
      );

      if (!mounted) return;

      Navigator.of(context).pop(
        savedProject,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar no banco de dados: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _idController.dispose();
    _clientController.dispose();
    _leaderController.dispose();
    _excelLinkController.dispose();
    _folderPathController.dispose();

    _disposeInternalControllers();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final String calculatedHours = _calculateTotalEstimatedHours();

    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D44),

      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _isEditing
                ? 'Editar Trabalho - ${widget.projectToEdit!.id}'
                : 'Novo Trabalho',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close,
              color: Colors.white70,
              size: 20,
            ),
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),

      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ==================================================
              // ID + STATUS
              // ==================================================

              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _idController,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'ID',
                        labelStyle: TextStyle(
                          color: Colors.white70,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: DropdownButtonFormField<String>(
                      value: _status,
                      dropdownColor: const Color(0xFF2D2D44),
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        labelStyle: TextStyle(
                          color: Colors.white70,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'INI_PRI',
                          child: Text('INI_PRI'),
                        ),
                        DropdownMenuItem(
                          value: 'INI_PRO',
                          child: Text('INI_PRO'),
                        ),
                        DropdownMenuItem(
                          value: 'TRAB',
                          child: Text('TRAB'),
                        ),
                        DropdownMenuItem(
                          value: 'EA',
                          child: Text('EA'),
                        ),
                        DropdownMenuItem(
                          value: 'TRAB_FIM',
                          child: Text('TRAB_FIM'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _status = value ?? 'INI_PRI';
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ==================================================
              // CLIENTE + TIPO SERVIÇO
              // ==================================================

              Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: TextField(
                      controller: _clientController,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cliente',
                        labelStyle: TextStyle(
                          color: Colors.white70,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<WorkFormat>(
                      value: _selectedWorkFormat,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2D2D44),
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Serviço',
                        labelStyle: TextStyle(
                          color: Colors.white70,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: widget.workFormats
                          .map(
                            (wf) => DropdownMenuItem<WorkFormat>(
                              value: wf,
                              child: Text(
                                wf.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val == null) {
                          return;
                        }

                        setState(() {
                          _selectedWorkFormat = val;

                          _updateInternalWorks(
                            val,
                            existingProject: widget.projectToEdit,
                          );
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ==================================================
              // PASTA + ARQUIVO
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _folderPathController,
                      readOnly: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Pasta de Documentos',
                        labelStyle: const TextStyle(
                          color: Colors.white70,
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: const Icon(
                          Icons.folder,
                          color: Colors.cyanAccent,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.folder_open,
                            color: Colors.cyanAccent,
                            size: 20,
                          ),
                          onPressed: () {
                            if (_folderPathController.text.isNotEmpty) {
                              _abrirCaminho(
                                _folderPathController.text,
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Nenhuma pasta cadastrada.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickExcelFile,
                      child: AbsorbPointer(
                        child: TextField(
                          controller: _excelLinkController,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Arquivo (Excel / Word / Link)',
                            labelStyle: TextStyle(
                              color: Colors.white70,
                            ),
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.insert_drive_file,
                              color: Colors.cyanAccent,
                              size: 20,
                            ),
                            suffixIcon: Icon(
                              Icons.attach_file,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ==================================================
              // TÍTULO
              // ==================================================

              const Text(
                'Trabalhos Internos do Serviço',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 3),

              const Text(
                'Clique nas datas em vermelho para editar o início e o término de cada etapa.',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 8),

              // ==================================================
              // TABELA DE TRABALHOS
              // ==================================================

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF232338),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white24,
                  ),
                ),
                child: _internalWorks.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Nenhum trabalho interno cadastrado para este serviço.',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Column(
                        children: _internalWorks.map(
                          (work) {
                            final DateTime sDate =
                                work['startDate'] as DateTime;

                            final DateTime eDate = work['endDate'] as DateTime;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  // =================================
                                  // NOME DA ETAPA
                                  // =================================

                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      work['name'] as String,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(
                                    width: 8,
                                  ),

                                  // =================================
                                  // DATA INÍCIO
                                  // =================================

                                  Expanded(
                                    flex: 2,
                                    child: InkWell(
                                      onTap: () => _editStartDate(
                                        work,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        4,
                                      ),
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          labelText: 'Início',
                                          labelStyle: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          suffixIcon: Icon(
                                            Icons.calendar_month,
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            size: 17,
                                          ),
                                        ),
                                        child: Text(
                                          _formatDate(
                                            sDate,
                                          ),
                                          style: const TextStyle(
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(
                                    width: 8,
                                  ),

                                  // =================================
                                  // DATA TÉRMINO
                                  // =================================

                                  Expanded(
                                    flex: 2,
                                    child: InkWell(
                                      onTap: () => _editEndDate(
                                        work,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        4,
                                      ),
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          labelText: 'Término',
                                          labelStyle: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                          ),
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          suffixIcon: Icon(
                                            Icons.calendar_month,
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            size: 17,
                                          ),
                                        ),
                                        child: Text(
                                          _formatDate(
                                            eDate,
                                          ),
                                          style: const TextStyle(
                                            color: Color(
                                              0xFFFF5252,
                                            ),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(
                                    width: 8,
                                  ),

                                  // =================================
                                  // HORAS
                                  // =================================

                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      controller: work['controller']
                                          as TextEditingController,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        HoursInputFormatter(),
                                      ],
                                      onChanged: (_) {
                                        setState(() {});
                                      },
                                      decoration: const InputDecoration(
                                        labelText: 'Horas',
                                        labelStyle: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                        hintText: '00:00',
                                        hintStyle: TextStyle(
                                          color: Colors.white24,
                                        ),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ).toList(),
                      ),
              ),

              const SizedBox(height: 16),

              // ==================================================
              // TOTAL + TIPO HORAS + LÍDER
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Hs Estimadas (Calc.)',
                        labelStyle: TextStyle(
                          color: Colors.white70,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Text(
                        calculatedHours,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _hourType,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2D2D44),
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Horas',
                        labelStyle: TextStyle(
                          color: Colors.white70,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Hs Cobradas',
                          child: Text(
                            'Hs Cobradas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Investimento',
                          child: Text(
                            'Hs Investimento',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Não Cobradas',
                          child: Text(
                            'Hs Não Cobradas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Internas',
                          child: Text(
                            'Hs Internas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Outras',
                          child: Text(
                            'Outras',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Hs Não Informadas',
                          child: Text(
                            'Hs Não Informadas',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _hourType = value ?? 'Hs Cobradas';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _leaderController,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Líder Prj',
                        labelStyle: TextStyle(
                          color: Colors.white70,
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

      // ============================================================
      // BOTÕES
      // ============================================================

      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancelar',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00FFCC),
            foregroundColor: Colors.black,
          ),
          onPressed: _isSaving ? null : _saveProject,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  _isEditing ? 'Salvar Alterações' : 'Salvar',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }
}
