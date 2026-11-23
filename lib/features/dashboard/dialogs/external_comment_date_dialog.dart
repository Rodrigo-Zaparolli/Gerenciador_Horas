import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/services/project_update_service.dart';

class ExternalCommentDateDialog extends StatefulWidget {
  const ExternalCommentDateDialog({super.key, required this.projectId, this.ownerUid});
  final String projectId;
  final String? ownerUid;
  static Future<bool?> show(BuildContext context, String projectId) =>
      showDialog<bool>(context: context, builder: (_) => ExternalCommentDateDialog(projectId: projectId, ownerUid: FirebaseAuth.instance.currentUser?.uid));
  @override
  State<ExternalCommentDateDialog> createState() => _ExternalCommentDateDialogState();
}

class _ExternalCommentDateDialogState extends State<ExternalCommentDateDialog> {
  DateTime date = DateUtils.dateOnly(DateTime.now());
  bool saving = false;
  String? error;
  Future<void> save() async {
    setState(() { saving = true; error = null; });
    try {
      final uid = widget.ownerUid;
      if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid) throw StateError('Entre novamente no sistema.');
      await ProjectUpdateService(uid).recordExternalComment(widget.projectId, date);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { saving = false; error = 'Não foi possível registrar a data. Tente novamente.'; });
    }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Comentário feito no E-Desk'),
    content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Solicitação ${widget.projectId}'),
      const SizedBox(height: 12),
      const Text('Informe quando você publicou o comentário diretamente no E-Desk. Esta ação registra a data no sistema.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: saving ? null : () async {
        final selected = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime.now());
        if (selected != null && mounted) setState(() => date = selected);
      }, icon: const Icon(Icons.calendar_today_outlined), label: Text(ProjectUpdateService.formatDate(date))),
      const SizedBox(height: 8),
      Text('Próxima atualização: ${ProjectUpdateService.formatDate(ProjectUpdateService.nextUpdate(date))}. Uma data anterior ao último comentário não substitui a mais recente.'),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Salvando…' : 'Registrar data'))],
  );
}
