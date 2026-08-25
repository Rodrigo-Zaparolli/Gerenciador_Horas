import 'package:cloud_firestore/cloud_firestore.dart';

class TaskModel {
  String subId;
  String stage;
  String status;
  DateTime startDate;
  DateTime? planStart;
  DateTime? planEnd;
  String estimatedHours;
  String hourType;

  TaskModel({
    required this.subId,
    required this.stage,
    required this.status,
    required this.startDate,
    this.planStart,
    this.planEnd,
    required this.estimatedHours,
    required this.hourType,
  });

  // ============================================================
  // TO JSON
  // ============================================================

  Map<String, dynamic> toJson() {
    return {
      'subId': subId,
      'stage': stage,
      'status': status,
      'startDate': startDate.toIso8601String(),
      'planStart': planStart?.toIso8601String(),
      'planEnd': planEnd?.toIso8601String(),
      'estimatedHours': estimatedHours,
      'hourType': hourType,
    };
  }

  // ============================================================
  // PARSE DATE
  // ============================================================

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  // ============================================================
  // FROM JSON
  // ============================================================

  factory TaskModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final DateTime? parsedStart = _parseDate(
      json['startDate'],
    );

    final DateTime? parsedPlanStart = _parseDate(
      json['planStart'],
    );

    final DateTime? parsedPlanEnd = _parseDate(
      json['planEnd'],
    );

    return TaskModel(
      subId: json['subId']?.toString() ?? '',
      stage: json['stage']?.toString() ?? '',
      status: json['status']?.toString() ?? 'INI_PRO',
      startDate: parsedStart ?? DateTime.now(),
      planStart: parsedPlanStart,
      planEnd: parsedPlanEnd,
      estimatedHours: json['estimatedHours']?.toString() ?? '00:00',
      hourType: json['hourType']?.toString() ?? 'Hs Cobradas',
    );
  }
}

// ==================================================================
// PROJECT MODEL
// ==================================================================

class ProjectModel {
  String id;
  String id2;
  String client;
  String serviceType;
  String stage;
  String task;
  String status;
  DateTime startDate;
  String estimatedHours;
  String leader;
  String hourType;

  // Campo adicionado para a observação inline na tabela
  String? observacao;

  List<TaskModel>? subTasks;

  // Novo campo para armazenar os itens do Check List do projeto
  List<Map<String, dynamic>> checklist;
  String? excelLink;
  String? folderPath;

  ProjectModel({
    required this.id,
    required this.id2,
    required this.client,
    required this.serviceType,
    required this.stage,
    required this.task,
    required this.status,
    required this.startDate,
    required this.estimatedHours,
    required this.leader,
    required this.hourType,
    this.observacao,
    this.subTasks,
    this.checklist = const [],
    this.excelLink,
    this.folderPath,
  });

  // ============================================================
  // TO JSON
  // ============================================================

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id2': id2,
      'client': client,
      'serviceType': serviceType,
      'stage': stage,
      'task': task,
      'status': status,
      'startDate': startDate.toIso8601String(),
      'estimatedHours': estimatedHours,
      'leader': leader,
      'hourType': hourType,
      'observacao': observacao,
      'subTasks': subTasks
          ?.map(
            (task) => task.toJson(),
          )
          .toList(),
      'checklist': checklist, // Salva os itens do check list no Firebase
      'excelLink': excelLink,
      'folderPath': folderPath,
    };
  }

  // ============================================================
  // PARSE DATE
  // ============================================================

  static DateTime? _parseDate(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(
        value.trim(),
      );
    }

    return null;
  }

  // ============================================================
  // FROM JSON
  // ============================================================

  factory ProjectModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final DateTime? parsedStart = _parseDate(
      json['startDate'],
    );

    List<TaskModel> parsedSubTasks = [];

    final dynamic rawSubTasks = json['subTasks'] ?? json['subtasks'];

    if (rawSubTasks is List) {
      parsedSubTasks = rawSubTasks
          .whereType<Map>()
          .map(
            (task) => TaskModel.fromJson(
              Map<String, dynamic>.from(
                task,
              ),
            ),
          )
          .toList();
    }

    // Leitura segura do checklist vindo do Firebase
    List<Map<String, dynamic>> parsedChecklist = [];
    final dynamic rawChecklist = json['checklist'];
    if (rawChecklist is List) {
      parsedChecklist = rawChecklist
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return ProjectModel(
      id: json['id']?.toString() ?? '',
      id2: json['id2']?.toString() ?? '',
      client: json['client']?.toString() ?? '',
      serviceType: json['serviceType']?.toString() ?? '',
      stage: json['stage']?.toString() ?? '',
      task: json['task']?.toString() ?? '',
      status: json['status']?.toString() ?? 'INI_PRO',
      startDate: parsedStart ?? DateTime.now(),
      estimatedHours: json['estimatedHours']?.toString() ?? '00:00',
      leader: json['leader']?.toString() ?? '',
      hourType: json['hourType']?.toString() ?? 'Hs Cobradas',
      observacao: json['observacao']?.toString(),
      subTasks: parsedSubTasks,
      checklist: parsedChecklist, // Atribui os itens lidos
      excelLink: json['excelLink']?.toString(),
      folderPath: json['folderPath']?.toString(),
    );
  }
}
