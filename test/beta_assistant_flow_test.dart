import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/features/assistant/beta_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/beta_audio.dart';
import 'package:gerenciador_horas/features/assistant/beta_assistant.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

class FakeAudio implements BetaAudio {
  late void Function(String, String) event;
  final spoken = <String>[];
  int listens = 0;
  @override
  void listen(String mode) {
    listens++;
  }

  @override
  void stop() {}
  @override
  void dispose() {}
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  void hear(String text) => event('text', text);
}

void main() {
  testWidgets('ADV voice command opens review only after wake, without sending', (tester) async {
    final audio = FakeAudio();
    var opens = 0, sends = 0;
    var canNavigate = true;
    await tester.pumpWidget(MaterialApp(home: BetaAssistant(
      owner: 'pilot', accountIsCurrent: () => true,
      voiceTransport: (_) async => '{"ready":true}',
      audioFactory: (event, transport) { audio.event = event; return audio; },
      loadDay: (_) async => [], openTasks: () {}, canNavigate: () => canNavigate,
      openAdv: () async { opens++; },
      send: (_) async { sends++; return null; },
      child: const Scaffold(body: Text('Projetos')),
    )));
    await tester.pumpAndSettle();
    audio.hear('abrir trabalho adv'); await tester.pumpAndSettle();
    expect(opens, 0);
    audio.hear('Olá Beta'); await tester.pumpAndSettle();
    canNavigate = false;
    audio.hear('abrir trabalho adv'); await tester.pumpAndSettle();
    expect(opens, 0);
    canNavigate = true;
    audio.hear('abrir trabalho ADV'); await tester.pumpAndSettle();
    expect(opens, 1);
    expect(sends, 0);
    expect(find.text('BETA'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final initialConflict in [true, false]) {
    testWidgets('overlapping hours cannot be sent; initial=$initialConflict', (tester) async {
      final audio = FakeAudio();
      var loads = 0, sends = 0;
      final now = DateTime.now();
      TimeLog log(String id, String start, String end) => TimeLog(
          id: id, targetId: id, date: now, startTime: start, endTime: end,
          durationFormatted: '01:00', isRegistered: true, projectName: id);
      await tester.pumpWidget(MaterialApp(home: BetaAssistant(
        owner: 'pilot', accountIsCurrent: () => true,
        voiceTransport: (_) async => '{"ready":true}',
        audioFactory: (event, transport) { audio.event = event; return audio; },
        loadDay: (_) async {
          loads++;
          return [log('Urban', '09:00', '10:00'),
            log('Outro', initialConflict || loads > 1 ? '09:30' : '10:00', '11:00')];
        },
        openTasks: () {}, canNavigate: () => true,
        send: (_) async { sends++; return 'Enviado'; },
        child: const Scaffold(body: Text('Tarefas')),
      )));
      await tester.pumpAndSettle();
      audio.hear('Olá Beta'); await tester.pumpAndSettle();
      audio.hear('enviar horas do dia'); await tester.pumpAndSettle();
      if (!initialConflict) {
        audio.hear('conferir na tela'); await tester.pumpAndSettle();
        audio.hear('pode enviar'); await tester.pumpAndSettle();
      }
      expect(audio.spoken.last, contains('sobrepostos'));
      expect(audio.spoken.last, contains('Urban'));
      audio.hear('pode enviar'); await tester.pumpAndSettle();
      expect(sends, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  setUp(() {
    LocalUserState.memory = {};
  });
  tearDown(() {
    LocalUserState.memory = null;
  });
  testWidgets('wake and farewell preserve the current screen state',
      (tester) async {
    final audio = FakeAudio();
    var creations = 0;
    await tester.pumpWidget(MaterialApp(
        home: BetaAssistant(
      owner: 'pilot',
      accountIsCurrent: () => true,
      voiceTransport: (_) async => '{"ready":true}',
      audioFactory: (event, transport) {
        audio.event = event;
        return audio;
      },
      loadDay: (_) async => [],
      openTasks: () => fail('Closing must not navigate'),
      canNavigate: () => true,
      send: (_) async => null,
      child: _ScreenProbe(onCreate: () => creations++),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local state: 0'));
    await tester.pump();
    audio.hear('Beta');
    await tester.pumpAndSettle();
    expect(find.text('Local state: 1'), findsOneWidget);
    audio.hear('fechar beta');
    await tester.pumpAndSettle();
    expect(find.text('BETA'), findsNothing);
    expect(find.text('Local state: 1'), findsOneWidget);
    expect(creations, 1);
    expect(audio.spoken.last, contains('só me chamar'));
    final listens = audio.listens;
    audio.hear('Beta');
    await tester.pumpAndSettle();
    expect(find.text('BETA'), findsOneWidget);
    expect(audio.listens, greaterThan(listens));
    expect(creations, 1);
    expect(find.text('Local state: 1'), findsOneWidget);
  });
  testWidgets('automatic listening retries integration and respects manual off',
      (tester) async {
    final audio = FakeAudio();
    var checks = 0;
    Widget app() => MaterialApp(
        home: BetaAssistant(
            owner: 'pilot',
            accountIsCurrent: () => true,
            voiceTransport: (_) async {
              checks++;
              if (checks == 1) throw StateError('integration unavailable');
              return '{"ready":true}';
            },
            audioFactory: (event, transport) {
              audio.event = event;
              return audio;
            },
            loadDay: (_) async => [],
            openTasks: () {},
            canNavigate: () => true,
            send: (_) async => null,
            child: Scaffold(
                appBar: AppBar(actions: const [BetaHeaderControl()]))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(audio.listens, 0);
    expect(find.text('BETA'), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(audio.listens, 1);
    audio.event('state', 'waiting');
    await tester.pumpAndSettle();
    expect(
        find.byTooltip(
            'Status da escuta: Clique em qualquer lugar da tela para liberar o áudio do navegador.'),
        findsOneWidget);
    audio.event('state', 'listening');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.info_outline), findsNothing);
    await tester.tap(find.byTooltip('Desativar escuta da BETA'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 3));
    expect(checks, 2);
    expect(audio.listens, 1);
    await tester.pumpWidget(const SizedBox());
  });
  for (final changed in [false, true]) {
    testWidgets(
        'visual review and explicit authorization; records changed=$changed',
        (tester) async {
      final audio = FakeAudio();
      var sends = 0, opens = 0, loads = 0;
      final now = DateTime.now();
      TimeLog log() => TimeLog(
          id: 'log',
          targetId: '2265001/3',
          date: DateTime(now.year, now.month, now.day),
          startTime: '09:00',
          endTime: changed && loads > 1 ? '10:30' : '10:00',
          durationFormatted: '01:00',
          isRegistered: true,
          projectName: 'Urban',
          taskName: 'Implantação',
          description: 'Relatórios');
      await tester.pumpWidget(MaterialApp(
          home: BetaAssistant(
              owner: 'pilot',
              accountIsCurrent: () => true,
              voiceTransport: (_) async => ' {"ready":true}',
              audioFactory: (event, transport) {
                audio.event = event;
                return audio;
              },
              loadDay: (_) async {
                loads++;
                return [log()];
              },
              openTasks: () {
                opens++;
              },
              canNavigate: () => true,
              send: (logs) async {
                sends++;
                return 'Envio confirmado';
              },
              child: Scaffold(
                  appBar: AppBar(actions: const [BetaHeaderControl()]),
                  body: const Text('Projetos')))));
      await tester.pumpAndSettle();
      expect(find.text('BETA'), findsNothing);
      expect(audio.listens, greaterThan(0));
      expect(find.byTooltip('Desativar escuta da BETA'), findsOneWidget);
      expect(find.text('BETA'), findsNothing);
      audio.hear('Olá Beta');
      await tester.pumpAndSettle();
      audio.hear('ajuda');
      await tester.pumpAndSettle();
      audio.hear('sim');
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(sends, 0);
      expect(find.text('Conferir na tela'), findsOneWidget);
      audio.hear('pode enviar');
      await tester.pumpAndSettle();
      expect(sends, 0);
      audio.hear('conferir na tela');
      await tester.pumpAndSettle();
      expect(find.textContaining('Urban'), findsOneWidget);
      audio.hear('pode enviar');
      await tester.pumpAndSettle();
      expect(sends, changed ? 0 : 1);
      if (!changed) {
        expect(find.byTooltip('Recolher BETA'), findsNothing);
        expect(audio.spoken.last, contains('só me chamar'));
      }
      if (changed) expect(audio.spoken.last, contains('mudaram'));
      audio.hear('pode enviar');
      await tester.pumpAndSettle();
      expect(sends, changed ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('account change ignores subsequent voice commands',
      (tester) async {
    final audio = FakeAudio();
    var current = true, loads = 0;
    await tester.pumpWidget(MaterialApp(
        home: BetaAssistant(
            owner: 'pilot',
            accountIsCurrent: () => current,
            voiceTransport: (_) async => '{"ready":true}',
            audioFactory: (event, transport) {
              audio.event = event;
              return audio;
            },
            loadDay: (_) async {
              loads++;
              return [];
            },
            openTasks: () {},
            canNavigate: () => true,
            send: (_) async => null,
            child: Scaffold(
                appBar: AppBar(actions: const [BetaHeaderControl()])))));
    await tester.pumpAndSettle();
    expect(audio.listens, greaterThan(0));
    await tester.tap(find.byTooltip('Desativar escuta da BETA'));
    await tester.pumpAndSettle();
    expect(LocalUserState.read('pilot', 'beta.preferences')?['alwaysListening'],
        false);
    await tester.tap(find.byTooltip('Ativar escuta da BETA'));
    await tester.pumpAndSettle();
    expect(LocalUserState.read('pilot', 'beta.preferences')?['alwaysListening'],
        true);
    audio.hear('Beta');
    await tester.pumpAndSettle();
    current = false;
    audio.hear('enviar horas do dia');
    await tester.pumpAndSettle();
    expect(loads, 0);
  });
}

class _ScreenProbe extends StatefulWidget {
  const _ScreenProbe({required this.onCreate});
  final VoidCallback onCreate;
  @override
  State<_ScreenProbe> createState() => _ScreenProbeState();
}

class _ScreenProbeState extends State<_ScreenProbe> {
  int counter = 0;
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: TextButton(
              onPressed: () => setState(() => counter++),
              child: Text('Local state: $counter'))));
}
