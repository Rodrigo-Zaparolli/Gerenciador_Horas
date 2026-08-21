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
  // INICIAR ESCUTA DOS LOGS DOS PROJETOS
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

    for (final projectId in projectIds) {
      final id = projectId.trim();

      if (id.isEmpty) {
        continue;
      }

      final subscription = _firestore
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(id)
          .collection('time_logs')
          .orderBy(
            'createdAt',
            descending: true,
          )
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
        final baseProjectId = log.targetId.split('_').first;

        return baseProjectId != projectId;
      },
    ).toList();

    final projectLogs = snapshot.docs.map(
      (doc) {
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
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots()
        .map(
      (snapshot) {
        return snapshot.docs.map(
          (doc) {
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
          },
        ).toList();
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
      throw Exception(
        'Usuário não autenticado.',
      );
    }

    final id = projectId.trim();

    if (id.isEmpty) {
      throw Exception(
        'ID do projeto inválido.',
      );
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

  Future<void> register(
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception(
        'Usuário não autenticado.',
      );
    }

    final projectId = log.targetId.split('_').first.trim();

    if (projectId.isEmpty) {
      throw Exception(
        'Não foi possível identificar o projeto do apontamento.',
      );
    }

    final logId = log.id.trim();

    if (logId.isEmpty) {
      final newId = await addFirebaseLog(
        projectId,
        log,
      );

      log.isRegistered = true;

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('projects')
          .doc(projectId)
          .collection('time_logs')
          .doc(newId)
          .update({
        'isRegistered': true,
        'registeredAt': FieldValue.serverTimestamp(),
      });

      return;
    }

    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('projects')
        .doc(projectId)
        .collection('time_logs')
        .doc(logId);

    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      await addFirebaseLog(
        projectId,
        log,
      );
    }

    await docRef.set(
      {
        'isRegistered': true,
        'registeredAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    log.isRegistered = true;

    notifyListeners();
  }

  // ============================================================
  // ATUALIZAR LOG
  // ============================================================

  Future<void> updateFirebaseLog(
    TimeLog log,
  ) async {
    final userId = _userId;

    if (userId == null || userId.trim().isEmpty) {
      throw Exception(
        'Usuário não autenticado.',
      );
    }

    final projectId = log.targetId.split('_').first.trim();

    if (projectId.isEmpty) {
      throw Exception(
        'Projeto inválido.',
      );
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
      throw Exception(
        'Usuário não autenticado.',
      );
    }

    final projectId = log.targetId.split('_').first.trim();

    if (projectId.isEmpty) {
      throw Exception(
        'Projeto inválido.',
      );
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

  void deleteLog(String s) {}

  void loadLogs() {}
}
