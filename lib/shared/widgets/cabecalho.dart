// ignore_for_file: unnecessary_cast

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';

class Cabecalho extends StatelessWidget implements PreferredSizeWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String userName;
  final ImageProvider?
      fotoPerfilProvider; // Imagem pronta vinda da tela principal
  final bool carregandoFoto; // Status de carregamento vindo da tela principal
  final VoidCallback? onAlterarFoto; // Função para abrir o seletor de foto

  const Cabecalho({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.userName,
    this.fotoPerfilProvider,
    this.carregandoFoto = false,
    this.onAlterarFoto,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  String _getUserName() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return userName.isNotEmpty ? userName : 'Usuário';

    final String displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;

    final String email = user.email?.trim() ?? '';
    if (email.isNotEmpty) return email;

    return userName.isNotEmpty ? userName : 'Usuário';
  }

  @override
  Widget build(BuildContext context) {
    final String nomeUsuario = _getUserName();
    final bool isProjectsSelected = selectedIndex == 0;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: CoresDashboard.fundoSecundario,
        border: Border(
          bottom: BorderSide(
            color: CoresDashboard.tabelaBorda,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        toolbarHeight: 60,
        titleSpacing: 20,
        title: Row(
          children: [
            InkWell(
              onTap: () => onSelectTab(0),
              borderRadius: BorderRadius.circular(TamanhosApp.raioBotao),
              child: SizedBox(
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 100,
                        width: 180,
                        child: Image.asset(
                          'assets/images/Logo_H.png',
                          fit: BoxFit.fill,
                          errorBuilder: (context, error, stackTrace) {
                            return Text(
                              'Gestão de Horas e Projetos',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isProjectsSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isProjectsSelected
                                    ? CoresApp.textoPrincipal
                                    : CoresApp.textoSecundario,
                              ),
                            );
                          },
                        ),
                      ),
                      if (isProjectsSelected)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: CoresApp.primaria,
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
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopTabItem(
                        index: 1,
                        label: 'Cadastro de Trabalho',
                        icon: Icons.add_circle_outline_rounded),
                    _buildTopTabItem(
                        index: 2,
                        label: 'Métricas',
                        icon: Icons.bar_chart_rounded),
                    _buildTopTabItem(
                        index: 3,
                        label: 'Projetos Finalizados',
                        icon: Icons.task_alt_rounded),
                    _buildTopTabItem(
                        index: 4,
                        label: 'Orientações',
                        icon: Icons.help_outline_rounded),
                    _buildTopTabItem(
                        index: 5,
                        label: 'Tarefas Executadas',
                        icon: Icons.warning_amber_rounded),
                    _buildTopTabItem(
                        index: 6,
                        label: 'Check List',
                        icon: Icons.checklist_rounded),
                    _buildTopTabItem(
                        index: 7,
                        label: 'Solicitações',
                        icon: Icons.folder_open_rounded),
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
                  height: 36,
                  child: TextField(
                    onChanged: onSearchChanged,
                    controller: TextEditingController(
                      text: searchQuery,
                    ),
                    style: const TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar...',
                      hintStyle: const TextStyle(
                        color: CoresApp.textoFraco,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: CoresApp.textoSecundario,
                        size: 16,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                      ),
                      filled: true,
                      fillColor: CoresTelas.campoFormulario,
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(TamanhosApp.raioBotao),
                        borderSide: const BorderSide(color: CoresApp.borda),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(TamanhosApp.raioBotao),
                        borderSide: const BorderSide(color: CoresApp.primaria),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 1,
                  height: 24,
                  color: CoresDashboard.tabelaDivisor,
                ),
                const SizedBox(width: 14),
                Tooltip(
                  message: 'Clique para alterar a foto de perfil',
                  child: InkWell(
                    onTap: onAlterarFoto,
                    borderRadius: BorderRadius.circular(16),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: CoresApp.primaria.withOpacity(0.15),
                      backgroundImage: fotoPerfilProvider,
                      child: (carregandoFoto)
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CoresApp.primaria,
                              ),
                            )
                          : (fotoPerfilProvider == null)
                              ? const Icon(
                                  Icons.person_outline_rounded,
                                  color: CoresApp.primaria,
                                  size: 18,
                                )
                              : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 150,
                  ),
                  child: Text(
                    nomeUsuario,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        elevation: 0,
      ),
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
      borderRadius: BorderRadius.circular(TamanhosApp.raioBotao),
      child: Container(
        height: 60,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color:
                      isSelected ? CoresApp.primaria : CoresApp.textoSecundario,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? CoresApp.textoPrincipal
                        : CoresApp.textoSecundario,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12,
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
                  decoration: BoxDecoration(
                    color: CoresApp.primaria,
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
