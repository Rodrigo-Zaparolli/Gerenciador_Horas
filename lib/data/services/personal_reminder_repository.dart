import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/models/personal_reminder.dart';

abstract class PersonalReminderRepository {
  Stream<List<PersonalReminder>> watch();
  String newId();
  Future<void> save(PersonalReminder reminder, {String? expectedRevision});
  Future<void> complete(PersonalReminder reminder, bool done);
  Future<void> remove(PersonalReminder reminder);
  Future<void> acknowledge(List<PersonalReminder> reminders, DateTime now);
}

class FirebasePersonalReminders implements PersonalReminderRepository {
  FirebasePersonalReminders(this.uid, this.authorized,
      {FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;
  final String uid;
  final bool Function() authorized;
  final FirebaseFirestore db;
  CollectionReference<Map<String, dynamic>> get collection =>
      db.collection('users').doc(uid).collection('personal_reminders');
  void check() {
    if (!authorized())
      throw StateError('A conta mudou. Abra os lembretes novamente.');
  }

  @override
  String newId() => collection.doc().id;
  @override
  Stream<List<PersonalReminder>> watch() =>
      collection.snapshots().map((snapshot) {
        check();
        return [
          for (final doc in snapshot.docs)
            PersonalReminder.fromMap(doc.id, doc.data())
        ].whereType<PersonalReminder>().toList();
      });
  @override
  Future<void> save(PersonalReminder reminder,
      {String? expectedRevision}) async {
    check();
    if (reminder.title.trim().isEmpty ||
        reminder.title.length > 200 ||
        reminder.notes.length > 2000)
      throw StateError(
          'Preencha o título com até 200 caracteres e a observação com até 2000.');
    await db.runTransaction((transaction) async {
      check();
      final ref = collection.doc(reminder.id);
      final existing = await transaction.get(ref);
      check();
      if (existing.exists &&
          existing.data()?['revision'] == reminder.revision &&
          existing.data()?['title'] == reminder.title.trim() &&
          existing.data()?['day'] == reminderDayKey(reminder.day) &&
          existing.data()?['minuteOfDay'] == reminder.minuteOfDay &&
          existing.data()?['notes'] == reminder.notes.trim()) return;
      if (expectedRevision == null
          ? existing.exists
          : !existing.exists ||
              existing.data()?['revision'] != expectedRevision)
        throw StateError(
            'Este lembrete mudou. Feche e abra a edição novamente.');
      transaction.set(ref,
          {...reminder.toMap(), 'updatedAt': FieldValue.serverTimestamp()});
    }).timeout(const Duration(seconds: 20));
    check();
  }

  Future<void> mutate(
      PersonalReminder reminder, Map<String, dynamic>? changes) async {
    check();
    await db.runTransaction((transaction) async {
      check();
      final ref = collection.doc(reminder.id);
      final existing = await transaction.get(ref);
      check();
      if (!existing.exists) return;
      if (existing.data()?['revision'] != reminder.revision)
        throw StateError('O lembrete mudou. Confira a lista atualizada.');
      if (changes == null) {
        transaction.delete(ref);
      } else {
        transaction.update(ref, {
          ...changes,
          'revision': newId(),
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
    }).timeout(const Duration(seconds: 20));
    check();
  }

  @override
  Future<void> complete(PersonalReminder reminder, bool done) =>
      mutate(reminder, {'done': done, 'popupAcknowledgedOn': ''});
  @override
  Future<void> remove(PersonalReminder reminder) => mutate(reminder, null);
  @override
  Future<void> acknowledge(
      List<PersonalReminder> reminders, DateTime now) async {
    for (var offset = 0; offset < reminders.length; offset += 50) {
      final chunk = reminders.skip(offset).take(50).toList();
      check();
      await db.runTransaction((transaction) async {
        final docs = await Future.wait([
          for (final reminder in chunk)
            transaction.get(collection.doc(reminder.id))
        ]);
        check();
        for (var i = 0; i < chunk.length; i++) {
          if (docs[i].exists &&
              docs[i].data()?['revision'] == chunk[i].revision) {
            transaction.update(
                docs[i].reference, {'popupAcknowledgedOn': reminderDayKey(now)});
          }
        }
      }).timeout(const Duration(seconds: 20));
    }
  }
}
