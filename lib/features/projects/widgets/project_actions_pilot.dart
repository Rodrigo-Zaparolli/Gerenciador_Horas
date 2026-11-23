import 'dart:math' as math;
import 'package:flutter/material.dart';

class ProjectActionsPilot extends StatelessWidget {
  const ProjectActionsPilot(
      {super.key,
      required this.hasFolder,
      required this.hasExcel,
      required this.onFolder,
      required this.onExcel,
      required this.onEditSpreadsheet,
      required this.onEditWork,
      required this.onChecklist,
      required this.onComment,
      required this.onEmail,
      this.onAudit,
      this.onAdv,
      this.onPluginNs,
      this.onPhases,
      this.onDocuments,
      this.onReport,
      this.onZendesk,
      this.projectId = '',
      this.client = '',
      this.serviceType = ''});
  final String projectId, client, serviceType;
  final bool hasFolder, hasExcel;
  final VoidCallback onFolder,
      onExcel,
      onEditSpreadsheet,
      onEditWork,
      onChecklist,
      onComment,
      onEmail;
  final VoidCallback? onAudit, onAdv, onPluginNs, onPhases, onDocuments, onReport;
  final VoidCallback? onZendesk;

  Future<void> _more(BuildContext context) async {
    final selected = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fechar ações do projeto',
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (context, animation, secondary, child) =>
            SlideTransition(
                position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                    .animate(animation),
                child: child),
        pageBuilder: (context, animation, secondary) => Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
                width: math.min(470, MediaQuery.sizeOf(context).width),
                height: MediaQuery.sizeOf(context).height,
                child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 16, 12, 16),
                              child: Row(children: [
                                const Expanded(
                                    child: Text('Ações do projeto',
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold))),
                                IconButton(
                                    tooltip: 'Fechar painel',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close)),
                              ])),
                          const Divider(height: 1),
                          Expanded(
                              child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (projectId.isNotEmpty ||
                                            client.isNotEmpty)
                                          Container(
                                              padding: const EdgeInsets.all(14),
                                              decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: .08),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                        'Solicitação $projectId',
                                                        style: TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .primary)),
                                                    const SizedBox(height: 6),
                                                    Text(client,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                    if (serviceType.isNotEmpty)
                                                      Text(serviceType),
                                                  ])),
                                        _group('Arquivos e checklist'),
                                        if (onDocuments != null)
                                          _tile(context, 'documents', Icons.edit_calendar_outlined,
                                              'Cronograma e Plano de Projeto',
                                              'Editar os dias e imprimir os documentos', enabled: hasExcel),
                                        if (onReport != null)
                                          _tile(context, 'report', Icons.description_outlined,
                                              'Relatório de atividades', 'Consultoria e Implantação de Plugin'),
                                        _tile(
                                            context,
                                            'folder',
                                            Icons.folder_outlined,
                                            'Abrir pasta',
                                            'Acessar os arquivos do projeto',
                                            enabled: hasFolder),
                                        _tile(
                                            context,
                                            'open',
                                            Icons.table_chart_outlined,
                                            'Abrir planilha no Excel',
                                            'Abrir o arquivo no aplicativo Excel',
                                            enabled: hasExcel),
                                        _tile(
                                            context,
                                            'check',
                                            Icons.checklist_rounded,
                                            'Checklist',
                                            'Acompanhar as tarefas de cada etapa'),
                                        if (onAudit != null || onPhases != null)
                                          _group('Conferência e fases'),
                                        if (onAudit != null)
                                          _tile(
                                              context,
                                              'audit',
                                              Icons.fact_check_outlined,
                                              'Conferir este projeto no E-Desk',
                                              'Comparar fases, datas e horas'),
                                        if (onPhases != null)
                                          _tile(
                                              context,
                                              'phases',
                                              Icons.sync,
                                              'Enviar fases ao E-Desk',
                                              'Revisar as etapas antes de enviar'),
                                        if (onZendesk != null) ...[
                                          _group('Suporte técnico'),
                                          _tile(context, 'zendesk', Icons.confirmation_number_outlined,
                                            'Abrir solicitação no Zendesk', 'Prioridade oficial, print e conferência antes de enviar'),
                                        ],
                                        if (onAdv != null || onPluginNs != null)
                                          _group('Solicitações ao E-Desk'),
                                        if (onAdv != null)
                                          _tile(
                                              context,
                                              'adv',
                                              Icons.add_task,
                                              'Criar trabalho para ADV',
                                              'Programação · Equipe Go Live'),
                                        if (onPluginNs != null)
                                          _tile(
                                              context,
                                              'plugin-ns',
                                              Icons.add_task,
                                              'Solicitar NS de plugin',
                                              'Dados do cliente e plugin editáveis'),
                                      ]))),
                        ]))))));
    if (!context.mounted) return;
    final actions = <String, VoidCallback>{
      if (onZendesk != null) 'zendesk': onZendesk!,
      if (onDocuments != null) 'documents': onDocuments!,
      if (onReport != null) 'report': onReport!,
      'folder': onFolder,
      'open': onExcel,
      'check': onChecklist,
      if (onAudit != null) 'audit': onAudit!,
      if (onAdv != null) 'adv': onAdv!,
      if (onPluginNs != null) 'plugin-ns': onPluginNs!,
      if (onPhases != null) 'phases': onPhases!
    };
    if ((selected == 'folder' && !hasFolder) || (selected == 'open' && !hasExcel)) return;
    actions[selected]?.call();
  }

  Widget _group(String title) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)));
  Widget _tile(BuildContext context, String value, IconData icon, String title,
          String subtitle, {bool enabled = true}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                  enabled: enabled,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  title: _ActionMenuLabel(icon, title, enabled: enabled),
                  subtitle: Padding(
                      padding: const EdgeInsets.only(left: 32, top: 4),
                      child:
                          Text(subtitle, style: const TextStyle(fontSize: 12))),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap:
                      enabled ? () => Navigator.pop(context, value) : null)));

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
      tooltip: 'Ações do projeto',
      icon: const Icon(Icons.more_horiz, size: 22),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      onSelected: (value) {
        if (value == 'more') {
          _more(context);
          return;
        }
        final actions = {
          'spreadsheet': onEditSpreadsheet,
          'work': onEditWork,
          'comment': onComment,
          'email': onEmail
        };
        if (value == 'spreadsheet' && !hasExcel) return;
        actions[value]?.call();
      },
      itemBuilder: (_) => [
            PopupMenuItem(
                value: 'spreadsheet', enabled: hasExcel,
                child: _ActionMenuLabel(Icons.edit_note_rounded,
                    'Editar planilha no sistema', enabled: hasExcel)),
            const PopupMenuItem(
                value: 'work',
                child:
                    _ActionMenuLabel(Icons.edit_outlined, 'Editar trabalho')),
            const PopupMenuItem(
                value: 'comment',
                child: _ActionMenuLabel(
                    Icons.chat_bubble_outline_rounded, 'Comentários')),
            const PopupMenuItem(
                value: 'email',
                child: _ActionMenuLabel(Icons.mail_outline_rounded, 'E-mails')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'more',
                child:
                    _ActionMenuLabel(Icons.dashboard_outlined, 'Mais ações…')),
          ]);
}

