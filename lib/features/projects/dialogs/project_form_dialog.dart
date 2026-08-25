import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
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

  // ============================================================
  // CHECKLIST
  // ============================================================

  List<ChecklistFormat> _checklistFormats = [];

  ChecklistFormat? _selectedChecklistFormat;

  List<Map<String, dynamic>> _checklistItems = [];

  bool _loadingChecklistFormats = true;

  final TextEditingController _newChecklistItemController =
      TextEditingController();

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

      _startDate = _onlyDate(project.startDate);

      if (project.subTasks != null && project.subTasks!.isNotEmpty) {
        final firstTask = project.subTasks!.first;

        _startDate = _onlyDate(
          firstTask.planStart ?? firstTask.startDate,
        );
      }

      debugPrint('====================================');
      debugPrint('EDITANDO PROJETO');
      debugPrint('ID: ${project.id}');
      debugPrint('CLIENTE: ${project.client}');
      debugPrint('DATA PROJETO: ${project.startDate}');
      debugPrint('SUBTASKS: ${project.subTasks?.length}');
      debugPrint(
        'CHECKLIST EXISTENTE: ${project.checklist?.length ?? 0}',
      );
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

      // ----------------------------------------------------------
      // CARREGA CHECKLIST EXISTENTE
      // ----------------------------------------------------------

      if (project.checklist != null && project.checklist!.isNotEmpty) {
        _checklistItems = project.checklist!
            .map(
              (item) => Map<String, dynamic>.from(item),
            )
            .toList();

        debugPrint(
          'CHECKLIST CARREGADO DO PROJETO: ${_checklistItems.length}',
        );
      }
    } else {
      // ----------------------------------------------------------
      // NOVO PROJETO
      // ----------------------------------------------------------

      final now = DateTime.now();

      _startDate = DateTime(
        now.year,
        now.month,
        now.day,
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

    // ------------------------------------------------------------
    // CARREGA MODELOS DE CHECKLIST
    // ------------------------------------------------------------

    _loadChecklistFormats();
  }

  // ============================================================
  // CARREGAR MODELOS DE CHECKLIST
  // ============================================================

  Future<void> _loadChecklistFormats() async {
    try {
      final formats = await _firebaseService.getChecklistFormats();

      if (!mounted) {
        return;
      }

      setState(() {
        _checklistFormats = formats;
        _loadingChecklistFormats = false;
      });

      debugPrint('==========================================');
      debugPrint('MODELOS DE CHECKLIST CARREGADOS');
      debugPrint('TOTAL: ${formats.length}');

      for (final format in formats) {
        debugPrint(
          'MODELO: ${format.name} | '
          'ID: ${format.id} | '
          'ITENS: ${format.items.length}',
        );
      }

      debugPrint('==========================================');

      if (_isEditing &&
          _checklistItems.isNotEmpty &&
          _selectedChecklistFormat == null &&
          formats.isNotEmpty) {
        final ChecklistFormat? matchedFormat =
            _findMatchingChecklistFormat(formats);

        if (matchedFormat != null && mounted) {
          setState(() {
            _selectedChecklistFormat = matchedFormat;
          });
        }
      }
    } catch (e) {
      debugPrint(
        'ERRO AO CARREGAR MODELOS DE CHECKLIST: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loadingChecklistFormats = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível carregar os modelos de Check List: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ============================================================
  // ENCONTRA MODELO COMPATÍVEL COM CHECKLIST EXISTENTE
  // ============================================================

  ChecklistFormat? _findMatchingChecklistFormat(
    List<ChecklistFormat> formats,
  ) {
    final existingNames = _checklistItems
        .map(
          (item) => item['name']?.toString().trim().toLowerCase() ?? '',
        )
        .where(
          (name) => name.isNotEmpty,
        )
        .toSet();

    if (existingNames.isEmpty) {
      return null;
    }

    ChecklistFormat? bestMatch;
    int bestMatchCount = 0;

    for (final format in formats) {
      int matchCount = 0;

      for (final item in format.items) {
        final name = item['name']?.toString().trim().toLowerCase() ?? '';

        if (name.isNotEmpty && existingNames.contains(name)) {
          matchCount++;
        }
      }

      if (matchCount > bestMatchCount) {
        bestMatchCount = matchCount;
        bestMatch = format;
      }
    }

    return bestMatch;
  }

  // ============================================================
  // APLICAR MODELO DE CHECKLIST
  // ============================================================

  void _applyChecklistFormat(
    ChecklistFormat? format,
  ) {
    if (format == null) {
      return;
    }

    debugPrint('==========================================');
    debugPrint('APLICANDO MODELO DE CHECKLIST');
    debugPrint('MODELO: ${format.name}');
    debugPrint('ID: ${format.id}');
    debugPrint('ITENS: ${format.items.length}');
    debugPrint('==========================================');

    final List<Map<String, dynamic>> newItems = [];

    for (int index = 0; index < format.items.length; index++) {
      final item = format.items[index];

      final String name = item['name']?.toString().trim() ?? '';

      if (name.isEmpty) {
        continue;
      }

      newItems.add(
        {
          'order': item['order']?.toString().isNotEmpty == true
              ? item['order'].toString()
              : (index + 1).toString(),
          'name': name,
          'completed': false,
          'source': 'model',
          'modelId': format.id,
          'modelName': format.name,
        },
      );
    }

    setState(() {
      _selectedChecklistFormat = format;
      _checklistItems = newItems;
    });

    debugPrint(
      'CHECKLIST APLICADO: ${_checklistItems.length} itens',
    );
  }

  // ============================================================
  // ADICIONAR ITEM MANUAL
  // ============================================================

  Future<void> _addChecklistItem() async {
    _newChecklistItemController.clear();

    final String? itemName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2D2D44),
          title: const Text(
            'Adicionar item ao Check List',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: _newChecklistItemController,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
              ),
              onSubmitted: (value) {
                final text = value.trim();

                if (text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(text);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Descrição do item',
                labelStyle: TextStyle(
                  color: Colors.white70,
                ),
                hintText: 'Digite o item do Check List',
                hintStyle: TextStyle(
                  color: Colors.white30,
                ),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
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
              onPressed: () {
                final text = _newChecklistItemController.text.trim();

                if (text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(text);
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

    if (itemName == null || itemName.trim().isEmpty || !mounted) {
      return;
    }

    setState(() {
      _checklistItems.add(
        {
          'order': (_checklistItems.length + 1).toString(),
          'name': itemName.trim(),
          'completed': false,
          'source': 'manual',
          'modelId': null,
          'modelName': null,
        },
      );
    });

    debugPrint(
      'ITEM MANUAL ADICIONADO: $itemName',
    );
  }

  // ============================================================
  // REMOVER ITEM DO CHECKLIST
  // ============================================================

  void _removeChecklistItem(
    int index,
  ) {
    if (index < 0 || index >= _checklistItems.length) {
      return;
    }

    final item = _checklistItems[index];

    final String source = item['source']?.toString() ?? 'model';

    setState(() {
      _checklistItems.removeAt(index);

      for (int i = 0; i < _checklistItems.length; i++) {
        _checklistItems[i]['order'] = (i + 1).toString();
      }
    });

    debugPrint(
      'ITEM REMOVIDO DO PROJETO: '
      '${item['name']} | source=$source',
    );
  }

  // ============================================================
  // MARCAR CHECKLIST
  // ============================================================

  void _toggleChecklistItem(
    int index,
    bool? value,
  ) {
    if (index < 0 || index >= _checklistItems.length) {
      return;
    }

    setState(() {
      _checklistItems[index]['completed'] = value == true;
    });
  }

  // ============================================================
  // CONVERTER CHECKLIST PARA SALVAMENTO
  // ============================================================

  List<Map<String, dynamic>> _buildChecklistForSave() {
    final List<Map<String, dynamic>> result = [];

    for (int index = 0; index < _checklistItems.length; index++) {
      final item = Map<String, dynamic>.from(
        _checklistItems[index],
      );

      final String name = item['name']?.toString().trim() ?? '';

      if (name.isEmpty) {
        continue;
      }

      result.add(
        {
          'order': (index + 1).toString(),
          'name': name,
          'completed': item['completed'] == true,
          'source': item['source']?.toString() ?? 'manual',
          'modelId': item['modelId'],
          'modelName': item['modelName'],
        },
      );
    }

    return result;
  }

  // ============================================================
  // CONVERTER ETAPA DO WORK FORMAT
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

  // ============================================================
  // SELETOR DE DATA
  //
  // CORRIGIDO:
  // - normaliza a data;
  // - garante que initialDate esteja entre firstDate/lastDate;
  // - não força locale diretamente no showDatePicker;
  // - protege contra exceções;
  // - retorna a data sem horário.
  // ============================================================

  Future<DateTime?> _selectDate({
    required DateTime initialDate,
  }) async {
    DateTime normalizedInitialDate = _onlyDate(
      initialDate,
    );

    final DateTime firstDate = DateTime(
      2000,
      1,
      1,
    );

    final DateTime lastDate = DateTime(
      2100,
      12,
      31,
    );

    // ----------------------------------------------------------
    // Garante que initialDate esteja dentro do intervalo.
    // ----------------------------------------------------------

    if (normalizedInitialDate.isBefore(firstDate)) {
      normalizedInitialDate = firstDate;
    }

    if (normalizedInitialDate.isAfter(lastDate)) {
      normalizedInitialDate = lastDate;
    }

    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: normalizedInitialDate,
        firstDate: firstDate,
        lastDate: lastDate,

        // IMPORTANTE:
        // Não usamos:
        //
        // locale: const Locale('pt', 'BR'),
        //
        // diretamente aqui.
        //
        // A localização deve ser configurada no MaterialApp.

        builder: (
          BuildContext dialogContext,
          Widget? child,
        ) {
          if (child == null) {
            return const SizedBox.shrink();
          }

          return Theme(
            data: Theme.of(dialogContext).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF00FFCC),
                onPrimary: Colors.black,
                surface: Color(0xFF2D2D44),
                onSurface: Colors.white,
              ),
              dialogTheme: const DialogThemeData(
                backgroundColor: Color(0xFF2D2D44),
              ),
            ),
            child: child,
          );
        },
      );

      if (picked == null) {
        return null;
      }

      return _onlyDate(
        picked,
      );
    } catch (e, stackTrace) {
      debugPrint('==========================================');
      debugPrint('ERRO AO ABRIR SELETOR DE DATA');
      debugPrint('DATA RECEBIDA: $initialDate');
      debugPrint(
        'DATA NORMALIZADA: $normalizedInitialDate',
      );
      debugPrint('ERRO: $e');
      debugPrint('STACK TRACE: $stackTrace');
      debugPrint('==========================================');

      if (!mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível abrir o calendário: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return null;
    }
  }

  // ============================================================
  // EDITAR DATA DE INÍCIO
  // ============================================================

  Future<void> _editStartDate(
    Map<String, dynamic> work,
  ) async {
    final dynamic rawStartDate = work['startDate'];
    final dynamic rawEndDate = work['endDate'];

    // ----------------------------------------------------------
    // Proteção contra dados inválidos.
    // ----------------------------------------------------------

    if (rawStartDate is! DateTime || rawEndDate is! DateTime) {
      debugPrint(
        'ERRO: datas inválidas no trabalho ${work['name']}',
      );

      debugPrint(
        'startDate: $rawStartDate '
        '(${rawStartDate.runtimeType})',
      );

      debugPrint(
        'endDate: $rawEndDate '
        '(${rawEndDate.runtimeType})',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível editar a data desta etapa.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      return;
    }

    final DateTime currentDate = _onlyDate(
      rawStartDate,
    );

    final DateTime endDate = _onlyDate(
      rawEndDate,
    );

    final DateTime? picked = await _selectDate(
      initialDate: currentDate,
    );

    if (picked == null || !mounted) {
      return;
    }

    // ----------------------------------------------------------
    // Valida início x término.
    // ----------------------------------------------------------

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

      if (_internalWorks.isNotEmpty &&
          identical(
            work,
            _internalWorks.first,
          )) {
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
    final dynamic rawStartDate = work['startDate'];
    final dynamic rawEndDate = work['endDate'];

    // ----------------------------------------------------------
    // Proteção contra dados inválidos.
    // ----------------------------------------------------------

    if (rawStartDate is! DateTime || rawEndDate is! DateTime) {
      debugPrint(
        'ERRO: datas inválidas no trabalho ${work['name']}',
      );

      debugPrint(
        'startDate: $rawStartDate '
        '(${rawStartDate.runtimeType})',
      );

      debugPrint(
        'endDate: $rawEndDate '
        '(${rawEndDate.runtimeType})',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível editar a data desta etapa.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      return;
    }

    final DateTime currentDate = _onlyDate(
      rawEndDate,
    );

    final DateTime startDate = _onlyDate(
      rawStartDate,
    );

    final DateTime? picked = await _selectDate(
      initialDate: currentDate,
    );

    if (picked == null || !mounted) {
      return;
    }

    // ----------------------------------------------------------
    // Valida término x início.
    // ----------------------------------------------------------

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
    for (final work in _internalWorks) {
      final controller = work['controller'];

      if (controller is TextEditingController) {
        controller.dispose();
      }
    }

    DateTime baseDate = _onlyDate(
      _startDate,
    );

    final List<TaskModel> existingTasks =
        existingProject?.subTasks ?? <TaskModel>[];

    debugPrint('==========================================');
    debugPrint('CARREGANDO TRABALHOS INTERNOS');
    debugPrint('PROJETO: ${existingProject?.id}');
    debugPrint(
      'ETAPAS DO FORMATO: ${workFormat.steps.length}',
    );
    debugPrint(
      'SUBTASKS DO PROJETO: ${existingTasks.length}',
    );

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

    _internalWorks = List.generate(
      workFormat.steps.length,
      (index) {
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

        DateTime stepStart = baseDate;

        DateTime stepEnd = baseDate.add(
          const Duration(days: 15),
        );

        String hoursText = '00:00';

        TaskModel? existingTask;

        if (existingTasks.isNotEmpty) {
          for (final task in existingTasks) {
            if (task.stage.trim().toLowerCase() ==
                workName.trim().toLowerCase()) {
              existingTask = task;
              break;
            }
          }

          if (existingTask == null && index < existingTasks.length) {
            existingTask = existingTasks[index];
          }
        }

        if (existingTask != null) {
          stepStart = existingTask.planStart ?? existingTask.startDate;

          stepEnd = existingTask.planEnd ??
              stepStart.add(
                const Duration(days: 15),
              );

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
        // Normaliza as datas.
        // --------------------------------------------------------

        stepStart = _onlyDate(
          stepStart,
        );

        stepEnd = _onlyDate(
          stepEnd,
        );

        // --------------------------------------------------------
        // Proteção contra término anterior ao início.
        // --------------------------------------------------------

        if (stepEnd.isBefore(stepStart)) {
          stepEnd = stepStart.add(
            const Duration(days: 15),
          );
        }

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

    if (_internalWorks.isNotEmpty) {
      _startDate = _internalWorks.first['startDate'] as DateTime;
    }

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

      final File file = File(path);

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
      final dynamic rawStartDate = work['startDate'];
      final dynamic rawEndDate = work['endDate'];

      if (rawStartDate is! DateTime || rawEndDate is! DateTime) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A etapa "${work['name']}" possui datas inválidas.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );

        return;
      }

      final DateTime startDate = _onlyDate(rawStartDate);

      final DateTime endDate = _onlyDate(rawEndDate);

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
    // CRIA SUBTASKS
    // ==========================================================

    final List<TaskModel> customSubTasks = [];

    for (int index = 0; index < _internalWorks.length; index++) {
      final work = _internalWorks[index];

      final TextEditingController controller =
          work['controller'] as TextEditingController;

      final DateTime stepStart = _onlyDate(work['startDate'] as DateTime);

      final DateTime stepEnd = _onlyDate(work['endDate'] as DateTime);

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
        ? _onlyDate(
            _internalWorks.first['startDate'] as DateTime,
          )
        : _onlyDate(_startDate);

    // ==========================================================
    // CHECKLIST
    // ==========================================================

    final List<Map<String, dynamic>> checklistToSave = _buildChecklistForSave();

    debugPrint('==========================================');
    debugPrint('SALVANDO CHECKLIST');
    debugPrint(
      'MODELO: ${_selectedChecklistFormat?.name ?? 'Nenhum'}',
    );
    debugPrint(
      'ITENS: ${checklistToSave.length}',
    );

    for (final item in checklistToSave) {
      debugPrint(
        '${item['order']} - '
        '${item['name']} - '
        'concluído=${item['completed']} - '
        'source=${item['source']}',
      );
    }

    debugPrint('==========================================');

    // ==========================================================
    // PROJETO
    // ==========================================================

    final ProjectModel savedProject = ProjectModel(
      id: id,
      id2: widget.projectToEdit?.id2 ?? '0',
      client: client,
      serviceType: _selectedWorkFormat?.name ?? 'Geral',
      stage: _internalWorks.isNotEmpty
          ? _internalWorks.first['name'] as String
          : 'Geral',
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
      checklist: checklistToSave,
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

    _newChecklistItemController.dispose();

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
          Expanded(
            child: Text(
              _isEditing
                  ? 'Editar Trabalho - ${widget.projectToEdit!.id}'
                  : 'Novo Trabalho',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
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
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(
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
              // CHECK LIST
              // ==================================================

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check List',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Selecione um modelo para aplicar os itens ao trabalho.',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (_checklistItems.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF00FFCC,
                        ).withOpacity(
                          0.10,
                        ),
                        borderRadius: BorderRadius.circular(
                          20,
                        ),
                        border: Border.all(
                          color: const Color(
                            0xFF00FFCC,
                          ).withOpacity(
                            0.30,
                          ),
                        ),
                      ),
                      child: Text(
                        '${_checklistItems.where((item) => item['completed'] == true).length}/${_checklistItems.length}',
                        style: const TextStyle(
                          color: Color(
                            0xFF00FFCC,
                          ),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // ==================================================
              // SELEÇÃO DO MODELO
              // ==================================================

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF232338,
                  ),
                  borderRadius: BorderRadius.circular(
                    8,
                  ),
                  border: Border.all(
                    color: Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.playlist_add_check,
                      color: Color(0xFF00FFCC),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _loadingChecklistFormats
                          ? const Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(
                                      0xFF00FFCC,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Carregando modelos de Check List...',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : DropdownButtonFormField<ChecklistFormat>(
                              value: _selectedChecklistFormat,
                              isExpanded: true,
                              dropdownColor: const Color(
                                0xFF2D2D44,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Modelo de Check List',
                                labelStyle: TextStyle(
                                  color: Colors.white70,
                                ),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              hint: const Text(
                                'Selecione um modelo',
                                style: TextStyle(
                                  color: Colors.white38,
                                ),
                              ),
                              items: _checklistFormats
                                  .map(
                                    (
                                      format,
                                    ) =>
                                        DropdownMenuItem<ChecklistFormat>(
                                      value: format,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              format.name,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${format.items.length} itens',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                _applyChecklistFormat(
                                  value,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ==================================================
              // ITENS DO CHECKLIST
              // ==================================================

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF232338,
                  ),
                  borderRadius: BorderRadius.circular(
                    8,
                  ),
                  border: Border.all(
                    color: Colors.white24,
                  ),
                ),
                child: _checklistItems.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.checklist,
                              color: Colors.white24,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Nenhum item no Check List deste trabalho.',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _addChecklistItem,
                              icon: const Icon(
                                Icons.add,
                                size: 18,
                              ),
                              label: const Text(
                                'Adicionar',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(
                                  0xFF00FFCC,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          ...List.generate(
                            _checklistItems.length,
                            (index) {
                              final item = _checklistItems[index];

                              final String itemName =
                                  item['name']?.toString() ?? '';

                              final bool completed = item['completed'] == true;

                              final String source =
                                  item['source']?.toString() ?? 'model';

                              final bool isManual = source == 'manual';

                              return Container(
                                margin: EdgeInsets.only(
                                  bottom: index == _checklistItems.length - 1
                                      ? 0
                                      : 6,
                                ),
                                decoration: BoxDecoration(
                                  color: completed
                                      ? const Color(
                                          0xFF00FFCC,
                                        ).withOpacity(
                                          0.06,
                                        )
                                      : Colors.white.withOpacity(
                                          0.02,
                                        ),
                                  borderRadius: BorderRadius.circular(
                                    6,
                                  ),
                                  border: Border.all(
                                    color: completed
                                        ? const Color(
                                            0xFF00FFCC,
                                          ).withOpacity(
                                            0.25,
                                          )
                                        : Colors.white.withOpacity(
                                            0.08,
                                          ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: completed,
                                      activeColor: const Color(
                                        0xFF00FFCC,
                                      ),
                                      checkColor: Colors.black,
                                      onChanged: (value) {
                                        _toggleChecklistItem(
                                          index,
                                          value,
                                        );
                                      },
                                    ),
                                    Container(
                                      width: 25,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        itemName,
                                        style: TextStyle(
                                          color: completed
                                              ? Colors.white38
                                              : Colors.white,
                                          fontSize: 12,
                                          decoration: completed
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          decorationColor: Colors.white38,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isManual
                                            ? Colors.orangeAccent.withOpacity(
                                                0.10,
                                              )
                                            : Colors.cyanAccent.withOpacity(
                                                0.08,
                                              ),
                                        borderRadius: BorderRadius.circular(
                                          10,
                                        ),
                                      ),
                                      child: Text(
                                        isManual ? 'Adicional' : 'Modelo',
                                        style: TextStyle(
                                          color: isManual
                                              ? Colors.orangeAccent
                                              : Colors.cyanAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      tooltip: 'Remover item deste trabalho',
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white30,
                                        size: 17,
                                      ),
                                      onPressed: () {
                                        _removeChecklistItem(
                                          index,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton.icon(
                              onPressed: _addChecklistItem,
                              icon: const Icon(
                                Icons.add,
                                size: 17,
                              ),
                              label: const Text(
                                'Adicionar item',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(
                                  0xFF00FFCC,
                                ),
                                side: BorderSide(
                                  color: const Color(
                                    0xFF00FFCC,
                                  ).withOpacity(
                                    0.50,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // TÍTULO TRABALHOS INTERNOS
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
                  color: const Color(
                    0xFF232338,
                  ),
                  borderRadius: BorderRadius.circular(
                    8,
                  ),
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
                                  // NOME
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

                                  const SizedBox(width: 8),

                                  // INÍCIO
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

                                  const SizedBox(width: 8),

                                  // TÉRMINO
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

                                  const SizedBox(width: 8),

                                  // HORAS
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
                                        setState(
                                          () {},
                                        );
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
                      dropdownColor: const Color(
                        0xFF2D2D44,
                      ),
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
