import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/platform/beta_audio.dart';
import '../../core/platform/local_user_state.dart';
import '../../domain/models/dashboard_models.dart';
import '../tasks/daily_hours_voice_command.dart' show dayHoursMinutes;
import '../tasks/theo_replies.dart' show spokenHours;
import 'beta_access.dart';
import 'beta_assistant_panel.dart';
import 'beta_controls.dart';
import 'beta_hours_check.dart';

String betaNormalize(String text) => text
    .toLowerCase()
    .trim()
    .replaceAll('á', 'a')
    .replaceAll('ã', 'a')
    .replaceAll('â', 'a')
    .replaceAll('ê', 'e')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ô', 'o')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
bool betaWake(String text) =>
    RegExp(r'^(?:(?:ola|oi|abrir|abre) (?:a )?)?beta$')
        .hasMatch(betaNormalize(text));
String betaHoursFingerprint(List<TimeLog> logs) {
  final rows = logs
      .map((l) => jsonEncode([
            l.id,
            l.targetId,
            l.date.toIso8601String(),
            l.startTime,
            l.endTime,
            l.taskName,
            l.description,
            l.typeHs,
            l.isRegistered
          ]))
      .toList()
    ..sort();
  return jsonEncode(rows);
}

class BetaAssistant extends StatefulWidget {
  const BetaAssistant(
      {super.key,
      required this.child,
      required this.owner,
      required this.loadDay,
      required this.openTasks,
      required this.canNavigate,
      this.accountIsCurrent,
      this.audioFactory,
      this.voiceTransport,
      this.openAdv,
      required this.send});
  final Widget child;
  final String owner;
  final Future<List<TimeLog>> Function(DateTime) loadDay;
  final VoidCallback openTasks;
  final bool Function() canNavigate;
  final Future<String?> Function(List<TimeLog>) send;
  final bool Function()? accountIsCurrent;
  final BetaAudio Function(void Function(String, String), BetaTransport)?
      audioFactory;
  final BetaTransport? voiceTransport;
  final Future<void> Function()? openAdv;
  @override
  State<BetaAssistant> createState() => _BetaAssistantState();
}

class _BetaAssistantState extends State<BetaAssistant> {
  late final BetaAudio _audio;
  final _input = TextEditingController();
  String _phase = 'asleep', _message = '', _status = 'Escuta desligada';
  bool _armed = false, _working = false, _speaking = false, _offered = false;
  int _turn = 0;
  bool _wantListening = true, _activating = false;
  Timer? _listenRetry;
  int _retrySeconds = 20;
  DateTime? _day;
  List<TimeLog> _logs = [];
  String _snapshot = '';
  bool get _current {
    if (widget.accountIsCurrent != null) {
      return mounted && widget.accountIsCurrent!();
    }
    final user = FirebaseAuth.instance.currentUser;
    return mounted &&
        user?.uid == widget.owner &&
        BetaAccess.allows(uid: user?.uid, email: user?.email);
  }

