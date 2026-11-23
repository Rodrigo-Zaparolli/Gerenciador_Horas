import 'package:flutter/material.dart';

class BetaControlState {
  const BetaControlState(
      {this.armed = false, this.busy = false, this.status = ''});
  final bool armed, busy;
  final String status;
}

class BetaControls {
  static final requests = ValueNotifier<int>(0);
  static final state =
      ValueNotifier<BetaControlState>(const BetaControlState());
}

class BetaHeaderControl extends StatelessWidget {
  const BetaHeaderControl({super.key});
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<BetaControlState>(
          valueListenable: BetaControls.state,
          builder: (context, state, child) =>
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: state.armed
                        ? 'Desativar escuta da BETA'
                        : 'Ativar escuta da BETA',
                    onPressed:
                        state.busy ? null : () => BetaControls.requests.value++,
                    icon: Icon(state.armed ? Icons.mic : Icons.mic_none,
                        color: state.armed
                            ? (state.status == 'Estou ouvindo'
                                ? Colors.cyan
                                : Colors.amber)
                            : null)),
                if (state.status.isNotEmpty &&
                    state.status != 'Estou ouvindo' &&
                    state.status != 'Escuta desligada')
                  IconButton(
                    tooltip: 'Status da escuta: ${state.status}',
                    icon: const Icon(Icons.info_outline,
                        color: Colors.amber, size: 18),
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                              title: const Text('Status da escuta'),
                              content: SelectableText(state.status),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Fechar'))
                              ],
                            )),
                  ),
              ]));
}
