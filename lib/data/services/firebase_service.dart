// ignore_for_file: unnecessary_cast

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gerenciador_horas/domain/models/checklist_format_model.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/work_format_model.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ============================================================
  // USUÁRIO ATUAL
  // ============================================================

  String get _userId {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    return user.uid;
  }

  // ============================================================
  // REFERÊNCIA DOS PROJETOS ATIVOS
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _projectsRef {
    return _db.collection('users').doc(_userId).collection('projects');
  }

  // ============================================================
  // REFERÊNCIA DOS PROJETOS FINALIZADOS
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _completedProjectsRef {
    return _db
        .collection('users')
        .doc(_userId)
        .collection('completed_projects');
  }

  // ============================================================
  // REFERÊNCIA DOS MODELOS DE CHECKLIST (Por Utilizador)
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _checklistFormatsRef {
    return _db.collection('users').doc(_userId).collection('checklist_formats');
  }

  // ============================================================
  // CONVERSÃO DE DATA
  // ============================================================

  DateTime? _parseDate(dynamic value) {
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
      return DateTime.tryParse(value);
    }

    return null;
  }

  // ============================================================
  // CONVERTE SUBTASKS DO FIRESTORE
  // ============================================================

  List<TaskModel> _parseSubTasks(dynamic value) {
    if (value == null || value is! List) {
      return [];
    }

    final List<TaskModel> tasks = [];

    for (final item in value) {
      if (item is! Map) {
        continue;
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(item);

      final DateTime? startDate = _parseDate(data['startDate']);

      final DateTime? planStart = _parseDate(data['planStart']);

      final DateTime? planEnd = _parseDate(data['planEnd']);

      final TaskModel task = TaskModel(
        subId: data['subId']?.toString() ?? '',
        stage: data['stage']?.toString() ?? '',
        status: data['status']?.toString() ?? 'INI_PRO',
        startDate: startDate ?? planStart ?? DateTime.now(),
        planStart: planStart,
        planEnd: planEnd,
        estimatedHours: data['estimatedHours']?.toString() ??
            data['workedHours']?.toString() ??
            data['horasTrabalhadas']?.toString() ??
            '00:00',
        hourType: data['hourType']?.toString() ?? 'Hs Cobradas',
      );

      tasks.add(task);
    }

    return tasks;
  }

  // ============================================================
  // FIRESTORE -> PROJECT MODEL
  // ============================================================

  ProjectModel _projectFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

    final DateTime projectStartDate =
        _parseDate(data['startDate']) ?? DateTime.now();

    final List<TaskModel> subTasks = _parseSubTasks(data['subTasks']);

    final String resolvedHours = data['estimatedHours']?.toString() ??
        data['workedHours']?.toString() ??
        data['horasTrabalhadas']?.toString() ??
        data['timeSpent']?.toString() ??
        '00:00';

    List<Map<String, dynamic>> parsedChecklist = [];
    final dynamic rawChecklist = data['checklist'];
    if (rawChecklist is List) {
      parsedChecklist = rawChecklist
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return ProjectModel(
      id: data['id']?.toString() ?? doc.id,
      id2: data['id2']?.toString() ?? '0',
      client: data['client']?.toString() ?? '',
      serviceType: data['serviceType']?.toString() ?? '',
      stage: data['stage']?.toString() ?? '',
      task: data['task']?.toString() ?? '',
      status: data['status']?.toString() ?? 'INI_PRO',
      startDate: projectStartDate,
      estimatedHours: resolvedHours,
      leader: data['leader']?.toString() ?? '',
      hourType: data['hourType']?.toString() ?? 'Hs Cobradas',
      subTasks: subTasks,
      checklist: parsedChecklist,
      observacao: data['observacao']?.toString(),
      excelLink: data['excelLink']?.toString(),
      folderPath: data['folderPath']?.toString(),
    );
  }

  // ============================================================
  // BUSCAR PROJETOS
  // ============================================================

  Future<List<ProjectModel>> getProjects() async {
    final snapshot = await _projectsRef.get();

    return snapshot.docs
        .map(
          (doc) => _projectFromFirestore(doc),
        )
        .toList();
  }

  // ============================================================
  // STREAM DE PROJETOS ATIVOS
  // ============================================================

  Stream<List<ProjectModel>> getProjectsStream() {
    return _projectsRef.snapshots().map(
      (snapshot) {
        return snapshot.docs
            .map(
              (doc) => _projectFromFirestore(doc),
            )
            .toList();
      },
    );
  }

  // ============================================================
  // BUSCAR UM PROJETO
  // ============================================================

  Future<ProjectModel?> getProject(
    String projectId,
  ) async {
    final doc = await _projectsRef.doc(projectId).get();

    if (!doc.exists) {
      return null;
    }

    return _projectFromFirestore(doc);
  }

  // ============================================================
  // SALVAR / ATUALIZAR PROJETO
  // ============================================================

  Future<void> saveProject(
    ProjectModel project, [
    String? docId,
  ]) async {
    final String targetDocId = (docId != null && docId.trim().isNotEmpty)
        ? docId.trim()
        : project.id.trim();

    if (targetDocId.isEmpty) {
      throw Exception(
        'Não foi possível salvar o projeto: ID vazio.',
      );
    }

    if (project.status == 'TRAB_FIM') {
      await finalizarProjeto(
        project,
        docId: targetDocId,
      );

      return;
    }

    final Map<String, dynamic> data = project.toJson();
    data['id'] = project.id;
    data['estimatedHours'] = project.estimatedHours;
    data['workedHours'] = project.estimatedHours;
    data['horasTrabalhadas'] = project.estimatedHours;

    await _projectsRef.doc(targetDocId).set(
          data,
          SetOptions(merge: true),
        );
  }

  // ============================================================
  // ADICIONAR APONTAMENTO DE HORAS (SUBCOLEÇÃO 'time_entries')
  // ============================================================

  Future<void> addTimeEntry({
    required String projectId,
    required String hours,
    required String description,
    DateTime? date,
  }) async {
    final String idTrimmed = projectId.trim();
    if (idTrimmed.isEmpty) {
      throw Exception('ID do projeto inválido para apontamento de horas.');
    }

    final entryRef = _projectsRef.doc(idTrimmed).collection('time_entries');

    await entryRef.add({
      'hours': hours,
      'description': description,
      'date': date ?? FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // BUSCAR APONTAMENTOS DE HORAS DE UM PROJETO
  // ============================================================

  Future<List<Map<String, dynamic>>> getTimeEntries(String projectId) async {
    final String idTrimmed = projectId.trim();
    if (idTrimmed.isEmpty) return [];

    final snapshot = await _projectsRef
        .doc(idTrimmed)
        .collection('time_entries')
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      return {
        'id': doc.id,
        ...doc.data(),
      };
    }).toList();
  }

  // ============================================================
  // ATUALIZAR APENAS AS HORAS TRABALHADAS DE UM PROJETO
  // ============================================================

  Future<void> atualizarHorasProjeto(
      String projectId, String novasHoras) async {
    final String idTrimmed = projectId.trim();
    if (idTrimmed.isEmpty) {
      throw Exception('ID do projeto inválido para atualizar horas.');
    }

    await _projectsRef.doc(idTrimmed).update({
      'estimatedHours': novasHoras,
      'workedHours': novasHoras,
      'horasTrabalhadas': novasHoras,
    });
  }

  // ============================================================
  // FINALIZAR / MOVER PROJETO
  // ============================================================

  Future<void> finalizarProjeto(
    ProjectModel project, {
    String? docId,
  }) async {
    final String projectId = (docId != null && docId.trim().isNotEmpty)
        ? docId.trim()
        : project.id.trim();

    if (projectId.isEmpty) {
      throw Exception(
        'Não foi possível finalizar o projeto: ID vazio.',
      );
    }

    project.status = 'TRAB_FIM';

    final Map<String, dynamic> completedData = project.toJson();
    completedData['id'] = project.id;
    completedData['status'] = 'TRAB_FIM';
    completedData['estimatedHours'] = project.estimatedHours;
    completedData['workedHours'] = project.estimatedHours;
    completedData['horasTrabalhadas'] = project.estimatedHours;
    completedData['finalizedAt'] = FieldValue.serverTimestamp();
    completedData['sourceCollection'] = 'projects';

    final DocumentReference<Map<String, dynamic>> activeProjectRef =
        _projectsRef.doc(projectId);

    final DocumentReference<Map<String, dynamic>> completedProjectRef =
        _completedProjectsRef.doc(projectId);

    final WriteBatch batch = _db.batch();

    batch.set(
      completedProjectRef,
      completedData,
      SetOptions(merge: true),
    );

    batch.delete(activeProjectRef);

    await batch.commit();

    final DocumentSnapshot<Map<String, dynamic>> activeCheck =
        await activeProjectRef.get();

    if (activeCheck.exists) {
      await activeProjectRef.delete();
    }
  }

  // ============================================================
  // EXCLUIR PROJETO ATIVO
  // ============================================================

  Future<void> deleteProject(
    String docId,
  ) async {
    await _projectsRef.doc(docId).delete();
  }

  // ============================================================
  // WORK FORMATS
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _workFormatsRef {
    return _db.collection('users').doc(_userId).collection('work_formats');
  }

  Future<List<WorkFormat>> getWorkFormats() async {
    final snapshot = await _workFormatsRef.get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      final dynamic rawSteps = data['steps'];
      final List<String> normalizedSteps = [];

      if (rawSteps is List) {
        for (final step in rawSteps) {
          if (step is String) {
            final value = step.trim();
            if (value.isNotEmpty) {
              normalizedSteps.add(value);
            }
          } else if (step is Map) {
            final Map<String, dynamic> map = Map<String, dynamic>.from(step);
            final dynamic name = map['name'] ??
                map['stage'] ??
                map['title'] ??
                map['descricao'] ??
                map['description'];

            if (name != null) {
              final value = name.toString().trim();
              if (value.isNotEmpty) {
                normalizedSteps.add(value);
              }
            }
          } else {
            final value = step.toString().trim();
            if (value.isNotEmpty) {
              normalizedSteps.add(value);
            }
          }
        }
      }

      return WorkFormat(
        id: doc.id,
        name: data['name']?.toString() ?? '',
        steps: normalizedSteps,
      );
    }).toList();
  }

  Future<void> saveWorkFormat(
    WorkFormat format,
  ) async {
    final List<String> normalizedSteps = [];

    for (final step in format.steps) {
      if (step is String) {
        final value = step.trim();
        if (value.isNotEmpty) {
          normalizedSteps.add(value);
        }
      } else if (step is Map) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(step);
        final dynamic name = map['name'] ??
            map['stage'] ??
            map['title'] ??
            map['descricao'] ??
            map['description'];

        if (name != null) {
          final value = name.toString().trim();
          if (value.isNotEmpty) {
            normalizedSteps.add(value);
          }
        }
      } else {
        final value = step.toString().trim();
        if (value.isNotEmpty) {
          normalizedSteps.add(value);
        }
      }
    }

    await _workFormatsRef.doc(format.id).set(
      {
        'id': format.id,
        'name': format.name,
        'steps': normalizedSteps,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteWorkFormat(
    String id,
  ) async {
    await _workFormatsRef.doc(id).delete();
  }

  // ============================================================
  // MÉTRICAS
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _metricsRef {
    return _db.collection('users').doc(_userId).collection('metrics');
  }

  Future<void> saveUserMetrics(
    Map<String, dynamic> data,
  ) async {
    await _metricsRef.doc('yearly_data').set(
          data,
          SetOptions(merge: true),
        );
  }

  Future<Map<String, dynamic>?> getUserMetrics() async {
    final doc = await _metricsRef.doc('yearly_data').get();
    return doc.data();
  }

  // ============================================================
  // ORIENTAÇÕES
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _orientacoesRef {
    return _db.collection('users').doc(_userId).collection('orientacoes');
  }

  Future<List<Map<String, dynamic>>> getOrientacoes() async {
    final snapshot = await _orientacoesRef.get();

    return snapshot.docs.map(
      (doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      },
    ).toList();
  }

  Future<void> saveOrientacao(
    String id,
    Map<String, dynamic> data,
  ) async {
    await _orientacoesRef.doc(id).set(
          data,
          SetOptions(merge: true),
        );
  }

  Future<void> deleteOrientacao(
    String id,
  ) async {
    await _orientacoesRef.doc(id).delete();
  }

  // ============================================================
  // PROJETOS FINALIZADOS
  // ============================================================

  Stream<List<Map<String, dynamic>>> getCompletedProjectsStream() {
    return _completedProjectsRef.snapshots().map(
      (snapshot) {
        return snapshot.docs.map(
          (doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              ...data,
            };
          },
        ).toList();
      },
    );
  }

  Future<List<Map<String, dynamic>>> getCompletedProjects() async {
    final snapshot = await _completedProjectsRef.get();

    return snapshot.docs.map(
      (doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
        };
      },
    ).toList();
  }

  Future<void> saveCompletedProject(
    String id,
    Map<String, dynamic> data,
  ) async {
    if (id.trim().isEmpty) {
      throw Exception(
        'Não foi possível salvar projeto finalizado: ID vazio.',
      );
    }

    final Map<String, dynamic> completedData = Map<String, dynamic>.from(data);

    completedData['id'] = id;
    completedData['status'] = 'TRAB_FIM';

    if (!completedData.containsKey('finalizedAt')) {
      completedData['finalizedAt'] = FieldValue.serverTimestamp();
    }

    await _completedProjectsRef.doc(id).set(
          completedData,
          SetOptions(merge: true),
        );

    await _projectsRef.doc(id).delete();
  }

  Future<void> deleteCompletedProject(
    String id,
  ) async {
    await _completedProjectsRef.doc(id).delete();
  }

  // ============================================================
  // REABRIR / REVERTER PROJETO FINALIZADO
  // ============================================================

  Future<void> reopenCompletedProject(
    String projectId,
  ) async {
    if (projectId.trim().isEmpty) {
      throw Exception('ID do projeto inválido.');
    }

    final String id = projectId.trim();

    final completedRef = _completedProjectsRef.doc(id);
    final completedSnapshot = await completedRef.get();

    if (!completedSnapshot.exists) {
      throw Exception(
        'O projeto $id não foi encontrado em projetos finalizados.',
      );
    }

    final Map<String, dynamic> completedData = Map<String, dynamic>.from(
      completedSnapshot.data() ?? <String, dynamic>{},
    );

    final dynamic savedPreviousStatus = completedData['statusBeforeCompletion'];

    final String previousStatus =
        savedPreviousStatus?.toString().trim().isNotEmpty == true
            ? savedPreviousStatus.toString()
            : 'TRAB';

    completedData['status'] = previousStatus;
    completedData.remove('finalizedAt');
    completedData.remove('statusBeforeCompletion');
    completedData['sourceCollection'] = 'projects';
    completedData['reopenedAt'] = FieldValue.serverTimestamp();

    final projectRef = _projectsRef.doc(id);
    final batch = _db.batch();

    batch.set(
      projectRef,
      completedData,
      SetOptions(merge: false),
    );

    batch.delete(completedRef);

    await batch.commit();
  }

  // ============================================================
  // CHECKLIST FORMATS (Modelos Globais de Check List)
  // ============================================================

  Future<List<ChecklistFormat>> getChecklistFormats() async {
    try {
      final snapshot = await _checklistFormatsRef.get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ChecklistFormat.fromJson(data, doc.id);
      }).toList();
    } catch (e) {
      print('Erro ao buscar modelos de check list: $e');
      return [];
    }
  }

  Future<void> saveChecklistFormat(ChecklistFormat format) async {
    try {
      await _checklistFormatsRef
          .doc(format.id)
          .set(format.toJson(), SetOptions(merge: true));
    } catch (e) {
      print('Erro ao salvar modelo de check list: $e');
      rethrow;
    }
  }

  Future<void> deleteChecklistFormat(String id) async {
    try {
      await _checklistFormatsRef.doc(id).delete();
    } catch (e) {
      print('Erro ao excluir modelo de check list: $e');
      rethrow;
    }
  }

  // ============================================================
  // ALIASES & EXTRAS
  // ============================================================

  Future<void> salvarProjeto(
    ProjectModel project, [
    String? docId,
  ]) async {
    await saveProject(
      project,
      docId,
    );
  }

  Future<void> excluirProjeto(String id) async {
    await _projectsRef.doc(id).delete();
    await _completedProjectsRef.doc(id).delete();
  }

  Future<void> deleteTimeLog(String s) async {}
}
