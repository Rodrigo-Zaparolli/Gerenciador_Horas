import 'dart:async';
import 'app_appearance.dart';

/// Restores the account choice without allowing a late read to undo a new choice.
class AccountThemeSync {
  AccountThemeSync(
      {required this.appearance, required this.read, required this.write}) {
    appearance.addListener(_changed);
  }
  final AppAppearance appearance;
  final Future<String?> Function(String uid) read;
  final Future<void> Function(String uid, String preference) write;
  String? _uid;
  int _generation = 0, _revision = 0;
  bool _restoring = false, _disposed = false;
  Future<void> _pending = Future.value();

  void _save(String uid, String preference) {
    _pending =
        _pending.then((_) => write(uid, preference)).catchError((Object _) {
      // Retain the browser preference and let the next choice retry storage.
    });
  }

  void _changed() {
    if (_restoring || _disposed) return;
    _revision++;
    final uid = _uid;
    if (uid != null) _save(uid, appearance.value.preference);
  }

  Future<void> bind(String? uid) async {
    _uid = uid;
    final generation = ++_generation;
    final revision = _revision;
    if (uid == null || _disposed) return;
    try {
      final saved = await read(uid);
      if (_disposed || generation != _generation || revision != _revision) {
        return;
      }
      final matches =
          AppVisualTheme.values.where((theme) => theme.preference == saved);
      if (matches.isNotEmpty) {
        _restoring = true;
        try {
          appearance.select(matches.first);
        } finally {
          _restoring = false;
        }
      } else if (saved == null && appearance.hasSavedPreference) {
        // Migrate an existing browser choice; never upload an unchosen default.
        _save(uid, appearance.value.preference);
      }
    } catch (_) {
      // A failed account read must not reset the theme or overwrite remote data.
    }
  }

  Future<void> get settled => _pending;
  void dispose() {
    _disposed = true;
    _generation++;
    appearance.removeListener(_changed);
  }
}
