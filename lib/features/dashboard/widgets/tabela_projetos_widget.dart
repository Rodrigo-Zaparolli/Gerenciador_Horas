import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pasteboard/pasteboard.dart';
import 'dart:typed_data';
import 'package:gerenciador_horas/data/services/edesk_service.dart';

class HoraInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    text = text.replaceAll(RegExp(r'[^0-9:]'), '');

    if (text.contains(':')) {
      final parts = text.split(':');
      String hours = parts[0];
      String minutes = parts.length > 1 ? parts[1] : '';

      if (hours.length > 4) {
        hours = hours.substring(0, 4);
      }

      if (minutes.length > 2) {
        minutes = minutes.substring(0, 2);
      }

      text = '$hours:$minutes';
    } else {
      if (text.length > 6) {
        text = text.substring(0, 6);
      }

      if (text.length > 2) {
        final hours = text.substring(0, text.length - 2);
        final minutes = text.substring(text.length - 2);
        text = '$hours:$minutes';
      }
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class TabelaProjetosWidget extends StatefulWidget {
  final List<ProjectModel> projects;
  final List<String> statusList;
  final Set<String> expandedProjectIds;
  final String? selectedTargetId;
  final List<String> idsEmAlerta;

  final List<TimeLog> timeLogs;
  final String? activeTimerTargetId;
  final DateTime? activeStartTime;
  final TimerState timerState;
  final int secondsElapsed;
  final bool showPostStopButton;

  final ScrollController horizontalController;
  final ScrollController verticalController;

  final ValueChanged<String> onSelectTarget;
  final ValueChanged<String> onToggleExpand;

  final ValueChanged<ProjectModel> onEditProject;
  final ValueChanged<ProjectModel> onDeleteProject;
  final ValueChanged<ProjectModel> onAddSubTask;

  final void Function(ProjectModel, String) onProjectStatusChanged;
  final void Function(TaskModel, String) onSubTaskStatusChanged;

  final void Function(ProjectModel, TaskModel) onEditSubTask;
  final void Function(ProjectModel, TaskModel) onDeleteSubTask;

  final ValueChanged<String> onStartTimer;
  final VoidCallback onPauseTimer;
  final VoidCallback onStopTimer;
  final ValueChanged<String> onManualTime;

  final ValueChanged<TimeLog> onEditLog;
  final ValueChanged<TimeLog> onDeleteLog;
  final ValueChanged<TimeLog> onRegisterLog;
  final ValueChanged<TaskModel> onMarkTaskCompleted;

  final String Function(int) formatDuration;
  final FirebaseService firebaseService;

  const TabelaProjetosWidget({
    super.key,
    required this.projects,
    required this.statusList,
    required this.expandedProjectIds,
    required this.selectedTargetId,
    this.idsEmAlerta = const [],
    required this.timeLogs,
    required this.activeTimerTargetId,
    required this.activeStartTime,
    required this.timerState,
    required this.secondsElapsed,
    required this.showPostStopButton,
    required this.horizontalController,
    required this.verticalController,
    required this.onSelectTarget,
    required this.onToggleExpand,
    required this.onEditProject,
    required this.onDeleteProject,
    required this.onAddSubTask,
    required this.onProjectStatusChanged,
    required this.onSubTaskStatusChanged,
    required this.onEditSubTask,
    required this.onDeleteSubTask,
    required this.onStartTimer,
    required this.onPauseTimer,
    required this.onStopTimer,
    required this.onManualTime,
    required this.onEditLog,
    required this.onDeleteLog,
    required this.onRegisterLog,
    required this.onMarkTaskCompleted,
    required this.formatDuration,
    required this.firebaseService,
  });

  @override
  State<TabelaProjetosWidget> createState() => _TabelaProjetosWidgetState();
}

class _TabelaProjetosWidgetState extends State<TabelaProjetosWidget>
    with SingleTickerProviderStateMixin {
  final Map<String, TextEditingController> _inlineControllers = {};
  final Map<String, TextEditingController> _logCommentControllers = {};

  late List<TimeLog> _localTimeLogs;

  late final AnimationController _deadlineBlinkController;

  final List<String> _tiposHsOpcoes = const [
    'Hs Cobradas',
    'Hs Investimento',
    'Hs Não Cobradas',
    'Hs Internas',
    'Outras',
    'Hs Não Informadas',
  ];

  @override
  void initState() {
    super.initState();
    _localTimeLogs = List.from(widget.timeLogs);

    _deadlineBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant TabelaProjetosWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.timeLogs != oldWidget.timeLogs) {
      _localTimeLogs = List.from(widget.timeLogs);
    }
  }

  @override
  void dispose() {
    for (final controller in _inlineControllers.values) {
      controller.dispose();
    }

    _deadlineBlinkController.dispose();

    for (final controller in _logCommentControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  TextEditingController _getInlineController(ProjectModel project) {
    if (!_inlineControllers.containsKey(project.id)) {
      _inlineControllers[project.id] = TextEditingController(
        text: project.observacao ?? '',
      );
    } else {
      final controller = _inlineControllers[project.id]!;

      if (controller.text != (project.observacao ?? '')) {
        controller.text = project.observacao ?? '';
      }
    }

    return _inlineControllers[project.id]!;
  }

  TextEditingController _getLogCommentController(TimeLog log) {
    final key =
        '${log.targetId}_${log.date.toIso8601String()}_${log.startTime}';

    if (!_logCommentControllers.containsKey(key)) {
      _logCommentControllers[key] = TextEditingController(
        text: log.description ?? '',
      );
    } else {
      final controller = _logCommentControllers[key]!;

      if (controller.text != (log.description ?? '')) {
        controller.text = log.description ?? '';
      }
    }

    return _logCommentControllers[key]!;
  }

  Color _getStageColor(String status) {
    switch (status) {
      case 'INI_PRO':
        return CoresDashboard.statusInicial;

      case 'TRAB':
        return CoresDashboard.statusTrabalhando;

      case 'EA':
        return CoresDashboard.statusAndamento;

      case 'TRAB_FIM':
        return CoresDashboard.statusFinalizado;

      default:
        return CoresApp.textoSecundario;
    }
  }

  bool _projectHasDeadlineAlert(ProjectModel project) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (project.subTasks != null && project.subTasks!.isNotEmpty) {
      return project.subTasks!.any((task) {
        if (task.status == 'TRAB_FIM') return false;

        final planEnd = task.planEnd ?? task.startDate;
        final normalizedEnd =
            DateTime(planEnd.year, planEnd.month, planEnd.day);
        final differenceDays = normalizedEnd.difference(today).inDays;

        return differenceDays <= 5;
      });
    }

    if (project.status == 'TRAB_FIM') return false;

    final planEnd = project.startDate;
    final normalizedEnd = DateTime(planEnd.year, planEnd.month, planEnd.day);
    final differenceDays = normalizedEnd.difference(today).inDays;

    return differenceDays <= 5;
  }

  bool _projectIsOverdue(ProjectModel project) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (project.subTasks != null && project.subTasks!.isNotEmpty) {
      return project.subTasks!.any((task) {
        if (task.status == 'TRAB_FIM') return false;

        final planEnd = task.planEnd ?? task.startDate;
        final normalizedEnd =
            DateTime(planEnd.year, planEnd.month, planEnd.day);

        return normalizedEnd.isBefore(today);
      });
    }

    if (project.status == 'TRAB_FIM') return false;

    final planEnd = project.startDate;
    final normalizedEnd = DateTime(planEnd.year, planEnd.month, planEnd.day);

    return normalizedEnd.isBefore(today);
  }

  bool _taskIsOverdue(TaskModel task) {
    if (task.status == 'TRAB_FIM') return false;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planEnd = task.planEnd ?? task.startDate;
    final normalizedEnd = DateTime(planEnd.year, planEnd.month, planEnd.day);

    return normalizedEnd.isBefore(today);
  }

  Widget _buildDeadlineDateText(
    String text, {
    required bool overdue,
    Color? normalColor,
    FontWeight? fontWeight,
  }) {
    if (!overdue) {
      return _buildCellText(
        text,
        color: normalColor ?? CoresApp.textoSecundario,
        fontWeight: fontWeight ?? FontWeight.normal,
      );
    }

    return AnimatedBuilder(
      animation: _deadlineBlinkController,
      builder: (context, child) {
        final t = _deadlineBlinkController.value;
        final backgroundOpacity = 0.10 + (t * 0.28);
        final borderOpacity = 0.35 + (t * 0.55);
        final textColor = Color.lerp(
          CoresApp.erro,
          Colors.white,
          t,
        )!;

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: CoresApp.erro.withOpacity(backgroundOpacity),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: CoresApp.erro.withOpacity(borderOpacity),
              width: 1.2,
            ),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: TamanhosApp.tabelaFonte,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.none,
            ),
          ),
        );
      },
    );
  }

  int _parseHoursToMinutes(String rawValue) {
    final cleanVal = rawValue.replaceAll(RegExp(r'[^0-9:]'), '');

    int hours = 0;
    int minutes = 0;

    if (cleanVal.contains(':')) {
      final parts = cleanVal.split(':');

      if (parts.length >= 2) {
        hours = int.tryParse(parts[0]) ?? 0;
        minutes = int.tryParse(parts[1]) ?? 0;
      }
    } else {
      if (cleanVal.length >= 3) {
        final splitIndex = cleanVal.length - 2;

        hours = int.tryParse(cleanVal.substring(0, splitIndex)) ?? 0;

        minutes = int.tryParse(cleanVal.substring(splitIndex)) ?? 0;
      } else {
        hours = int.tryParse(cleanVal) ?? 0;
      }
    }

    return (hours * 60) + minutes;
  }

  String _formatMinutesToHHMM(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;

    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}';
  }

  String _calculateTotalEstimatedHours(
    List<TextEditingController> controllers,
  ) {
    int totalMinutes = 0;

    for (final controller in controllers) {
      totalMinutes += _parseHoursToMinutes(controller.text);
    }

    return _formatMinutesToHHMM(totalMinutes);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().substring(2)}';
  }

  void _handleRegisterLog(TimeLog log) {
    setState(() {
      log.isRegistered = true;
    });

    widget.onRegisterLog(log);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tempo cadastrado e contabilizado com sucesso!',
        ),
        backgroundColor: CoresApp.sucesso,
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: TamanhosApp.tabelaFonteCabecalho,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildCellText(
    String text, {
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    double? fontSize,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? CoresApp.textoSecundario,
        fontSize: fontSize ?? TamanhosApp.tabelaFonte,
        fontWeight: fontWeight,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationThickness: 2.0,
      ),
    );
  }

  Widget _buildProjectIdBadge(
    ProjectModel project,
    bool hasSubtasks,
    bool isExpanded,
    bool emAlerta,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(TamanhosApp.raioBotao),
      onTap: hasSubtasks ? () => widget.onToggleExpand(project.id) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            child: hasSubtasks
                ? Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color:
                        emAlerta ? CoresApp.destaqueAmarelo : CoresApp.destaque,
                    size: TamanhosApp.iconeTabela,
                  )
                : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: CoresApp.destaque.withOpacity(0.09),
              borderRadius: BorderRadius.circular(
                TamanhosApp.raioBadge,
              ),
              border: Border.all(
                color: CoresApp.destaque.withOpacity(0.35),
                width: emAlerta ? 1.5 : TamanhosApp.espessuraBorda,
              ),
            ),
            child: Text(
              project.id,
              style: TextStyle(
                color: emAlerta
                    ? CoresApp.destaqueAmarelo
                    : CoresApp.textoPrincipal,
                fontSize: TamanhosApp.tabelaFonte,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({
    required String status,
    required ValueChanged<String?> onChanged,
  }) {
    final color = _getStageColor(status);

    final currentValue = widget.statusList.contains(status)
        ? status
        : widget.statusList.isNotEmpty
            ? widget.statusList.first
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBadge,
        ),
        border: Border.all(
          color: color.withOpacity(0.55),
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isDense: true,
          dropdownColor: CoresApp.superficie,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: color,
            size: TamanhosApp.iconeStatus,
          ),
          style: TextStyle(
            color: color,
            fontSize: TamanhosApp.tabelaFonteStatus,
            fontWeight: FontWeight.bold,
          ),
          onChanged: onChanged,
          items: widget.statusList.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: TamanhosApp.tabelaFonteStatus,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  InputDecoration _dialogInputDecoration({
    required String label,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: TamanhosApp.tabelaFonteSecundaria,
      ),
      prefixIcon: icon != null
          ? Icon(
              icon,
              color: CoresApp.destaque,
              size: TamanhosApp.iconeTabela,
            )
          : null,
      suffixIcon: suffix,
      filled: true,
      fillColor: CoresTelas.campoFormulario,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBotao,
        ),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBotao,
        ),
        borderSide: BorderSide(
          color: CoresApp.bordaSuave,
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBotao,
        ),
        borderSide: BorderSide(
          color: CoresApp.destaque,
          width: TamanhosApp.espessuraBorda,
        ),
      ),
    );
  }

  void _showCheckListDialog(ProjectModel project) {
    final newItemController = TextEditingController();
    final checklistScrollController = ScrollController();
    String? selectedFormatId;
    List<ChecklistFormat> availableFormats = [];
    bool isLoadingFormats = true;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isLoadingFormats) {
              widget.firebaseService.getChecklistFormats().then((formats) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    availableFormats = formats;
                    isLoadingFormats = false;
                  });
                }
              }).catchError((_) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    isLoadingFormats = false;
                  });
                }
              });
            }

            final checklistItems = project.checklist ?? [];
            final int totalItems = checklistItems.length;
            final int completedItems = checklistItems
                .where((item) => item['completed'] == true)
                .length;
            final double progressValue =
                totalItems > 0 ? completedItems / totalItems : 0.0;
            final int progressPercent = (progressValue * 100).round();

            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: CoresApp.borda),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.checklist_rounded,
                    color: CoresApp.destaque,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Check List - Projeto ${project.id}',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 550,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: isLoadingFormats
                              ? const Center(
                                  child: SizedBox(
                                    height: 25,
                                    width: 25,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : DropdownButtonFormField<String>(
                                  value: selectedFormatId,
                                  dropdownColor: CoresApp.superficie,
                                  decoration: _dialogInputDecoration(
                                    label: 'Importar Modelo de Checklist',
                                    icon: Icons.library_books_rounded,
                                  ),
                                  hint: Text(
                                    'Selecione um modelo...',
                                    style: TextStyle(
                                      color: CoresApp.textoSecundario,
                                      fontSize: 13,
                                    ),
                                  ),
                                  items: availableFormats.map((format) {
                                    final String formatId = format.id;
                                    final String formatName =
                                        format.name.trim().isNotEmpty
                                            ? format.name
                                            : 'Sem nome';

                                    return DropdownMenuItem<String>(
                                      value: formatId,
                                      child: Text(
                                        formatName,
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      selectedFormatId = value;
                                    });
                                  },
                                ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CoresApp.destaque,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          onPressed: selectedFormatId == null
                              ? null
                              : () async {
                                  ChecklistFormat? chosenFormat;

                                  for (final format in availableFormats) {
                                    if (format.id == selectedFormatId) {
                                      chosenFormat = format;
                                      break;
                                    }
                                  }

                                  if (chosenFormat != null) {
                                    project.checklist ??=
                                        <Map<String, dynamic>>[];

                                    for (final formatItem
                                        in chosenFormat.items) {
                                      final name = formatItem['name']
                                              ?.toString()
                                              .trim() ??
                                          '';

                                      if (name.isEmpty) continue;

                                      project.checklist!.add({
                                        'order':
                                            formatItem['order']?.toString() ??
                                                '',
                                        'name': name,
                                        'completed': false,
                                      });
                                    }

                                    try {
                                      await widget.firebaseService
                                          .salvarProjeto(project);

                                      widget.onEditProject(project);

                                      setDialogState(() {
                                        selectedFormatId = null;
                                      });

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Modelo importado com sucesso!',
                                            ),
                                            backgroundColor: CoresApp.sucesso,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Erro ao importar modelo: $e',
                                            ),
                                            backgroundColor: CoresApp.erro,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                          child: const Text(
                            'Aplicar',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newItemController,
                            style: TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 13,
                            ),
                            decoration: _dialogInputDecoration(
                              label: 'Nova tarefa manual',
                              icon: Icons.add_task_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CoresApp.destaque,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () async {
                            final text = newItemController.text.trim();

                            if (text.isNotEmpty) {
                              project.checklist ??= [];

                              final nextOrder =
                                  (project.checklist!.length + 1).toString();

                              project.checklist!.add({
                                'order': nextOrder,
                                'name': text,
                                'completed': false,
                              });

                              newItemController.clear();

                              try {
                                await widget.firebaseService
                                    .salvarProjeto(project);

                                widget.onEditProject(project);

                                setDialogState(() {});
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao salvar item: $e'),
                                      backgroundColor: CoresApp.erro,
                                    ),
                                  );
                                }
                              }
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
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: (project.checklist == null ||
                              project.checklist!.isEmpty)
                          ? Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Center(
                                child: Text(
                                  'Nenhum item cadastrado no checklist.',
                                  style: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : Scrollbar(
                              controller: checklistScrollController,
                              thumbVisibility: true,
                              child: ListView.separated(
                                controller: checklistScrollController,
                                shrinkWrap: true,
                                itemCount: project.checklist!.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = project.checklist![index];
                                  final bool isCompleted =
                                      item['completed'] == true;
                                  final String order =
                                      item['order']?.toString() ??
                                          '${index + 1}';
                                  final String name =
                                      item['name']?.toString() ?? '';

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '$order. $name',
                                      style: TextStyle(
                                        color: isCompleted
                                            ? CoresApp.textoSecundario
                                            : CoresApp.textoPrincipal,
                                        decoration: isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        fontSize: 13,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            color: CoresApp.erro,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            project.checklist!.removeAt(index);

                                            try {
                                              await widget.firebaseService
                                                  .salvarProjeto(project);

                                              widget.onEditProject(project);

                                              setDialogState(() {});
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Erro ao excluir item: $e',
                                                    ),
                                                    backgroundColor:
                                                        CoresApp.erro,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                        Checkbox(
                                          activeColor: CoresApp.destaque,
                                          checkColor: Colors.black,
                                          value: isCompleted,
                                          onChanged: (bool? value) async {
                                            setDialogState(() {
                                              item['completed'] =
                                                  value ?? false;
                                            });

                                            try {
                                              await widget.firebaseService
                                                  .salvarProjeto(project);

                                              widget.onEditProject(project);
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Erro ao atualizar checklist: $e',
                                                    ),
                                                    backgroundColor:
                                                        CoresApp.erro,
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
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progresso',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '$progressPercent%',
                                style: TextStyle(
                                  color: CoresApp.destaque,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progressValue,
                              backgroundColor: CoresApp.borda,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                CoresApp.destaque,
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CoresApp.destaque,
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text(
                        'Fechar',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      newItemController.dispose();
      checklistScrollController.dispose();
    });
  }

/////////////////////////////////////////////
  ///Abre o modal de editar
//////////////////////
  void _showLinksDialog(ProjectModel project) {
    final idController = TextEditingController(text: project.id);
    final clientController = TextEditingController(text: project.client);
    final folderController =
        TextEditingController(text: project.folderPath ?? '');
    final excelController =
        TextEditingController(text: project.excelLink ?? '');
    final leaderController = TextEditingController(text: project.leader);
    final serviceTypeController =
        TextEditingController(text: project.serviceType);
    final hourTypeController = TextEditingController(text: project.hourType);
    final observacaoController =
        TextEditingController(text: project.observacao ?? '');

    final linksScrollController = ScrollController();

    bool atualizandoFasesEdesk = false;

    // ============================================================
    // ETAPAS TEMPORÁRIAS
    // ============================================================

    List<TaskModel> tempSubTasks = project.subTasks != null
        ? project.subTasks!
            .map(
              (s) => TaskModel(
                subId: s.subId,
                stage: s.stage,
                status: s.status,
                startDate: s.startDate,
                planStart: s.planStart,
                planEnd: s.planEnd,
                estimatedHours: s.estimatedHours,
                hourType: _tiposHsOpcoes.contains(s.hourType)
                    ? s.hourType
                    : _tiposHsOpcoes.first,

                // ===================================================
                // E-DESK
                // ===================================================
                edeskUrl: s.edeskUrl,
                edeskIdTrabalho: s.edeskIdTrabalho,
              ),
            )
            .toList()
        : [];

    // ============================================================
    // HORAS
    // ============================================================

    final estimatedHoursController = TextEditingController();
    final List<TextEditingController> subHoursControllers = [];

    for (final s in tempSubTasks) {
      final ctrl = TextEditingController(
        text: s.estimatedHours,
      );

      ctrl.addListener(() {
        estimatedHoursController.text = _calculateTotalEstimatedHours(
          subHoursControllers,
        );
      });

      subHoursControllers.add(ctrl);
    }

    estimatedHoursController.text = project.estimatedHours.isNotEmpty
        ? project.estimatedHours
        : _calculateTotalEstimatedHours(
            subHoursControllers,
          );

    String selectedStatus = widget.statusList.contains(project.status)
        ? project.status
        : widget.statusList.isNotEmpty
            ? widget.statusList.first
            : '';

    // ============================================================
    // ABRIR MODAL
    // ============================================================

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // =============================================================
            // CARREGA AS CONFIGURAÇÕES DO FIREBASE AO ABRIR O MODAL
            // =============================================================
            //
            // As etiquetas padrão existem apenas como fallback para usuários
            // que ainda não possuem configuração salva.
            //
            // Se já existe configuração no Firebase, ela passa a ser a
            // fonte definitiva.
            // =============================================================

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 30,
                vertical: 25,
              ),
              child: Container(
                width: 950,
                constraints: const BoxConstraints(
                  maxHeight: 820,
                ),
                decoration: BoxDecoration(
                  color: CoresTelas.fundoModal,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: CoresApp.borda,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: CoresApp.overlay,
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // ==================================================
                    // CABEÇALHO
                    // ==================================================

                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        22,
                        18,
                        14,
                        18,
                      ),
                      decoration: BoxDecoration(
                        color: CoresTelas.fundoModalSecundario,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: CoresApp.destaque.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.edit_note_rounded,
                              color: CoresApp.destaque,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Atualize os dados e as etapas do projeto',
                                  style: TextStyle(
                                    color: CoresApp.textoSecundario,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fechar',
                            icon: Icon(
                              Icons.close_rounded,
                              color: CoresApp.textoSecundario,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),

                    // ==================================================
                    // CONTEÚDO
                    // ==================================================

                    Expanded(
                      child: Scrollbar(
                        controller: linksScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: linksScrollController,
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ========================================
                              // ID / STATUS
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: idController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'ID',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: InputDecorator(
                                      decoration: _dialogInputDecoration(
                                        label: 'Status',
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: selectedStatus.isNotEmpty
                                              ? selectedStatus
                                              : null,
                                          dropdownColor: CoresApp.superficie,
                                          isDense: true,
                                          isExpanded: true,
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 13,
                                          ),
                                          icon: Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: CoresApp.textoSecundario,
                                          ),
                                          items: widget.statusList.map((st) {
                                            return DropdownMenuItem<String>(
                                              value: st,
                                              child: Text(st),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            if (value != null) {
                                              setDialogState(
                                                () => selectedStatus = value,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // ========================================
                              // CLIENTE / SERVIÇO
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: clientController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Cliente',
                                        icon: Icons.business_rounded,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextField(
                                      controller: serviceTypeController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Tipo de Serviço',
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

// ========================================
// OBSERVAÇÃO
// ========================================

                              Align(
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 500,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: TextField(
                                      controller: observacaoController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 13,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Informações Úteis / Descritivo',
                                        icon: Icons.description_rounded,
                                      ),
                                      maxLines: 2,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // ========================================
                              // PASTA / ARQUIVO
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: folderController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Pasta de Documentos',
                                        icon: Icons.folder_rounded,
                                        suffix: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.create_new_folder_rounded,
                                                color: CoresApp.destaque,
                                                size: 19,
                                              ),
                                              tooltip: 'Criar Pasta do Projeto',
                                              onPressed: () async {
                                                try {
                                                  final pastaBase =
                                                      await FilePicker.platform
                                                          .getDirectoryPath(
                                                    dialogTitle:
                                                        'Escolha onde criar a pasta do projeto',
                                                  );

                                                  if (pastaBase == null) return;

                                                  final idProjeto =
                                                      idController.text.trim();
                                                  final cliente =
                                                      clientController.text
                                                          .trim();

                                                  if (idProjeto.isEmpty ||
                                                      cliente.isEmpty) {
                                                    if (dialogContext.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Informe o ID e o Cliente antes de criar a pasta.',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  String limparNomePasta(
                                                    String valor,
                                                  ) {
                                                    return valor
                                                        .replaceAll(
                                                          RegExp(
                                                              r'[<>:"/\\|?*]'),
                                                          '-',
                                                        )
                                                        .replaceAll(
                                                          RegExp(r'\s+'),
                                                          ' ',
                                                        )
                                                        .trim();
                                                  }

                                                  final nomePasta =
                                                      limparNomePasta(
                                                    '$idProjeto - $cliente',
                                                  );
                                                  final separador =
                                                      Platform.pathSeparator;
                                                  final caminhoPasta =
                                                      '$pastaBase$separador$nomePasta';

                                                  final pastaProjeto =
                                                      Directory(caminhoPasta);
                                                  if (!await pastaProjeto
                                                      .exists()) {
                                                    await pastaProjeto.create(
                                                      recursive: true,
                                                    );
                                                  }

                                                  if (!dialogContext.mounted)
                                                    return;
                                                  setDialogState(() {
                                                    folderController.text =
                                                        caminhoPasta;
                                                  });
                                                } catch (e) {
                                                  debugPrint(
                                                    'Erro ao criar pasta do projeto: $e',
                                                  );
                                                  if (dialogContext.mounted) {
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Não foi possível criar a pasta: $e',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.search_rounded,
                                                color: CoresApp.destaque,
                                                size: 18,
                                              ),
                                              tooltip: 'Selecionar Pasta',
                                              onPressed: () async {
                                                try {
                                                  final selectedDirectory =
                                                      await FilePicker.platform
                                                          .getDirectoryPath(
                                                    dialogTitle:
                                                        'Selecione a Pasta do Projeto',
                                                  );

                                                  if (selectedDirectory !=
                                                          null &&
                                                      dialogContext.mounted) {
                                                    setDialogState(() {
                                                      folderController.text =
                                                          selectedDirectory;
                                                    });
                                                  }
                                                } catch (e) {
                                                  debugPrint(
                                                    'Erro ao abrir seletor de pastas: $e',
                                                  );
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: excelController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Arquivo / Link',
                                        icon: Icons.insert_drive_file_rounded,
                                        suffix: IconButton(
                                          icon: Icon(
                                            Icons.attach_file_rounded,
                                            color: CoresApp.destaque,
                                            size: 18,
                                          ),
                                          tooltip: 'Selecionar Arquivo',
                                          onPressed: () async {
                                            final result = await FilePicker
                                                .platform
                                                .pickFiles(
                                              type: FileType.custom,
                                              allowedExtensions: [
                                                'xlsx',
                                                'xls',
                                                'xlsm',
                                                'csv',
                                                'doc',
                                                'docx',
                                                'pdf',
                                                'txt',
                                              ],
                                            );

                                            if (result != null &&
                                                result.files.single.path !=
                                                    null) {
                                              setDialogState(() {
                                                excelController.text =
                                                    result.files.single.path!;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),

// ========================================
// TÍTULO ETAPAS + AÇÕES
// ========================================

                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Trabalhos Internos do Serviço',
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Atualize as datas, nomes, horas e o tipo de hora de cada etapa.',
                                          style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  // ======================================
// ATUALIZAR FASES E-DESK
// ======================================

                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: atualizandoFasesEdesk
                                          ? Colors.blue.withOpacity(0.08)
                                          : Colors.blue.withOpacity(0.12),
                                      foregroundColor: Colors.blueAccent,
                                      disabledForegroundColor:
                                          Colors.blueAccent.withOpacity(0.75),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: Colors.blueAccent.withOpacity(
                                            atualizandoFasesEdesk ? 0.25 : 0.45,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // ============================================================
                                    // BOTÃO DESABILITADO ENQUANTO A AUTOMAÇÃO ESTÁ EXECUTANDO
                                    // ============================================================

                                    onPressed: atualizandoFasesEdesk
                                        ? null
                                        : () async {
                                            // ============================================
                                            // VALIDAÇÕES
                                            // ============================================

                                            final id = idController.text.trim();
                                            final cliente =
                                                clientController.text.trim();

                                            if (id.isEmpty) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'Informe o ID da solicitação antes de atualizar o E-Desk.',
                                                  ),
                                                  backgroundColor:
                                                      CoresApp.erro,
                                                ),
                                              );
                                              return;
                                            }

                                            if (cliente.isEmpty) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'Informe o cliente antes de atualizar o E-Desk.',
                                                  ),
                                                  backgroundColor:
                                                      CoresApp.erro,
                                                ),
                                              );
                                              return;
                                            }

                                            if (tempSubTasks.isEmpty) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'Este projeto não possui etapas para enviar ao E-Desk.',
                                                  ),
                                                  backgroundColor:
                                                      CoresApp.erro,
                                                ),
                                              );
                                              return;
                                            }

                                            // ============================================
                                            // MONTA AS FASES
                                            // ============================================

                                            final List<Map<String, String>>
                                                fases = [];

                                            for (final sub in tempSubTasks) {
                                              final nome = sub.stage.trim();

                                              if (nome.isEmpty) {
                                                continue;
                                              }

                                              fases.add({
                                                'nome': nome,
                                                'dataInicial': _formatDate(
                                                  sub.startDate,
                                                ),
                                                'dataFinal': sub.planEnd != null
                                                    ? _formatDate(
                                                        sub.planEnd!,
                                                      )
                                                    : '',
                                              });
                                            }

                                            if (fases.isEmpty) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'Nenhuma fase válida foi encontrada.',
                                                  ),
                                                  backgroundColor:
                                                      CoresApp.erro,
                                                ),
                                              );
                                              return;
                                            }

                                            // ============================================
                                            // LOG
                                            // ============================================

                                            debugPrint('');
                                            debugPrint(
                                              '========== ATUALIZAÇÃO FASES E-DESK ==========',
                                            );
                                            debugPrint(
                                              '[E-DESK] Solicitação: $id',
                                            );
                                            debugPrint(
                                              '[E-DESK] Cliente: $cliente',
                                            );
                                            debugPrint(
                                              '[E-DESK] Quantidade de fases: ${fases.length}',
                                            );

                                            for (final fase in fases) {
                                              debugPrint(
                                                '[E-DESK] '
                                                '${fase['nome']} | '
                                                'Inicial=${fase['dataInicial']} | '
                                                'Final=${fase['dataFinal']}',
                                              );
                                            }

                                            debugPrint(
                                              '================================================',
                                            );

                                            // ============================================
                                            // MOSTRA O SPINNER IMEDIATAMENTE
                                            // ============================================

                                            setDialogState(() {
                                              atualizandoFasesEdesk = true;
                                            });

                                            try {
                                              final resultado =
                                                  await EdeskService()
                                                      .atualizarFasesViaPython(
                                                id: id,
                                                cliente: cliente,
                                                fases: fases,

                                                // ==================================================
                                                // QUANDO O PYTHON REALMENTE TERMINAR
                                                // ==================================================

                                                onConcluido:
                                                    (sucesso, mensagem) {
                                                  if (!dialogContext.mounted) {
                                                    return;
                                                  }

                                                  setDialogState(() {
                                                    atualizandoFasesEdesk =
                                                        false;
                                                  });

                                                  ScaffoldMessenger.of(
                                                          dialogContext)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        mensagem,
                                                      ),
                                                      backgroundColor: sucesso
                                                          ? CoresApp.sucesso
                                                          : CoresApp.erro,
                                                      duration: const Duration(
                                                        seconds: 5,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );

                                              debugPrint(
                                                '[E-DESK] Resultado inicial: '
                                                'confirmed=${resultado.confirmed} | '
                                                'status=${resultado.statusCode} | '
                                                'message=${resultado.message}',
                                              );

                                              // ==================================================
                                              // ERRO AO INICIAR O PROCESSO
                                              //
                                              // Se o Python nem chegou a iniciar, o callback acima
                                              // não será chamado.
                                              // ==================================================

                                              if (!resultado.confirmed) {
                                                if (!dialogContext.mounted) {
                                                  return;
                                                }

                                                setDialogState(() {
                                                  atualizandoFasesEdesk = false;
                                                });

                                                ScaffoldMessenger.of(
                                                        dialogContext)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      resultado.message,
                                                    ),
                                                    backgroundColor:
                                                        CoresApp.erro,
                                                    duration: const Duration(
                                                      seconds: 5,
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              debugPrint(
                                                '[E-DESK] Erro ao atualizar fases: $e',
                                              );

                                              if (!dialogContext.mounted) {
                                                return;
                                              }

                                              setDialogState(() {
                                                atualizandoFasesEdesk = false;
                                              });

                                              ScaffoldMessenger.of(
                                                      dialogContext)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Erro ao atualizar fases no E-Desk: $e',
                                                  ),
                                                  backgroundColor:
                                                      CoresApp.erro,
                                                  duration: const Duration(
                                                    seconds: 5,
                                                  ),
                                                ),
                                              );
                                            }
                                          },

                                    // ============================================================
                                    // ÍCONE
                                    // ============================================================

                                    icon: atualizandoFasesEdesk
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.blueAccent,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.sync_rounded,
                                            size: 18,
                                          ),

                                    // ============================================================
                                    // TEXTO
                                    // ============================================================

                                    label: Text(
                                      atualizandoFasesEdesk
                                          ? 'Atualizando...'
                                          : 'Atualizar Fases E-Desk',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // ======================================
                                  // NOVA ETAPA
                                  // ======================================

                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          CoresApp.destaque.withOpacity(0.15),
                                      foregroundColor: CoresApp.destaque,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(
                                          color: CoresApp.destaque
                                              .withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.playlist_add_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Adicionar Nova Etapa',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: () {
                                      int maiorId = 0;

                                      for (final etapa in tempSubTasks) {
                                        final id = int.tryParse(
                                              etapa.subId.toString(),
                                            ) ??
                                            0;

                                        if (id > maiorId) {
                                          maiorId = id;
                                        }
                                      }

                                      final agora = DateTime.now();

                                      final novaEtapa = TaskModel(
                                        subId: '${maiorId + 1}',
                                        stage: 'Nova Etapa',
                                        status: 'INI_PRO',
                                        startDate: agora,
                                        planStart: agora,
                                        planEnd: agora,
                                        estimatedHours: '00:00',
                                        hourType: _tiposHsOpcoes.first,

                                        // E-DESK
                                        edeskUrl: null,
                                        edeskIdTrabalho: null,
                                      );

                                      final ctrl = TextEditingController(
                                        text: '00:00',
                                      );

                                      ctrl.addListener(() {
                                        estimatedHoursController.text =
                                            _calculateTotalEstimatedHours(
                                          subHoursControllers,
                                        );
                                      });

                                      setDialogState(() {
                                        tempSubTasks.add(
                                          novaEtapa,
                                        );

                                        subHoursControllers.add(
                                          ctrl,
                                        );

                                        estimatedHoursController.text =
                                            _calculateTotalEstimatedHours(
                                          subHoursControllers,
                                        );
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // ========================================
                              // LISTA DE ETAPAS
                              // ========================================

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: CoresTelas.fundoModalSecundario,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: CoresApp.bordaSuave,
                                  ),
                                ),
                                child: tempSubTasks.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Center(
                                          child: Text(
                                            'Este projeto não possui etapas cadastradas.',
                                            style: TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                    : ListView.separated(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: tempSubTasks.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(
                                          height: 10,
                                        ),
                                        itemBuilder: (context, index) {
                                          final sub = tempSubTasks[index];

                                          return Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: CoresTelas.campoFormulario,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: CoresApp.bordaSuave,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 60,
                                                  child: TextFormField(
                                                    initialValue: sub.subId,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter
                                                          .digitsOnly,
                                                    ],
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: CoresApp.destaque,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Nº',
                                                    ),
                                                    onChanged: (value) {
                                                      sub.subId = value.trim();
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  flex: 4,
                                                  child: TextFormField(
                                                    initialValue: sub.stage,
                                                    style: TextStyle(
                                                      color: CoresApp
                                                          .textoPrincipal,
                                                      fontSize: 12,
                                                    ),
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Nome da Etapa',
                                                    ),
                                                    onChanged: (val) {
                                                      sub.stage = val;
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                // DATA INÍCIO
                                                Expanded(
                                                  flex: 3,
                                                  child: InkWell(
                                                    onTap: () async {
                                                      final picked =
                                                          await showDatePicker(
                                                        context: context,
                                                        initialDate:
                                                            sub.startDate,
                                                        firstDate:
                                                            DateTime(2020),
                                                        lastDate:
                                                            DateTime(2030),
                                                        locale: const Locale(
                                                          'pt',
                                                          'BR',
                                                        ),
                                                        builder: (
                                                          BuildContext context,
                                                          Widget? child,
                                                        ) {
                                                          return Theme(
                                                            data:
                                                                ThemeData.dark()
                                                                    .copyWith(
                                                              colorScheme:
                                                                  ColorScheme
                                                                      .dark(
                                                                primary: CoresApp
                                                                    .destaque,
                                                                onPrimary:
                                                                    Colors
                                                                        .black,
                                                                surface: CoresTelas
                                                                    .fundoModal,
                                                                onSurface: CoresApp
                                                                    .textoPrincipal,
                                                              ),
                                                              dialogBackgroundColor:
                                                                  CoresTelas
                                                                      .fundoModal,
                                                            ),
                                                            child: Localizations
                                                                .override(
                                                              context: context,
                                                              locale:
                                                                  const Locale(
                                                                'pt',
                                                                'BR',
                                                              ),
                                                              child: child!,
                                                            ),
                                                          );
                                                        },
                                                      );

                                                      if (picked != null) {
                                                        setDialogState(
                                                          () {
                                                            sub.startDate =
                                                                picked;
                                                            sub.planStart =
                                                                picked;
                                                          },
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: CoresTelas
                                                            .fundoModalSecundario,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: CoresApp
                                                              .bordaSuave,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Text(
                                                            'Início: ${_formatDate(sub.startDate)}',
                                                            style: TextStyle(
                                                              color: CoresApp
                                                                  .textoPrincipal,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .calendar_today_rounded,
                                                            size: 14,
                                                            color: CoresApp
                                                                .destaque,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // DATA FINAL
                                                Expanded(
                                                  flex: 3,
                                                  child: InkWell(
                                                    onTap: () async {
                                                      final picked =
                                                          await showDatePicker(
                                                        context: context,
                                                        initialDate:
                                                            sub.planEnd ??
                                                                sub.startDate,
                                                        firstDate:
                                                            DateTime(2020),
                                                        lastDate:
                                                            DateTime(2030),
                                                        locale: const Locale(
                                                          'pt',
                                                          'BR',
                                                        ),
                                                        builder: (
                                                          BuildContext context,
                                                          Widget? child,
                                                        ) {
                                                          return Theme(
                                                            data:
                                                                ThemeData.dark()
                                                                    .copyWith(
                                                              colorScheme:
                                                                  ColorScheme
                                                                      .dark(
                                                                primary: CoresApp
                                                                    .destaque,
                                                                onPrimary:
                                                                    Colors
                                                                        .black,
                                                                surface: CoresTelas
                                                                    .fundoModal,
                                                                onSurface: CoresApp
                                                                    .textoPrincipal,
                                                              ),
                                                              dialogBackgroundColor:
                                                                  CoresTelas
                                                                      .fundoModal,
                                                            ),
                                                            child: Localizations
                                                                .override(
                                                              context: context,
                                                              locale:
                                                                  const Locale(
                                                                'pt',
                                                                'BR',
                                                              ),
                                                              child: child!,
                                                            ),
                                                          );
                                                        },
                                                      );

                                                      if (picked != null) {
                                                        setDialogState(
                                                          () {
                                                            sub.planEnd =
                                                                picked;
                                                          },
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: CoresTelas
                                                            .fundoModalSecundario,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: CoresApp
                                                              .bordaSuave,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Text(
                                                            'Fim: ${sub.planEnd != null ? _formatDate(sub.planEnd!) : '-'}',
                                                            style: TextStyle(
                                                              color: CoresApp
                                                                  .textoPrincipal,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                          Icon(
                                                            Icons
                                                                .calendar_today_rounded,
                                                            size: 14,
                                                            color: CoresApp
                                                                .destaque,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // HORAS
                                                Expanded(
                                                  flex: 2,
                                                  child: TextField(
                                                    controller:
                                                        subHoursControllers[
                                                            index],
                                                    keyboardType:
                                                        TextInputType.text,
                                                    inputFormatters: [
                                                      HoraInputFormatter(),
                                                    ],
                                                    style: TextStyle(
                                                      color: CoresApp
                                                          .textoPrincipal,
                                                      fontSize: 12,
                                                    ),
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Horas',
                                                    ),
                                                    onChanged: (_) {
                                                      setDialogState(() {});
                                                    },
                                                  ),
                                                ),

                                                const SizedBox(width: 8),

                                                // TIPO HORAS
                                                Expanded(
                                                  flex: 3,
                                                  child: InputDecorator(
                                                    decoration:
                                                        _dialogInputDecoration(
                                                      label: 'Tipo de Horas',
                                                    ),
                                                    child:
                                                        DropdownButtonHideUnderline(
                                                      child: DropdownButton<
                                                          String>(
                                                        value: _tiposHsOpcoes
                                                                .contains(
                                                          sub.hourType,
                                                        )
                                                            ? sub.hourType
                                                            : _tiposHsOpcoes
                                                                .first,
                                                        dropdownColor:
                                                            CoresApp.superficie,
                                                        isDense: true,
                                                        isExpanded: true,
                                                        style: TextStyle(
                                                          color: CoresApp
                                                              .textoPrincipal,
                                                          fontSize: 11,
                                                        ),
                                                        icon: Icon(
                                                          Icons
                                                              .keyboard_arrow_down_rounded,
                                                          color: CoresApp
                                                              .textoSecundario,
                                                          size: 16,
                                                        ),
                                                        items:
                                                            _tiposHsOpcoes.map(
                                                          (tipo) {
                                                            return DropdownMenuItem<
                                                                String>(
                                                              value: tipo,
                                                              child: Text(
                                                                tipo,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            );
                                                          },
                                                        ).toList(),
                                                        onChanged: (newValue) {
                                                          if (newValue !=
                                                              null) {
                                                            setDialogState(
                                                              () {
                                                                sub.hourType =
                                                                    newValue;
                                                              },
                                                            );
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),

                              const SizedBox(height: 15),

                              // ========================================
                              // HORAS GERAIS
                              // ========================================

                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: estimatedHoursController,
                                      readOnly: true,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Hs Estimadas (Calc.)',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: hourTypeController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Tipo de Horas Geral',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: leaderController,
                                      style: TextStyle(
                                        color: CoresApp.textoPrincipal,
                                        fontSize: 12,
                                      ),
                                      decoration: _dialogInputDecoration(
                                        label: 'Líder Prj',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ==================================================
                    // RODAPÉ
                    // ==================================================

                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        22,
                        13,
                        22,
                        13,
                      ),
                      decoration: BoxDecoration(
                        color: CoresTelas.fundoModalSecundario,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(18),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: CoresApp.bordaSuave,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
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
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CoresApp.destaque,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  TamanhosApp.raioBotao,
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.save_rounded,
                              size: 17,
                            ),
                            label: const Text(
                              'Salvar alterações',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: () async {
                              // ======================================
                              // ATUALIZA HORAS DAS ETAPAS
                              // ======================================

                              for (int i = 0; i < tempSubTasks.length; i++) {
                                tempSubTasks[i].estimatedHours =
                                    subHoursControllers[i].text.trim();
                              }

                              // ======================================
                              // ATUALIZA PROJETO
                              // ======================================

                              project.id = idController.text.trim();

                              project.client = clientController.text.trim();

                              project.status = selectedStatus;

                              project.serviceType =
                                  serviceTypeController.text.trim();

                              project.subTasks = tempSubTasks;

                              project.estimatedHours =
                                  estimatedHoursController.text.trim();

                              project.observacao =
                                  observacaoController.text.trim();

                              if (tempSubTasks.isNotEmpty) {
                                project.startDate =
                                    tempSubTasks.first.startDate;
                              }

                              project.folderPath =
                                  folderController.text.trim().isEmpty
                                      ? null
                                      : folderController.text.trim();

                              project.excelLink =
                                  excelController.text.trim().isEmpty
                                      ? null
                                      : excelController.text.trim();

                              project.leader = leaderController.text.trim();

                              project.hourType = hourTypeController.text.trim();

                              // ======================================
                              // SALVA
                              // ======================================

                              try {
                                await widget.firebaseService
                                    .salvarProjeto(project);

                                widget.onEditProject(
                                  project,
                                );

                                if (mounted) {
                                  setState(() {});
                                }

                                if (dialogContext.mounted) {
                                  Navigator.of(
                                    dialogContext,
                                  ).pop();
                                }

                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        'Trabalho salvo com sucesso no banco de dados!',
                                      ),
                                      backgroundColor: CoresApp.sucesso,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Erro ao salvar no Firebase: $e',
                                      ),
                                      backgroundColor: CoresApp.erro,
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      linksScrollController.dispose();
      idController.dispose();
      clientController.dispose();
      folderController.dispose();
      excelController.dispose();
      leaderController.dispose();
      serviceTypeController.dispose();
      hourTypeController.dispose();
      observacaoController.dispose();
      estimatedHoursController.dispose();

      for (final controller in subHoursControllers) {
        controller.dispose();
      }
    });
  }

  double checklistProgress(
    List<Map<String, dynamic>> checklist,
  ) {
    if (checklist.isEmpty) return 0;

    final completed =
        checklist.where((item) => item['completed'] == true).length;

    return completed / checklist.length;
  }

  List<DataRow> _generateRows(
    List<ProjectModel> projects,
  ) {
    final List<DataRow> rows = [];

    final now = DateTime.now();

    final todayFormatted = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year.toString().substring(2)}';

    final listaAlertasNormalizada = widget.idsEmAlerta
        .map(
          (id) => id.toString().trim(),
        )
        .toList();

    for (final project in projects) {
      final isExpanded = widget.expandedProjectIds.contains(project.id);
      final isRowSelected = widget.selectedTargetId == project.id;

      final bool emAlerta =
          listaAlertasNormalizada.contains(project.id.toString().trim()) ||
              _projectHasDeadlineAlert(project);
      final bool dataVencida = _projectIsOverdue(project);

      final hasSubtasks = project.subTasks?.isNotEmpty ?? false;
      final startFormatted = _formatDate(project.startDate);

      final endFormatted = hasSubtasks && project.subTasks!.isNotEmpty
          ? project.subTasks!
                      .where(
                        (task) => task.planEnd != null,
                      )
                      .map(
                        (task) => task.planEnd!,
                      )
                      .fold<DateTime?>(
                    null,
                    (latest, date) {
                      if (latest == null || date.isAfter(latest)) {
                        return date;
                      }

                      return latest;
                    },
                  ) !=
                  null
              ? _formatDate(
                  project.subTasks!
                      .where(
                        (task) => task.planEnd != null,
                      )
                      .map(
                        (task) => task.planEnd!,
                      )
                      .reduce(
                        (a, b) => a.isAfter(b) ? a : b,
                      ),
                )
              : startFormatted
          : startFormatted;

      rows.add(
        DataRow(
          selected: isRowSelected,
          onSelectChanged: (_) => widget.onSelectTarget(project.id),
          color: WidgetStateProperty.resolveWith<Color?>(
            (states) {
              if (states.contains(WidgetState.hovered)) {
                return CoresDashboard.tabelaHover1;
              }

              if (isRowSelected) {
                return CoresDashboard.tabelaLinhaSelecionada;
              }

              if (isExpanded) {
                return CoresDashboard.tabelaLinhaExpandida;
              }

              return null;
            },
          ),
          cells: [
            DataCell(
              _buildProjectIdBadge(
                project,
                hasSubtasks,
                isExpanded,
                emAlerta,
              ),
            ),
            DataCell(
              _buildCellText(
                project.id2,
                color: CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              _buildCellText(
                project.client,
                color: emAlerta
                    ? CoresApp.destaqueAmarelo
                    : CoresApp.textoPrincipal,
                fontWeight: FontWeight.w700,
              ),
            ),
            DataCell(
              _buildCellText(
                project.serviceType,
                color: emAlerta ? Colors.white70 : CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              SizedBox(
                width: 150,
                height: 30,
                child: TextField(
                  controller: _getInlineController(project),
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: TamanhosApp.tabelaFonte,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Info útil...',
                    hintStyle: TextStyle(
                      color: CoresApp.textoSecundario.withOpacity(0.5),
                      fontSize: 11,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    filled: true,
                    fillColor: CoresTelas.campoFormulario.withOpacity(0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: CoresApp.bordaSuave,
                        width: TamanhosApp.espessuraBorda,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: CoresApp.bordaSuave,
                        width: TamanhosApp.espessuraBorda,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                        color: CoresApp.destaque,
                        width: TamanhosApp.espessuraBorda,
                      ),
                    ),
                  ),
                  onSubmitted: (value) async {
                    project.observacao = value.trim();

                    try {
                      await widget.firebaseService.salvarProjeto(project);

                      widget.onEditProject(project);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Informação salva com sucesso!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao salvar: $e'),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            DataCell(
              _buildStatusBadge(
                status: project.status,
                onChanged: (newStatus) async {
                  if (newStatus != null) {
                    project.status = newStatus;

                    try {
                      await widget.firebaseService.salvarProjeto(project);

                      widget.onProjectStatusChanged(
                        project,
                        newStatus,
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
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
              ),
            ),
            DataCell(
              _buildDeadlineDateText(
                '$startFormatted - $endFormatted',
                overdue: dataVencida,
                normalColor: emAlerta
                    ? CoresApp.destaqueAmarelo
                    : CoresApp.textoSecundario,
                fontWeight: emAlerta ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            DataCell(
              _buildCellText(
                project.estimatedHours,
                color: emAlerta
                    ? CoresApp.destaqueAmarelo
                    : CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              _buildCellText(
                project.leader,
                color: emAlerta ? Colors.white70 : CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              _buildCellText(
                project.hourType,
                color: emAlerta ? Colors.white70 : CoresApp.textoSecundario,
              ),
            ),
            DataCell(
              _buildProjectActionControls(
                project: project,
                onDelete: () => widget.onDeleteProject(project),
                onAddSubTask: () => widget.onAddSubTask(project),
              ),
            ),
          ],
        ),
      );

      if (isExpanded && project.subTasks != null) {
        for (final sub in project.subTasks!) {
          final subTargetId = '${project.id}_${sub.subId}';
          final isSubTargetActive = widget.activeTimerTargetId == subTargetId;
          final isSubRowSelected = widget.selectedTargetId == subTargetId;

          final subStartFormatted = _formatDate(sub.startDate);
          final subEndFormatted = sub.planEnd != null
              ? _formatDate(sub.planEnd!)
              : subStartFormatted;
          final bool subDataVencida = _taskIsOverdue(sub);

          rows.add(
            DataRow(
              selected: isSubRowSelected || isSubTargetActive,
              onSelectChanged: (_) => widget.onSelectTarget(
                subTargetId,
              ),
              color: WidgetStateProperty.resolveWith<Color?>(
                (states) {
                  if (isSubTargetActive) {
                    return CoresDashboard.tabelaLinhaExecucao;
                  }

                  if (isSubRowSelected) {
                    return CoresDashboard.tabelaLinhaSelecionada;
                  }

                  return CoresDashboard.tabelaLinhaEtapa;
                },
              ),
              cells: [
                const DataCell(
                  SizedBox(width: 24),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.textoPrincipal.withOpacity(0.035),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      sub.subId,
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: TamanhosApp.tabelaFonteSecundaria,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                    ),
                    child: _buildCellText(
                      project.client,
                      color: CoresApp.textoSecundario.withOpacity(0.65),
                    ),
                  ),
                ),
                DataCell(
                  _buildCellText(
                    project.serviceType,
                    color: CoresApp.textoSecundario.withOpacity(0.65),
                  ),
                ),
                const DataCell(
                  SizedBox.shrink(),
                ),
                DataCell(
                  _buildCellText(
                    sub.stage,
                    color: _getStageColor(sub.status),
                    fontWeight: sub.status != 'TRAB_FIM'
                        ? FontWeight.w700
                        : FontWeight.normal,
                  ),
                ),
                DataCell(
                  _buildStatusBadge(
                    status: sub.status,
                    onChanged: (newStatus) async {
                      if (newStatus != null) {
                        sub.status = newStatus;

                        try {
                          await widget.firebaseService.salvarProjeto(project);

                          widget.onSubTaskStatusChanged(
                            sub,
                            newStatus,
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Erro ao atualizar status da etapa: $e',
                              ),
                              backgroundColor: CoresApp.erro,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                DataCell(
                  _buildDeadlineDateText(
                    '$subStartFormatted - $subEndFormatted',
                    overdue: subDataVencida,
                    normalColor: CoresApp.textoSecundario,
                  ),
                ),
                DataCell(
                  _buildCellText(
                    sub.estimatedHours,
                    color: CoresApp.textoSecundario,
                  ),
                ),
                DataCell(
                  _buildCellText(
                    sub.hourType,
                    color: CoresApp.textoSecundario,
                  ),
                ),
                DataCell(
                  _buildSubTaskActionControls(
                    project: project,
                    task: sub,
                    targetId: subTargetId,
                    title: 'Etapa ${sub.subId} - ${sub.stage}',
                  ),
                ),
              ],
            ),
          );

          if (isSubTargetActive) {
            final startTimeFormatted = widget.activeStartTime != null
                ? '${widget.activeStartTime!.hour.toString().padLeft(2, '0')}:'
                    '${widget.activeStartTime!.minute.toString().padLeft(2, '0')}'
                : '';

            rows.add(
              _buildActiveRecordRow(
                project: project,
                task: sub,
                id: project.id,
                id2: sub.subId,
                client: project.client,
                serviceType: project.serviceType,
                todayFormatted: todayFormatted,
                startTimeFormatted: startTimeFormatted,
                durationFormatted: widget.formatDuration(
                  widget.secondsElapsed,
                ),
                targetId: subTargetId,
                title: 'Etapa ${sub.subId} - ${sub.stage}',
              ),
            );
          }

          final completedLogsSub = _localTimeLogs
              .where(
                (l) => l.targetId == subTargetId,
              )
              .toList();

          for (final log in completedLogsSub) {
            if (log.isRegistered) continue;

            rows.add(
              _buildSavedRecordRow(
                project: project,
                id: project.id,
                id2: sub.subId,
                client: project.client,
                serviceType: project.serviceType,
                log: log,
                estimatedHours: sub.estimatedHours,
                hourType: sub.hourType,
                targetId: subTargetId,
              ),
            );
          }
        }
      }
    }

    return rows;
  }

  DataRow _buildActiveRecordRow({
    required ProjectModel project,
    required TaskModel task,
    required String id,
    required String id2,
    required String client,
    required String serviceType,
    required String todayFormatted,
    required String startTimeFormatted,
    required String durationFormatted,
    required String targetId,
    required String title,
  }) {
    final activeColor = CoresDashboard.tabelaLinhaExecucao;

    return DataRow(
      color: WidgetStateProperty.all(activeColor),
      cells: [
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: CoresApp.destaque.withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: CoresApp.destaque.withOpacity(0.65),
              ),
            ),
            child: Text(
              id,
              style: TextStyle(
                color: CoresApp.destaque,
                fontSize: TamanhosApp.tabelaFonteSecundaria,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            id2,
            style: TextStyle(
              color: CoresApp.destaque,
              fontSize: TamanhosApp.tabelaFonteSecundaria,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(
          _buildCellText(
            client,
            color: CoresApp.textoPrincipal,
          ),
        ),
        DataCell(
          _buildCellText(
            serviceType,
            color: CoresApp.textoPrincipal,
          ),
        ),
        const DataCell(
          SizedBox.shrink(),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: CoresApp.destaque,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const Text(
              'EA',
              style: TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        DataCell(
          Tooltip(
            message: 'Início: $startTimeFormatted | Tempo: $durationFormatted',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: CoresApp.aviso,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'EM EXECUÇÃO  $startTimeFormatted | $durationFormatted',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            '-',
            style: TextStyle(
              color: CoresApp.textoFraco,
            ),
          ),
        ),
        DataCell(
          Text(
            '-',
            style: TextStyle(
              color: CoresApp.textoFraco,
            ),
          ),
        ),
        DataCell(
          _buildCellText(
            '-',
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.timerState == TimerState.running) ...[
                _buildActionIconButton(
                  icon: Icons.pause_circle_filled_rounded,
                  color: CoresApp.destaqueAmarelo,
                  tooltip: 'Pausar',
                  onPressed: widget.onPauseTimer,
                ),
                _buildActionIconButton(
                  icon: Icons.stop_circle_rounded,
                  color: CoresApp.erro,
                  tooltip: 'Stop',
                  onPressed: widget.onStopTimer,
                ),
              ] else if (widget.timerState == TimerState.paused) ...[
                _buildActionIconButton(
                  icon: Icons.play_circle_fill_rounded,
                  color: CoresDashboard.statusTrabalhando,
                  tooltip: 'Retomar',
                  onPressed: () => widget.onStartTimer(
                    targetId,
                  ),
                ),
                _buildActionIconButton(
                  icon: Icons.stop_circle_rounded,
                  color: CoresApp.erro,
                  tooltip: 'Stop',
                  onPressed: widget.onStopTimer,
                ),
              ],
              _buildActionIconButton(
                icon: Icons.more_time_rounded,
                color: CoresApp.destaque,
                tooltip: 'Adicionar Horas Manualmente',
                onPressed: () => widget.onManualTime(
                  title,
                ),
              ),
              _buildActionIconButton(
                icon: Icons.delete_outline_rounded,
                color: CoresApp.erro,
                tooltip: 'Descartar Execução Atual',
                onPressed: () {
                  widget.onStopTimer();
                  setState(() {});
                },
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(
                  Icons.task_alt_rounded,
                  color: CoresApp.destaque,
                  size: TamanhosApp.iconeAcao,
                ),
                tooltip: 'Marcar Etapa como Realizada',
                onPressed: () async {
                  task.status = 'TRAB';

                  try {
                    await widget.firebaseService.salvarProjeto(project);

                    widget.onMarkTaskCompleted(
                      task,
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Etapa ${task.subId} marcada como realizada e salva!',
                          ),
                          backgroundColor: CoresApp.sucesso,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Erro ao salvar no Firebase: $e',
                          ),
                          backgroundColor: CoresApp.erro,
                        ),
                      );
                    }
                  }
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.playlist_add_check_rounded,
                  color: CoresDashboard.statusTrabalhando,
                  size: 21,
                ),
                tooltip: 'Adicionar e Salvar Tempo',
                onPressed: widget.onStopTimer,
              ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _buildSavedRecordRow({
    required ProjectModel project,
    required String id,
    required String id2,
    required String client,
    required String serviceType,
    required TimeLog log,
    required String estimatedHours,
    required String hourType,
    required String targetId,
  }) {
    final dateFormatted = _formatDate(log.date);
    final bool showCadastrarHere = !log.isRegistered;

    return DataRow(
      color: WidgetStateProperty.all(
        CoresDashboard.tabelaLinhaRegistrada,
      ),
      cells: [
        DataCell(
          _buildCellText(
            id,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            id2,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            client,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            serviceType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          SizedBox(
            width: 150,
            height: 30,
            child: TextField(
              controller: _getLogCommentController(
                log,
              ),
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: TamanhosApp.tabelaFonte,
              ),
              decoration: InputDecoration(
                hintText: 'Comentário do registro...',
                hintStyle: TextStyle(
                  color: CoresApp.textoSecundario.withOpacity(0.5),
                  fontSize: 11,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                filled: true,
                fillColor: CoresTelas.campoFormulario.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: CoresApp.bordaSuave,
                    width: TamanhosApp.espessuraBorda,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: CoresApp.bordaSuave,
                    width: TamanhosApp.espessuraBorda,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: CoresApp.destaque,
                    width: TamanhosApp.espessuraBorda,
                  ),
                ),
              ),
              onSubmitted: (value) async {
                log.description = value.trim();

                try {
                  await widget.firebaseService.salvarProjeto(project);

                  widget.onEditLog(log);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Comentário do registro salvo com sucesso!',
                      ),
                      backgroundColor: CoresApp.sucesso,
                      duration: const Duration(
                        seconds: 1,
                      ),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Erro ao salvar comentário: $e',
                      ),
                      backgroundColor: CoresApp.erro,
                    ),
                  );
                }
              },
            ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: CoresApp.sucesso.withOpacity(0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: CoresApp.sucesso.withOpacity(0.7),
              ),
            ),
            child: Text(
              'TRAB',
              style: TextStyle(
                color: CoresDashboard.statusTrabalhando,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        DataCell(
          // CORREÇÃO APLICADA: Uso de Flexible/Overflow gerencimento na célula de data/hora + botão
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '$dateFormatted (${log.startTime} - ${log.endTime} | ${log.durationFormatted})',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CoresDashboard.statusTrabalhando,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (showCadastrarHere) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.primaria,
                    foregroundColor: CoresApp.textoPrincipal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    minimumSize: const Size(0, 28),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        TamanhosApp.raioBotao,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.cloud_upload_outlined,
                    size: 14,
                  ),
                  label: const Text(
                    'Cadastrar',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () => _handleRegisterLog(
                    log,
                  ),
                ),
              ],
            ],
          ),
        ),
        DataCell(
          _buildCellText(
            estimatedHours,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            '-',
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            hourType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: CoresApp.sucesso,
                size: 19,
              ),
              const SizedBox(width: 5),
              IconButton(
                icon: Icon(
                  Icons.edit_rounded,
                  color: CoresApp.destaqueAmarelo,
                  size: 18,
                ),
                tooltip: 'Editar Horário',
                onPressed: () => widget.onEditLog(
                  log,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                  size: 18,
                ),
                tooltip: 'Excluir Apontamento',
                onPressed: () {
                  setState(() {
                    _localTimeLogs.remove(log);
                  });

                  widget.onDeleteLog(log);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProjectActionControls({
    required ProjectModel project,
    VoidCallback? onDelete,
    VoidCallback? onAddSubTask,
  }) {
    final hasFolder =
        project.folderPath != null && project.folderPath!.trim().isNotEmpty;
    final hasExcel =
        project.excelLink != null && project.excelLink!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 3,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: CoresApp.textoPrincipal.withOpacity(0.018),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.folder_rounded,
              color: hasFolder
                  ? CoresApp.destaque
                  : CoresApp.textoSecundario.withOpacity(0.3),
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: hasFolder
                ? 'Abrir Pasta: ${project.folderPath}'
                : 'Nenhuma pasta definida',
            onPressed: hasFolder
                ? () async {
                    try {
                      final folderDir = Directory(
                        project.folderPath!,
                      );

                      if (await folderDir.exists()) {
                        await Process.run(
                          'explorer',
                          [project.folderPath!],
                        );
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'A pasta informada não existe mais no disco.',
                              ),
                              backgroundColor: CoresApp.erro,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Erro ao abrir pasta: $e',
                            ),
                            backgroundColor: CoresApp.erro,
                          ),
                        );
                      }
                    }
                  }
                : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.insert_drive_file_rounded,
              color: hasExcel
                  ? CoresDashboard.statusTrabalhando
                  : CoresApp.textoSecundario.withOpacity(0.3),
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: hasExcel
                ? 'Abrir Arquivo/Excel: ${project.excelLink}'
                : 'Nenhum arquivo/link definido',
            onPressed: hasExcel
                ? () async {
                    try {
                      final link = project.excelLink!;

                      if (link.startsWith('http://') ||
                          link.startsWith('https://')) {
                        final uri = Uri.parse(link);

                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      } else {
                        final file = File(link);

                        if (await file.exists()) {
                          await Process.run(
                            'cmd',
                            [
                              '/c',
                              'start',
                              '',
                              link,
                            ],
                          );
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'O arquivo informado não existe mais no disco.',
                                ),
                                backgroundColor: CoresApp.erro,
                              ),
                            );
                          }
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Erro ao abrir arquivo/link: $e',
                            ),
                            backgroundColor: CoresApp.erro,
                          ),
                        );
                      }
                    }
                  }
                : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.edit_rounded,
              color: CoresApp.destaqueAmarelo,
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: 'Editar Trabalho',
            onPressed: () => _showLinksDialog(project),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.checklist_rounded,
              color: CoresApp.destaque,
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: 'Checklist',
            onPressed: () => _showCheckListDialog(project),
          ),

          //////////////////////////////////////////////
          /// Enviar comentário para o E-desk
          /// ///////////////////////////////////////////

          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Enviar Comentário E-desk',
            icon: Icon(
              Icons.comment_rounded,
              color: CoresApp.destaque,
              size: TamanhosApp.iconeAcao,
            ),
            onPressed: () {
              _showComentarioEdeskDialog(project);
            },
          ),

          if (onDelete != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.delete_outline_rounded,
                color: CoresApp.erro,
                size: TamanhosApp.iconeAcao,
              ),
              tooltip: 'Excluir Trabalho',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  Widget _buildSubTaskActionControls({
    required ProjectModel project,
    required TaskModel task,
    required String targetId,
    required String title,
  }) {
    final isCurrentTarget = widget.activeTimerTargetId == targetId;
    final isRunning =
        isCurrentTarget && widget.timerState == TimerState.running;
    final isPaused = isCurrentTarget && widget.timerState == TimerState.paused;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRunning) ...[
          _buildActionIconButton(
            icon: Icons.pause_circle_filled_rounded,
            color: CoresApp.destaqueAmarelo,
            tooltip: 'Pausar',
            onPressed: widget.onPauseTimer,
          ),
          _buildActionIconButton(
            icon: Icons.stop_circle_rounded,
            color: CoresApp.erro,
            tooltip: 'Stop',
            onPressed: widget.onStopTimer,
          ),
        ] else if (isPaused) ...[
          _buildActionIconButton(
            icon: Icons.play_circle_fill_rounded,
            color: CoresDashboard.statusTrabalhando,
            tooltip: 'Retomar',
            onPressed: () => widget.onStartTimer(
              targetId,
            ),
          ),
          _buildActionIconButton(
            icon: Icons.stop_circle_rounded,
            color: CoresApp.erro,
            tooltip: 'Stop',
            onPressed: widget.onStopTimer,
          ),
        ] else ...[
          _buildActionIconButton(
            icon: Icons.play_circle_fill_rounded,
            color: CoresDashboard.statusTrabalhando,
            tooltip: 'Iniciar Cronômetro',
            onPressed: () => widget.onStartTimer(
              targetId,
            ),
          ),
        ],
        _buildActionIconButton(
          icon: Icons.more_time_rounded,
          color: CoresApp.destaque,
          tooltip: 'Adicionar Horas Manualmente',
          onPressed: () => widget.onManualTime(
            title,
          ),
        ),
        _buildActionIconButton(
          icon: Icons.delete_outline_rounded,
          color: CoresApp.erro,
          tooltip: 'Excluir Subtrabalho',
          onPressed: () async {
            final bool? confirmar = await showDialog<bool>(
              context: context,
              builder: (BuildContext dialogContext) {
                return AlertDialog(
                  backgroundColor: CoresTelas.fundoModal,
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
                        Icons.warning_amber_rounded,
                        color: CoresApp.erro,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Confirmar Exclusão',
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    'Deseja realmente excluir a etapa "${task.subId} - ${task.stage}"? Esta ação não poderá ser desfeita.',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 13,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(false),
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
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(true),
                      child: const Text(
                        'Excluir',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );

            if (confirmar != true) return;

            project.subTasks?.removeWhere(
              (s) => s.subId == task.subId,
            );

            setState(() {});

            try {
              await widget.firebaseService.salvarProjeto(project);

              widget.onEditProject(
                project,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Etapa excluída com sucesso!',
                    ),
                    backgroundColor: CoresApp.sucesso,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Erro ao excluir etapa: $e',
                    ),
                    backgroundColor: CoresApp.erro,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildActionIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(
        minWidth: 30,
        minHeight: 30,
      ),
      icon: Icon(
        icon,
        color: color,
        size: TamanhosApp.iconeAcao,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _generateRows(widget.projects);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CoresDashboard.tabelaFundo,
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioTabela,
        ),
        border: Border.all(
          color: CoresDashboard.tabelaBorda,
          width: TamanhosApp.espessuraBorda,
        ),
        boxShadow: [
          BoxShadow(
            color: CoresApp.overlay,
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: CoresApp.destaque,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(
                  TamanhosApp.raioTabela,
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 350,
              maxHeight: 700,
            ),
            child: Scrollbar(
              controller: widget.verticalController,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: widget.verticalController,
                scrollDirection: Axis.vertical,
                child: Scrollbar(
                  controller: widget.horizontalController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: widget.horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width:
                          1650, // Aumentado de 1500 para 1650 para comportar folga nas colunas
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 16.0,
                        horizontalMargin: 16.0,
                        headingRowHeight: 48,
                        dataRowMinHeight: 28,
                        dataRowMaxHeight: 36,
                        dividerThickness: 0.35,
                        headingRowColor: WidgetStateProperty.all(
                          CoresDashboard.tabelaCabecalho,
                        ),
                        dataRowColor: WidgetStateProperty.resolveWith(
                          (states) {
                            if (states.contains(
                              WidgetState.hovered,
                            )) {
                              return CoresDashboard.tabelaHover;
                            }

                            return null;
                          },
                        ),
                        columns: [
                          DataColumn(
                            label: _buildTableHeader('ID'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Nº'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Cliente'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Tipo de Serviço'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Informações'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Status'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Data Início / Fim'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Hs Estimadas'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Líder Prj'),
                          ),
                          DataColumn(
                            label: _buildTableHeader('Tipo HS'),
                          ),
                          DataColumn(
                            label: _buildTableHeader(
                              'Ações / Cronômetro / Check List',
                            ),
                          ),
                        ],
                        rows: rows,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

///////////////////////////////////////////////
  /// Modal para enviar comentário para o E-Desk (Móvel e Redimensionável com Barra de Formatação)
  ///////////////////////////////////////////////

  void _showComentarioEdeskDialog(ProjectModel project) {
    final comentarioController = TextEditingController();
    final ImagePicker imagePicker = ImagePicker();

    // ===============================================================
    // CONTROLE DO EDITOR DE COMENTÁRIO
    // ===============================================================

    final comentarioFocusNode = FocusNode();

    // ===============================================================
    // CONTROLE DE POSIÇÃO E TAMANHO (MOVER E REDIMENSIONAR O MODAL)
    // ===============================================================
    Offset offsetModal = Offset.zero;
    double? larguraCustomizada;
    double? alturaCustomizada;

    // ===============================================================
    // CONTROLE DO FORMULÁRIO DE COMENTÁRIO
    // ===============================================================

    bool salvando = false;
    bool excluindo = false;

    String? comentarioSelecionadoId;
    String? imagemBase64;

    // Todas as imagens que serão enviadas no mesmo comentário.
    final List<String> imagensBase64 = <String>[];

    // Blocos já confirmados no editor, preservando a ordem real
    // Texto -> imagem -> texto -> imagem...
    final List<Map<String, String>> blocosComentario = <Map<String, String>>[];

    // Formatação do bloco de texto atualmente em edição.
    String fonteComentario = 'Segoe UI';
    double tamanhoFonteComentario = 11;
    bool negritoComentario = false;
    bool italicoComentario = false;
    bool sublinhadoComentario = false;
    bool tachadoComentario = false;
    TextAlign alinhamentoComentario = TextAlign.left;
    Color corFonteComentario = CoresApp.textoPrincipal;

    Map<String, String> criarBlocoTexto(String texto) => {
          'tipo': 'texto',
          'valor': texto,
          'fonte': fonteComentario,
          'tamanho': tamanhoFonteComentario.toString(),
          'negrito': negritoComentario.toString(),
          'italico': italicoComentario.toString(),
          'sublinhado': sublinhadoComentario.toString(),
          'tachado': tachadoComentario.toString(),
          'alinhamento': alinhamentoComentario.name,
          'cor': corFonteComentario.value.toRadixString(16).padLeft(8, '0'),
        };

    TextAlign alinhamentoDoBloco(Map<String, String> bloco) {
      switch (bloco['alinhamento']) {
        case 'center':
          return TextAlign.center;
        case 'right':
          return TextAlign.right;
        case 'justify':
          return TextAlign.justify;
        default:
          return TextAlign.left;
      }
    }

    Color corDoBloco(Map<String, String> bloco) {
      final valor = bloco['cor'];
      if (valor == null || valor.isEmpty) return CoresApp.textoPrincipal;
      final parsed = int.tryParse(valor, radix: 16);
      return parsed == null ? CoresApp.textoPrincipal : Color(parsed);
    }

    TextStyle estiloDoBloco(Map<String, String> bloco) {
      return TextStyle(
        color: corDoBloco(bloco),
        fontSize: double.tryParse(bloco['tamanho'] ?? '') ?? 11,
        fontFamily: bloco['fonte'] ?? 'Segoe UI',
        fontWeight:
            bloco['negrito'] == 'true' ? FontWeight.bold : FontWeight.normal,
        fontStyle:
            bloco['italico'] == 'true' ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (bloco['sublinhado'] == 'true') TextDecoration.underline,
          if (bloco['tachado'] == 'true') TextDecoration.lineThrough,
        ]),
      );
    }

    List<Map<String, String>> blocosParaPersistir() {
      final resultado =
          blocosComentario.map((e) => Map<String, String>.from(e)).toList();
      final textoAtual = comentarioController.text;
      if (textoAtual.trim().isNotEmpty) {
        resultado.add(criarBlocoTexto(textoAtual));
      }
      return resultado;
    }

    void adicionarImagemAoEditor(String base64Imagem) {
      final textoAtual = comentarioController.text;
      if (textoAtual.trim().isNotEmpty) {
        blocosComentario.add(criarBlocoTexto(textoAtual));
      }
      blocosComentario.add({'tipo': 'imagem', 'valor': base64Imagem});
      comentarioController.clear();
      imagensBase64.add(base64Imagem);
      imagemBase64 = base64Imagem;
    }

    String montarTextoOrdenado() {
      final buffer = StringBuffer();
      var indiceImagem = 0;
      for (final bloco in blocosComentario) {
        if (bloco['tipo'] == 'texto') {
          final valor = bloco['valor'] ?? '';
          if (valor.isNotEmpty) {
            buffer.write(valor);
            if (!valor.endsWith('\n')) buffer.write('\n');
          }
        } else if (bloco['tipo'] == 'imagem') {
          buffer.writeln('[[EDESK_IMAGE_$indiceImagem]]');
          indiceImagem++;
        }
      }
      final textoFinal = comentarioController.text;
      if (textoFinal.isNotEmpty) buffer.write(textoFinal);
      return buffer.toString().trim();
    }

    // Texto utilizado para filtrar o histórico da lateral direita.
    String buscaHistorico = '';

    // ===============================================================
    // EXCEL DO PROJETO
    // ===============================================================

    String? imagemExcelBase64;

    // Mantém todas as tabelas do Excel adicionadas ao comentário.
    final List<String> imagensExcelBase64 = <String>[];
    final List<String> intervalosExcelAdicionados = <String>[];

    bool carregandoExcel = false;
    String? erroExcel;

    // ===============================================================
    // TIPO DO COMENTÁRIO
    // ===============================================================

    String tipoComentario = 'Interno';

// ===============================================================
// CONFIGURAÇÕES DOS COMENTÁRIOS E-DESK
// Etiquetas + campos/faixas do Excel
// ===============================================================

    String etiquetaSelecionada = 'Enterprise';

// Campo do Excel escolhido no botão "Usar imagem do Excel".
    String? campoExcelSelecionado;

// Configuração carregada do Firebase.
//
// Estrutura:
//
// {
//   'Enterprise': [
//     {
//       'nome': 'Capa do projeto',
//       'intervalo': 'A1:D20',
//     },
//   ],
// }
    Map<String, List<Map<String, String>>> camposExcelPorEtiqueta = {
      'Enterprise': [
        {
          'nome': 'Capa do projeto',
          'intervalo': 'A1:D20',
        },
        {
          'nome': 'Cronograma',
          'intervalo': 'A22:H60',
        },
        {
          'nome': 'Recursos',
          'intervalo': 'A62:F90',
        },
      ],
      'Professional': [],
      'Catalog': [],
      'Consultoria': [],
    };

// Lista exibida no dropdown "ETIQUETAS DO CHAMADO".
    List<String> etiquetasComentario = [
      'Enterprise',
      'Professional',
      'Catalog',
      'Consultoria',
    ];

    bool carregandoConfiguracoesEdesk = false;
    bool configuracoesEdeskCarregadas = false;

// ===============================================================
// REFERÊNCIA DA CONFIGURAÇÃO NO FIREBASE
// ===============================================================

    DocumentReference<Map<String, dynamic>> configuracaoComentariosEdeskRef() {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('configuracoes')
          .doc('comentarios_edesk');
    }

// ===============================================================
// CARREGAR CONFIGURAÇÕES DO FIREBASE
// ===============================================================

    Future<void> carregarConfiguracoesComentariosEdesk(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      if (carregandoConfiguracoesEdesk) return;

      setDialogState(() {
        carregandoConfiguracoesEdesk = true;
      });

      try {
        final snapshot = await configuracaoComentariosEdeskRef().get();

        if (!dialogContext.mounted) return;

        // -------------------------------------------------------------
        // Ainda não existe configuração salva.
        // Mantemos os valores padrão definidos acima.
        // -------------------------------------------------------------

        if (!snapshot.exists) {
          configuracoesEdeskCarregadas = true;

          if (etiquetasComentario.isNotEmpty &&
              !etiquetasComentario.contains(etiquetaSelecionada)) {
            etiquetaSelecionada = etiquetasComentario.first;
          }

          return;
        }

        final dados = snapshot.data();

        if (dados == null) {
          configuracoesEdeskCarregadas = true;
          return;
        }

        // -------------------------------------------------------------
        // CARREGA ETIQUETAS
        // -------------------------------------------------------------

        final etiquetasFirebase = dados['etiquetas'];

        final novasEtiquetas = <String>[];

        if (etiquetasFirebase is List) {
          for (final item in etiquetasFirebase) {
            final nome = item.toString().trim();

            if (nome.isNotEmpty && !novasEtiquetas.contains(nome)) {
              novasEtiquetas.add(nome);
            }
          }
        }

        // -------------------------------------------------------------
        // CARREGA CAMPOS DO EXCEL
        // -------------------------------------------------------------

        final novosCampos = <String, List<Map<String, String>>>{};

        final camposFirebase = dados['camposExcel'];

        if (camposFirebase is Map) {
          for (final entry in camposFirebase.entries) {
            final etiqueta = entry.key.toString().trim();

            if (etiqueta.isEmpty) continue;

            final listaCampos = <Map<String, String>>[];

            final valor = entry.value;

            if (valor is List) {
              for (final campo in valor) {
                if (campo is Map) {
                  final nome = campo['nome']?.toString().trim() ?? '';
                  final intervalo =
                      campo['intervalo']?.toString().trim().toUpperCase() ?? '';

                  if (nome.isNotEmpty || intervalo.isNotEmpty) {
                    listaCampos.add({
                      'nome': nome,
                      'intervalo': intervalo,
                    });
                  }
                }
              }
            }

            novosCampos[etiqueta] = listaCampos;
          }
        }

        // -------------------------------------------------------------
        // ATUALIZA O MODAL PRINCIPAL
        // -------------------------------------------------------------

        setDialogState(() {
          // O Firebase é a fonte definitiva da configuração.
// Inclusive uma lista vazia precisa ser respeitada.
          etiquetasComentario = List<String>.from(novasEtiquetas);

          camposExcelPorEtiqueta = {
            for (final etiqueta in etiquetasComentario)
              etiqueta: List<Map<String, String>>.from(
                novosCampos[etiqueta] ?? const [],
              ),
          };

          if (!etiquetasComentario.contains(etiquetaSelecionada)) {
            etiquetaSelecionada =
                etiquetasComentario.isNotEmpty ? etiquetasComentario.first : '';
          }

          campoExcelSelecionado = null;
          configuracoesEdeskCarregadas = true;
        });
      } catch (e) {
        debugPrint(
          'Erro ao carregar configurações dos comentários E-Desk: $e',
        );

        // Se ocorrer erro no Firebase, mantemos a configuração local
        // para não impedir a abertura do modal.
        configuracoesEdeskCarregadas = true;
      } finally {
        setDialogState(() {
          carregandoConfiguracoesEdesk = false;
        });
      }
    }

// ===============================================================
// SALVAR CONFIGURAÇÕES NO FIREBASE
// ===============================================================

    Future<void> salvarConfiguracoesComentariosEdesk({
      required List<String> etiquetas,
      required Map<String, List<Map<String, String>>> campos,
    }) async {
      final etiquetasLimpas = etiquetas
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

      final camposFirebase = <String, dynamic>{};

      for (final etiqueta in etiquetasLimpas) {
        final lista = campos[etiqueta] ?? const [];

        camposFirebase[etiqueta] = lista
            .map(
              (campo) => {
                'nome': campo['nome']?.trim() ?? '',
                'intervalo': campo['intervalo']?.trim().toUpperCase() ?? '',
              },
            )
            .where(
              (campo) =>
                  campo['nome']!.isNotEmpty || campo['intervalo']!.isNotEmpty,
            )
            .toList();
      }

// Substitui completamente a configuração.
// Assim, etiquetas e campos excluídos também são removidos do Firebase.
      await configuracaoComentariosEdeskRef().set(
        {
          'etiquetas': etiquetasLimpas,
          'camposExcel': camposFirebase,
          'atualizadoEm': FieldValue.serverTimestamp(),
        },
      );
    }

// ===============================================================
// ETIQUETA E-DESK DO PROJETO
// ===============================================================

    DocumentReference<Map<String, dynamic>> projetoEdeskRef() {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }
      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('projects')
          .doc(project.id.trim());
    }

    Future<void> carregarEtiquetaProjeto(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      try {
        final snapshot = await projetoEdeskRef().get();
        if (!dialogContext.mounted) return;

        final etiquetaSalva =
            snapshot.data()?['etiquetaComentarioEdesk']?.toString().trim() ??
                '';

        if (etiquetaSalva.isNotEmpty &&
            etiquetasComentario.contains(etiquetaSalva)) {
          setDialogState(() {
            etiquetaSelecionada = etiquetaSalva;
            campoExcelSelecionado = null;
            imagemExcelBase64 = null;
          });
        }
      } catch (e) {
        debugPrint('Erro ao carregar etiqueta E-Desk do projeto: $e');
      }
    }

    Future<void> salvarEtiquetaProjeto(String etiqueta) async {
      final valor = etiqueta.trim();
      if (valor.isEmpty) return;

      await projetoEdeskRef().set(
        {
          'etiquetaComentarioEdesk': valor,
          'etiquetaComentarioEdeskAtualizadaEm': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

// ===============================================================
// CAMPOS DO EXCEL DA ETIQUETA ATUAL
// ===============================================================

    List<Map<String, String>> camposExcelEtiquetaAtual() {
      return camposExcelPorEtiqueta[etiquetaSelecionada] ?? const [];
    }
    // ===============================================================
    // CONTROLE E-DESK
    // ===============================================================

    bool testandoEdesk = false;
    bool enviandoEdesk = false;

    // ===============================================================
    // REFERÊNCIA DOS COMENTÁRIOS E-DESK
    // ===============================================================

    CollectionReference<Map<String, dynamic>> comentariosRef() {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Usuário não autenticado.');
      }

      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('projects')
          .doc(project.id.trim())
          .collection('comentarios_edesk');
    }

    // ===============================================================
    // LOCALIZA A ETAPA CONFIGURADA PARA O E-DESK
    // ===============================================================

    TaskModel? obterTaskEdesk() {
      final tarefas = project.subTasks ?? [];

      for (final task in tarefas) {
        if (task.edeskIdTrabalho?.trim().isNotEmpty ?? false) {
          return task;
        }
      }

      return null;
    }

    // ===============================================================
    // SELECIONAR IMAGEM
    // ===============================================================

    Future<void> selecionarImagem(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      try {
        final XFile? arquivo = await imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
          maxWidth: 1600,
          maxHeight: 1600,
        );

        if (arquivo == null) return;

        final bytes = await arquivo.readAsBytes();

        setDialogState(() {
          final novaImagem = base64Encode(bytes);
          adicionarImagemAoEditor(novaImagem);
        });
      } catch (e) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar imagem: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }

    // ===============================================================
    // LIMPAR FORMULÁRIO
    // ===============================================================

    void limparFormulario(
      StateSetter setDialogState,
    ) {
      comentarioController.clear();
      comentarioFocusNode.unfocus();

      setDialogState(() {
        comentarioSelecionadoId = null;
        imagensBase64.clear();
        blocosComentario.clear();
        imagensExcelBase64.clear();
        intervalosExcelAdicionados.clear();
        imagemBase64 = null;
        imagemExcelBase64 = null;
        campoExcelSelecionado = null;
        tipoComentario = 'Interno';
      });
    }

    // ===============================================================
    // EXCLUIR COMENTÁRIO
    // ===============================================================

    Future<void> excluirComentario(
      BuildContext dialogContext,
      StateSetter setDialogState,
      String comentarioId,
    ) async {
      final confirmar = await showDialog<bool>(
        context: dialogContext,
        builder: (confirmContext) {
          return AlertDialog(
            backgroundColor: CoresTelas.fundoModal,
            title: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  color: CoresApp.erro,
                ),
                const SizedBox(width: 8),
                Text(
                  'Excluir comentário',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                  ),
                ),
              ],
            ),
            content: Text(
              'Deseja realmente excluir este comentário?',
              style: TextStyle(
                color: CoresApp.textoPrincipal,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(confirmContext).pop(false);
                },
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: CoresApp.textoSecundario,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CoresApp.erro,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                ),
                label: const Text('Excluir'),
                onPressed: () {
                  Navigator.of(confirmContext).pop(true);
                },
              ),
            ],
          );
        },
      );

      if (confirmar != true) return;

      setDialogState(() {
        excluindo = true;
      });

      try {
        final ref = comentariosRef();
        await ref.doc(comentarioId).delete();

        if (comentarioSelecionadoId == comentarioId) {
          comentarioController.clear();
          comentarioFocusNode.unfocus();

          setDialogState(() {
            comentarioSelecionadoId = null;
            imagemBase64 = imagemExcelBase64;
            tipoComentario = 'Interno';
          });
        }

        setDialogState(() {
          excluindo = false;
        });

        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Comentário excluído com sucesso.',
            ),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      } catch (e) {
        setDialogState(() {
          excluindo = false;
        });

        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao excluir comentário: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }

// ===============================================================
// CARREGA IMAGEM DO EXCEL DO PROJETO
// ===============================================================

    Future<void> carregarExcelProjeto(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      // =============================================================
      // VALIDAÇÕES
      // =============================================================

      final caminho = project.excelLink?.trim() ?? '';

      if (caminho.isEmpty) {
        setDialogState(() {
          erroExcel = 'Nenhum arquivo Excel vinculado a este projeto.';
          carregandoExcel = false;
        });

        return;
      }

      final intervalo = campoExcelSelecionado?.trim().toUpperCase() ?? '';

      if (intervalo.isEmpty) {
        setDialogState(() {
          erroExcel = 'Selecione uma área do Excel para utilizar.';
          carregandoExcel = false;
        });

        return;
      }

      final arquivo = File(caminho);

      if (!await arquivo.exists()) {
        setDialogState(() {
          erroExcel = 'Arquivo Excel não encontrado:\n$caminho';
          carregandoExcel = false;
        });

        return;
      }

      setDialogState(() {
        carregandoExcel = true;
        erroExcel = null;
      });

      Process? processo;

      try {
        // =============================================================
        // PYTHON
        //
        // IMPORTANTE:
        // O openpyxl foi confirmado neste Python 3.14.
        // Não usamos mais a .venv antiga para o Excel Preview.
        // =============================================================

        final localAppData = Platform.environment['LOCALAPPDATA'];

        if (localAppData == null || localAppData.trim().isEmpty) {
          throw Exception(
            'Não foi possível localizar LOCALAPPDATA do Windows.',
          );
        }

        final pythonExe =
            '$localAppData\\Python\\pythoncore-3.14-64\\python.exe';

        const scriptExcel =
            r'D:\APP\gerenciador_horas\edesk_bot\excel_preview.py';

        final pythonFile = File(pythonExe);
        final scriptFile = File(scriptExcel);

        // =============================================================
        // CONFERE OS ARQUIVOS
        // =============================================================

        if (!await pythonFile.exists()) {
          throw Exception(
            'Python 3.14 não encontrado:\n$pythonExe',
          );
        }

        if (!await scriptFile.exists()) {
          throw Exception(
            'Script excel_preview.py não encontrado:\n$scriptExcel',
          );
        }

        debugPrint('');
        debugPrint('==============================================');
        debugPrint('[ExcelPreview] INICIANDO PREVIEW');
        debugPrint('==============================================');
        debugPrint('[ExcelPreview] Python: $pythonExe');
        debugPrint('[ExcelPreview] Script: $scriptExcel');
        debugPrint('[ExcelPreview] Excel: $caminho');
        debugPrint('[ExcelPreview] Intervalo: $intervalo');

        // =============================================================
        // INICIA O PYTHON
        // =============================================================

        processo = await Process.start(
          pythonExe,
          [
            '-u',
            scriptExcel,
          ],
          runInShell: false,
        );

        debugPrint(
          '[ExcelPreview] Processo iniciado. PID: ${processo.pid}',
        );

        // =============================================================
        // STDERR
        // =============================================================

        final stderrBuffer = StringBuffer();

        processo.stderr
            .transform(
              const Utf8Decoder(
                allowMalformed: true,
              ),
            )
            .transform(
              const LineSplitter(),
            )
            .listen(
          (linha) {
            final texto = linha.trim();

            if (texto.isEmpty) {
              return;
            }

            stderrBuffer.writeln(texto);

            debugPrint(
              '[excel_preview.py] $texto',
            );
          },
          onError: (erro) {
            debugPrint(
              '[ExcelPreview] Erro ao ler STDERR: $erro',
            );
          },
        );

        // =============================================================
        // PREPARA A RESPOSTA
        // =============================================================

        final respostaCompleter = Completer<Map<String, dynamic>>();

        processo.stdout
            .transform(
              const Utf8Decoder(
                allowMalformed: true,
              ),
            )
            .transform(
              const LineSplitter(),
            )
            .listen(
          (linha) {
            final texto = linha.trim();

            if (texto.isEmpty) {
              return;
            }

            debugPrint(
              '[excel_preview.py stdout] $texto',
            );

            try {
              final decoded = jsonDecode(texto);

              if (decoded is Map) {
                final resposta = Map<String, dynamic>.from(decoded);

                if (!respostaCompleter.isCompleted) {
                  respostaCompleter.complete(resposta);
                }
              }
            } catch (_) {
              // Ignora qualquer saída que não seja JSON.
            }
          },
          onError: (erro) {
            if (!respostaCompleter.isCompleted) {
              respostaCompleter.completeError(
                Exception(
                  'Erro ao ler resposta do excel_preview.py: $erro',
                ),
              );
            }
          },
          onDone: () {
            if (!respostaCompleter.isCompleted) {
              final erroPython = stderrBuffer.toString().trim();

              if (erroPython.isNotEmpty) {
                respostaCompleter.completeError(
                  Exception(
                    'excel_preview.py foi encerrado sem retornar '
                    'uma resposta válida.\n\n$erroPython',
                  ),
                );
              } else {
                respostaCompleter.completeError(
                  Exception(
                    'excel_preview.py foi encerrado sem retornar '
                    'uma resposta válida.',
                  ),
                );
              }
            }
          },
        );

        // =============================================================
        // ENVIA COMANDO PARA O PYTHON
        // =============================================================

        final comando = jsonEncode({
          'acao': 'open',
          'path': caminho,
          'intervalo': intervalo,
        });

        debugPrint(
          'Excel preview -> arquivo: $caminho',
        );

        debugPrint(
          'Excel preview -> intervalo: $intervalo',
        );

        processo.stdin.writeln(comando);

        await processo.stdin.flush();

        // =============================================================
        // AGUARDA A RESPOSTA
        // =============================================================

        final resposta = await respostaCompleter.future.timeout(
          const Duration(
            seconds: 30,
          ),
          onTimeout: () {
            throw TimeoutException(
              'O excel_preview.py não respondeu em 30 segundos.',
            );
          },
        );

        if (!dialogContext.mounted) return;

        // =============================================================
        // VALIDA RETORNO
        // =============================================================

        if (resposta['ok'] != true) {
          final mensagem = resposta['erro']?.toString().trim() ??
              resposta['message']?.toString().trim() ??
              'Erro desconhecido ao gerar a imagem do Excel.';

          throw Exception(mensagem);
        }

        // =============================================================
        // RECEBE BASE64
        // =============================================================

        final base64Recebido =
            resposta['imagemBase64']?.toString().trim() ?? '';

        if (base64Recebido.isEmpty) {
          throw Exception(
            'O excel_preview.py não retornou a imagem '
            'do intervalo $intervalo.',
          );
        }

        // =============================================================
        // ATUALIZA O MODAL
        // =============================================================

        setDialogState(() {
          // A nova tabela SEMPRE é acrescentada ao comentário.
          // Não substituímos a tabela anterior, mesmo que venha de outra
          // etiqueta ou utilize o mesmo intervalo configurado.
          imagemExcelBase64 = base64Recebido;
          intervalosExcelAdicionados.add(intervalo);
          imagensExcelBase64.add(base64Recebido);
          adicionarImagemAoEditor(base64Recebido);

          erroExcel = null;
          carregandoExcel = false;
        });

        debugPrint(
          '[ExcelPreview] Imagem carregada com sucesso.',
        );

        debugPrint(
          '[ExcelPreview] Intervalo carregado: $intervalo',
        );

        debugPrint(
          '[ExcelPreview] Base64: ${base64Recebido.length} caracteres',
        );
      } on TimeoutException catch (e) {
        if (!dialogContext.mounted) return;

        debugPrint(
          '[ExcelPreview] TIMEOUT: $e',
        );

        setDialogState(() {
          erroExcel = e.message ?? 'Tempo limite excedido.';
          carregandoExcel = false;
        });
      } catch (e, stackTrace) {
        if (!dialogContext.mounted) return;

        debugPrint(
          '[ExcelPreview] ERRO: $e',
        );

        debugPrint(
          '[ExcelPreview] STACK: $stackTrace',
        );

        setDialogState(() {
          erroExcel = e.toString().replaceFirst(
                'Exception: ',
                '',
              );

          carregandoExcel = false;
        });
      } finally {
        // =============================================================
        // ENCERRA O PYTHON
        // =============================================================

        if (processo != null) {
          try {
            processo.stdin.writeln(
              jsonEncode({
                'acao': 'close',
              }),
            );

            await processo.stdin.flush();
          } catch (_) {
            // Processo já pode ter sido encerrado.
          }

          try {
            await processo.stdin.close();
          } catch (_) {
            // Ignora.
          }

          try {
            processo.kill();
          } catch (_) {
            // Ignora.
          }
        }
      }
    }

    // ===============================================================
    // SALVAR COMENTÁRIO
    // ===============================================================

    Future<void> salvarComentario(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      final texto = montarTextoOrdenado();

      if (texto.isEmpty && imagensBase64.isEmpty && imagemBase64 == null) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Digite um comentário ou adicione uma imagem.',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );

        return;
      }

      setDialogState(() {
        salvando = true;
      });

      try {
        final firebaseUser = FirebaseAuth.instance.currentUser;

        if (firebaseUser == null) {
          throw Exception('Usuário não autenticado no Firebase.');
        }

        final ref = comentariosRef();

        final dados = <String, dynamic>{
          'comentario': texto,
          'imagemBase64': imagemBase64,
          'imagensBase64': List<String>.from(imagensBase64),
          'blocosComentario': blocosParaPersistir(),
          'tipoComentario': tipoComentario,
          'modoExecucao': 'Salvo',
          'projetoId': project.id.trim(),
          'usuarioId': firebaseUser.uid,
          'usuario':
              firebaseUser.displayName ?? firebaseUser.email ?? 'Usuário',
        };

        if (comentarioSelecionadoId == null) {
          dados['status'] = 'Pendente';
          dados['dataHora'] = FieldValue.serverTimestamp();
          dados['tentativas'] = 0;

          final documento = await ref.add(dados);

          setDialogState(() {
            comentarioSelecionadoId = documento.id;
          });
        } else {
          dados['atualizadoEm'] = FieldValue.serverTimestamp();
          await ref.doc(comentarioSelecionadoId).update(dados);
        }

        comentarioFocusNode.unfocus();

        if (!dialogContext.mounted) return;

        setDialogState(() {
          salvando = false;
        });

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text('Comentário salvo com sucesso.'),
            backgroundColor: CoresApp.sucesso,
          ),
        );
      } catch (e) {
        if (!dialogContext.mounted) return;

        setDialogState(() {
          salvando = false;
        });

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar comentário: $e'),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }

    // ===============================================================
    // TESTAR / ENVIAR PARA E-DESK
    // ===============================================================

    Future<void> executarEdesk({
      required BuildContext dialogContext,
      required StateSetter setDialogState,
      required bool enviar,
    }) async {
      final texto = montarTextoOrdenado();

      final imagensParaEnvio = imagensBase64.isNotEmpty
          ? List<String>.from(imagensBase64)
          : (imagemBase64 != null ? <String>[imagemBase64!] : <String>[]);

      // O EdeskService continua recebendo String. Quando há mais de uma
      // imagem, enviamos a lista codificada em JSON; o Python atualizado
      // abaixo entende os dois formatos.
      final String? imagemPayload = imagensParaEnvio.isEmpty
          ? null
          : (imagensParaEnvio.length == 1
              ? imagensParaEnvio.first
              : jsonEncode(imagensParaEnvio));

      if (texto.isEmpty && imagensParaEnvio.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Digite um comentário ou adicione um print.',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );

        return;
      }

      final task = obterTaskEdesk();

      if (task == null) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: const Text(
              'Este projeto não possui uma etapa com E-Desk configurado.',
            ),
            backgroundColor: CoresApp.erro,
            duration: const Duration(seconds: 5),
          ),
        );

        return;
      }

      var edeskUrl = task.edeskUrl?.trim() ?? '';
      final idTrabalho = task.edeskIdTrabalho?.trim() ?? '';
      final solicitacao = project.id.trim();

      if (edeskUrl.isEmpty) {
        edeskUrl = 'https://promob.e-desk.com.br';
      }

      if (!edeskUrl.startsWith('http://') && !edeskUrl.startsWith('https://')) {
        edeskUrl = 'https://$edeskUrl';
      }

      final edeskUri = Uri.tryParse(edeskUrl);

      if (edeskUri == null || edeskUri.host.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('URL do E-Desk inválida.')),
        );

        return;
      }

      if (idTrabalho.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível identificar o ID do trabalho E-Desk.',
            ),
          ),
        );

        return;
      }

      if (solicitacao.isEmpty) {
        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text(
              'A solicitação E-Desk não foi informada na tarefa.',
            ),
          ),
        );

        return;
      }

      if (enviar) {
        setDialogState(() {
          enviandoEdesk = true;
        });
      } else {
        setDialogState(() {
          testandoEdesk = true;
        });
      }

      String? comentarioId = comentarioSelecionadoId;
      EdeskService? service;

      try {
        final firebaseUser = FirebaseAuth.instance.currentUser;

        if (firebaseUser == null) {
          throw Exception('Usuário não autenticado no Firebase.');
        }

        final ref = comentariosRef();
        final statusInicial = enviar ? 'Enviando' : 'Teste';

        if (comentarioId == null) {
          final dados = <String, dynamic>{
            'comentario': texto,
            'imagemBase64': imagemBase64,
            'imagensBase64': List<String>.from(imagensParaEnvio),
            'blocosComentario': blocosParaPersistir(),
            'tipoComentario': tipoComentario,
            'tipoComentarioEdesk': _tipoComentarioEdesk(tipoComentario),
            'status': statusInicial,
            'modoExecucao': enviar ? 'Envio' : 'Teste',
            'projetoId': project.id.trim(),
            'usuarioId': firebaseUser.uid,
            'usuario':
                firebaseUser.displayName ?? firebaseUser.email ?? 'Usuário',
            'dataHora': FieldValue.serverTimestamp(),
            'tentativas': 1,
          };

          final documento = await ref.add(dados);
          comentarioId = documento.id;

          setDialogState(() {
            comentarioSelecionadoId = documento.id;
          });
        } else {
          final documentoRef = ref.doc(comentarioId);

          await documentoRef.update({
            'comentario': texto,
            'imagemBase64': imagemBase64,
            'imagensBase64': List<String>.from(imagensParaEnvio),
            'blocosComentario': blocosParaPersistir(),
            'tipoComentario': tipoComentario,
            'tipoComentarioEdesk': _tipoComentarioEdesk(tipoComentario),
            'status': statusInicial,
            'modoExecucao': enviar ? 'Envio' : 'Teste',
            'projetoId': project.id.trim(),
            'usuarioId': firebaseUser.uid,
            'usuario':
                firebaseUser.displayName ?? firebaseUser.email ?? 'Usuário',
            'ultimaTentativa': FieldValue.serverTimestamp(),
            'tentativas': FieldValue.increment(1),
            'erroEnvio': FieldValue.delete(),
          });
        }

        service = EdeskService();

        final resultado = await service.executarComentarioViaPython(
          pageUri: edeskUri,
          solicitacao: solicitacao,
          idTrabalho: idTrabalho,
          tipoComentario: tipoComentario,
          texto: texto,
          imagemBase64: imagemPayload,
          enviar: enviar,
        );

        if (comentarioId != null) {
          final docRef = comentariosRef().doc(comentarioId);

          if (!enviar) {
            await docRef.update({
              'status': resultado.confirmed ? 'Teste' : 'Erro',
              'resultadoTeste': resultado.message,
              'testadoEm': FieldValue.serverTimestamp(),
              if (!resultado.confirmed) 'erroEnvio': resultado.message,
              if (!resultado.confirmed) 'erroEm': FieldValue.serverTimestamp(),
            });
          } else {
            if (resultado.confirmed) {
              await docRef.update({
                'status': 'Enviado',
                'enviadoEm': FieldValue.serverTimestamp(),
                'erroEnvio': FieldValue.delete(),
              });
            } else {
              await docRef.update({
                'status': 'Erro',
                'erroEnvio': resultado.message,
                'erroEm': FieldValue.serverTimestamp(),
              });
            }
          }
        }

        if (!dialogContext.mounted) return;

        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(resultado.message),
            backgroundColor:
                resultado.confirmed ? CoresApp.sucesso : CoresApp.erro,
            duration: const Duration(seconds: 5),
          ),
        );

        if (enviar && resultado.confirmed) {
          comentarioController.clear();
          comentarioFocusNode.unfocus();

          setDialogState(() {
            comentarioSelecionadoId = null;
            imagensBase64.clear();
            blocosComentario.clear();
            imagensExcelBase64.clear();
            intervalosExcelAdicionados.clear();
            imagemBase64 = null;
            imagemExcelBase64 = null;
            campoExcelSelecionado = null;
            tipoComentario = 'Interno';
          });
        }
      } catch (e) {
        if (comentarioId != null) {
          try {
            await comentariosRef().doc(comentarioId).update({
              'status': 'Erro',
              'erroEnvio': e.toString(),
              'erroEm': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }

        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(
              content: Text('Erro E-Desk: $e'),
              backgroundColor: CoresApp.erro,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } finally {
        try {
          service?.dispose();
        } catch (_) {}

        if (dialogContext.mounted) {
          setDialogState(() {
            testandoEdesk = false;
            enviandoEdesk = false;
          });
        }
      }
    }

    // ===============================================================
    // MODAL SEPARADO — HISTÓRICO DE COMENTÁRIOS
    // ===============================================================

    Future<void> abrirHistoricoComentarios(
      BuildContext parentContext,
      StateSetter setDialogStatePrincipal,
    ) async {
      String buscaHistoricoModal = '';
      Offset offsetHistorico = Offset.zero;
      double? larguraHistoricoCustom;
      double? alturaHistoricoCustom;

      await showDialog<void>(
        context: parentContext,
        barrierDismissible: true,
        builder: (historicoContext) {
          return StatefulBuilder(
            builder: (context, setHistoricoState) {
              final tamanhoTela = MediaQuery.of(historicoContext).size;

              final double margem = tamanhoTela.width < 700 ? 8 : 16;
              final double larguraPadrao = (tamanhoTela.width - (margem * 2))
                  .clamp(320.0, 950.0)
                  .toDouble();
              final double alturaPadrao = (tamanhoTela.height - (margem * 2))
                  .clamp(420.0, 850.0)
                  .toDouble();

              final double larguraFinal =
                  larguraHistoricoCustom ?? larguraPadrao;
              final double alturaFinal = alturaHistoricoCustom ?? alturaPadrao;

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.zero,
                child: Transform.translate(
                  offset: offsetHistorico,
                  child: Center(
                    child: Stack(
                      children: [
                        Container(
                          width: larguraFinal,
                          height: alturaFinal,
                          decoration: BoxDecoration(
                            color: CoresTelas.fundoModal,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: CoresApp.borda),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              GestureDetector(
                                onPanUpdate: (details) {
                                  setHistoricoState(() {
                                    offsetHistorico += details.delta;
                                  });
                                },
                                child: Container(
                                  height: 76,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  decoration: BoxDecoration(
                                    color: CoresTelas.fundoModal,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(14),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(color: CoresApp.borda),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      MouseRegion(
                                        cursor: SystemMouseCursors.move,
                                        child: Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: CoresApp.destaque
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(9),
                                          ),
                                          child: Icon(
                                            Icons.open_with_rounded,
                                            color: CoresApp.destaque,
                                            size: 21,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Histórico de comentários',
                                              style: TextStyle(
                                                color: CoresApp.textoPrincipal,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${project.id} - ${project.client}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: CoresApp.textoSecundario,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Fechar',
                                        onPressed: () {
                                          Navigator.of(historicoContext).pop();
                                        },
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: CoresApp.textoSecundario,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                child: SizedBox(
                                  height: 42,
                                  child: TextField(
                                    onChanged: (value) {
                                      setHistoricoState(() {
                                        buscaHistoricoModal =
                                            value.trim().toLowerCase();
                                      });
                                    },
                                    style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 11,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Pesquisar comentários...',
                                      hintStyle: TextStyle(
                                        color: CoresApp.textoSecundario,
                                        fontSize: 11,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        color: CoresApp.textoSecundario,
                                        size: 18,
                                      ),
                                      filled: true,
                                      fillColor: CoresApp.fundoSecundario,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: CoresApp.borda,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: CoresApp.borda,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: CoresApp.destaque,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: comentariosRef()
                                      .orderBy('dataHora', descending: true)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: CoresApp.destaque,
                                        ),
                                      );
                                    }

                                    if (snapshot.hasError) {
                                      return Center(
                                        child: Text(
                                          'Erro ao carregar comentários.',
                                          style: TextStyle(
                                            color: CoresApp.erro,
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    }

                                    final todosComentarios =
                                        snapshot.data?.docs ?? [];
                                    final comentarios =
                                        todosComentarios.where((doc) {
                                      if (buscaHistoricoModal.isEmpty)
                                        return true;
                                      final dados = doc.data();
                                      final texto = dados['comentario']
                                              ?.toString()
                                              .toLowerCase() ??
                                          '';
                                      final tipo = dados['tipoComentario']
                                              ?.toString()
                                              .toLowerCase() ??
                                          '';
                                      final usuario = dados['usuario']
                                              ?.toString()
                                              .toLowerCase() ??
                                          '';

                                      return texto
                                              .contains(buscaHistoricoModal) ||
                                          tipo.contains(buscaHistoricoModal) ||
                                          usuario.contains(buscaHistoricoModal);
                                    }).toList();

                                    if (comentarios.isEmpty) {
                                      return Center(
                                        child: Text(
                                          buscaHistoricoModal.isEmpty
                                              ? 'Nenhum comentário salvo.'
                                              : 'Nenhum comentário encontrado.',
                                          style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 11,
                                          ),
                                        ),
                                      );
                                    }

                                    return ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 4, 16, 16),
                                      itemCount: comentarios.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final doc = comentarios[index];
                                        final dados = doc.data();
                                        final texto =
                                            dados['comentario']?.toString() ??
                                                '';
                                        final status =
                                            dados['status']?.toString() ??
                                                'Pendente';
                                        final usuario =
                                            dados['usuario']?.toString() ?? '';
                                        final imagem =
                                            dados['imagemBase64']?.toString();
                                        final imagensSalvas =
                                            (dados['imagensBase64'] as List?)
                                                    ?.map((e) => e.toString())
                                                    .where((e) => e.isNotEmpty)
                                                    .toList() ??
                                                <String>[];
                                        final blocosSalvos =
                                            (dados['blocosComentario'] as List?)
                                                    ?.whereType<Map>()
                                                    .map((e) => e.map((k, v) =>
                                                        MapEntry(k.toString(),
                                                            v.toString())))
                                                    .toList() ??
                                                <Map<String, String>>[];
                                        final tipoSalvo =
                                            dados['tipoComentario']?.toString();
                                        final timestamp =
                                            dados['dataHora'] as Timestamp?;
                                        final dataHora = timestamp?.toDate();
                                        final enviado = status == 'Enviado';
                                        final erro = status == 'Erro';

                                        void carregar({required bool editar}) {
                                          comentarioController.clear();
                                          comentarioFocusNode.unfocus();

                                          setDialogStatePrincipal(() {
                                            comentarioSelecionadoId =
                                                editar ? doc.id : null;
                                            blocosComentario
                                              ..clear()
                                              ..addAll(blocosSalvos.map((e) =>
                                                  Map<String, String>.from(e)));
                                            imagensBase64
                                              ..clear()
                                              ..addAll(imagensSalvas);
                                            if (imagensBase64.isEmpty &&
                                                imagem != null &&
                                                imagem.isNotEmpty) {
                                              imagensBase64.add(imagem);
                                            }
                                            imagemBase64 =
                                                imagensBase64.isNotEmpty
                                                    ? imagensBase64.last
                                                    : imagem;
                                            // Compatibilidade com comentários antigos, que não possuíam blocos.
                                            if (blocosComentario.isEmpty &&
                                                texto.isNotEmpty) {
                                              comentarioController.text = texto;
                                            }
                                            if (tipoSalvo != null &&
                                                [
                                                  'Interno',
                                                  'Externo',
                                                  'Padrão',
                                                  'Padrão (Interno)',
                                                ].contains(tipoSalvo)) {
                                              tipoComentario = tipoSalvo;
                                            } else {
                                              tipoComentario = 'Interno';
                                            }
                                          });

                                          Navigator.of(historicoContext).pop();
                                        }

                                        final linhas = texto
                                            .split('\n')
                                            .where((l) => l.trim().isNotEmpty)
                                            .toList();
                                        final titulo = linhas.isNotEmpty
                                            ? linhas.first
                                            : 'Comentário com imagem';

                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: CoresApp.fundoSecundario,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: CoresApp.borda),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (imagem != null &&
                                                      imagem.isNotEmpty)
                                                    Container(
                                                      width: 95,
                                                      height: 62,
                                                      margin:
                                                          const EdgeInsets.only(
                                                        right: 10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: CoresTelas
                                                            .fundoModal,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(7),
                                                        border: Border.all(
                                                          color: CoresApp.borda,
                                                        ),
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        child: Image.memory(
                                                          base64Decode(imagem),
                                                          fit: BoxFit.contain,
                                                          errorBuilder:
                                                              (_, __, ___) =>
                                                                  const SizedBox
                                                                      .shrink(),
                                                        ),
                                                      ),
                                                    ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          titulo,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: CoresApp
                                                                .textoPrincipal,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        if (dataHora !=
                                                            null) ...[
                                                          const SizedBox(
                                                              height: 5),
                                                          Text(
                                                            _formatarDataComentario(
                                                              dataHora,
                                                            ),
                                                            style: TextStyle(
                                                              color: CoresApp
                                                                  .textoSecundario,
                                                              fontSize: 9,
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    tooltip: 'Opções',
                                                    color:
                                                        CoresTelas.fundoModal,
                                                    icon: Icon(
                                                      Icons.more_vert_rounded,
                                                      color: CoresApp
                                                          .textoSecundario,
                                                      size: 18,
                                                    ),
                                                    onSelected: (opcao) async {
                                                      if (opcao == 'editar') {
                                                        carregar(editar: true);
                                                        return;
                                                      }
                                                      if (opcao ==
                                                          'reutilizar') {
                                                        carregar(editar: false);
                                                        return;
                                                      }
                                                      if (opcao == 'excluir') {
                                                        await excluirComentario(
                                                          historicoContext,
                                                          setHistoricoState,
                                                          doc.id,
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (context) =>
                                                        const [
                                                      PopupMenuItem<String>(
                                                        value: 'editar',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .edit_outlined,
                                                              size: 17,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text('Editar'),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem<String>(
                                                        value: 'reutilizar',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .content_copy_outlined,
                                                              size: 17,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text('Reutilizar'),
                                                          ],
                                                        ),
                                                      ),
                                                      PopupMenuItem<String>(
                                                        value: 'excluir',
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .delete_outline_rounded,
                                                              size: 17,
                                                            ),
                                                            SizedBox(width: 8),
                                                            Text('Excluir'),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 5,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: enviado
                                                          ? CoresApp.sucesso
                                                              .withOpacity(0.10)
                                                          : erro
                                                              ? CoresApp.erro
                                                                  .withOpacity(
                                                                      0.10)
                                                              : CoresApp
                                                                  .destaque
                                                                  .withOpacity(
                                                                      0.08),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              5),
                                                    ),
                                                    child: Text(
                                                      status,
                                                      style: TextStyle(
                                                        color: enviado
                                                            ? CoresApp.sucesso
                                                            : erro
                                                                ? CoresApp.erro
                                                                : CoresApp
                                                                    .destaque,
                                                        fontSize: 8,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  if (tipoSalvo != null &&
                                                      tipoSalvo.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 7,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                          color: CoresApp.borda,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(5),
                                                      ),
                                                      child: Text(
                                                        tipoSalvo,
                                                        style: TextStyle(
                                                          color: CoresApp
                                                              .textoSecundario,
                                                          fontSize: 8,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              if (texto.trim().isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  texto,
                                                  maxLines: 5,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: CoresApp
                                                        .textoSecundario,
                                                    fontSize: 10,
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ],
                                              if (usuario.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  usuario,
                                                  style: TextStyle(
                                                    color: CoresApp
                                                        .textoSecundario,
                                                    fontSize: 8,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeDownRight,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                setHistoricoState(() {
                                  final novaLargura =
                                      larguraFinal + details.delta.dx;
                                  final novaAltura =
                                      alturaFinal + details.delta.dy;
                                  larguraHistoricoCustom = novaLargura.clamp(
                                      320.0, tamanhoTela.width);
                                  alturaHistoricoCustom = novaAltura.clamp(
                                      350.0, tamanhoTela.height);
                                });
                              },
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: CoresApp.destaque.withOpacity(0.3),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(14),
                                  ),
                                ),
                                child: Icon(
                                  Icons.signal_cellular_null,
                                  size: 12,
                                  color: CoresApp.textoPrincipal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // ===============================================================
// MODAL — CONFIGURAÇÕES DOS COMENTÁRIOS E-DESK
// ===============================================================

    Future<void> abrirConfiguracoesComentariosEdesk(
      BuildContext parentContext,
      StateSetter setDialogStatePrincipal,
    ) async {
      // Trabalhamos com cópias para que "Cancelar" não altere
      // as configurações atualmente utilizadas pelo modal principal.
      final etiquetasTemp = List<String>.from(etiquetasComentario);

      final camposTemp = <String, List<Map<String, String>>>{
        for (final entry in camposExcelPorEtiqueta.entries)
          entry.key: entry.value
              .map(
                (campo) => <String, String>{
                  'nome': campo['nome'] ?? '',
                  'intervalo': campo['intervalo'] ?? '',
                },
              )
              .toList(),
      };

      // Garante uma lista de campos para todas as etiquetas.
      for (final etiqueta in etiquetasTemp) {
        camposTemp.putIfAbsent(
          etiqueta,
          () => <Map<String, String>>[],
        );
      }

      int abaSelecionada = 0;

      String etiquetaConfiguracaoSelecionada =
          etiquetasTemp.contains(etiquetaSelecionada)
              ? etiquetaSelecionada
              : (etiquetasTemp.isNotEmpty ? etiquetasTemp.first : '');

      bool salvandoConfiguracoes = false;

      Offset offsetConfiguracoes = Offset.zero;

      // ---------------------------------------------------------------
      // ADICIONAR ETIQUETA
      // ---------------------------------------------------------------

      Future<void> adicionarEtiqueta(
        BuildContext modalContext,
        StateSetter setConfigState,
      ) async {
        final controller = TextEditingController();

        final nome = await showDialog<String>(
          context: modalContext,
          builder: (contextNome) {
            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              title: Text(
                'Nova etiqueta',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
                decoration: InputDecoration(
                  hintText: 'Nome da etiqueta',
                  hintStyle: TextStyle(
                    color: CoresApp.textoSecundario,
                  ),
                  filled: true,
                  fillColor: CoresTelas.fundoModal,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.borda,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.borda,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.destaque,
                    ),
                  ),
                ),
                onSubmitted: (value) {
                  Navigator.of(contextNome).pop(value.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(contextNome).pop();
                  },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.destaque,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(contextNome).pop(
                      controller.text.trim(),
                    );
                  },
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 17,
                  ),
                  label: const Text('Adicionar'),
                ),
              ],
            );
          },
        );

        controller.dispose();

        if (nome == null || nome.trim().isEmpty) return;

        final nomeLimpo = nome.trim();

        final jaExiste = etiquetasTemp.any(
          (item) => item.toLowerCase() == nomeLimpo.toLowerCase(),
        );

        if (jaExiste) {
          if (!modalContext.mounted) return;

          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Já existe uma etiqueta com esse nome.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );

          return;
        }

        setConfigState(() {
          etiquetasTemp.add(nomeLimpo);

          camposTemp[nomeLimpo] = <Map<String, String>>[];

          etiquetaConfiguracaoSelecionada = nomeLimpo;
        });
      }

      // ---------------------------------------------------------------
      // RENOMEAR ETIQUETA
      // ---------------------------------------------------------------

      Future<void> editarEtiqueta(
        BuildContext modalContext,
        StateSetter setConfigState,
        String etiquetaAtual,
      ) async {
        final controller = TextEditingController(
          text: etiquetaAtual,
        );

        final novoNome = await showDialog<String>(
          context: modalContext,
          builder: (contextNome) {
            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              title: Text(
                'Editar etiqueta',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
                decoration: InputDecoration(
                  labelText: 'Nome da etiqueta',
                  labelStyle: TextStyle(
                    color: CoresApp.textoSecundario,
                  ),
                  filled: true,
                  fillColor: CoresTelas.fundoModal,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.borda,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: CoresApp.destaque,
                    ),
                  ),
                ),
                onSubmitted: (value) {
                  Navigator.of(contextNome).pop(value.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(contextNome).pop();
                  },
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
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(contextNome).pop(
                      controller.text.trim(),
                    );
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );

        controller.dispose();

        if (novoNome == null || novoNome.trim().isEmpty) return;

        final nomeLimpo = novoNome.trim();

        if (nomeLimpo == etiquetaAtual) return;

        final jaExiste = etiquetasTemp.any(
          (item) =>
              item != etiquetaAtual &&
              item.toLowerCase() == nomeLimpo.toLowerCase(),
        );

        if (jaExiste) {
          if (!modalContext.mounted) return;

          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Já existe uma etiqueta com esse nome.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );

          return;
        }

        setConfigState(() {
          final indice = etiquetasTemp.indexOf(etiquetaAtual);

          if (indice >= 0) {
            etiquetasTemp[indice] = nomeLimpo;
          }

          final camposAntigos =
              camposTemp.remove(etiquetaAtual) ?? <Map<String, String>>[];

          camposTemp[nomeLimpo] = camposAntigos;

          if (etiquetaConfiguracaoSelecionada == etiquetaAtual) {
            etiquetaConfiguracaoSelecionada = nomeLimpo;
          }
        });
      }

      // ---------------------------------------------------------------
      // EXCLUIR ETIQUETA
      // ---------------------------------------------------------------

      Future<void> excluirEtiqueta(
        BuildContext modalContext,
        StateSetter setConfigState,
        String etiqueta,
      ) async {
        final confirmar = await showDialog<bool>(
          context: modalContext,
          builder: (confirmContext) {
            return AlertDialog(
              backgroundColor: CoresTelas.fundoModal,
              title: Text(
                'Excluir etiqueta',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                'Deseja excluir a etiqueta "$etiqueta" e todos os campos do Excel configurados para ela?',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(confirmContext).pop(false);
                  },
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CoresApp.erro,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(confirmContext).pop(true);
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                  ),
                  label: const Text('Excluir'),
                ),
              ],
            );
          },
        );

        if (confirmar != true) return;

        setConfigState(() {
          etiquetasTemp.remove(etiqueta);
          camposTemp.remove(etiqueta);

          if (etiquetaConfiguracaoSelecionada == etiqueta) {
            etiquetaConfiguracaoSelecionada =
                etiquetasTemp.isNotEmpty ? etiquetasTemp.first : '';
          }
        });
      }

      // ---------------------------------------------------------------
      // ADICIONAR CAMPO DO EXCEL
      // ---------------------------------------------------------------

      void adicionarCampoExcel(
        StateSetter setConfigState,
      ) {
        if (etiquetaConfiguracaoSelecionada.isEmpty) return;

        setConfigState(() {
          camposTemp.putIfAbsent(
            etiquetaConfiguracaoSelecionada,
            () => <Map<String, String>>[],
          );

          camposTemp[etiquetaConfiguracaoSelecionada]!.add({
            'nome': '',
            'intervalo': '',
          });
        });
      }

      // ---------------------------------------------------------------
      // SALVAR CONFIGURAÇÕES
      // ---------------------------------------------------------------

      Future<void> salvarConfiguracoes(
        BuildContext modalContext,
        StateSetter setConfigState,
      ) async {
        if (etiquetasTemp.isEmpty) {
          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Cadastre pelo menos uma etiqueta.',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );

          return;
        }

        // Validação dos campos.
        for (final etiqueta in etiquetasTemp) {
          final campos = camposTemp[etiqueta] ?? const [];

          for (final campo in campos) {
            final nome = campo['nome']?.trim() ?? '';
            final intervalo = campo['intervalo']?.trim() ?? '';

            if (nome.isEmpty || intervalo.isEmpty) {
              ScaffoldMessenger.of(modalContext).showSnackBar(
                SnackBar(
                  content: Text(
                    'Preencha o nome e o intervalo de todos os campos da etiqueta "$etiqueta".',
                  ),
                  backgroundColor: CoresApp.erro,
                ),
              );

              return;
            }
          }
        }

        setConfigState(() {
          salvandoConfiguracoes = true;
        });

        try {
          await salvarConfiguracoesComentariosEdesk(
            etiquetas: etiquetasTemp,
            campos: camposTemp,
          );

          configuracoesEdeskCarregadas = true;

          setDialogStatePrincipal(() {
            etiquetasComentario = List<String>.from(etiquetasTemp);

            camposExcelPorEtiqueta = {
              for (final entry in camposTemp.entries)
                entry.key: entry.value
                    .map(
                      (campo) => <String, String>{
                        'nome': campo['nome']?.trim() ?? '',
                        'intervalo':
                            campo['intervalo']?.trim().toUpperCase() ?? '',
                      },
                    )
                    .toList(),
            };

            if (!etiquetasComentario.contains(etiquetaSelecionada)) {
              etiquetaSelecionada = etiquetasComentario.isNotEmpty
                  ? etiquetasComentario.first
                  : '';
            }

            campoExcelSelecionado = null;
            imagemExcelBase64 = null;
          });

          if (!modalContext.mounted) return;

          Navigator.of(modalContext).pop();

          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: const Text(
                'Configurações dos comentários E-Desk salvas.',
              ),
              backgroundColor: CoresApp.sucesso,
            ),
          );
        } catch (e) {
          if (!modalContext.mounted) return;

          setConfigState(() {
            salvandoConfiguracoes = false;
          });

          ScaffoldMessenger.of(modalContext).showSnackBar(
            SnackBar(
              content: Text(
                'Erro ao salvar configurações: $e',
              ),
              backgroundColor: CoresApp.erro,
            ),
          );
        }
      }

      // ===============================================================
      // ABRE O MODAL
      // ===============================================================

      await showDialog<void>(
        context: parentContext,
        barrierDismissible: false,
        builder: (configContext) {
          return StatefulBuilder(
            builder: (context, setConfigState) {
              final tamanhoTela = MediaQuery.of(configContext).size;

              final largura =
                  (tamanhoTela.width - 32).clamp(320.0, 760.0).toDouble();

              final altura =
                  (tamanhoTela.height - 32).clamp(480.0, 720.0).toDouble();

              final camposEtiqueta =
                  camposTemp[etiquetaConfiguracaoSelecionada] ??
                      <Map<String, String>>[];

              // =========================================================
              // CONTEÚDO — ETIQUETAS
              // =========================================================

              Widget construirAbaEtiquetas() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Etiquetas do chamado',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Estas etiquetas serão exibidas no dropdown do modal de comentários E-Desk.',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: etiquetasTemp.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final etiqueta = etiquetasTemp[index];

                          return Container(
                            height: 46,
                            padding: const EdgeInsets.only(left: 12),
                            decoration: BoxDecoration(
                              color: CoresTelas.fundoModal,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: CoresApp.borda,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 17,
                                  color: CoresApp.textoSecundario,
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.sell_outlined,
                                  size: 17,
                                  color: CoresApp.destaque,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    etiqueta,
                                    style: TextStyle(
                                      color: CoresApp.textoPrincipal,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Editar etiqueta',
                                  onPressed: () {
                                    editarEtiqueta(
                                      configContext,
                                      setConfigState,
                                      etiqueta,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 17,
                                    color: CoresApp.textoSecundario,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Excluir etiqueta',
                                  onPressed: () {
                                    excluirEtiqueta(
                                      configContext,
                                      setConfigState,
                                      etiqueta,
                                    );
                                  },
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: CoresApp.erro,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          adicionarEtiqueta(
                            configContext,
                            setConfigState,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CoresApp.textoPrincipal,
                          side: BorderSide(
                            color: CoresApp.destaque,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 17,
                        ),
                        label: const Text(
                          'Adicionar etiqueta',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              // =========================================================
              // CONTEÚDO — CAMPOS DO EXCEL
              // =========================================================

              Widget construirAbaCamposExcel() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CoresApp.destaque.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: CoresApp.destaque.withOpacity(0.55),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: CoresApp.destaque,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Configure quais células ou áreas do Excel serão copiadas como imagem para cada etiqueta. Esses campos serão usados ao clicar em "Usar imagem do Excel".',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Selecione a etiqueta para configurar',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 42,
                      child: DropdownButtonFormField<String>(
                        value: etiquetaConfiguracaoSelecionada.isEmpty
                            ? null
                            : etiquetaConfiguracaoSelecionada,
                        isExpanded: true,
                        dropdownColor: CoresTelas.fundoModal,
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            Icons.sell_outlined,
                            size: 17,
                            color: CoresApp.destaque,
                          ),
                          filled: true,
                          fillColor: CoresTelas.fundoModal,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: CoresApp.borda,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          color: CoresApp.textoPrincipal,
                          fontSize: 11,
                        ),
                        items: etiquetasTemp.map((etiqueta) {
                          return DropdownMenuItem<String>(
                            value: etiqueta,
                            child: Text(etiqueta),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;

                          setConfigState(() {
                            etiquetaConfiguracaoSelecionada = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Campos do Excel para esta etiqueta',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: camposEtiqueta.isEmpty
                          ? Center(
                              child: Text(
                                'Nenhum campo configurado para esta etiqueta.',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 11,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: camposEtiqueta.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 7),
                              itemBuilder: (context, index) {
                                final campo = camposEtiqueta[index];

                                return Row(
                                  key: ObjectKey(campo),
                                  children: [
                                    Icon(
                                      Icons.drag_indicator_rounded,
                                      color: CoresApp.textoSecundario,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 5,
                                      child: TextFormField(
                                        key: ObjectKey(campo),
                                        initialValue: campo['nome'] ?? '',
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 11,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Ex.: Capa do projeto',
                                          hintStyle: TextStyle(
                                            color: CoresApp.textoSecundario,
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: CoresTelas.fundoModal,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            borderSide: BorderSide(
                                              color: CoresApp.borda,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          campo['nome'] = value;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        key: ValueKey(
                                          'intervalo-${identityHashCode(campo)}',
                                        ),
                                        initialValue: campo['intervalo'] ?? '',
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        style: TextStyle(
                                          color: CoresApp.textoPrincipal,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'A1:D20',
                                          hintStyle: TextStyle(
                                            color: CoresApp.textoSecundario,
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: CoresTelas.fundoModal,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(7),
                                            borderSide: BorderSide(
                                              color: CoresApp.borda,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          campo['intervalo'] =
                                              value.toUpperCase();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      tooltip: 'Duplicar campo',
                                      onPressed: () {
                                        setConfigState(() {
                                          camposEtiqueta.insert(
                                            index + 1,
                                            {
                                              'nome':
                                                  '${campo['nome'] ?? ''} cópia',
                                              'intervalo':
                                                  campo['intervalo'] ?? '',
                                            },
                                          );
                                        });
                                      },
                                      icon: Icon(
                                        Icons.copy_outlined,
                                        size: 17,
                                        color: CoresApp.textoSecundario,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Excluir campo',
                                      onPressed: () {
                                        setConfigState(() {
                                          camposEtiqueta.removeAt(index);
                                        });
                                      },
                                      icon: Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: CoresApp.erro,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: etiquetaConfiguracaoSelecionada.isEmpty
                            ? null
                            : () {
                                adicionarCampoExcel(
                                  setConfigState,
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CoresApp.textoPrincipal,
                          side: BorderSide(
                            color: CoresApp.destaque,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.add_circle_rounded,
                          size: 17,
                        ),
                        label: const Text(
                          'Adicionar campo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(16),
                child: Transform.translate(
                  offset: offsetConfiguracoes,
                  child: Center(
                    child: Container(
                      width: largura,
                      height: altura,
                      decoration: BoxDecoration(
                        color: CoresTelas.fundoModal,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: CoresApp.borda,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.40),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // =================================================
                          // CABEÇALHO
                          // =================================================

                          GestureDetector(
                            onPanUpdate: (details) {
                              setConfigState(() {
                                offsetConfiguracoes += details.delta;
                              });
                            },
                            child: Container(
                              height: 74,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: CoresApp.borda,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: CoresApp.sucesso.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(
                                      Icons.settings_outlined,
                                      color: CoresApp.sucesso,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Configurações - Comentários E-Desk',
                                          style: TextStyle(
                                            color: CoresApp.textoPrincipal,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Personalize as etiquetas e os campos do Excel utilizados no modal.',
                                          style: TextStyle(
                                            color: CoresApp.textoSecundario,
                                            fontSize: 9,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Fechar',
                                    onPressed: salvandoConfiguracoes
                                        ? null
                                        : () {
                                            Navigator.of(configContext).pop();
                                          },
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: CoresApp.textoSecundario,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // =================================================
                          // ABAS
                          // =================================================

                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              18,
                              14,
                              18,
                              0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setConfigState(() {
                                          abaSelecionada = 0;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: abaSelecionada == 0
                                            ? CoresApp.destaque
                                            : CoresApp.textoPrincipal,
                                        side: BorderSide(
                                          color: abaSelecionada == 0
                                              ? CoresApp.destaque
                                              : CoresApp.borda,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.sell_outlined,
                                        size: 17,
                                      ),
                                      label: const Text(
                                        'Etiquetas do chamado',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: 42,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setConfigState(() {
                                          abaSelecionada = 1;
                                        });
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: abaSelecionada == 1
                                            ? CoresApp.destaque
                                            : CoresApp.textoPrincipal,
                                        side: BorderSide(
                                          color: abaSelecionada == 1
                                              ? CoresApp.destaque
                                              : CoresApp.borda,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.table_view_outlined,
                                        size: 17,
                                      ),
                                      label: const Text(
                                        'Campos do Excel',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // =================================================
                          // CONTEÚDO
                          // =================================================

                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: abaSelecionada == 0
                                  ? construirAbaEtiquetas()
                                  : construirAbaCamposExcel(),
                            ),
                          ),

                          // =================================================
                          // RODAPÉ
                          // =================================================

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: CoresApp.borda,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                OutlinedButton(
                                  onPressed: salvandoConfiguracoes
                                      ? null
                                      : () {
                                          Navigator.of(configContext).pop();
                                        },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: CoresApp.textoPrincipal,
                                    side: BorderSide(
                                      color: CoresApp.borda,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 13,
                                    ),
                                  ),
                                  child: const Text('Cancelar'),
                                ),
                                const Spacer(),
                                ElevatedButton.icon(
                                  onPressed: salvandoConfiguracoes
                                      ? null
                                      : () {
                                          salvarConfiguracoes(
                                            configContext,
                                            setConfigState,
                                          );
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: CoresApp.sucesso,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 13,
                                    ),
                                  ),
                                  icon: salvandoConfiguracoes
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    salvandoConfiguracoes
                                        ? 'Salvando...'
                                        : 'Salvar configurações',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

// ===============================================================
// MODAL — COMENTÁRIOS E-DESK (Móvel e Redimensionável)
// ===============================================================

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // =========================================================
            // CARREGA CONFIGURAÇÕES SALVAS NO FIREBASE
            // =========================================================
            //
            // Executa somente uma vez ao abrir o modal.
            // Depois do carregamento, o Firebase passa a definir
            // quais etiquetas e campos do Excel serão exibidos.
            // =========================================================

            if (!configuracoesEdeskCarregadas &&
                !carregandoConfiguracoesEdesk) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!dialogContext.mounted) return;

                await carregarConfiguracoesComentariosEdesk(
                  dialogContext,
                  setDialogState,
                );

                if (!dialogContext.mounted) return;

                await carregarEtiquetaProjeto(
                  dialogContext,
                  setDialogState,
                );
              });
            }

            final tamanhoTela = MediaQuery.of(dialogContext).size;

            final bool telaMuitoPequena = tamanhoTela.width < 700;
            final bool telaCompacta = tamanhoTela.width < 1050;

            final double margemModal = telaMuitoPequena ? 8 : 16;

            final double larguraDisponivel =
                tamanhoTela.width - (margemModal * 2);

            final double alturaDisponivel =
                tamanhoTela.height - (margemModal * 2);

            final double larguraPadrao =
                larguraDisponivel > 1100 ? 1100 : larguraDisponivel;

            final double alturaPadrao =
                alturaDisponivel > 750 ? 750 : alturaDisponivel;

            final double larguraFinal = larguraCustomizada ?? larguraPadrao;

            final double alturaFinal = alturaCustomizada ?? alturaPadrao;

            final double paddingConteudo =
                telaMuitoPequena ? 8 : (telaCompacta ? 12 : 16);
            final double paddingCard =
                telaMuitoPequena ? 10 : (telaCompacta ? 12 : 16);

            Widget botaoImagem({
              required IconData icon,
              required String texto,
              required VoidCallback? onPressed,
            }) {
              return OutlinedButton.icon(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: CoresApp.textoPrincipal,
                  side: BorderSide(color: CoresApp.borda),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: Icon(icon, size: 16, color: CoresApp.destaque),
                label: Text(
                  texto,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                ),
              );
            }

            return Dialog(
              insetPadding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              child: Transform.translate(
                offset: offsetModal,
                child: Center(
                  child: Stack(
                    children: [
                      Container(
                        width: larguraFinal,
                        height: alturaFinal,
                        constraints: BoxConstraints(
                          maxWidth: tamanhoTela.width,
                          maxHeight: tamanhoTela.height,
                        ),
                        decoration: BoxDecoration(
                          color: CoresTelas.fundoModal,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: CoresApp.borda),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // =================================================
                            // CABEÇALHO (Com função de arrastar/mover o modal)
                            // =================================================

                            GestureDetector(
                              onPanUpdate: (details) {
                                setDialogState(() {
                                  offsetModal += details.delta;
                                });
                              },
                              child: Container(
                                height: 70,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                decoration: BoxDecoration(
                                  color: CoresTelas.fundoModal,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(14)),
                                  border: Border(
                                    bottom: BorderSide(color: CoresApp.borda),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    MouseRegion(
                                      cursor: SystemMouseCursors.move,
                                      child: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: CoresApp.destaque
                                              .withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(9),
                                        ),
                                        child: Icon(
                                          Icons.open_with_rounded,
                                          color: CoresApp.destaque,
                                          size: 19,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Comentários E-Desk',
                                            style: TextStyle(
                                              color: CoresApp.textoPrincipal,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Text(
                                                'Projeto:',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontSize: 10,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  '${project.id} - ${project.client}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton.icon(
                                      onPressed: (salvando ||
                                              testandoEdesk ||
                                              enviandoEdesk ||
                                              carregandoConfiguracoesEdesk)
                                          ? null
                                          : () async {
                                              await abrirConfiguracoesComentariosEdesk(
                                                dialogContext,
                                                setDialogState,
                                              );
                                            },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            CoresApp.textoPrincipal,
                                        side: BorderSide(
                                          color: CoresApp.borda,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 11,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: Icon(
                                        Icons.settings_outlined,
                                        size: 17,
                                        color: CoresApp.textoSecundario,
                                      ),
                                      label: const Text(
                                        'Configurações',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Fechar',
                                      onPressed: (testandoEdesk ||
                                              enviandoEdesk ||
                                              salvando)
                                          ? null
                                          : () {
                                              Navigator.of(dialogContext).pop();
                                            },
                                      icon: Icon(
                                        Icons.close_rounded,
                                        color: CoresApp.textoSecundario,
                                        size: 22,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // =================================================
                            // CONTEÚDO PRINCIPAL (Flexível e Responsivo)
                            // =================================================

                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(paddingConteudo),
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(paddingCard),
                                  decoration: BoxDecoration(
                                    color: CoresApp.fundoSecundario,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: CoresApp.borda),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Linha Superior: Título + Etiqueta + Histórico
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final bool compacto =
                                              constraints.maxWidth < 750;

                                          final tituloComentario = Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                comentarioSelecionadoId == null
                                                    ? Icons.add_comment_rounded
                                                    : Icons.edit_note_rounded,
                                                color: CoresApp.destaque,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                comentarioSelecionadoId == null
                                                    ? 'Novo comentário'
                                                    : 'Editar comentário',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoPrincipal,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          );

                                          final seletorEtiqueta = Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'ETIQUETAS DO CHAMADO',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              SizedBox(
                                                width: 160,
                                                height: 36,
                                                child: DropdownButtonFormField<
                                                    String>(
                                                  value: etiquetaSelecionada,
                                                  isExpanded: true,
                                                  isDense: true,
                                                  dropdownColor:
                                                      CoresTelas.fundoModal,
                                                  decoration: InputDecoration(
                                                    filled: true,
                                                    fillColor:
                                                        CoresTelas.fundoModal,
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: BorderSide(
                                                        color: CoresApp.borda,
                                                      ),
                                                    ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: BorderSide(
                                                        color: CoresApp.borda,
                                                      ),
                                                    ),
                                                    focusedBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: BorderSide(
                                                        color:
                                                            CoresApp.destaque,
                                                      ),
                                                    ),
                                                  ),
                                                  style: TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  items: etiquetasComentario
                                                      .map((etiqueta) {
                                                    return DropdownMenuItem<
                                                        String>(
                                                      value: etiqueta,
                                                      child: Text(etiqueta),
                                                    );
                                                  }).toList(),
                                                  onChanged: (salvando ||
                                                          testandoEdesk ||
                                                          enviandoEdesk)
                                                      ? null
                                                      : (value) async {
                                                          if (value == null)
                                                            return;

                                                          setDialogState(() {
                                                            etiquetaSelecionada =
                                                                value;
                                                            campoExcelSelecionado =
                                                                null;
                                                            imagemExcelBase64 =
                                                                null;
                                                          });

                                                          try {
                                                            await salvarEtiquetaProjeto(
                                                              value,
                                                            );
                                                          } catch (e) {
                                                            debugPrint(
                                                              'Erro ao salvar etiqueta E-Desk do projeto: $e',
                                                            );
                                                          }
                                                        },
                                                ),
                                              ),
                                            ],
                                          );

                                          final botaoHistorico = SizedBox(
                                            height: 36,
                                            child: OutlinedButton.icon(
                                              onPressed: (salvando ||
                                                      testandoEdesk ||
                                                      enviandoEdesk)
                                                  ? null
                                                  : () {
                                                      abrirHistoricoComentarios(
                                                        dialogContext,
                                                        setDialogState,
                                                      );
                                                    },
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    CoresApp.textoPrincipal,
                                                side: BorderSide(
                                                    color: CoresApp.borda),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12),
                                              ),
                                              icon: Icon(
                                                Icons.history_rounded,
                                                color: CoresApp.textoSecundario,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Histórico',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                            ),
                                          );

                                          if (compacto) {
                                            return Wrap(
                                              spacing: 10,
                                              runSpacing: 10,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.end,
                                              children: [
                                                tituloComentario,
                                                seletorEtiqueta,
                                                botaoHistorico,
                                              ],
                                            );
                                          }

                                          return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Expanded(child: tituloComentario),
                                              seletorEtiqueta,
                                              const SizedBox(width: 10),
                                              botaoHistorico,
                                            ],
                                          );
                                        },
                                      ),

                                      const SizedBox(height: 10),

                                      // Seção: Tipo + Imagem
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.end,
                                        children: [
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Tipo:',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontSize: 10,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              SizedBox(
                                                width: 170,
                                                height: 36,
                                                child: DropdownButtonFormField<
                                                    String>(
                                                  value: tipoComentario,
                                                  isDense: true,
                                                  isExpanded: true,
                                                  dropdownColor:
                                                      CoresTelas.fundoModal,
                                                  decoration: InputDecoration(
                                                    filled: true,
                                                    fillColor:
                                                        CoresTelas.fundoModal,
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: BorderSide(
                                                        color: CoresApp.borda,
                                                      ),
                                                    ),
                                                    enabledBorder:
                                                        OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      borderSide: BorderSide(
                                                        color: CoresApp.borda,
                                                      ),
                                                    ),
                                                  ),
                                                  style: TextStyle(
                                                    color:
                                                        CoresApp.textoPrincipal,
                                                    fontSize: 11,
                                                  ),
                                                  items: const [
                                                    DropdownMenuItem(
                                                      value: 'Interno',
                                                      child: Text('Interno'),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'Externo',
                                                      child: Text('Externo'),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'Padrão',
                                                      child: Text('Padrão'),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'Padrão (Interno)',
                                                      child: Text(
                                                          'Padrão (Interno)'),
                                                    ),
                                                  ],
                                                  onChanged: (salvando ||
                                                          testandoEdesk ||
                                                          enviandoEdesk)
                                                      ? null
                                                      : (value) {
                                                          if (value == null)
                                                            return;
                                                          setDialogState(() {
                                                            tipoComentario =
                                                                value;
                                                          });
                                                        },
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'USAR IMAGEM',
                                                style: TextStyle(
                                                  color:
                                                      CoresApp.textoSecundario,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  PopupMenuButton<
                                                      Map<String, String>>(
                                                    tooltip:
                                                        'Usar imagem do Excel',

                                                    enabled: !(salvando ||
                                                        testandoEdesk ||
                                                        enviandoEdesk ||
                                                        carregandoExcel),

                                                    color:
                                                        CoresTelas.fundoModal,
                                                    elevation: 12,

                                                    offset: const Offset(0, 42),

                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                      side: BorderSide(
                                                        color: CoresApp.borda,
                                                      ),
                                                    ),

                                                    onSelected: (campo) async {
                                                      final nome = campo['nome']
                                                              ?.trim() ??
                                                          '';
                                                      final intervalo = campo[
                                                                  'intervalo']
                                                              ?.trim()
                                                              .toUpperCase() ??
                                                          '';

                                                      if (intervalo.isEmpty) {
                                                        ScaffoldMessenger.of(
                                                                dialogContext)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: const Text(
                                                              'Este campo não possui um intervalo do Excel configurado.',
                                                            ),
                                                            backgroundColor:
                                                                CoresApp.erro,
                                                          ),
                                                        );

                                                        return;
                                                      }

                                                      setDialogState(() {
                                                        campoExcelSelecionado =
                                                            intervalo;

                                                        // Mantém as tabelas já adicionadas.
                                                        // Selecionar outro campo acrescenta uma nova imagem.
                                                      });

                                                      // No próximo bloco esta função será modificada
                                                      // para utilizar campoExcelSelecionado.
                                                      await carregarExcelProjeto(
                                                        dialogContext,
                                                        setDialogState,
                                                      );

                                                      debugPrint(
                                                        'Excel selecionado: $nome - $intervalo',
                                                      );
                                                    },

                                                    itemBuilder: (context) {
                                                      final campos =
                                                          camposExcelEtiquetaAtual();

                                                      // -------------------------------------------------------------
                                                      // NENHUM CAMPO CONFIGURADO
                                                      // -------------------------------------------------------------

                                                      if (campos.isEmpty) {
                                                        return [
                                                          PopupMenuItem<
                                                              Map<String,
                                                                  String>>(
                                                            enabled: false,
                                                            child: SizedBox(
                                                              width: 270,
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    Icons
                                                                        .info_outline_rounded,
                                                                    size: 17,
                                                                    color: CoresApp
                                                                        .textoSecundario,
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  Expanded(
                                                                    child: Text(
                                                                      'Nenhum campo do Excel configurado para "$etiquetaSelecionada".',
                                                                      style:
                                                                          TextStyle(
                                                                        color: CoresApp
                                                                            .textoSecundario,
                                                                        fontSize:
                                                                            10,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ];
                                                      }

                                                      // -------------------------------------------------------------
                                                      // CAMPOS CONFIGURADOS PARA A ETIQUETA
                                                      // -------------------------------------------------------------

                                                      return campos
                                                          .map((campo) {
                                                        final nome =
                                                            campo['nome']
                                                                    ?.trim() ??
                                                                '';
                                                        final intervalo = campo[
                                                                    'intervalo']
                                                                ?.trim()
                                                                .toUpperCase() ??
                                                            '';

                                                        return PopupMenuItem<
                                                            Map<String,
                                                                String>>(
                                                          value: campo,
                                                          child: SizedBox(
                                                            width: 270,
                                                            child: Row(
                                                              children: [
                                                                Container(
                                                                  width: 30,
                                                                  height: 30,
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: CoresApp
                                                                        .destaque
                                                                        .withOpacity(
                                                                            0.10),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(7),
                                                                  ),
                                                                  child: Icon(
                                                                    Icons
                                                                        .table_view_outlined,
                                                                    size: 16,
                                                                    color: CoresApp
                                                                        .destaque,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    width: 10),
                                                                Expanded(
                                                                  child: Column(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        nome.isEmpty
                                                                            ? 'Campo sem nome'
                                                                            : nome,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              CoresApp.textoPrincipal,
                                                                          fontSize:
                                                                              11,
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              2),
                                                                      Text(
                                                                        intervalo,
                                                                        style:
                                                                            TextStyle(
                                                                          color:
                                                                              CoresApp.textoSecundario,
                                                                          fontSize:
                                                                              9,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                                Icon(
                                                                  Icons
                                                                      .chevron_right_rounded,
                                                                  size: 17,
                                                                  color: CoresApp
                                                                      .textoSecundario,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        );
                                                      }).toList();
                                                    },

                                                    // ---------------------------------------------------------------
                                                    // APARÊNCIA DO BOTÃO
                                                    // ---------------------------------------------------------------

                                                    child: Container(
                                                      height: 38,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                        border: Border.all(
                                                          color: CoresApp.borda,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (carregandoExcel)
                                                            SizedBox(
                                                              width: 15,
                                                              height: 15,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: CoresApp
                                                                    .destaque,
                                                              ),
                                                            )
                                                          else
                                                            Icon(
                                                              Icons
                                                                  .table_view_outlined,
                                                              size: 16,
                                                              color: CoresApp
                                                                  .destaque,
                                                            ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Text(
                                                            carregandoExcel
                                                                ? 'Carregando Excel...'
                                                                : 'Usar imagem do Excel',
                                                            style: TextStyle(
                                                              color: CoresApp
                                                                  .textoPrincipal,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 7),
                                                          Icon(
                                                            Icons
                                                                .keyboard_arrow_down_rounded,
                                                            size: 17,
                                                            color: CoresApp
                                                                .textoSecundario,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  ElevatedButton.icon(
                                                    onPressed: (salvando ||
                                                            testandoEdesk ||
                                                            enviandoEdesk)
                                                        ? null
                                                        : () {
                                                            selecionarImagem(
                                                              dialogContext,
                                                              setDialogState,
                                                            );
                                                          },
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          CoresApp.destaque,
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                    ),
                                                    icon: const Icon(
                                                      Icons.image_outlined,
                                                      size: 16,
                                                    ),
                                                    label: const Text(
                                                      'Buscar imagem',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 10),

                                      // Descrição do comentário
                                      Row(
                                        children: [
                                          Text(
                                            'DESCRIÇÃO DO COMENTÁRIO',
                                            style: TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${comentarioController.text.length} / 2000',
                                            style: TextStyle(
                                              color: CoresApp.textoSecundario,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 5),

                                      // Editor de texto com barra de formatação (Toolbar) e campo de texto
                                      Expanded(
                                        child: Container(
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            color: CoresTelas.fundoModal,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: CoresApp.borda),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Column(
                                            children: [
                                              // =================================================
                                              // BARRA DE FORMATAÇÃO RICA
                                              // A formatação é aplicada ao bloco de texto atual.
                                              // Ao inserir uma tabela/imagem, o bloco é consolidado
                                              // mantendo fonte, tamanho e estilos escolhidos.
                                              // =================================================
                                              Container(
                                                height: 42,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8),
                                                decoration: BoxDecoration(
                                                  color:
                                                      CoresApp.fundoSecundario,
                                                  border: Border(
                                                      bottom: BorderSide(
                                                          color:
                                                              CoresApp.borda)),
                                                ),
                                                child: SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  child: Row(
                                                    children: [
                                                      SizedBox(
                                                        width: 135,
                                                        child: DropdownButton<
                                                            String>(
                                                          value:
                                                              fonteComentario,
                                                          isExpanded: true,
                                                          isDense: true,
                                                          underline:
                                                              const SizedBox
                                                                  .shrink(),
                                                          dropdownColor:
                                                              CoresTelas
                                                                  .fundoModal,
                                                          style: TextStyle(
                                                              color: CoresApp
                                                                  .textoPrincipal,
                                                              fontSize: 11),
                                                          items: const [
                                                            'Segoe UI',
                                                            'Arial',
                                                            'Calibri',
                                                            'Verdana',
                                                            'Tahoma',
                                                            'Times New Roman',
                                                            'Georgia',
                                                            'Courier New'
                                                          ]
                                                              .map((fonte) =>
                                                                  DropdownMenuItem(
                                                                      value:
                                                                          fonte,
                                                                      child: Text(
                                                                          fonte)))
                                                              .toList(),
                                                          onChanged: (v) {
                                                            if (v == null)
                                                              return;
                                                            setDialogState(() =>
                                                                fonteComentario =
                                                                    v);
                                                            comentarioFocusNode
                                                                .requestFocus();
                                                          },
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      SizedBox(
                                                        width: 62,
                                                        child: DropdownButton<
                                                            double>(
                                                          value:
                                                              tamanhoFonteComentario,
                                                          isExpanded: true,
                                                          isDense: true,
                                                          underline:
                                                              const SizedBox
                                                                  .shrink(),
                                                          dropdownColor:
                                                              CoresTelas
                                                                  .fundoModal,
                                                          style: TextStyle(
                                                              color: CoresApp
                                                                  .textoPrincipal,
                                                              fontSize: 11),
                                                          items: const [
                                                            9.0,
                                                            10.0,
                                                            11.0,
                                                            12.0,
                                                            14.0,
                                                            16.0,
                                                            18.0,
                                                            20.0,
                                                            24.0
                                                          ]
                                                              .map((t) =>
                                                                  DropdownMenuItem(
                                                                      value: t,
                                                                      child: Text(
                                                                          '${t.toInt()}')))
                                                              .toList(),
                                                          onChanged: (v) {
                                                            if (v == null)
                                                              return;
                                                            setDialogState(() =>
                                                                tamanhoFonteComentario =
                                                                    v);
                                                            comentarioFocusNode
                                                                .requestFocus();
                                                          },
                                                        ),
                                                      ),
                                                      const VerticalDivider(
                                                          width: 12,
                                                          indent: 8,
                                                          endIndent: 8),
                                                      PopupMenuButton<Color>(
                                                        tooltip: 'Cor da fonte',
                                                        initialValue:
                                                            corFonteComentario,
                                                        onSelected: (cor) {
                                                          setDialogState(() =>
                                                              corFonteComentario =
                                                                  cor);
                                                          comentarioFocusNode
                                                              .requestFocus();
                                                        },
                                                        itemBuilder:
                                                            (context) => const [
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFFF5F7FA),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFFF5F7FA),
                                                                  nome:
                                                                      'Branco')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFF000000),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFF000000),
                                                                  nome:
                                                                      'Preto')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFFE53935),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFFE53935),
                                                                  nome:
                                                                      'Vermelho')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFFFFB300),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFFFFB300),
                                                                  nome:
                                                                      'Amarelo')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFF43A047),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFF43A047),
                                                                  nome:
                                                                      'Verde')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFF1E88E5),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFF1E88E5),
                                                                  nome:
                                                                      'Azul')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFF8E24AA),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFF8E24AA),
                                                                  nome:
                                                                      'Roxo')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFF00ACC1),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFF00ACC1),
                                                                  nome:
                                                                      'Ciano')),
                                                          PopupMenuItem(
                                                              value: Color(
                                                                  0xFFFF7043),
                                                              child: _CorFonteItem(
                                                                  cor: Color(
                                                                      0xFFFF7043),
                                                                  nome:
                                                                      'Laranja')),
                                                        ],
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 7),
                                                          child: Column(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                  Icons
                                                                      .format_color_text,
                                                                  size: 17,
                                                                  color: CoresApp
                                                                      .textoSecundario),
                                                              Container(
                                                                  width: 17,
                                                                  height: 3,
                                                                  color:
                                                                      corFonteComentario),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      const VerticalDivider(
                                                          width: 12,
                                                          indent: 8,
                                                          endIndent: 8),
                                                      IconButton(
                                                        tooltip: 'Negrito',
                                                        icon: Icon(
                                                            Icons.format_bold,
                                                            size: 17,
                                                            color: negritoComentario
                                                                ? CoresApp
                                                                    .destaque
                                                                : CoresApp
                                                                    .textoSecundario),
                                                        onPressed: () {
                                                          setDialogState(() =>
                                                              negritoComentario =
                                                                  !negritoComentario);
                                                          comentarioFocusNode
                                                              .requestFocus();
                                                        },
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Itálico',
                                                        icon: Icon(
                                                            Icons.format_italic,
                                                            size: 17,
                                                            color: italicoComentario
                                                                ? CoresApp
                                                                    .destaque
                                                                : CoresApp
                                                                    .textoSecundario),
                                                        onPressed: () {
                                                          setDialogState(() =>
                                                              italicoComentario =
                                                                  !italicoComentario);
                                                          comentarioFocusNode
                                                              .requestFocus();
                                                        },
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Sublinhado',
                                                        icon: Icon(
                                                            Icons
                                                                .format_underlined,
                                                            size: 17,
                                                            color: sublinhadoComentario
                                                                ? CoresApp
                                                                    .destaque
                                                                : CoresApp
                                                                    .textoSecundario),
                                                        onPressed: () {
                                                          setDialogState(() =>
                                                              sublinhadoComentario =
                                                                  !sublinhadoComentario);
                                                          comentarioFocusNode
                                                              .requestFocus();
                                                        },
                                                      ),
                                                      IconButton(
                                                        tooltip: 'Tachado',
                                                        icon: Icon(
                                                            Icons
                                                                .format_strikethrough,
                                                            size: 17,
                                                            color: tachadoComentario
                                                                ? CoresApp
                                                                    .destaque
                                                                : CoresApp
                                                                    .textoSecundario),
                                                        onPressed: () {
                                                          setDialogState(() =>
                                                              tachadoComentario =
                                                                  !tachadoComentario);
                                                          comentarioFocusNode
                                                              .requestFocus();
                                                        },
                                                      ),
                                                      const VerticalDivider(
                                                          width: 12,
                                                          indent: 8,
                                                          endIndent: 8),
                                                      IconButton(
                                                        tooltip:
                                                            'Lista com marcadores',
                                                        icon: Icon(
                                                            Icons
                                                                .format_list_bulleted,
                                                            size: 17,
                                                            color: CoresApp
                                                                .textoSecundario),
                                                        onPressed: () {
                                                          final linhas =
                                                              comentarioController
                                                                  .text
                                                                  .split('\n');
                                                          comentarioController
                                                                  .text =
                                                              linhas
                                                                  .map((l) => l
                                                                          .trim()
                                                                          .isEmpty
                                                                      ? l
                                                                      : '• ${l.replaceFirst(RegExp(r'^[•-]\s*'), '')}')
                                                                  .join('\n');
                                                          comentarioController
                                                                  .selection =
                                                              TextSelection.collapsed(
                                                                  offset:
                                                                      comentarioController
                                                                          .text
                                                                          .length);
                                                          setDialogState(() {});
                                                        },
                                                      ),
                                                      IconButton(
                                                        tooltip:
                                                            'Lista numerada',
                                                        icon: Icon(
                                                            Icons
                                                                .format_list_numbered,
                                                            size: 17,
                                                            color: CoresApp
                                                                .textoSecundario),
                                                        onPressed: () {
                                                          final linhas =
                                                              comentarioController
                                                                  .text
                                                                  .split('\n');
                                                          var n = 0;
                                                          comentarioController
                                                                  .text =
                                                              linhas.map((l) {
                                                            if (l
                                                                .trim()
                                                                .isEmpty)
                                                              return l;
                                                            n++;
                                                            return '$n. ${l.replaceFirst(RegExp(r'^\d+\.\s*'), '')}';
                                                          }).join('\n');
                                                          comentarioController
                                                                  .selection =
                                                              TextSelection.collapsed(
                                                                  offset:
                                                                      comentarioController
                                                                          .text
                                                                          .length);
                                                          setDialogState(() {});
                                                        },
                                                      ),
                                                      const VerticalDivider(
                                                          width: 12,
                                                          indent: 8,
                                                          endIndent: 8),
                                                      IconButton(
                                                          tooltip:
                                                              'Alinhar à esquerda',
                                                          icon: Icon(
                                                              Icons
                                                                  .format_align_left,
                                                              size: 17,
                                                              color: alinhamentoComentario ==
                                                                      TextAlign
                                                                          .left
                                                                  ? CoresApp
                                                                      .destaque
                                                                  : CoresApp
                                                                      .textoSecundario),
                                                          onPressed: () =>
                                                              setDialogState(() =>
                                                                  alinhamentoComentario =
                                                                      TextAlign
                                                                          .left)),
                                                      IconButton(
                                                          tooltip:
                                                              'Centralizar',
                                                          icon: Icon(
                                                              Icons
                                                                  .format_align_center,
                                                              size: 17,
                                                              color: alinhamentoComentario ==
                                                                      TextAlign
                                                                          .center
                                                                  ? CoresApp
                                                                      .destaque
                                                                  : CoresApp
                                                                      .textoSecundario),
                                                          onPressed: () =>
                                                              setDialogState(() =>
                                                                  alinhamentoComentario =
                                                                      TextAlign
                                                                          .center)),
                                                      IconButton(
                                                          tooltip:
                                                              'Alinhar à direita',
                                                          icon: Icon(
                                                              Icons
                                                                  .format_align_right,
                                                              size: 17,
                                                              color: alinhamentoComentario ==
                                                                      TextAlign
                                                                          .right
                                                                  ? CoresApp
                                                                      .destaque
                                                                  : CoresApp
                                                                      .textoSecundario),
                                                          onPressed: () =>
                                                              setDialogState(() =>
                                                                  alinhamentoComentario =
                                                                      TextAlign
                                                                          .right)),
                                                      IconButton(
                                                          tooltip: 'Justificar',
                                                          icon: Icon(
                                                              Icons
                                                                  .format_align_justify,
                                                              size: 17,
                                                              color: alinhamentoComentario ==
                                                                      TextAlign
                                                                          .justify
                                                                  ? CoresApp
                                                                      .destaque
                                                                  : CoresApp
                                                                      .textoSecundario),
                                                          onPressed: () =>
                                                              setDialogState(() =>
                                                                  alinhamentoComentario =
                                                                      TextAlign
                                                                          .justify)),
                                                      const VerticalDivider(
                                                          width: 12,
                                                          indent: 8,
                                                          endIndent: 8),
                                                      IconButton(
                                                        tooltip:
                                                            'Inserir imagem',
                                                        icon: Icon(
                                                            Icons
                                                                .image_outlined,
                                                            size: 17,
                                                            color: CoresApp
                                                                .textoSecundario),
                                                        onPressed: () =>
                                                            selecionarImagem(
                                                                dialogContext,
                                                                setDialogState),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  child: ListView(
                                                    padding: EdgeInsets.zero,
                                                    children: [
                                                      if (carregandoExcel)
                                                        const Padding(
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  vertical: 8),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              SizedBox(
                                                                width: 18,
                                                                height: 18,
                                                                child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2),
                                                              ),
                                                              SizedBox(
                                                                  width: 8),
                                                              Text(
                                                                  'Adicionando nova tabela...'),
                                                            ],
                                                          ),
                                                        ),
                                                      if (!carregandoExcel &&
                                                          erroExcel != null)
                                                        Text(
                                                          erroExcel!,
                                                          style: TextStyle(
                                                            color:
                                                                CoresApp.erro,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      if (blocosComentario
                                                          .isNotEmpty) ...[
                                                        ...List.generate(
                                                          blocosComentario
                                                              .length,
                                                          (index) {
                                                            final bloco =
                                                                blocosComentario[
                                                                    index];
                                                            final tipo =
                                                                bloco['tipo'] ??
                                                                    '';
                                                            final valor = bloco[
                                                                    'valor'] ??
                                                                '';

                                                            if (tipo ==
                                                                'texto') {
                                                              return Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        bottom:
                                                                            8),
                                                                child: Align(
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  child:
                                                                      SizedBox(
                                                                    width: double
                                                                        .infinity,
                                                                    child: Text(
                                                                      valor,
                                                                      textAlign:
                                                                          alinhamentoDoBloco(
                                                                              bloco),
                                                                      style: estiloDoBloco(
                                                                          bloco),
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            }

                                                            return Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          8),
                                                              child: Stack(
                                                                children: [
                                                                  Container(
                                                                    constraints:
                                                                        const BoxConstraints(
                                                                      maxWidth:
                                                                          760,
                                                                      maxHeight:
                                                                          180,
                                                                      minHeight:
                                                                          80,
                                                                    ),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      border:
                                                                          Border
                                                                              .all(
                                                                        color: CoresApp
                                                                            .destaque
                                                                            .withOpacity(0.5),
                                                                      ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              6),
                                                                    ),
                                                                    child: Image
                                                                        .memory(
                                                                      base64Decode(
                                                                          valor),
                                                                      fit: BoxFit
                                                                          .contain,
                                                                    ),
                                                                  ),
                                                                  Positioned(
                                                                    top: 4,
                                                                    right: 4,
                                                                    child:
                                                                        IconButton(
                                                                      tooltip:
                                                                          'Remover esta tabela',
                                                                      onPressed:
                                                                          () {
                                                                        setDialogState(
                                                                            () {
                                                                          final removida =
                                                                              valor;
                                                                          blocosComentario
                                                                              .removeAt(index);
                                                                          imagensBase64
                                                                              .remove(removida);
                                                                          final indiceExcel =
                                                                              imagensExcelBase64.indexOf(removida);
                                                                          if (indiceExcel >=
                                                                              0) {
                                                                            imagensExcelBase64.removeAt(indiceExcel);
                                                                            if (indiceExcel <
                                                                                intervalosExcelAdicionados.length) {
                                                                              intervalosExcelAdicionados.removeAt(indiceExcel);
                                                                            }
                                                                          }
                                                                          imagemBase64 = imagensBase64.isNotEmpty
                                                                              ? imagensBase64.last
                                                                              : null;
                                                                          imagemExcelBase64 = imagensExcelBase64.isNotEmpty
                                                                              ? imagensExcelBase64.last
                                                                              : null;
                                                                        });
                                                                      },
                                                                      icon:
                                                                          const Icon(
                                                                        Icons
                                                                            .delete_outline,
                                                                        size:
                                                                            16,
                                                                        color: Colors
                                                                            .red,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                      TextField(
                                                        controller:
                                                            comentarioController,
                                                        focusNode:
                                                            comentarioFocusNode,
                                                        enabled:
                                                            !testandoEdesk &&
                                                                !enviandoEdesk,
                                                        keyboardType:
                                                            TextInputType
                                                                .multiline,
                                                        minLines: 5,
                                                        maxLines: null,
                                                        expands: false,
                                                        maxLength: 2000,
                                                        onChanged: (_) =>
                                                            setDialogState(
                                                                () {}),
                                                        textAlign:
                                                            alinhamentoComentario,
                                                        style: TextStyle(
                                                          color:
                                                              corFonteComentario,
                                                          fontSize:
                                                              tamanhoFonteComentario,
                                                          fontFamily:
                                                              fonteComentario,
                                                          fontWeight:
                                                              negritoComentario
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .normal,
                                                          fontStyle:
                                                              italicoComentario
                                                                  ? FontStyle
                                                                      .italic
                                                                  : FontStyle
                                                                      .normal,
                                                          decoration:
                                                              TextDecoration
                                                                  .combine([
                                                            if (sublinhadoComentario)
                                                              TextDecoration
                                                                  .underline,
                                                            if (tachadoComentario)
                                                              TextDecoration
                                                                  .lineThrough,
                                                          ]),
                                                        ),
                                                        decoration:
                                                            const InputDecoration(
                                                          counterText: '',
                                                          hintText:
                                                              'Digite sua resposta ou atualização para o E-Desk...',
                                                          border:
                                                              InputBorder.none,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 10),
                                      Divider(height: 1, color: CoresApp.borda),
                                      const SizedBox(height: 10),

                                      // Rodapé com botões de ação responsivos
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final bool compacto =
                                              constraints.maxWidth < 650;

                                          final botoesEsquerda = Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: (salvando ||
                                                        testandoEdesk ||
                                                        enviandoEdesk)
                                                    ? null
                                                    : () => limparFormulario(
                                                        setDialogState),
                                                icon: const Icon(
                                                    Icons.note_add_outlined,
                                                    size: 16),
                                                label: const Text('Novo',
                                                    style: TextStyle(
                                                        fontSize: 11)),
                                              ),
                                              ElevatedButton.icon(
                                                onPressed: (salvando ||
                                                        testandoEdesk ||
                                                        enviandoEdesk)
                                                    ? null
                                                    : () => salvarComentario(
                                                        dialogContext,
                                                        setDialogState),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      CoresApp.sucesso,
                                                  foregroundColor: Colors.white,
                                                ),
                                                icon: salvando
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .check_circle_rounded,
                                                        size: 16,
                                                      ),
                                                label: Text(
                                                  salvando
                                                      ? 'Salvando...'
                                                      : 'Salvar',
                                                  style: const TextStyle(
                                                      fontSize: 11),
                                                ),
                                              ),
                                            ],
                                          );

                                          final botoesDireita = Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: (salvando ||
                                                        testandoEdesk ||
                                                        enviandoEdesk)
                                                    ? null
                                                    : () => executarEdesk(
                                                          dialogContext:
                                                              dialogContext,
                                                          setDialogState:
                                                              setDialogState,
                                                          enviar: false,
                                                        ),
                                                icon: testandoEdesk
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.science_outlined,
                                                        size: 16,
                                                      ),
                                                label: Text(
                                                  testandoEdesk
                                                      ? 'Testando...'
                                                      : 'Testar',
                                                  style: const TextStyle(
                                                      fontSize: 11),
                                                ),
                                              ),
                                              ElevatedButton.icon(
                                                onPressed: (salvando ||
                                                        testandoEdesk ||
                                                        enviandoEdesk)
                                                    ? null
                                                    : () => executarEdesk(
                                                          dialogContext:
                                                              dialogContext,
                                                          setDialogState:
                                                              setDialogState,
                                                          enviar: true,
                                                        ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      CoresApp.destaque,
                                                  foregroundColor: Colors.white,
                                                ),
                                                icon: enviandoEdesk
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.send_rounded,
                                                        size: 16,
                                                      ),
                                                label: Text(
                                                  enviandoEdesk
                                                      ? 'Enviando...'
                                                      : 'Enviar para E-Desk',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );

                                          if (compacto) {
                                            return Wrap(
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                botoesEsquerda,
                                                botoesDireita,
                                              ],
                                            );
                                          }

                                          return Row(
                                            children: [
                                              botoesEsquerda,
                                              const Spacer(),
                                              botoesDireita,
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ===============================================================
                      // ALÇA DE REDIMENSIONAMENTO NO CANTO INFERIOR DIREITO
                      // ===============================================================

                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeDownRight,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setDialogState(() {
                                final novaLargura =
                                    larguraFinal + details.delta.dx;
                                final novaAltura =
                                    alturaFinal + details.delta.dy;

                                larguraCustomizada =
                                    novaLargura.clamp(400.0, tamanhoTela.width);
                                alturaCustomizada =
                                    novaAltura.clamp(350.0, tamanhoTela.height);
                              });
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: CoresApp.destaque.withOpacity(0.3),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomRight: Radius.circular(14),
                                ),
                              ),
                              child: Icon(
                                Icons.signal_cellular_null,
                                size: 12,
                                color: CoresApp.textoPrincipal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      comentarioController.dispose();
      comentarioFocusNode.dispose();
    });
  }

  String _formatarDataComentario(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final ano = data.year.toString();

    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    return '$dia/$mes/$ano $hora:$minuto';
  }

  int _tipoComentarioEdesk(String tipo) {
    switch (tipo) {
      case 'Interno':
        return 0;

      case 'Externo':
        return 1;

      case 'Padrão':
        return 3;

      case 'Padrão (Interno)':
        return 4;

      default:
        return 0;
    }
  }
}

class _CorFonteItem extends StatelessWidget {
  final Color cor;
  final String nome;

  const _CorFonteItem({required this.cor, required this.nome});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: cor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(width: 10),
        Text(nome),
      ],
    );
  }
}
