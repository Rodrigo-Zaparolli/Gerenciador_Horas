import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/platform/local_user_state.dart';
import '../../domain/models/dashboard_alert_preferences.dart';

/// Account preference only: never modifies projects, comments or deadlines.
class DashboardAlertPreferencesStore {
  DashboardAlertPreferencesStore(
    this.uid, {
    Future<Map<String, dynamic>?> Function()? readRemote,
    Future<void> Function(Map<String, dynamic>)? writeRemote,
    bool Function()? isCurrentAccount,
  })  : _readRemote = readRemote,
        _writeRemote = writeRemote,
        _isCurrentAccount = isCurrentAccount ??
            (() => FirebaseAuth.instance.currentUser?.uid == uid);

  static const feature = 'dashboard.alerts';
  final String uid;
  final Future<Map<String, dynamic>?> Function()? _readRemote;
  final Future<void> Function(Map<String, dynamic>)? _writeRemote;
  final bool Function() _isCurrentAccount;
  DocumentReference<Map<String, dynamic>> get _document =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('preferences')
          .doc('dashboard_alerts');

  DashboardAlertPreferences readLocal() =>
      DashboardAlertPreferences.fromJson(LocalUserState.read(uid, feature));

  bool cache(DashboardAlertPreferences value) =>
      LocalUserState.write(uid, feature, value.toJson());

  Future<DashboardAlertPreferences> load() async {
    final local = readLocal();
    if (!_isCurrentAccount()) return local;
    try {
      final data = await (_readRemote != null
              ? _readRemote()
              : _document.get().then((doc) => doc.data()))
          .timeout(const Duration(seconds: 5));
      // The caller decides whether a delayed read is still current.
      return data == null ? local : DashboardAlertPreferences.fromJson(data);
    } catch (_) {
      return local;
    }
  }

  /// Returns false if cloud sync fails; the owner's local copy is retained.
  Future<bool> save(DashboardAlertPreferences value) async {
    if (!_isCurrentAccount()) throw StateError('A conta mudou.');
    final localSaved = cache(value);
    try {
      final data = value.toJson();
      if (_writeRemote != null) {
        await _writeRemote(data).timeout(const Duration(seconds: 8));
      } else {
        await _document.set(
            {...data, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true)).timeout(const Duration(seconds: 8));
      }
      return true;
    } catch (_) {
      if (!localSaved)
        throw StateError('Não foi possível salvar as preferências.');
      return false;
    }
  }
}
