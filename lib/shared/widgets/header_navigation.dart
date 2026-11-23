import '../../core/theme/app_visuals.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_appearance.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/cores_app.dart';

class HeaderNavigationItem {
  final int index;
  final String label;
  final IconData icon;

  const HeaderNavigationItem({
    required this.index,
    required this.label,
    required this.icon,
  });
}

const List<HeaderNavigationItem> headerNavigationItems = [
  HeaderNavigationItem(
    index: 0,
    label: 'Projetos',
    icon: Icons.dashboard_outlined,
  ),
  HeaderNavigationItem(
    index: 5,
    label: 'Tarefas',
    icon: Icons.playlist_add_check_rounded,
  ),
  HeaderNavigationItem(
    index: 2,
    label: 'Métricas',
    icon: Icons.analytics_outlined,
  ),
  HeaderNavigationItem(
    index: 1,
    label: 'Cadastro de Trabalhos',
    icon: Icons.work_outline_rounded,
  ),
  HeaderNavigationItem(
    index: 4,
    label: 'Orientações',
    icon: Icons.menu_book_outlined,
  ),
  HeaderNavigationItem(
    index: 3,
    label: 'Projetos Finalizados',
    icon: Icons.task_alt_rounded,
  ),
  HeaderNavigationItem(
    index: 6,
    label: 'Check List',
    icon: Icons.checklist_rounded,
  ),
  HeaderNavigationItem(
    index: 7,
    label: 'Solicitações',
    icon: Icons.markunread_mailbox_outlined,
  ),
];

/// Navigation presentation only; the owning screen decides how to switch tabs.
class HeaderNavigationTab extends StatelessWidget {
  const HeaderNavigationTab(
      {super.key,
      required this.item,
      required this.selectedIndex,
      required this.onSelectTab});
  final HeaderNavigationItem item;
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  @override
  Widget build(BuildContext context) {
    final selecionado = selectedIndex == item.index;

    return Tooltip(
        message: item.label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              onSelectTab(item.index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: selecionado
                  ? AppVisuals.panel(radius: 10, prominent: true).copyWith(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [
                          0,
                          .65,
                          1
                        ],
                          colors: [
                          AppPalette.accent.withValues(alpha: .06),
                          AppPalette.accent.withValues(alpha: .22),
                          AppPalette.accent
                              .withValues(alpha: AppPalette.dark ? .72 : .32),
                        ]))
                  : BoxDecoration(borderRadius: BorderRadius.circular(10)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 22,
                    color: selecionado
                        ? CoresApp.primaria
                        : CoresApp.textoSecundario,
                  ),
                  ...[
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selecionado
                            ? CoresApp.textoPrincipal
                            : CoresApp.textoSecundario,
                        fontSize: 12,
                        fontWeight:
                            selecionado ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 2,
                    width: selecionado ? 20 : 0,
                    decoration: BoxDecoration(
                      color: CoresApp.primaria,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}

/// Returns a tab index through the route without changing application state.
class HeaderNavigationSheet extends StatelessWidget {
  const HeaderNavigationSheet({super.key, required this.selectedIndex});
  final int selectedIndex;
  @override
  Widget build(BuildContext context) {
    AppAppearance.watch(context);
    return Material(
      color: CoresApp.superficie,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(22),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            14,
            12,
            14,
            18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Navegação',
                style: TextStyle(
                  color: CoresApp.textoPrincipal,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...headerNavigationItems.map(
                (item) {
                  final selecionado = selectedIndex == item.index;

                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    tileColor: selecionado
                        ? CoresApp.primaria.withValues(alpha: 0.12)
                        : Colors.transparent,
                    leading: Icon(
                      item.icon,
                      color: selecionado
                          ? CoresApp.primaria
                          : CoresApp.textoSecundario,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        color: selecionado
                            ? CoresApp.textoPrincipal
                            : CoresApp.textoSecundario,
                        fontWeight:
                            selecionado ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: selecionado
                        ? Icon(
                            Icons.check_rounded,
                            color: CoresApp.primaria,
                          )
                        : null,
                    onTap: () {
                      Navigator.of(context).pop(item.index);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