class _ActionMenuLabel extends StatelessWidget {
  const _ActionMenuLabel(this.icon, this.label, {this.enabled = true});
  final bool enabled;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon == Icons.add_task)
          CustomPaint(
              size: const Size.square(20),
              painter: _MenuAdvPainter(Theme.of(context).colorScheme.onSurface))
        else if (icon == Icons.mail_outline_rounded)
          CustomPaint(
              size: const Size.square(20),
              painter:
                  _MenuEmailPainter(Theme.of(context).colorScheme.onSurface))
        else
          Icon(icon,
              size: 20,
              color: enabled
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).disabledColor),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ]);
}

class _MenuAdvPainter extends CustomPainter {
  const _MenuAdvPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 2, 12, 16), const Radius.circular(2)),
        paint);
    canvas.drawLine(const Offset(6, 6), const Offset(12, 6), paint);
    canvas.drawLine(const Offset(6, 9), const Offset(10, 9), paint);
    canvas.drawCircle(const Offset(14, 14), 5, Paint()..color = color);
    final plus = Paint()
      ..color = color.computeLuminance() > .5 ? Colors.black : Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(11.5, 14), const Offset(16.5, 14), plus);
    canvas.drawLine(const Offset(14, 11.5), const Offset(14, 16.5), plus);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MenuAdvPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MenuEmailPainter extends CustomPainter {
  const _MenuEmailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(
        size.width * .08, size.height * .2, size.width * .84, size.height * .6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
    canvas.drawPath(
        Path()
          ..moveTo(rect.left + 1, rect.top + 1)
          ..lineTo(rect.center.dx, rect.center.dy + 1)
          ..lineTo(rect.right - 1, rect.top + 1),
        paint);
  }

  @override
  bool shouldRepaint(covariant _MenuEmailPainter oldDelegate) =>
      oldDelegate.color != color;
}
