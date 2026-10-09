import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ComentarioDialogPalette {
  static const background = Color(0xFF0D1C29);
  static const editor = Color(0xFF0C1622);
  static const panel = Color(0xFF171F30);
  static const input = Color(0xFF182639);
  static const border = Color(0xFF2C4057);
  static const text = Color(0xFFE2E8F2);
  static const muted = Color(0xFF94A3B8);
  static const blue = Color(0xFF61A8FF);
  static const green = Color(0xFF28C49A);
  static const gradient = LinearGradient(
    colors: [Color(0xFF377FF5), Color(0xFF2B9EC5), Color(0xFF1EBFA5)],
  );
}

/// The dialog frame keeps the editor and its controllers owned by the caller.
class ComentarioControlsRow extends StatelessWidget {
  const ComentarioControlsRow({
    super.key,
    required this.type,
    required this.tag,
    required this.model,
  });

  final Widget type;
  final Widget tag;
  final Widget model;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 18,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            SizedBox(width: math.min(166, constraints.maxWidth), child: type),
            SizedBox(width: math.min(248, constraints.maxWidth), child: tag),
            SizedBox(width: math.min(320, constraints.maxWidth), child: model),
          ],
        ),
      );
}

class ComentarioDialogLayout extends StatelessWidget {
  const ComentarioDialogLayout({
    super.key,
    required this.title,
    required this.project,
    required this.linked,
    required this.controls,
    required this.editor,
    required this.history,
    required this.attachments,
    required this.characterCount,
    required this.onClose,
    required this.onTest,
    required this.onSend,
    required this.onOpenHistory,
    this.headerAction,
    this.testing = false,
    this.sending = false,
    this.saving = false,
    this.onDrag,
    this.onResize,
  });

  final String title;
  final String project;
  final bool linked;
  final Widget controls;
  final Widget editor;
  final Widget history;
  final Widget attachments;
  final ValueListenable<int> characterCount;
  final VoidCallback onClose;
  final VoidCallback onTest;
  final VoidCallback onSend;
  final VoidCallback onOpenHistory;
  final Widget? headerAction;
  final bool testing;
  final bool sending;
  final bool saving;
  final GestureDragUpdateCallback? onDrag;
  final GestureDragUpdateCallback? onResize;

  bool get busy => testing || sending || saving;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 1100 || constraints.maxHeight < 620;
      final narrow = constraints.maxWidth < 600;
      final horizontalPadding = narrow ? 16.0 : 32.0;

