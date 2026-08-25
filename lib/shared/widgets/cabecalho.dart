// ignore_for_file: unnecessary_cast

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/data/services/user_cache.dart';

class Cabecalho extends StatefulWidget implements PreferredSizeWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String userName;

  const Cabecalho({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.userName,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  State<Cabecalho> createState() => _CabecalhoState();
}

class _CabecalhoState extends State<Cabecalho> {
  final UserCache _cache = UserCache();

  @override
  void initState() {
    super.initState();

    if (!_cache.carregado) {
      _carregarFotoDoFirestore();
    }
  }

  // ============================================================
  // CARREGAR FOTO E NOME DO USUÁRIO
  // ============================================================

  Future<void> _carregarFotoDoFirestore() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final String displayName = user.displayName?.trim() ?? '';
        final String email = user.email?.trim() ?? '';

        _cache.userName = displayName.isNotEmpty
            ? displayName
            : (email.isNotEmpty
                ? email
                : (widget.userName.isNotEmpty ? widget.userName : 'Usuário'));

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists && doc.data()?['photoBase64'] != null) {
          final String base64Str = doc.data()!['photoBase64'];

          final bytes = base64Decode(base64Str);

          if (mounted) {
            setState(() {
              _cache.fotoPerfilProvider = MemoryImage(bytes);
            });
          }
        }
      }
    } catch (e) {
      debugPrint(
        'Erro ao carregar foto no cabeçalho: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _cache.carregado = true;
        });
      }
    }
  }

  // ============================================================
  // ALTERAR FOTO DE PERFIL
  // ============================================================

  Future<void> _alterarFotoPerfil() async {
    final ImagePicker picker = ImagePicker();

    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 70,
    );

    if (image == null) {
      return;
    }

    try {
      final User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final bytes = await image.readAsBytes();

        final String base64Image = base64Encode(bytes);

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {
            'photoBase64': base64Image,
          },
          SetOptions(merge: true),
        );

        if (mounted) {
          setState(() {
            _cache.fotoPerfilProvider = MemoryImage(bytes);
            _cache.carregado = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Foto alterada com sucesso!',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao alterar foto: $e',
            ),
            backgroundColor: CoresApp.erro,
          ),
        );
      }
    }
  }

  // ============================================================
  // NOME DO USUÁRIO
  // ============================================================

  String _getUserName() {
    if (_cache.userName.isNotEmpty) {
      return _cache.userName;
    }

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return widget.userName.isNotEmpty ? widget.userName : 'Usuário';
    }

    final String displayName = user.displayName?.trim() ?? '';

    if (displayName.isNotEmpty) {
      return displayName;
    }

    final String email = user.email?.trim() ?? '';

    if (email.isNotEmpty) {
      return email;
    }

    return widget.userName.isNotEmpty ? widget.userName : 'Usuário';
  }

// ============================================================
// CONFIRMAÇÃO DE LOGOUT
// ============================================================

  Future<void> _confirmarLogout() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.fundoSecundario,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresDashboard.tabelaBorda,
              width: 1,
            ),
          ),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: CoresApp.erro.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: CoresApp.erro,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Sair da conta',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Deseja realmente sair da sua conta?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 14,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            14,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              icon: const Icon(
                Icons.logout_rounded,
                size: 17,
              ),
              label: const Text(
                'Sair',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    await _realizarLogout();
  }

  // ============================================================
  // REALIZAR LOGOUT
  // ============================================================

  // ============================================================
// REALIZAR LOGOUT
// ============================================================

  // ============================================================