  @override
  void initState() {
    super.initState();
    _audio = (widget.audioFactory ?? createBetaAudio)(_event, _request);
    _wantListening = LocalUserState.read(
            widget.owner, 'beta.preferences')?['alwaysListening'] !=
        false;
    BetaControls.requests.addListener(_headerRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        BetaControls.state.value = const BetaControlState();
        if (_wantListening) unawaited(_activate(automatic: true));
      }
    });
  }

  void _headerRequest() {
    if (_current && !_working) unawaited(_activate());
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    BetaControls.state.value =
        BetaControlState(armed: _armed, busy: _working, status: _status);
  }

  @override
  void dispose() {
    _turn++;
    _listenRetry?.cancel();
    BetaControls.requests.removeListener(_headerRequest);
    _audio.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<String> _request(String raw) async {
    if (!_current) throw StateError('A conta mudou.');
    if (widget.voiceTransport != null) return widget.voiceTransport!(raw);
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    if (!_current || token == null) throw StateError('Entre novamente.');
    final client = http.Client();
    try {
      final response = await client
          .post(Uri.parse('http://127.0.0.1:8765/api/beta-voice'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token'
              },
              body: raw)
          .timeout(Duration(
              seconds: jsonDecode(raw)['action'] == 'status' ? 30 : 90));
      if (!_current) throw StateError('A conta mudou.');
      if (response.statusCode != 200) {
        if (response.statusCode == 404)
          throw StateError(
              'Atualize a integração para v60 e execute Preparar voz Beta.cmd.');
        final body = jsonDecode(response.body);
        throw StateError(body['message']?.toString() ??
            'Verifique a integração local da BETA.');
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  void _event(String type, String value) {
    if (!_current) return;
    if (type == 'text' && _armed && !_working && !_speaking) {
      unawaited(_command(value));
    }
    if (type == 'state') {
      setState(() => _status = value == 'listening'
          ? 'Estou ouvindo'
          : 'Clique em qualquer lugar da tela para liberar o áudio do navegador.');
    }
    if (type == 'error') {
      setState(() {
        _armed = false;
        _status = value;
      });
      // Never repeatedly request permission after a microphone denial.
      if (!value.toLowerCase().contains('microfone')) _scheduleListenRetry();
    }
  }

  void _resume() {
    if (_current && _armed && !_speaking && !_working) _audio.listen(_phase);
  }

  Future<void> _say(String text) async {
    if (!_current) return;
    final turn = _turn;
    setState(() {
      _message = text;
      _speaking = true;
      _status = 'Respondendo…';
    });
    _audio.stop();
    try {
      await _audio.speak(text);
    } catch (error) {
      if (_current && turn == _turn) {
        setState(() => _status = error is StateError
            ? error.message.toString()
            : 'Não consegui reproduzir a voz local. Confira se a integração v60 está ativa e se Preparar voz Beta.cmd foi executado.');
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _speaking = false);
        _resume();
      }
    }
  }

  void _scheduleListenRetry() {
    _listenRetry?.cancel();
    if (!_current || !_wantListening || _armed) return;
    _listenRetry = Timer(Duration(seconds: _retrySeconds), () {
      if (_current && _wantListening && !_armed)
        unawaited(_activate(automatic: true));
    });
    _retrySeconds = (_retrySeconds * 2).clamp(20, 120);
  }

  Future<void> _activate({bool automatic = false}) async {
    if (!_current || _activating) return;
    if (automatic && (!_wantListening || _armed)) return;
    _listenRetry?.cancel();
    if (_armed) {
      _wantListening = false;
      LocalUserState.write(
          widget.owner, 'beta.preferences', {'alwaysListening': false});
      _audio.stop();
      setState(() {
        _armed = false;
        _speaking = false;
        _status = 'Escuta desligada';
      });
      return;
    }
    _wantListening = true;
    if (!automatic)
      LocalUserState.write(
          widget.owner, 'beta.preferences', {'alwaysListening': true});
    _activating = true;
    setState(() => _status = 'Verificando voz local…');
    try {
      final status =
          jsonDecode(await _request(jsonEncode({'action': 'status'})));
      if (!_current) return;
      if (status['ready'] != true) {
        throw StateError(
            'Prepare a voz local com scripts/setup_beta_voice.ps1.');
      }
      setState(() => _armed = true);
      _retrySeconds = 20;
      _resume();
    } catch (error) {
      if (_current) {
        setState(() => _status = error is TimeoutException
            ? 'A integração deste computador não respondeu à verificação de voz em 30 segundos. Abra a integração local e tente novamente. Se já estiver aberta, reinicie somente a integração.'
            : 'Não consegui ativar a BETA. $error');
        _scheduleListenRetry();
      }
    } finally {
      _activating = false;
    }
  }

  Future<void> _prepare() async {
    if (!widget.canNavigate()) {
      await _say(
          'Conclua ou feche a edição aberta antes de conferir as horas.');
      return;
    }
    final turn = _turn;
    setState(() {
      _working = true;
      _phase = 'loading';
      _logs = [];
      _offered = false;
    });
    _audio.stop();
    widget.openTasks();
    try {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final logs = await widget.loadDay(day);
      if (!_current || turn != _turn) return;
      final valid = logs
          .where((l) => l.isRegistered && DateUtils.isSameDay(l.date, day))
          .toList();
      if (valid.isEmpty) {
        setState(() => _phase = 'ready');
        await _say('Não encontrei apontamentos registrados hoje para enviar.');
        return;
      }
      final problem = betaHoursProblem(valid);
      if (problem != null) {
        setState(() => _phase = 'ready');
        await _say(problem);
        return;
      }
      _day = day;
      _logs = valid;
      _snapshot = betaHoursFingerprint(valid);
      setState(() => _phase = 'choose');
      await _say(
          'Não encontrei sobreposição. Quer que eu leia ou prefere conferir na tela?');
    } catch (_) {
      if (_current && turn == _turn) {
        setState(() => _phase = 'ready');
        await _say(
            'Não consegui carregar todas as horas de hoje. Nenhum envio foi feito. Tente novamente.');
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _working = false);
        _resume();
      }
    }
  }

  Future<void> _review(bool read) async {
    setState(() => _phase = 'review');
    if (!read) {
      await _say(
          'Confira na tela. Quando estiver tudo certo, diga: pode enviar.');
      return;
    }
    final turn = _turn;
    setState(() => _working = true);
    try {
      for (final log in _logs) {
        if (!_current || turn != _turn) return;
        await _say(
            '${log.projectName ?? log.targetId}. ${log.taskName ?? ''}. Das ${log.startTime} às ${log.endTime}. ${spokenHours(dayHoursMinutes(log))}. ${log.description ?? ''}');
      }
      if (_current && turn == _turn) {
        await _say(
            'Ao todo, ${spokenHours(_logs.fold(0, (sum, l) => sum + dayHoursMinutes(l)))}. Está tudo certo? Diga: pode enviar.');
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _working = false);
        _resume();
      }
    }
  }

  Future<void> _send() async {
    if (_phase != 'review' || _logs.isEmpty || _day == null) return;
    final turn = _turn;
    setState(() {
      _working = true;
      _phase = 'sending';
      _status = 'Verificando apontamentos antes do envio…';
    });
    _audio.stop();
    try {
      final fresh = await widget.loadDay(_day!);
      if (!_current || turn != _turn) return;
      final problem = betaHoursProblem(fresh);
      if (problem != null) {
        setState(() { _phase = 'ready'; _logs = []; });
        await _say(problem);
        return;
      }
      if (!DateUtils.isSameDay(_day, DateTime.now()) ||
          betaHoursFingerprint(fresh) != _snapshot) {
        setState(() {
          _phase = 'ready';
          _logs = [];
        });
        await _say(
            'Os apontamentos ou a data mudaram. Vamos conferir novamente antes de enviar.');
        return;
      }
      final result = await widget.send(_logs);
      if (!_current || turn != _turn) return;
      setState(() => _phase = 'ready');
      _logs = [];
      await _say('${result ?? 'O envio foi cancelado.'} Qualquer coisa, é só me chamar.');
      if (_current && turn == _turn) {
        if (_current && turn == _turn) setState(() => _phase = 'asleep');
      }
    } catch (_) {
      if (_current && turn == _turn) {
        setState(() => _phase = 'ready');
        _logs = [];
        await _say(
            'Não consegui confirmar o envio. Confira o resultado na tela antes de tentar de novo. Qualquer coisa, é só me chamar.');
        if (_current && turn == _turn) {
          if (_current && turn == _turn) setState(() => _phase = 'asleep');
        }
      }
    } finally {
      if (_current && turn == _turn) {
        setState(() => _working = false);
        _resume();
      }
    }
  }

  Future<void> _command(String raw) async {
    if (!_current || _working || _speaking) return;
    final text = betaNormalize(raw);
    if (betaWake(text)) {
      setState(() {
        _phase = 'ready';
        _logs = [];
        _offered = false;
      });
      final hour = DateTime.now().hour;
      await _say(
          '${hour < 12 ? 'Bom dia' : hour < 18 ? 'Boa tarde' : 'Boa noite'}, Rodrigo! Como posso ajudar?');
      return;
    }
    if (_phase == 'asleep') {
      _resume();
      return;
    }
    if (['abrir trabalho adv', 'abrir trabalho para adv', 'abrir adv',
        'abrir trabalho a de ve', 'abrir trabalho para a de ve'].contains(text)) {
      if (!widget.canNavigate()) {
        await _say('Feche a edição aberta antes de abrir o trabalho ADV.');
        return;
      }
      if (widget.openAdv == null) {
        await _say('Não consegui abrir o trabalho ADV nesta tela.');
        return;
      }
      final turn = _turn;
      setState(() { _working = true; _logs = []; _offered = false; });
      try {
        await _say('Escolha o projeto na tela. Vou abrir o cadastro para o ADV.');
        if (!_current || turn != _turn) return;
        setState(() => _phase = 'asleep');
        await widget.openAdv!();
      } catch (_) {
        if (_current && turn == _turn) {
          setState(() => _phase = 'ready');
          await _say('Não consegui abrir o trabalho ADV. Tente novamente.');
        }
      } finally {
        if (_current && turn == _turn) {
          setState(() => _working = false);
          _resume();
        }
      }
      return;
    }
    if (['fechar beta', 'cancelar', 'cancelar envio'].contains(text)) {
      if (text == 'fechar beta') {
        final turn = _turn;
        await _say('Qualquer coisa, é só me chamar.');
        if (!_current || turn != _turn) return;
      }
      _turn++;
      _audio.stop();
      setState(() {
        _phase = text == 'fechar beta' ? 'asleep' : 'ready';
        _logs = [];
        _offered = false;
      });
      _resume();
      return;
    }
    if (text == 'enviar horas do dia' ||
        text == 'enviar as horas do dia' ||
        text == 'enviar horas de hoje' ||
        text == 'enviar minhas horas de hoje' ||
        (_phase == 'ready' &&
            _offered &&
            ['sim', 'pode conferir', 'quero'].contains(text))) {
      await _prepare();
      return;
    }
    if (['choose', 'review'].contains(_phase)) {
      if ([
        'sim',
        'pode ler',
        'leia',
        'ler as horas',
        'leia as horas',
        'por voz',
        'leitura por voz'
      ].contains(text)) {
        await _review(true);
        return;
      }
      if ([
        'conferencia visual',
        'conferir na tela',
        'vou conferir na tela',
        'na tela',
        'visual'
      ].contains(text)) {
        await _review(false);
        return;
      }
      if (_phase == 'review' &&
          ['pode enviar', 'confirmar envio'].contains(text)) {
        await _send();
        return;
      }
      await _say(_phase == 'choose'
          ? 'Quer que eu leia ou prefere conferir na tela?'
          : 'Se estiver tudo certo, diga: pode enviar.');
      return;
    }
    _offered = true;
    await _say(
        'Vamos conferir suas horas de hoje?');
  }

  void _stopReading() {
    _turn++;
    _audio.stop();
    setState(() {
      _working = false;
      _speaking = false;
      _status = 'Confira os registros na tela.';
    });
    _resume();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_phase != 'asleep')
        Positioned(
            right: 16,
            bottom: 16,
            child: BetaAssistantPanel(
              message: _message,
              status: _status,
              phase: _phase,
              speaking: _speaking,
              working: _working,
              logs: _logs,
              input: _input,
              onCommand: (value) {
                unawaited(_command(value));
              },
              onStopVoice: _stopReading,
              onClose: () {
                if (_working) return;
                _turn++;
                _audio.stop();
                setState(() {
                  _speaking = false;
                  _phase = 'asleep';
                  _logs = [];
                  _offered = false;
                });
                _resume();
              },
            )),
    ]);
  }
}
