import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

void main() {
  testWidgets('compact menu cancels without navigation and preserves selection',
      (tester) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    UserCache()
      ..carregado = true
      ..userName = 'Fixture';
    addTearDown(() => UserCache().limparCache());
    final selections = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: Cabecalho(
          selectedIndex: 5,
          onSelectTab: selections.add,
          searchQuery: 'unchanged search',
          onSearchChanged: (_) => fail('Opening the menu changed the search'),
          userName: 'Fixture',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Navegação'));
    await tester.pumpAndSettle();
    final selectedTile = tester.widget<ListTile>(find.ancestor(
      of: find.text('Tarefas'),
      matching: find.byType(ListTile),
    ));
    expect(selectedTile.trailing, isA<Icon>());
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(selections, isEmpty);
    await tester.tap(find.byTooltip('Navegação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitações'));
    await tester.pumpAndSettle();
    expect(selections, [7]);
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dismissed header does not receive a late menu selection',
      (tester) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    UserCache()
      ..carregado = true
      ..userName = 'Fixture';
    addTearDown(() => UserCache().limparCache());
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final selections = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, showHeader, __) => Scaffold(
          appBar: showHeader
              ? Cabecalho(
                  selectedIndex: 0,
                  onSelectTab: selections.add,
                  searchQuery: '',
                  onSearchChanged: (_) {},
                  userName: 'Fixture',
                )
              : null,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Navegação'));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tarefas'));
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