// REALIZAR LOGOUT
// ============================================================

  Future<void> _realizarLogout() async {
    try {
      // ----------------------------------------------------------
      // 1. FAZ LOGOUT NO FIREBASE
      // ----------------------------------------------------------

      await FirebaseAuth.instance.signOut();

      // ----------------------------------------------------------
      // 2. LIMPA O CACHE DA FOTO E DO NOME
      // ----------------------------------------------------------

      _cache.carregado = false;
      _cache.userName = '';
      _cache.fotoPerfilProvider = null;

      // ----------------------------------------------------------
      // 3. NÃO PRECISAMOS NAVEGAR MANUALMENTE
      // ----------------------------------------------------------
      //
      // O authStateChanges() do app.dart detectará o signOut()
      // e automaticamente trocará:
      //
      // MainNavigationScreen
      //
      // por:
      //
      // LoginScreen
      //
      // ----------------------------------------------------------

      debugPrint('Logout realizado com sucesso.');
    } catch (e) {
      debugPrint('Erro ao realizar logout: $e');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao sair da conta: $e',
          ),
          backgroundColor: CoresApp.erro,
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final String nomeUsuario = _getUserName();

    final bool carregando = !_cache.carregado;

    final ImageProvider? fotoProvider = _cache.fotoPerfilProvider;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isCompact = constraints.maxWidth < 1100;

          return AppBar(
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            toolbarHeight: 60,
            titleSpacing: 20,
            title: Row(
              children: [
                // ==================================================
                // LOGOTIPO
                // ==================================================

                SizedBox(
                  height: 80,
                  width: 150,
                  child: Image.asset(
                    'assets/images/Logo_H.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Text(
                        'Gerenciamento de Horas',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: CoresApp.textoPrincipal,
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(width: 12),

                // ==================================================
                // MENU
                // ==================================================

                Expanded(
                  child: isCompact
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: PopupMenuButton<int>(
                            icon: const Icon(
                              Icons.menu,
                              color: CoresApp.textoPrincipal,
                              size: 24,
                            ),
                            tooltip: 'Menu de Navegação',
                            color: CoresDashboard.fundoSecundario,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: CoresApp.primaria.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            onSelected: (int index) {
                              widget.onSelectTab(index);
                            },
                            itemBuilder: (BuildContext context) => [
                              _buildPopupMenuItem(
                                0,
                                'Projetos',
                              ),
                              _buildPopupMenuItem(
                                1,
                                'Cadastro de Trabalho',
                              ),
                              _buildPopupMenuItem(
                                2,
                                'Métricas',
                              ),
                              _buildPopupMenuItem(
                                3,
                                'Projetos Finalizados',
                              ),
                              _buildPopupMenuItem(
                                4,
                                'Orientações',
                              ),
                              _buildPopupMenuItem(
                                5,
                                'Tarefas Executadas',
                              ),
                              _buildPopupMenuItem(
                                6,
                                'Check List',
                              ),
                              _buildPopupMenuItem(
                                7,
                                'Solicitações',
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTopTabItem(
                                index: 0,
                                label: 'Projetos',
                                icon: Icons.storefront,
                              ),
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
                                label: 'Projetos Finalizados',
                                icon: Icons.check_circle_outline,
                              ),
                              _buildTopTabItem(
                                index: 4,
                                label: 'Orientações',
                                icon: Icons.help_outline_rounded,
                              ),
                              _buildTopTabItem(
                                index: 5,
                                label: 'Tarefas Executadas',
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
                                icon: Icons.mail_outline,
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),

            // ====================================================
            // ÁREA DO USUÁRIO
            // ====================================================

            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ============================================
                    // PESQUISA
                    // ============================================

                    SizedBox(
                      width: 180,
                      height: 36,
                      child: TextField(
                        onChanged: widget.onSearchChanged,
                        controller: TextEditingController(
                          text: widget.searchQuery,
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
                            borderRadius: BorderRadius.circular(
                              TamanhosApp.raioBotao,
                            ),
                            borderSide: const BorderSide(
                              color: CoresApp.borda,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              TamanhosApp.raioBotao,
                            ),
                            borderSide: const BorderSide(
                              color: CoresApp.primaria,
                            ),
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

                    // ============================================
                    // FOTO DO USUÁRIO
                    // ============================================

                    Tooltip(
                      message: 'Clique para alterar a foto de perfil',
                      child: InkWell(
                        onTap: _alterarFotoPerfil,
                        borderRadius: BorderRadius.circular(16),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: CoresApp.primaria.withOpacity(0.15),
                          backgroundImage: fotoProvider,
                          child: carregando
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: CoresApp.primaria,
                                  ),
                                )
                              : fotoProvider == null
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

                    // ============================================
                    // NOME DO USUÁRIO
                    // CLICÁVEL PARA LOGOUT
                    // ============================================

                    Tooltip(
                      message: 'Clique para sair da conta',
                      child: InkWell(
                        onTap: _confirmarLogout,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
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
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: CoresApp.textoSecundario,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            elevation: 0,
          );
        },
      ),
    );
  }

  // ============================================================
  // ITEM DO MENU COMPACTO
  // ============================================================

  PopupMenuItem<int> _buildPopupMenuItem(
    int index,
    String label,
  ) {
    final bool isSelected = widget.selectedIndex == index;

    return PopupMenuItem<int>(
      value: index,
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? CoresApp.primaria : CoresApp.textoPrincipal,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  // ============================================================
  // ITEM DO MENU SUPERIOR
  // ============================================================

  Widget _buildTopTabItem({
    required int index,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = widget.selectedIndex == index;

    return InkWell(
      onTap: () => widget.onSelectTab(index),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
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
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
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
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(
                        2,
                      ),
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
