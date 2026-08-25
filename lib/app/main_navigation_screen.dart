import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gerenciador_horas/core/theme/app_theme.dart';

import 'package:gerenciador_horas/domain/models/work_format_model.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';

import 'package:gerenciador_horas/features/dashboard/dashboard_screen.dart';
import 'package:gerenciador_horas/features/tasks/tarefas_executadas_screen.dart';

import 'package:gerenciador_horas/features/metrics/metrics_screen.dart'
    as metrics;

import 'package:gerenciador_horas/features/completed_projects/completed_projects_screen.dart'
    as completed;

import 'package:gerenciador_horas/features/orientations/orientacao_screen.dart';
import 'package:gerenciador_horas/features/work_formats/work_formats_screen.dart';
import 'package:gerenciador_horas/features/checklist_formats/checklist_formats_screen.dart';
import 'package:gerenciador_horas/features/solicitacoes/solicitacoes_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  int _selectedIndex = 0;

  final TimeLogStore _timeLogStore = TimeLogStore();

  List<WorkFormat> _workFormats = [];

  bool _isLoadingFormats = true;

  String _userName = 'Usuário';

  @override
  void initState() {
    super.initState();

    _loadUserData();
    _loadWorkFormats();
  }

  // ============================================================
  // CARREGAR USUÁRIO
  // ============================================================

  void _loadUserData() {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        _userName = user.displayName!;
      } else if (user.email != null && user.email!.isNotEmpty) {
        _userName = user.email!.split('@').first;
      }
    }
  }

  // ============================================================
  // CARREGAR MODELOS DE TRABALHO
  // ============================================================

  Future<void> _loadWorkFormats() async {
    try {
      final formats = await _firebaseService.getWorkFormats();

      if (mounted) {
        setState(() {
          _workFormats = formats;
          _isLoadingFormats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFormats = false;
        });
      }
    }
  }

  // ============================================================
  // NAVEGAÇÃO
  // ============================================================

  void _onSelectTab(int index) {
    if (index < 0 || index > 7) {
      return;
    }

    // Sempre que voltar para o Dashboard,
    // atualizamos os modelos de trabalho.
    if (index == 0) {
      _loadWorkFormats();
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  // ============================================================
  // FUNDO GLOBAL
  // ============================================================

  Widget _buildGlobalBackground({
    required Widget child,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // --------------------------------------------------------
        // IMAGEM DE FUNDO
        // --------------------------------------------------------

        Image.asset(
          AppTheme.caminhoFundo,
          fit: BoxFit.cover,
        ),

        // --------------------------------------------------------
        // CAMADA ESCURA SOBRE A IMAGEM
        //
        // Deixa os textos, cards e tabelas mais fáceis de enxergar.
        // --------------------------------------------------------

        Container(
          color: Colors.black.withOpacity(
            AppTheme.opacidadeFundo,
          ),
        ),

        // --------------------------------------------------------
        // PÁGINA ATUAL
        // --------------------------------------------------------

        child,
      ],
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFormats) {
      return _buildGlobalBackground(
        child: const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    // ==========================================================
    // TELAS
    // ==========================================================

    final List<Widget> screens = <Widget>[
      // --------------------------------------------------------
      // 0 - DASHBOARD
      // --------------------------------------------------------

      DashboardScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        workFormats: _workFormats,
        timeLogStore: _timeLogStore,
      ),

      // --------------------------------------------------------
      // 1 - MODELOS / TRABALHOS
      // --------------------------------------------------------

      WorkFormatsScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        userName: _userName,
      ),

      // --------------------------------------------------------
      // 2 - MÉTRICAS
      // --------------------------------------------------------

      metrics.MetricsScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        timeLogStore: _timeLogStore,
        userName: _userName,
      ),

      // --------------------------------------------------------
      // 3 - PROJETOS FINALIZADOS
      // --------------------------------------------------------

      completed.CompletedProjectsScreen(
        firebaseService: _firebaseService,
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        userName: _userName,
      ),

      // --------------------------------------------------------
      // 4 - ORIENTAÇÕES
      // --------------------------------------------------------

      OrientacaoScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        userName: _userName,
      ),

      // --------------------------------------------------------
      // 5 - TAREFAS EXECUTADAS
      // --------------------------------------------------------

      TarefasScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        timeLogStore: _timeLogStore,
        userName: _userName,
      ),

      // --------------------------------------------------------
      // 6 - MODELOS DE CHECK LIST
      // --------------------------------------------------------

      ChecklistFormatsScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        timeLogStore: _timeLogStore,
        userName: _userName,
      ),

      // --------------------------------------------------------
      // 7 - SOLICITAÇÕES
      // --------------------------------------------------------

      SolicitacoesScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        userName: _userName,
      ),
    ];

    // ==========================================================
    // ÍNDICE SEGURO
    // ==========================================================

    final int safeIndex =
        (_selectedIndex >= 0 && _selectedIndex < screens.length)
            ? _selectedIndex
            : 0;

    // ==========================================================
    // PÁGINA ATUAL COM FUNDO GLOBAL
    // ==========================================================

    return _buildGlobalBackground(
      child: screens[safeIndex],
    );
  }
}
