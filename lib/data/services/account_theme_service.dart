import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/account_theme_sync.dart';
import '../../core/theme/app_appearance.dart';

/// One account-scoped preference, independent of project or spreadsheet data.
class AccountThemeService {
  static AccountThemeSync? _sync;
  static StreamSubscription<User?>? _subscription;

  static void start() {
    if (_subscription != null) return;
    final sync = _sync ??= AccountThemeSync(
      appearance: AppAppearance.instance,
      read: (uid) async {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('preferences')
            .doc('appearance')
            .get();
        final value = doc.data()?['theme'];
        return value is String ? value : null;
      },
      write: (uid, preference) async {
        if (FirebaseAuth.instance.currentUser?.uid != uid) return;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('preferences')
            .doc('appearance')
            .set({
          'theme': preference,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      },
    );
    _subscription = FirebaseAuth.instance.authStateChanges().listen(
          (user) => unawaited(sync.bind(user?.uid)),
          onError: (Object _) {},
        );
  }
}