      Widget descriptionLabel() => Row(
            children: [
              const Expanded(
                  child: ComentarioSectionLabel('DESCRIÇÃO DO COMENTÁRIO')),
              ValueListenableBuilder<int>(
                valueListenable: characterCount,
                builder: (context, count, _) => Text(
                  '$count / 2000${narrow ? '' : ' caracteres'}',
                  style: TextStyle(
                    color: count > 2000
                        ? const Color(0xFFF87171)
                        : ComentarioDialogPalette.muted,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          );

      Widget attachmentSection() => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ComentarioSectionLabel('ANEXOS'),
              const SizedBox(height: 9),
              attachments,
            ],
          );

      final body = compact
          ? SingleChildScrollView(
              key: const ValueKey('comment-compact-body'),
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  controls,
                  const SizedBox(height: 24),
                  descriptionLabel(),
                  const SizedBox(height: 12),
                  SizedBox(
                      height: math.max(280.0, constraints.maxHeight - 360),
                      child: editor),
                  const SizedBox(height: 24),
                  attachmentSection(),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: busy ? null : onOpenHistory,
                      icon: const Icon(Icons.history_rounded, size: 17),
                      label: const Text('Histórico do projeto'),
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: EdgeInsets.fromLTRB(
                  horizontalPadding, 24, horizontalPadding, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: constraints.maxWidth - horizontalPadding * 2 - 432,
                      child: controls,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: descriptionLabel()),
                    const SizedBox(width: 432),
                  ]),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: editor),
                        const SizedBox(width: 24),
                        SizedBox(width: 408, child: history),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  attachmentSection(),
                ],
              ),
            );

      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ComentarioDialogPalette.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ComentarioDialogPalette.border),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(
                    height: 24,
                    width: double.infinity,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: ComentarioDialogPalette.gradient)),
                  ),
                  GestureDetector(
                    onPanUpdate: onDrag,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 74,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: ComentarioDialogPalette.border)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 22,
                            backgroundColor: Color(0xFF213752),
                            child: Icon(Icons.notes_rounded,
                                color: ComentarioDialogPalette.blue, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: ComentarioDialogPalette.text,
                                      fontSize: narrow ? 17 : 20,
                                      fontWeight: FontWeight.w700,
                                    )),
                                const SizedBox(height: 5),
                                Text(project,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: ComentarioDialogPalette.muted,
                                      fontSize: 10,
                                    )),
                              ],
                            ),
                          ),
                          if (!narrow) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 7),
                              decoration: BoxDecoration(
                                color: linked
                                    ? const Color(0xFF152E2A)
                                    : ComentarioDialogPalette.input,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                    color: linked
                                        ? const Color(0xFF27584A)
                                        : ComentarioDialogPalette.border),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle,
                                        size: 8,
                                        color: linked
                                            ? ComentarioDialogPalette.green
                                            : ComentarioDialogPalette.muted),
                                    const SizedBox(width: 7),
                                    Text(
                                        linked
                                            ? 'E-Desk vinculado'
                                            : 'Sem vínculo E-Desk',
                                        style: const TextStyle(
                                          color: ComentarioDialogPalette.text,
                                          fontSize: 11,
                                        )),
                                  ]),
                            ),
                            const SizedBox(width: 20),
                          ],
                          if (headerAction != null) headerAction!,
                          IconButton(
                            tooltip: 'Fechar comentário',
                            onPressed: busy ? null : onClose,
                            style: IconButton.styleFrom(
                                backgroundColor: ComentarioDialogPalette.input,
                                fixedSize: const Size(34, 34),
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                            icon: const Icon(Icons.close_rounded,
                                color: ComentarioDialogPalette.muted, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: body),
                  _footer(narrow, compact, horizontalPadding),
                ],
              ),
              if (onResize != null)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: GestureDetector(
                      onPanUpdate: onResize,
                      child: const SizedBox(
                          width: 14,
                          height: 14,
                          child: Icon(
                            Icons.south_east_rounded,
                            size: 11,
                            color: ComentarioDialogPalette.muted,
                          )),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _footer(bool narrow, bool compact, double horizontalPadding) {
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 9,
      runSpacing: 8,
      children: [
        SizedBox(
          width: narrow ? 92 : 122,
          height: 36,
          child: OutlinedButton(
            onPressed: busy ? null : onClose,
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF1D2B3B),
              foregroundColor: ComentarioDialogPalette.text,
              side: const BorderSide(color: ComentarioDialogPalette.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
            child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
          ),
        ),
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onTest,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: const Color(0xFF173A58),
              foregroundColor: const Color(0xFFACD4FA),
              side: const BorderSide(color: Color(0xFF2D638D)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
            icon:
                testing ? _progress() : const Icon(Icons.add_rounded, size: 18),
            label: Text(
                testing
                    ? 'Testando...'
                    : narrow
                        ? 'Testar'
                        : 'Testar sem salvar',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
              gradient: ComentarioDialogPalette.gradient,
              borderRadius: BorderRadius.circular(9)),
          child: SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: busy ? null : onSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: sending
                  ? _progress()
                  : const Icon(Icons.check_rounded, size: 17),
              label: Text(
                  sending
                      ? 'Enviando...'
                      : narrow
                          ? 'Enviar'
                          : 'Enviar comentário',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
    const hint = Text('O teste preenche o formulário no E-Desk sem salvar.',
        style: TextStyle(
          color: ComentarioDialogPalette.muted,
          fontSize: 10,
        ));
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(horizontalPadding, compact ? 10 : 0,
          horizontalPadding, compact ? 12 : 0),
      decoration: const BoxDecoration(
          border:
              Border(top: BorderSide(color: ComentarioDialogPalette.border))),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!narrow) ...[hint, const SizedBox(height: 10)],
              actions,
            ])
          : Row(children: [
              const Expanded(child: hint),
              const SizedBox(width: 20),
              actions
            ]),
    );
  }

  Widget _progress() => const SizedBox(
      width: 15,
      height: 15,
      child: CircularProgressIndicator(
          strokeWidth: 2, color: ComentarioDialogPalette.text));
}

class ComentarioSectionLabel extends StatelessWidget {
  const ComentarioSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
        color: ComentarioDialogPalette.muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
      ));
}

