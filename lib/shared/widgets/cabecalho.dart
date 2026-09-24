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
  Size get preferredSize => const Size.fromHeight(64);

  @override
  State<Cabecalho> createState() => _CabecalhoState();
}

class _CabecalhoState extends State<Cabecalho> {
  final UserCache _cache = UserCache();

  late final TextEditingController _searchController;

  bool _carregandoFoto = false;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController(
      text: widget.searchQuery,
    );

    if (!_cache.carregado) {
      _carregarFotoDoFirestore();
    }
  }

  @override
  void didUpdateWidget(covariant Cabecalho oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.searchQuery != widget.searchQuery &&
        _searchController.text != widget.searchQuery) {
      _searchController.text = widget.searchQuery;

      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // FOTO / USUÁRIO
  // ============================================================

  Future<void> _carregarFotoDoFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _cache.carregado = true;
        return;
      }

      _cache.userName = user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : user.email?.split('@').first ?? widget.userName;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();

      if (data != null) {
        final fotoBase64 = data['photoBase64'];

        if (fotoBase64 is String && fotoBase64.isNotEmpty) {
          try {
            final bytes = base64Decode(fotoBase64);

            _cache.fotoPerfilProvider = MemoryImage(bytes);
          } catch (_) {
            _cache.fotoPerfilProvider = null;
          }
        }
      }

      _cache.carregado = true;

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      _cache.carregado = true;
    }
  }

  Future<void> _alterarFotoPerfil() async {
    if (_carregandoFoto) return;

    try {
      final picker = ImagePicker();

      final XFile? imagem = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 70,
      );

      if (imagem == null) return;

      setState(() {
        _carregandoFoto = true;
      });

      final bytes = await imagem.readAsBytes();
      final base64Imagem = base64Encode(bytes);

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'photoBase64': base64Imagem,
        },
        SetOptions(merge: true),
      );

      _cache.fotoPerfilProvider = MemoryImage(bytes);
      _cache.carregado = true;

      if (mounted) {
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil atualizada.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível alterar a foto: $e',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _carregandoFoto = false;
        });
      }
    }
  }

  String _getUserName() {
    final cacheName = _cache.userName?.trim();

    if (cacheName != null && cacheName.isNotEmpty) {
      return cacheName;
    }

    final user = FirebaseAuth.instance.currentUser;

    final displayName = user?.displayName?.trim();

    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user?.email?.trim();

    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    final widgetName = widget.userName.trim();

    if (widgetName.isNotEmpty) {
      return widgetName;
    }

    return 'Usuário';
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _confirmarLogout() async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: CoresApp.superficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Sair da conta',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Deseja realmente sair da sua conta?',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.primaria,
                foregroundColor: CoresApp.textoPrincipal,
              ),
              child: const Text('Sair'),
            ),
          ],
        );
      },
    );

    if (resultado == true) {
      await _realizarLogout();
    }
  }

  Future<void> _realizarLogout() async {
    try {
      await FirebaseAuth.instance.signOut();

      _cache.carregado = false;
      _cache.userName = '';
      _cache.fotoPerfilProvider = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao sair da conta: $e',
            ),
          ),
        );
      }
    }
  }

  // ============================================================
  // MENU DO USUÁRIO
  // ============================================================

  Future<void> _abrirMenuUsuario() async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: CoresApp.superficie,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                18,
                12,
                18,
                18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _buildProfileAvatar(size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getUserName(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Conta conectada',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(
                    color: CoresApp.borda,
                    height: 1,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: CoresApp.primaria.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.photo_camera_outlined,
                        color: CoresApp.primaria,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Alterar foto de perfil',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Escolher uma nova imagem',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop('foto');
                    },
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: CoresApp.erro.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: CoresApp.erro,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Sair da conta',
                      style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Encerrar a sessão atual',
                      style: TextStyle(
                        color: CoresApp.textoSecundario,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop('logout');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    if (escolha == 'foto') {
      await _alterarFotoPerfil();
    } else if (escolha == 'logout') {
      await _confirmarLogout();
    }
  }

  // ============================================================
  // AVATAR
  // ============================================================

  Widget _buildProfileAvatar({
    double size = 38,
  }) {
    final foto = _cache.fotoPerfilProvider;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: CoresApp.borda,
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: foto != null
            ? Image(
                image: foto,
                fit: BoxFit.cover,
              )
            : Container(
                color: CoresApp.primaria.withOpacity(0.18),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: CoresApp.primaria,
                  size: size * 0.52,
                ),
              ),
      ),
    );
  }

  // ============================================================
  // NAVEGAÇÃO
  // ============================================================

  final List<_MenuItemData> _menuItems = const [
    _MenuItemData(
      index: 0,
      label: 'Projetos',
      icon: Icons.dashboard_outlined,
    ),
    _MenuItemData(
      index: 1,
      label: 'Cadastro de Trabalhos',
      icon: Icons.work_outline_rounded,
    ),
    _MenuItemData(
      index: 2,
      label: 'Métricas',
      icon: Icons.analytics_outlined,
    ),
    _MenuItemData(
      index: 3,
      label: 'Projetos Finalizados',
      icon: Icons.task_alt_rounded,
    ),
    _MenuItemData(
      index: 4,
      label: 'Orientações',
      icon: Icons.menu_book_outlined,
    ),
    _MenuItemData(
      index: 5,
      label: 'Tarefas',
      icon: Icons.playlist_add_check_rounded,
    ),
    _MenuItemData(
      index: 6,
      label: 'Check List',
      icon: Icons.checklist_rounded,
    ),
    _MenuItemData(
      index: 7,
      label: 'Solicitações',
      icon: Icons.markunread_mailbox_outlined,
    ),
  ];

  Widget _buildTopTabItem(
    _MenuItemData item,
    bool compact,
  ) {
    final selecionado = widget.selectedIndex == item.index;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          widget.onSelectTab(item.index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 11,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selecionado
                ? CoresApp.primaria.withOpacity(0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: compact ? 18 : 19,
                color:
                    selecionado ? CoresApp.primaria : CoresApp.textoSecundario,
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selecionado
                        ? CoresApp.textoPrincipal
                        : CoresApp.textoSecundario,
                    fontSize: 10.5,
                    fontWeight: selecionado ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2,
                width: selecionado ? 24 : 0,
                decoration: BoxDecoration(
                  color: CoresApp.primaria,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MENU COMPACTO
  // ============================================================

  Future<void> _abrirMenuNavegacao() async {
    final escolha = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: CoresApp.superficie,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(22),
            ),
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
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Navegação',
                    style: TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._menuItems.map(
                    (item) {
                      final selecionado = widget.selectedIndex == item.index;

                      return ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: selecionado
                            ? CoresApp.primaria.withOpacity(0.12)
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
                            ? const Icon(
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
      },
    );

    if (!mounted || escolha == null) return;

    widget.onSelectTab(escolha);
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final bool isVeryCompact = width < 850;
    final bool isCompact = width < 1150;

    final userName = _getUserName();

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: CoresApp.fundo,
          border: const Border(
            bottom: BorderSide(
              color: CoresApp.bordaSuave,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              // ==================================================
              // LOGO
              // ==================================================

              Padding(
                padding: EdgeInsets.only(
                  left: isVeryCompact ? 10 : 16,
                  right: isVeryCompact ? 8 : 14,
                ),
                child: SizedBox(
                  width: isVeryCompact ? 108 : 132,
                  height: 54,
                  child: Image.asset(
                    'assets/images/Logo_H.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              Container(
                width: 1,
                height: 30,
                color: CoresApp.bordaSuave,
              ),

              const SizedBox(width: 6),

              // ==================================================
              // NAVEGAÇÃO
              // ==================================================

              if (isVeryCompact)
                IconButton(
                  tooltip: 'Navegação',
                  onPressed: _abrirMenuNavegacao,
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: CoresApp.textoPrincipal,
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _menuItems
                          .map(
                            (item) => _buildTopTabItem(
                              item,
                              isCompact,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),

              if (!isVeryCompact) const SizedBox(width: 8),

              // ==================================================
              // BUSCA
              // ==================================================

              if (!isVeryCompact)
                SizedBox(
                  width: isCompact ? 145 : 185,
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      widget.onSearchChanged(value);
                      setState(() {});
                    },
                    style: const TextStyle(
                      color: CoresApp.textoPrincipal,
                      fontSize: 12.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar...',
                      hintStyle: const TextStyle(
                        color: CoresApp.textoFraco,
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: CoresApp.textoSecundario,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Limpar',
                              onPressed: () {
                                _searchController.clear();
                                widget.onSearchChanged('');
                                setState(() {});
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: CoresApp.textoSecundario,
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: CoresApp.superficieEscura,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(
                          color: CoresApp.bordaSuave,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(
                          color: CoresApp.bordaSuave,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11),
                        borderSide: const BorderSide(
                          color: CoresApp.primaria,
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              Container(
                width: 1,
                height: 30,
                color: CoresApp.bordaSuave,
              ),

              // ==================================================
              // PERFIL
              // ==================================================

              const SizedBox(width: 8),

              if (isVeryCompact)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _abrirMenuUsuario,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Stack(
                      children: [
                        _buildProfileAvatar(size: 38),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: CoresApp.sucesso,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: CoresApp.fundo,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _abrirMenuUsuario,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: CoresApp.superficieEscura,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: CoresApp.bordaSuave,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            _buildProfileAvatar(size: 36),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: CoresApp.sucesso,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: CoresApp.fundo,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 9),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: isCompact ? 105 : 145,
                          ),
                          child: Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CoresApp.textoPrincipal,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: CoresApp.textoSecundario,
                          size: 19,
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// MODELO INTERNO DOS ITENS DO MENU
// ================================================================

class _MenuItemData {
  final int index;
  final String label;
  final IconData icon;

  const _MenuItemData({
    required this.index,
    required this.label,
    required this.icon,
  });
}
