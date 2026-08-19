import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class Cabecalho extends StatelessWidget implements PreferredSizeWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  const Cabecalho({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.searchQuery,
    required this.onSearchChanged,
    required String userName,
  });

  @override
  Size get preferredSize => const Size.fromHeight(50);

  String _getUserName() {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return 'Usuário';
    }

    final String displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }

    final String email = user.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return email;
    }

    return 'Usuário';
  }

  @override
  Widget build(BuildContext context) {
    final String userName = _getUserName();
    final bool isProjectsSelected = selectedIndex == 0;

    return AppBar(
      backgroundColor: const Color(0xFF252538),
      toolbarHeight: 50,
      titleSpacing: 24,
      title: Row(
        children: [
          // Título com comportamento visual idêntico às abas (sublinhado e mudança de cor)
          InkWell(
            onTap: () => onSelectTab(0),
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'Gestão de Horas e Projetos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: isProjectsSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isProjectsSelected ? Colors.white : Colors.white60,
                    ),
                  ),
                  if (isProjectsSelected)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 3,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTopTabItem(
                    index: 1,
                    label: 'Cadastro de Trabalho',
                    icon: Icons.work_outline,
                  ),
                  _buildTopTabItem(
                    index: 2,
                    label: 'Métricas',
                    icon: Icons.bar_chart_rounded,
                  ),
                  _buildTopTabItem(
                    index: 3,
                    label: 'Proj. Finalizados',
                    icon: Icons.check_circle_outline,
                  ),
                  _buildTopTabItem(
                    index: 4,
                    label: 'Orientações',
                    icon: Icons.help_outline_rounded,
                  ),
                  _buildTopTabItem(
                    index: 5,
                    label: 'Histórico',
                    icon: Icons.warning_rounded,
                  ),
                  _buildTopTabItem(
                    index: 6,
                    label: 'Check List',
                    icon: Icons.checklist_rounded,
                  ),
                  _buildTopTabItem(
                    index: 7,
                    label: 'Solicitações',
                    icon: Icons.folder_open_rounded,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                height: 34,
                child: TextField(
                  onChanged: onSearchChanged,
                  controller: TextEditingController(
                    text: searchQuery,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.white38,
                      size: 16,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 0,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: 1,
                height: 24,
                color: Colors.white12,
              ),
              const SizedBox(width: 14),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.25),
                  ),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 180,
                ),
                child: Text(
                  userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      elevation: 0,
    );
  }

  Widget _buildTopTabItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = selectedIndex == index;

    return InkWell(
      onTap: () => onSelectTab(index),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(
          horizontal: 11,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.blue : Colors.white60,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 3,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