class ComentarioAttachmentTile extends StatelessWidget {
  const ComentarioAttachmentTile(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap,
      this.loading = false,
      this.width = 164});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;
  final double width;

  @override
  Widget build(BuildContext context) => Material(
        color: ComentarioDialogPalette.input,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: width,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ComentarioDialogPalette.border)),
            child: Row(children: [
              Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                    color: const Color(0xFF223E5C),
                    borderRadius: BorderRadius.circular(6)),
                child:
                    Icon(icon, size: 17, color: ComentarioDialogPalette.blue),
              ),
              const SizedBox(width: 9),
              Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: const TextStyle(
                            color: ComentarioDialogPalette.text,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: ComentarioDialogPalette.muted, fontSize: 9)),
                  ])),
              if (loading)
                const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
        ),
      );
}

class ComentarioHistoryPanel extends StatelessWidget {
  const ComentarioHistoryPanel(
      {super.key,
      required this.onSearch,
      required this.onOpenHistory,
      required this.child});
  final ValueChanged<String> onSearch;
  final VoidCallback onOpenHistory;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: ComentarioDialogPalette.panel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: ComentarioDialogPalette.border),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 17, 20, 12),
            child: Text('Histórico do projeto',
                style: TextStyle(
                    color: ComentarioDialogPalette.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: onSearch,
                style: const TextStyle(
                    color: ComentarioDialogPalette.text, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'Buscar comentários...',
                  hintStyle: const TextStyle(
                      color: ComentarioDialogPalette.muted, fontSize: 11),
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: ComentarioDialogPalette.muted, size: 18),
                  filled: true,
                  fillColor: ComentarioDialogPalette.editor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(
                          color: ComentarioDialogPalette.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(
                          color: ComentarioDialogPalette.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(
                          color: ComentarioDialogPalette.blue)),
                ),
              ),
            ),
          ),
          Expanded(child: child),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextButton(
                onPressed: onOpenHistory,
                style: TextButton.styleFrom(
                    foregroundColor: ComentarioDialogPalette.blue,
                    minimumSize: const Size(0, 24),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Ver histórico completo',
                      style: TextStyle(fontSize: 11)),
                  SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 16),
                ]),
              ),
            ),
          ),
        ]),
      );
}

class ComentarioHistoryCard extends StatelessWidget {
  const ComentarioHistoryCard(
      {super.key,
      required this.author,
      required this.date,
      required this.text,
      required this.status,
      this.highlighted = false,
      this.actions,
      this.onTap});
  final String author;
  final String date;
  final String text;
  final String status;
  final bool highlighted;
  final Widget? actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initials = author
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final sent = status.toLowerCase().contains('enviado');
    return Stack(children: [
      Material(
        color: highlighted ? const Color(0xFF192B40) : const Color(0xFF162333),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            decoration: BoxDecoration(
                border: Border.all(
                    color: highlighted
                        ? const Color(0xFF34516E)
                        : ComentarioDialogPalette.border),
                borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFF2B4362),
                  child: Text(initials.isEmpty ? 'U' : initials,
                      style: const TextStyle(
                          color: ComentarioDialogPalette.text,
                          fontSize: 9,
                          fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                          child: Text(author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: ComentarioDialogPalette.text,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700))),
                      const SizedBox(width: 6),
                      Text(date,
                          style: const TextStyle(
                              color: ComentarioDialogPalette.muted,
                              fontSize: 9)),
                      if (actions != null)
                        SizedBox(width: 22, height: 20, child: actions!),
                    ]),
                    const SizedBox(height: 7),
                    Text(text.isEmpty ? 'Comentário com anexo' : text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: ComentarioDialogPalette.muted,
                            fontSize: 11,
                            height: 1.4)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: sent
                              ? const Color(0xFF173E35)
                              : const Color(0xFF453A1B),
                          borderRadius: BorderRadius.circular(15)),
                      child: Text(status,
                          style: TextStyle(
                              color: sent
                                  ? const Color(0xFF8CDDC2)
                                  : const Color(0xFFF4D26B),
                              fontSize: 9)),
                    ),
                  ])),
            ]),
          ),
        ),
      ),
      if (highlighted)
        Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
                width: 3,
                decoration: BoxDecoration(
                    color: ComentarioDialogPalette.blue,
                    borderRadius: BorderRadius.circular(4)))),
    ]);
  }
}
