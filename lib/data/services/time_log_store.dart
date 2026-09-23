import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

class TimeLogStore extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<TimeLog> _logs = [];

  List<TimeLog> get logs => List.unmodifiable(_logs);

  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _subscriptions = {};

  String? get _userId => _auth.currentUser?.uid;

  // ============================================================
  // AUXILIAR: IDENTIFICA O ID DO PROJETO DE UM LOG
  // ============================================================

  String _getProjectIdFromLog(TimeLog log) {
    final targetId = log.targetId.trim();

    if (targetId.isEmpty) {
      return '';
    }

    return targetId.split('_').first.trim();
  }

  // ============================================================
  // AUXILIAR: CONVERTE "HH:MM" PARA MINUTOS
  // ============================================================

  int _timeToMinutes(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');

      if (parts.length == 2) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;

        return (hours * 60) + minutes;
      }

      if (parts.length == 1) {
        final val = double.tryParse(parts[0].replaceAll(',', '.')) ?? 0.0;

        return (val * 60).round();
      }
    } catch (_) {}

    return 0;
  }

  // ============================================================
  // AUXILIAR: CONVERTE MINUTOS PARA "HH:MM"
  // ============================================================

  String _minutesToTime(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // MÉTODOS DE METAS ANUAIS E MENSAIS
  // ============================================================

  Future<Map<String, dynamic>?> carregarMetasAnuais(int ano) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return null;
    }

    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('metrics')
          .doc('yearly_$ano')
          .get();

      return doc.data();
    } catch (e) {
      debugPrint('Erro ao carregar metas anuais: $e');
      return null;
    }
  }

  Future<void> salvarMetaMensal(
    int ano,
    String mesIndex,
    String valor,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return;
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('metrics')
          .doc('yearly_$ano');

      final docSnapshot = await docRef.get();

      final Map<String, dynamic> dadosAtuais = docSnapshot.data() ?? {};

      dadosAtuais[mesIndex] = valor;

      int totalMinutesSum = 0;

      final List<String> mesesValidos = [
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
        '11',
        '12',
        'janeiro',
        'fevereiro',
        'março',
        'abril',
        'maio',
        'junho',
        'julho',
        'agosto',
        'setembro',
        'outubro',
        'novembro',
        'dezembro',
      ];

      dadosAtuais.forEach((key, val) {
        if (mesesValidos.contains(key.toLowerCase())) {
          final timeStr = val?.toString() ?? '00:00';

          totalMinutesSum += _timeToMinutes(timeStr);
        }
      });

      final String totalFormatado = _minutesToTime(totalMinutesSum);

      await docRef.set(
        {
          mesIndex: valor,
          'totalAnual': totalFormatado,
        },
        SetOptions(merge: true),
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Erro ao salvar meta mensal e atualizar total: $e',
      );
    }
  }

  Future<void> salvarMetasAnuaisCompleta(
    int ano,
    Map<String, dynamic> metasMensais,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('metrics')
          .doc('yearly_$ano');

      int totalMinutesSum = 0;

      final List<String> mesesValidos = [
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
        '11',
        '12',
        'janeiro',
        'fevereiro',
        'março',
        'abril',
        'maio',
        'junho',
        'julho',
        'agosto',
        'setembro',
        'outubro',
        'novembro',
        'dezembro',
      ];

      metasMensais.forEach((key, val) {
        if (mesesValidos.contains(key.toLowerCase())) {
          final timeStr = val?.toString() ?? '00:00';

          totalMinutesSum += _timeToMinutes(timeStr);
        }
      });

      final String totalFormatado = _minutesToTime(totalMinutesSum);

      final Map<String, dynamic> dadosCompletos = {
        ...metasMensais,
        'totalAnual': totalFormatado,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await docRef.set(
        dadosCompletos,
        SetOptions(merge: true),
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Erro ao salvar o conjunto completo de métricas anuais: $e',
      );

      rethrow;
    }
  }

  // ============================================================
  // CONVERTER DOCUMENTO FIRESTORE EM TIMELOG
  // ============================================================

  TimeLog _timeLogFromDocument(
    String projectId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    DateTime date = DateTime.now();

    final dynamic dateValue = data['date'];
    final dynamic createdAt = data['createdAt'];

    if (dateValue is Timestamp) {
      date = dateValue.toDate();
    } else if (createdAt is Timestamp) {
      date = createdAt.toDate();
    }

    double? hours;

    final dynamic rawHours = data['hours'];

    if (rawHours is num) {
      hours = rawHours.toDouble();
    } else {
      hours = double.tryParse(
        rawHours?.toString() ?? '',
      );
    }

    return TimeLog(
      id: doc.id,
      targetId: data['targetId']?.toString() ?? projectId,
      hours: hours,
      description: data['description']?.toString(),
      isRegistered: data['isRegistered'] == true,
      date: date,
      startTime: data['startTime']?.toString() ?? '',
      endTime: data['endTime']?.toString() ?? '',
      durationFormatted: data['durationFormatted']?.toString() ?? '',
      projectName: data['projectName']?.toString(),
      taskName: data['taskName']?.toString(),
      typeHs: data['typeHs']?.toString(),
    );
  }

  // ============================================================
  // BUSCAR TAMBÉM OS PROJETOS FINALIZADOS
  //
  // IMPORTANTE:
  //
  // O projeto finalizado é movido para:
  //
  // users/{uid}/completed_projects/{id}
  //
  // Mas os time_logs continuam em:
  //
  // users/{uid}/projects/{id}/time_logs
  //
  // Portanto precisamos descobrir os IDs dos projetos
  // finalizados e continuar lendo os time_logs no caminho
  // original.
  // ============================================================

  Future<Set<String>> _getCompletedProjectIds() async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return <String>{};
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('completed_projects')
          .get();

      return snapshot.docs
          .map((doc) {
            final data = doc.data();

            final String id = data['id']?.toString().trim() ?? '';

            if (id.isNotEmpty) {
              return id;
            }

            return doc.id.trim();
          })
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint(
        'TimeLogStore: erro ao buscar projetos finalizados: $e',
      );

      return <String>{};
    }
  }

  // ============================================================
  // INICIAR ESCUTA DOS LOGS DOS PROJETOS
  //
  // AGORA ESCUTA:
  //
  // 1. Projetos ativos
  // 2. Projetos finalizados
  //
  // Isso faz com que os horários não desapareçam quando o
  // projeto é movido para completed_projects.
  // ============================================================

  Future<void> startListeningToProjects(
    List<String> projectIds,
  ) async {
    await stopListening();

    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      debugPrint(
        'TimeLogStore: usuário não autenticado.',
      );
      return;
    }

    final Set<String> ids =
        projectIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();

    // ----------------------------------------------------------
    // ADICIONA PROJETOS FINALIZADOS
    // ----------------------------------------------------------

    final completedProjectIds = await _getCompletedProjectIds();

    ids.addAll(completedProjectIds);

    debugPrint(
      'TimeLogStore: iniciando escuta de '
      '${ids.length} projetos '
      '(${completedProjectIds.length} finalizados).',
    );

    // ----------------------------------------------------------
    // CRIA OS LISTENERS
    // ----------------------------------------------------------

    for (final id in ids) {
      final subscription = _firestore
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(id)
          .collection('time_logs')
          .snapshots()
          .listen(
        (snapshot) {
          _replaceProjectLogs(
            projectId: id,
            snapshot: snapshot,
          );
        },
        onError: (error) {
          debugPrint(
            'Erro ao escutar logs do projeto $id: $error',
          );
        },
      );

      _subscriptions[id] = subscription;
    }
  }

  // ============================================================
  // SUBSTITUIR OS LOGS DE UM PROJETO
  // ============================================================

  void _replaceProjectLogs({
    required String projectId,
    required QuerySnapshot<Map<String, dynamic>> snapshot,
  }) {
    final otherLogs = _logs.where(
      (log) {
        final baseProjectId = _getProjectIdFromLog(log);

        return baseProjectId != projectId;
      },
    ).toList();

    final projectLogs = snapshot.docs
        .map(
          (doc) => _timeLogFromDocument(
            projectId,
            doc,
          ),
        )
        .toList();

    projectLogs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    _logs = [
      ...otherLogs,
      ...projectLogs,
    ];

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  // ============================================================
  // CARREGAR LOGS DE UM PROJETO IMEDIATAMENTE
  // ============================================================

  Future<void> _loadProjectLogsIntoMemory(
    String projectId,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      return;
    }

    final id = projectId.trim();

    if (id.isEmpty) {
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(id)
          .collection('time_logs')
          .get();

      final projectLogs = snapshot.docs
          .map(
            (doc) => _timeLogFromDocument(
              id,
              doc,
            ),
          )
          .toList();

      final otherLogs = _logs.where(
        (log) {
          return _getProjectIdFromLog(log) != id;
        },
      ).toList();

      _logs = [
        ...otherLogs,
        ...projectLogs,
      ];

      _logs.sort(
        (a, b) => b.date.compareTo(a.date),
      );

      notifyListeners();
    } catch (e) {
      debugPrint(
        'Erro ao carregar logs do projeto $id: $e',
      );
    }
  }

  // ============================================================
  // STREAM INDIVIDUAL DE UM PROJETO
  // ============================================================

  Stream<List<TimeLog>> streamProjectTimeLogs(
    String userId,
    String projectId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(projectId)
        .collection('time_logs')
        .snapshots()
        .map(
      (snapshot) {
        final logs = snapshot.docs
            .map(
              (doc) => _timeLogFromDocument(
                projectId,
                doc,
              ),
            )
            .toList();

        logs.sort(
          (a, b) => b.date.compareTo(a.date),
        );

        return logs;
      },
    );
  }

  // ============================================================
  // SALVAR NOVO LOG
  // ============================================================

  Future<String> addFirebaseLog(
    String projectId,
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final id = projectId.trim();

    if (id.isEmpty) {
      throw Exception('ID do projeto inválido.');
    }

    final String logId = log.id.trim().isNotEmpty
        ? log.id.trim()
        : DateTime.now().microsecondsSinceEpoch.toString();

    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(id)
        .collection('time_logs')
        .doc(logId);

    await docRef.set(
      {
        'targetId': log.targetId,
        'projectId': id,
        'hours': log.hours,
        'description': log.description,
        'isRegistered': log.isRegistered,
        'date': Timestamp.fromDate(log.date),
        'startTime': log.startTime,
        'endTime': log.endTime,
        'durationFormatted': log.durationFormatted,
        'projectName': log.projectName,
        'taskName': log.taskName,
        'typeHs': log.typeHs,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return logId;
  }

  // ============================================================
  // CADASTRAR / REGISTRAR
  // ============================================================

  Future<void> register(TimeLog log) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final projectId = _getProjectIdFromLog(log);

    if (projectId.isEmpty) {
      throw Exception(
        'Não foi possível identificar o projeto do apontamento.',
      );
    }

    final logId = log.id.trim();

    String targetLogId = logId;

    if (logId.isEmpty) {
      log.isRegistered = true;

      targetLogId = await addFirebaseLog(
        projectId,
        log,
      );
    } else {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(projectId)
          .collection('time_logs')
          .doc(logId);

      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        log.isRegistered = true;

        targetLogId = await addFirebaseLog(
          projectId,
          log,
        );
      } else {
        await docRef.set(
          {
            'isRegistered': true,
            'registeredAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    }

    final index = _logs.indexWhere(
      (item) => item.id == targetLogId,
    );

    if (index != -1) {
      _logs[index].isRegistered = true;
    } else {
      log.isRegistered = true;
      _logs.add(log);
    }

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  // ============================================================
  // REGISTRAR TODOS OS APONTAMENTOS DO PROJETO
  // ============================================================

  Future<void> registerProjectLogs(
    String projectId,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final id = projectId.trim();

    if (id.isEmpty) {
      throw Exception('ID do projeto inválido.');
    }

    final collection = _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(id)
        .collection('time_logs');

    // ----------------------------------------------------------
    // 1. BUSCA TODOS OS LOGS
    // ----------------------------------------------------------

    final snapshot = await collection.get();

    debugPrint(
      'TimeLogStore: projeto $id possui '
      '${snapshot.docs.length} apontamentos.',
    );

    // ----------------------------------------------------------
    // 2. REGISTRA OS LOGS PENDENTES
    // ----------------------------------------------------------

    final pending = snapshot.docs.where(
      (doc) {
        final data = doc.data();

        return data['isRegistered'] != true;
      },
    ).toList();

    if (pending.isNotEmpty) {
      final batch = _firestore.batch();

      for (final doc in pending) {
        batch.set(
          doc.reference,
          {
            'isRegistered': true,
            'registeredAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();

      debugPrint(
        'TimeLogStore: ${pending.length} '
        'apontamentos registrados no projeto $id.',
      );
    }

    // ----------------------------------------------------------
    // 3. CARREGA NOVAMENTE PARA A MEMÓRIA
    // ----------------------------------------------------------

    await _loadProjectLogsIntoMemory(id);

    // ----------------------------------------------------------
    // 4. GARANTE REGISTRO LOCAL
    // ----------------------------------------------------------

    for (final log in _logs) {
      if (_getProjectIdFromLog(log) == id) {
        log.isRegistered = true;
      }
    }

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();

    debugPrint(
      'TimeLogStore: finalização do projeto $id concluída. '
      'Todos os horários estão registrados.',
    );
  }

  // ============================================================
  // ATUALIZAR LOG
  // ============================================================

  Future<void> updateFirebaseLog(
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final projectId = _getProjectIdFromLog(log);

    if (projectId.isEmpty) {
      throw Exception('Projeto inválido.');
    }

    if (log.id.trim().isEmpty) {
      throw Exception(
        'ID do apontamento inválido.',
      );
    }

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(projectId)
        .collection('time_logs')
        .doc(log.id)
        .set(
      {
        'targetId': log.targetId,
        'projectId': projectId,
        'hours': log.hours,
        'description': log.description,
        'isRegistered': log.isRegistered,
        'date': Timestamp.fromDate(log.date),
        'startTime': log.startTime,
        'endTime': log.endTime,
        'durationFormatted': log.durationFormatted,
        'projectName': log.projectName,
        'taskName': log.taskName,
        'typeHs': log.typeHs,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    update(log);
  }

  // ============================================================
  // EXCLUIR DO FIRESTORE
  // ============================================================

  Future<void> deleteFirebaseLog(
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception('Usuário não autenticado.');
    }

    final projectId = _getProjectIdFromLog(log);

    if (projectId.isEmpty) {
      throw Exception('Projeto inválido.');
    }

    if (log.id.trim().isEmpty) {
      throw Exception(
        'ID do apontamento inválido.',
      );
    }

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(projectId)
        .collection('time_logs')
        .doc(log.id)
        .delete();

    removeById(log.id);
  }

  // ============================================================
  // MEMÓRIA LOCAL
  // ============================================================

  void add(TimeLog log) {
    _logs.removeWhere(
      (item) => item.id == log.id,
    );

    _logs.add(log);

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  void update(TimeLog log) {
    final index = _logs.indexWhere(
      (item) => item.id == log.id,
    );

    if (index != -1) {
      _logs[index] = log;
    } else {
      _logs.add(log);
    }

    _logs.sort(
      (a, b) => b.date.compareTo(a.date),
    );

    notifyListeners();
  }

  void removeById(String id) {
    _logs.removeWhere(
      (log) => log.id == id,
    );

    notifyListeners();
  }

  void removeByTargetId(String targetId) {
    _logs.removeWhere(
      (log) => log.targetId == targetId,
    );

    notifyListeners();
  }

  // ============================================================
  // ENCERRAR STREAMS
  // ============================================================

  Future<void> stopListening() async {
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }

    _subscriptions.clear();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }

    _subscriptions.clear();

    super.dispose();
  }

  // ============================================================
  // COMPATIBILIDADE
  // ============================================================

  void deleteLog(String s) {}

  void loadLogs() {}
}
