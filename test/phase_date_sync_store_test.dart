import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'received_work_store_test.dart'
    show ImportAuth, ImportDatabase, ImportTransaction;
import 'backup_restore_test.dart' show MemorySnapshot;

class PhaseDatabase extends ImportDatabase {
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> handler,
      {Duration timeout = const Duration(seconds: 30),
      int maxAttempts = 5}) async {
    final transaction = PhaseTransaction(this);
    final result = await handler(transaction);
    documents.addAll(transaction.pending);
    return result;
  }
}

class PhaseSnapshot extends MemorySnapshot {
  PhaseSnapshot(super.value, this.reference);
  @override
  final DocumentReference<Map<String, dynamic>> reference;
  @override
  String get id => reference.id;
}

class PhaseTransaction extends ImportTransaction {
  PhaseTransaction(super.db);
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
      DocumentReference<T> reference) async {
    expect(pending, isEmpty);
    return PhaseSnapshot(db.documents[reference.path],
            reference as DocumentReference<Map<String, dynamic>>)
        as DocumentSnapshot<T>;
  }
}

void main() {
  for (final legacy in [false, true]) {
    test(
        'transaction saves selected Rimo dates and preserves links; legacy=$legacy',
        () async {
      final db = PhaseDatabase();
      const path = 'users/owner/projects/2265173';
      final other = {
        'subId': '5',
        'stage': 'Acompanhamento',
        'estimatedHours': '09:00'
      };
      db.documents[path] = {
        if (!legacy) 'id': '2265173',
        'client': 'Rimo',
        'excelLink': 'same workbook',
        'folderPath': 'same folder',
        'subTasks': [
          {
            'subId': '4',
            'stage': 'Treinamento Catalog (OH)',
            'planStart': '2026-10-06T00:00:00.000',
            'planEnd': '2026-10-26T00:00:00.000',
            'status': 'TRAB_FIM',
            'estimatedHours': '32:00'
          },
          other
        ]
      };
      await FirebaseService(database: db, auth: ImportAuth())
          .applyAuditedPhaseDates(
              ownerUid: 'owner',
              projectId: '2265173',
              request: '2265173',
              work: '4',
              phase: 'Treinamento Catalog (OH)',
              expectedStart: '06/10/2026',
              expectedEnd: '26/10/2026',
              start: DateTime(2026, 10, 6),
              end: DateTime(2026, 10, 30));
      final saved = db.documents[path]!;
      expect(saved['excelLink'], 'same workbook');
      expect(saved['folderPath'], 'same folder');
      expect(saved['subTasks'][0]['planEnd'], '2026-10-30T00:00:00.000');
      expect(saved['subTasks'][0]['status'], 'TRAB_FIM');
      expect(saved['subTasks'][0]['estimatedHours'], '32:00');
      expect(saved['subTasks'][1], other);
      expect(db.documents.keys, [path]);
    });
  }
}
