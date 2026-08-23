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
      debugPrint('Erro ao carregar foto no cabeçalho: $e');
    } finally {
      if (mounted) {
        setState(() {
          _cache.carregado = true;
        });
      }
    }
  }

  Future<void> _alterarFotoPerfil() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 70,
    );

    if (image == null) return;

    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final bytes = await image.readAsBytes();
        final String base64Image = base64Encode(bytes);

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'photoBase64': base64Image,
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() {
            _cache.fotoPerfilProvider = MemoryImage(bytes);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto alterada com sucesso!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alterar foto: $e')),
        );
      }
    }
  }

  String _getUserName() {
    if (_cache.userName.isNotEmpty) return _cache.userName;
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return widget.userName.isNotEmpty ? widget.userName : 'Usuário';
    }

    final String displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;

    final String email = user.email?.trim() ?? '';
    if (email.isNotEmpty) return email;

    return widget.userName.isNotEmpty ? widget.userName : 'Usuário';
  }

  @override
  Widget build(BuildContext context) {
    final String nomeUsuario = _getUserName();
    final bool isProjectsSelected = widget.selectedIndex == 0;
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
          // Se a largura for menor que 1100 pixels, exibe o menu responsivo (hambúrguer)
          final bool isCompact = constraints.maxWidth < 1100;

          return AppBar(
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            toolbarHeight: 60,
            titleSpacing: 20,
            title: Row(
              children: [
                Tooltip(
                  message: 'Gestão de Horas e Projetos',
                  decoration: BoxDecoration(
                    color: CoresDashboard.fundoSecundario.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: CoresApp.primaria.withOpacity(0.4),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  textStyle: const TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  preferBelow: true,
                  verticalOffset: 16,
                  child: InkWell(
                    onTap: () => widget.onSelectTab(0),
                    borderRadius: BorderRadius.circular(TamanhosApp.raioBotao),
                    child: SizedBox(
                      height: 60,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: 80,
                              width: 120,
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
                                    borderRadius: const BorderRadius.vertical(
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
                ),
                const SizedBox(width: 8),
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
                              _buildPopupMenuItem(1, 'Cadastro de Trabalho'),
                              _buildPopupMenuItem(2, 'Métricas'),
                              _buildPopupMenuItem(3, 'Projetos Finalizados'),
                              _buildPopupMenuItem(4, 'Orientações'),
                              _buildPopupMenuItem(5, 'Tarefas Executadas'),
                              _buildPopupMenuItem(6, 'Check List'),
                              _buildPopupMenuItem(7, 'Solicitações'),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTopTabItem(
                                index: 1,
                                label: 'Cadastro de Trabalho',
                                assetImagePath:
                                    'assets/images/cadastro_trabalho.png',
                              ),
                              _buildTopTabItem(
                                index: 2,
                                label: 'Métricas',
                                assetImagePath: 'assets/images/metricas.png',
                              ),
                              _buildTopTabItem(
                                index: 3,
                                label: 'Projetos Finalizados',
                                assetImagePath:
                                    'assets/images/projetos_finalizados.png',
                              ),
                              _buildTopTabItem(
                                index: 4,
                                label: 'Orientações',
                                assetImagePath: 'assets/images/orientacoes.png',
                              ),
                              _buildTopTabItem(
                                index: 5,
                                label: 'Tarefas Executadas',
                                assetImagePath:
                                    'assets/images/tarefas_executadas.png',
                              ),
                              _buildTopTabItem(
                                index: 6,
                                label: 'Check List',
                                assetImagePath: 'assets/images/check_list.png',
                              ),
                              _buildTopTabItem(
                                index: 7,
                                label: 'Solicitações',
                                assetImagePath:
                                    'assets/images/solicitacoes.png',
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
                            borderRadius:
                                BorderRadius.circular(TamanhosApp.raioBotao),
                            borderSide: const BorderSide(color: CoresApp.borda),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(TamanhosApp.raioBotao),
                            borderSide:
                                const BorderSide(color: CoresApp.primaria),
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
                        onTap: _alterarFotoPerfil,
                        borderRadius: BorderRadius.circular(16),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: CoresApp.primaria.withOpacity(0.15),
                          backgroundImage: fotoProvider,
                          child: (carregando)
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: CoresApp.primaria,
                                  ),
                                )
                              : (fotoProvider == null)
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
          );
        },
      ),
    );
  }

  PopupMenuItem<int> _buildPopupMenuItem(int index, String label) {
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

  Widget _buildTopTabItem({
    required int index,
    required String label,
    required String assetImagePath,
  }) {
    final bool isSelected = widget.selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.2),
      child: Tooltip(
        message: label,
        decoration: BoxDecoration(
          color: CoresDashboard.fundoSecundario.withOpacity(0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: CoresApp.primaria.withOpacity(0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: const TextStyle(
          color: CoresApp.textoPrincipal,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        preferBelow: true,
        verticalOffset: 16,
        child: InkWell(
          onTap: () => widget.onSelectTab(index),
          borderRadius: BorderRadius.circular(TamanhosApp.raioBotao),
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 50,
                    width: 133,
                    child: Image.asset(
                      assetImagePath,
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? CoresApp.textoPrincipal
                                  : CoresApp.textoSecundario,
                            ),
                          ),
                        );
                      },
                    ),
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
      ),
    );
  }
}
