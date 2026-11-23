import 'package:flutter/material.dart';
import '../../domain/models/dashboard_models.dart';
import '../tasks/daily_hours_voice_command.dart' show dayHoursMinutes;
import '../tasks/theo_replies.dart' show spokenHours;
import 'beta_hologram.dart';

class BetaAssistantPanel extends StatefulWidget {
  const BetaAssistantPanel(
      {super.key,
      required this.message,
      required this.status,
      required this.phase,
      required this.speaking,
      required this.working,
      required this.logs,
      required this.input,
      required this.onCommand,
      required this.onStopVoice,
      required this.onClose});
  final String message, status, phase;
  final bool speaking, working;
  final List<TimeLog> logs;
  final TextEditingController input;
  final ValueChanged<String> onCommand;
  final VoidCallback onStopVoice, onClose;
  @override
  State<BetaAssistantPanel> createState() => _BetaAssistantPanelState();
}

class _BetaAssistantPanelState extends State<BetaAssistantPanel> {
  bool _typing = false;
  static const _cyan = Color(0xff72e7ee);
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final available = (size.width - 32).clamp(0.0, 380.0);
    final active = !widget.working && !widget.speaking;
    return SizedBox(
      width: available,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * .8),
        child: DecoratedBox(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .35),
                      blurRadius: 32,
                      offset: const Offset(0, 12)),
                  BoxShadow(color: _cyan.withValues(alpha: .06), blurRadius: 22)
                ],
                border: Border.all(color: _cyan.withValues(alpha: .24)),
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff132932), Color(0xff0a151f)])),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Material(
                  color: Colors.transparent,
                  child: SingleChildScrollView(
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 12, 14),
                    child: DefaultTextStyle(
                        style: const TextStyle(
                            fontFamily: 'Roboto',
                            color: Color(0xffeaf3f5),
                            fontSize: 13,
                            height: 1.5),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                        color: _cyan, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                const Text('BETA',
                                    style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 3,
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                IconButton(
                                    tooltip: 'Digitar comando',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: active
                                        ? () =>
                                            setState(() => _typing = !_typing)
                                        : null,
                                    icon: const Icon(Icons.keyboard_outlined,
                                        size: 17, color: Color(0xff8babb5))),
                                IconButton(
                                    tooltip: 'Recolher BETA',
                                    visualDensity: VisualDensity.compact,
                                    onPressed:
                                        widget.working ? null : widget.onClose,
                                    icon: const Icon(Icons.close_rounded,
                                        size: 17, color: Color(0xff8babb5))),
                              ]),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    IgnorePointer(
                                        child: SizedBox(
                                            width: 144,
                                            height: 168,
                                            child: Center(
                                                child: BetaHologram(
                                                    speaking:
                                                        widget.speaking)))),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: Padding(
                                            padding:
                                                const EdgeInsets.only(right: 6),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      widget.working
                                                          ? 'CONFERINDO'
                                                          : widget.speaking
                                                              ? 'RESPONDENDO'
                                                              : widget.status ==
                                                                      'Estou ouvindo'
                                                                  ? 'ESTOU OUVINDO'
                                                                  : 'AGUARDANDO',
                                                      style: const TextStyle(
                                                          fontSize: 9,
                                                          letterSpacing: 1.7,
                                                          color: _cyan,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                  const SizedBox(height: 6),
                                                  Text(widget.message,
                                                      style: const TextStyle(
                                                          fontSize: 14,
                                                          height: 1.45)),
                                                ]))),
                                  ]),
                              if (widget.status != 'Estou ouvindo' &&
                                  !widget.status.startsWith('Preparando voz'))
                                Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4, bottom: 6),
                                    child: Text(widget.status,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xffadc2ca)))),
                              if (widget.logs.isNotEmpty) ...[
                                const Divider(
                                    color: Color(0xff28414c), height: 24),
                                Text(
                                    '${widget.logs.length} apontamentos · ${spokenHours(widget.logs.fold(0, (sum, l) => sum + dayHoursMinutes(l)))}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                SizedBox(
                                    height: (widget.logs.length * 62.0)
                                        .clamp(62.0, 170.0),
                                    child: ListView(children: [
                                      for (final log in widget.logs)
                                        Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 6),
                                            child: Text(
                                                '${log.projectName ?? log.targetId} · ${log.taskName ?? ''}\n${log.startTime}–${log.endTime} · ${log.description ?? ''}',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xffb8cbd3))))
                                    ])),
                              ],
                              if (active) ...[
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  if (widget.phase == 'choose') ...[
                                    _action('Ler por voz',
                                        Icons.volume_up_outlined, 'pode ler'),
                                    _action(
                                        'Conferir na tela',
                                        Icons.fact_check_outlined,
                                        'conferir na tela'),
                                  ],
                                  if (widget.phase == 'review')
                                    _action('Pode enviar', Icons.send_rounded,
                                        'pode enviar'),
                                  if (widget.phase == 'ready')
                                    _action(
                                        'Enviar horas do dia',
                                        Icons.schedule_rounded,
                                        'enviar horas do dia'),
                                ]),
                                if (_typing)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: TextField(
                                          autofocus: true,
                                          controller: widget.input,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13),
                                          decoration: const InputDecoration(
                                              isDense: true,
                                              hintText: 'Digite um comando…',
                                              hintStyle: TextStyle(
                                                  color: Color(0xff8babb5))),
                                          onSubmitted: (value) {
                                            widget.input.clear();
                                            widget.onCommand(value);
                                          })),
                              ],
                              if (widget.speaking && widget.phase != 'sending')
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                        tooltip: 'Parar voz',
                                        onPressed: widget.onStopVoice,
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.pause_rounded,
                                            size: 19, color: _cyan))),
                            ])),
                  ))),
            )),
      ),
    );
  }

  Widget _action(String label, IconData icon, String command) =>
      OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: _cyan,
              side: const BorderSide(color: Color(0xff31515e)),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 11),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          onPressed: () => widget.onCommand(command),
          icon: Icon(icon, size: 14),
          label: Text(label));
}
