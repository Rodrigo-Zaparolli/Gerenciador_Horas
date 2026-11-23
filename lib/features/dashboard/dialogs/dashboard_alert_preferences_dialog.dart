import 'package:flutter/material.dart';
import '../../../domain/models/dashboard_alert_preferences.dart';

class DashboardAlertPreferencesDialog extends StatefulWidget {
  const DashboardAlertPreferencesDialog({super.key, required this.initial});
  final DashboardAlertPreferences initial;
  static Future<DashboardAlertPreferences?> show(
          BuildContext context, DashboardAlertPreferences initial) =>
      showDialog<DashboardAlertPreferences>(
          context: context,
          builder: (_) => DashboardAlertPreferencesDialog(initial: initial));
  @override
  State<DashboardAlertPreferencesDialog> createState() => _PreferencesState();
}

class _PreferencesState extends State<DashboardAlertPreferencesDialog> {
  late bool enabled, overdue, deadlines, comments;
  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    enabled = p.enabled;
    overdue = p.overdue;
    deadlines = p.deadlines;
    comments = p.comments;
  }

  DashboardAlertPreferences get value => DashboardAlertPreferences(
      enabled: enabled,
      overdue: overdue,
      deadlines: deadlines,
      comments: comments);
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Configurar Central de Alertas'),
        content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                    key: const ValueKey('alerts-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exibir Central de Alertas'),
                    subtitle: const Text(
                        'Inclui os avisos automáticos ao abrir Projetos.'),
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v)),
                const Divider(),
                const Text('Quais alertas deseja acompanhar?'),
                CheckboxListTile(
                    key: const ValueKey('alerts-overdue'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Projetos e etapas em atraso'),
                    value: overdue,
                    onChanged:
                        enabled ? (v) => setState(() => overdue = v!) : null),
                CheckboxListTile(
                    key: const ValueKey('alerts-deadlines'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Prazos próximos de projetos e etapas'),
                    value: deadlines,
                    onChanged:
                        enabled ? (v) => setState(() => deadlines = v!) : null),
                CheckboxListTile(
                    key: const ValueKey('alerts-comments'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Atualizações de comentários'),
                    value: comments,
                    onChanged:
                        enabled ? (v) => setState(() => comments = v!) : null),
                if (enabled && !value.hasTopics)
                  Text('Selecione um tipo de alerta ou desative a central.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                const Text('Preferência pessoal, salva na sua conta.'),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: enabled && !value.hasTopics
                  ? null
                  : () => Navigator.pop(context, value),
              child: const Text('Salvar')),
        ],
      );
}
