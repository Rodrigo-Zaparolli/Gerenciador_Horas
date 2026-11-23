import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/account_theme_sync.dart';

void main() {
  test('every selectable theme survives a fresh application controller',
      () async {
    String? storage;
    for (final theme in [
      AppVisualTheme.light,
      AppVisualTheme.dark,
      AppVisualTheme.intermediate,
      AppVisualTheme.black,
      AppVisualTheme.petroleum,
      AppVisualTheme.ocean
    ]) {
      final first = AppAppearance(
          readPreference: () async => storage,
          writePreference: (value) async {
            storage = value;
          });
      first.select(theme);
      await Future<void>.delayed(Duration.zero);
      final reopened = AppAppearance(readPreference: () async => storage);
      await reopened.restore();
      expect(reopened.value, theme);
      first.dispose();
      reopened.dispose();
    }
  });
  test('late browser restore cannot replace a newly selected theme', () async {
    final pending = Completer<String?>();
    final appearance = AppAppearance(
        readPreference: () => pending.future, writePreference: (_) async {});
    final restoring = appearance.restore();
    appearance.select(AppVisualTheme.dark);
    pending.complete('light');
    await restoring;
    expect(appearance.value, AppVisualTheme.dark);
    appearance.dispose();
  });
  test('account restores theme after browser preference is missing', () async {
    final appearance = AppAppearance(
        readPreference: () async => null, writePreference: (_) async {});
    await appearance.restore();
    final writes = <String>[];
    final sync = AccountThemeSync(
        appearance: appearance,
        read: (_) async => 'dark',
        write: (_, value) async {
          writes.add(value);
        });
    await sync.bind('user');
    await sync.settled;
    expect(appearance.value, AppVisualTheme.dark);
    expect(writes, isEmpty);
    sync.dispose();
    appearance.dispose();
  });
  test('new choice wins over a pending account read and is stored', () async {
    final remote = Completer<String?>();
    final writes = <String>[];
    final appearance = AppAppearance(initialMode: AppVisualTheme.ocean,
        writePreference: (_) async {});
    final sync = AccountThemeSync(
        appearance: appearance,
        read: (_) => remote.future,
        write: (uid, value) async {
          writes.add('$uid:$value');
        });
    final binding = sync.bind('A');
    appearance.select(AppVisualTheme.ocean);
    remote.complete('light');
    await binding;
    await sync.settled;
    expect(appearance.value, AppVisualTheme.ocean);
    expect(writes, ['A:ocean']);
    sync.dispose();
    appearance.dispose();
  });
  test('switching accounts ignores a late theme from the previous account',
      () async {
    final old = Completer<String?>();
    final appearance = AppAppearance(writePreference: (_) async {});
    final sync = AccountThemeSync(
        appearance: appearance,
        read: (uid) => uid == 'A' ? old.future : Future.value('black'),
        write: (_, __) async {});
    final a = sync.bind('A');
    await sync.bind('B');
    old.complete('light');
    await a;
    expect(appearance.value, AppVisualTheme.black);
    sync.dispose();
    appearance.dispose();
  });
  test('migrates an existing browser choice but never an unchosen default',
      () async {
    final writes = <String>[];
    final appearance = AppAppearance(
        readPreference: () async => 'dark', writePreference: (_) async {});
    final sync = AccountThemeSync(
        appearance: appearance,
        read: (_) async => null,
        write: (_, v) async {
          writes.add(v);
        });
    await sync.bind('user');
    await sync.settled;
    expect(writes, isEmpty);
    await sync.bind(null);
    await appearance.restore();
    await sync.bind('user');
    await sync.settled;
    expect(writes, ['dark']);
    sync.dispose();
    appearance.dispose();
  });
  test(
      'failed read keeps current theme and failed write does not poison later saves',
      () async {
    final appearance = AppAppearance(
        initialMode: AppVisualTheme.dark, writePreference: (_) async {});
    final writes = <String>[];
    final sync = AccountThemeSync(
        appearance: appearance,
        read: (_) async => throw StateError('offline'),
        write: (_, value) async {
          writes.add(value);
          if (writes.length == 1) throw StateError('offline');
        });
    await sync.bind('user');
    expect(appearance.value, AppVisualTheme.dark);
    appearance.select(AppVisualTheme.black);
    appearance.select(AppVisualTheme.petroleum);
    await sync.settled;
    expect(writes, ['black', 'petroleum']);
    sync.dispose();
    appearance.dispose();
  });
}
