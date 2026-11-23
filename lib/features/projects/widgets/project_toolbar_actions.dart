import 'package:flutter/material.dart';
import '../../reminders/personal_reminders.dart';

enum _ProjectAction { received, audit, internalNs }

class ProjectToolbarActions extends StatelessWidget {
  const ProjectToolbarActions(
      {super.key,
      required this.onQueue,
      required this.onReceived,
      required this.onAudit,
      required this.onInternalNs});
  final VoidCallback onQueue, onReceived, onAudit, onInternalNs;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
    PopupMenuItem<_ProjectAction> item(_ProjectAction value, IconData icon,
            String title, String subtitle) =>
        PopupMenuItem(
          value: value,
          height: 66,
          child: Row(children: [
            Icon(icon, size: 19, color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: colors.onSurfaceVariant)),
                ])),
          ]),
        );
    PopupMenuItem<_ProjectAction> section(String title) => PopupMenuItem(
          enabled: false,
          height: 30,
          child: Text(title,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: colors.onSurfaceVariant)),
        );
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: onQueue,
          icon: const Icon(Icons.playlist_add_check, size: 18),
          label: const Text('Fila de comentários'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              foregroundColor: colors.onSurface,
              side: BorderSide(color: colors.outlineVariant),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              shape: shape),
        ),
        PopupMenuButton<_ProjectAction>(
          tooltip: 'Ações dos projetos',
          position: PopupMenuPosition.under,
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (action) {
            switch (action) {
              case _ProjectAction.received:
                onReceived();
              case _ProjectAction.audit:
                onAudit();
              case _ProjectAction.internalNs:
                onInternalNs();
            }
          },
          itemBuilder: (_) => [
            section('CONSULTAS E CONFERÊNCIA'),
            item(
                _ProjectAction.received,
                Icons.move_to_inbox_outlined,
                'Trabalhos recebidos',
                'Consultar trabalhos disponíveis no E-Desk'),
            item(_ProjectAction.audit, Icons.fact_check_outlined,
                'Conferir no E-Desk', 'Comparar fases, datas e horas'),
            const PopupMenuDivider(),
            section('SOLICITAÇÕES'),
            item(
                _ProjectAction.internalNs,
                Icons.key_outlined,
                'Solicitar NS de uso interno',
                'Abrir um novo pedido no E-Desk'),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: colors.primary, borderRadius: BorderRadius.circular(9)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Ações',
                  style: TextStyle(
                      color: colors.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Icon(Icons.arrow_drop_down, size: 18, color: colors.onPrimary),
            ]),
          ),
        ),
      ],
    );
  }
}

class ProjectSectionHeading extends StatelessWidget {
  const ProjectSectionHeading(
      {super.key, required this.projectCount, this.actions});
  final int projectCount;
  final Widget? actions;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = Row(children: [
      Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12)),
          child:
              Icon(Icons.table_rows_outlined, size: 21, color: colors.primary)),
      const SizedBox(width: 12),
      Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Wrap(
                spacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Projetos e tarefas',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface)),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(7)),
                      child: Text(
                          '$projectCount ${projectCount == 1 ? 'projeto' : 'projetos'}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant))),
                  const PersonalReminderButton(showLabel: true),
                ]),
          ])),
    ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .6)))),
      child: LayoutBuilder(builder: (context, constraints) {
        if (actions == null) return title;
        if (constraints.maxWidth >= 960) {
          return Row(children: [
            Expanded(child: title),
            const SizedBox(width: 24),
            actions!
          ]);
        }
        return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerRight, child: actions!),
            ]);
      }),
    );
  }
}
