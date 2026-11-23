import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/data/services/project_update_service.dart';
import 'package:gerenciador_horas/domain/models/deadline_alert.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/dashboard_alerts_modal.dart';
import 'package:gerenciador_horas/features/dashboard/widgets/dashboard_alert_widgets.dart';
import 'dashboard_cards_test.dart' as fixture;

void main() {
  final day = DateTime(2026, 11, 21);
  DeadlineAlert deadline(String id, String client, int difference) =>
      DeadlineAlert(
          id: id,
          id2: '2',
          client: client,
          serviceType: 'Consultoria',
          stage: 'Implantação',
          planStart: day,
          planEnd: day.add(Duration(days: difference)),
          status: 'INI_PRO',
          differenceDays: difference);
  final deadlines = [
    deadline('1', 'Cliente Zeta', 5),
    deadline('2', 'Cliente Alfa', -3),
    deadline('3', 'Cliente Beta', 3)
  ];
  final projectA = fixture.project([])
    ..id = '4'
    ..client = 'Cliente Delta';
  final projectB = fixture.project([])
    ..id = '5'
    ..client = 'Cliente Gama';
  final updates = [
    PendingProjectUpdate(
        projectA, ProjectCommentUpdate('a', DateTime(2026, 11, 5), ''), day),
    PendingProjectUpdate(
        projectB, ProjectCommentUpdate('b', DateTime(2026, 11, 7), ''), day)
  ];

  Future<void> open(WidgetTester tester,
      {bool unavailable = false,
      bool empty = false,
      ValueChanged<String?>? result,
      Key? capture}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppAppearance.instance.value = AppVisualTheme.dark;
    addTearDown(() => AppAppearance.instance.value = AppVisualTheme.light);
    await tester.pumpWidget(RepaintBoundary(
        key: capture,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          final value = await DashboardAlertsModal.show(context,
                              empty ? [] : deadlines, empty ? [] : updates,
                              updatesUnavailable: unavailable);
                          result?.call(value);
                        },
                        child: const Text('Abrir')))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'counts preserve overlap; overdue filter and categories do not change source records',
      (tester) async {
    await open(tester);
    expect(
        tester.widgetList<SizedBox>(find.byType(SizedBox)).any(
            (box) => box.width == 1180 && box.height == 700),
        isTrue);
    expect(tester.getSize(find.byType(AlertSummaryCard).first).height,
        lessThanOrEqualTo(105));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('alerts-header')),
            matching: find.byType(AlertSummaryCard)),
        findsNWidgets(3));
    expect(find.text('5 pendências precisam de atenção'), findsOneWidget);
    final cards = tester
        .widgetList<AlertSummaryCard>(find.byType(AlertSummaryCard))
        .toList();
    expect(cards.map((c) => c.count), ['2', '3', '2']);
    expect(find.byType(AlertListEntry), findsNWidgets(5));
    await tester.tap(find.text('Em atraso'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertListEntry), findsNWidgets(2));
    await tester.tap(find.text('Em atraso'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertListEntry), findsNWidgets(5));
    await tester.tap(find.text('Prazos de projetos e etapas (3)'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertListEntry), findsNWidgets(2));
    await tester.tap(find.text('Prazos de projetos e etapas (3)'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertListEntry), findsNWidgets(5));
    expect(deadlines.map((e) => e.id), ['1', '2', '3']);
    expect(updates.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sort, filter menu and requests action retain contracts',
      (tester) async {
    String? result;
    await open(tester, result: (value) => result = value);
    await tester.tap(find.text('Mais urgentes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente (A–Z)').last);
    await tester.pumpAndSettle();
    final entries =
        tester.widgetList<AlertListEntry>(find.byType(AlertListEntry)).toList();
    expect(entries.take(3).map((e) => e.title),
        ['Cliente Alfa - 2', 'Cliente Beta - 3', 'Cliente Zeta - 1']);
    await tester.tap(find.byTooltip('Filtrar alertas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem &&
        widget.child is Text &&
        (widget.child as Text).data == 'Comentários'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertListEntry), findsNWidgets(2));
    await tester.tap(find.text('Ver solicitações'));
    await tester.pumpAndSettle();
    expect(result, 'requests');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable comments remain unknown rather than confirmed zero',
      (tester) async {
    await open(tester, unavailable: true, empty: true);
    expect(find.text('Comentários ainda não consultados'), findsOneWidget);
    expect(
        tester
            .widgetList<AlertSummaryCard>(find.byType(AlertSummaryCard))
            .last
            .count,
        '—');
    expect(find.textContaining('Não foi possível verificar os comentários'),
        findsOneWidget);
    expect(find.text('Nenhum alerta pendente no momento.'), findsNothing);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardAlertsModal), findsNothing);
  });

  testWidgets('renderable modal with reference layout and fixed action footer',
      (tester) async {
    final output = Platform.environment['ALERTS_LAYOUT_CAPTURE'];
    if (output != null) {
      final fonts = FontLoader('Segoe UI')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      await fonts.load();
      await (FontLoader('Roboto')
            ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
    final capture = GlobalKey();
    await open(tester, capture: capture);
    expect(find.byType(AlertSummaryCard), findsNWidgets(3));
    expect(find.byType(AlertCategory), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    if (output != null) {
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
