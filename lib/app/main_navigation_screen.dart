import 'package:flutter/material.dart';

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

// Import da tela de Modelos de Check List
import 'package:gerenciador_horas/features/checklist_formats/checklist_formats_screen.dart';

// Import da nova tela de Solicitações
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

  @override
  void initState() {
    super.initState();
    _loadWorkFormats();
  }

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

  void _onSelectTab(int index) {
    // Permitir até o índice 7 (0 a 7 = 8 abas no total)
    if (index < 0 || index > 7) {
      return;
    }

    if (index == 0) {
      _loadWorkFormats();
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingFormats) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final List<Widget> screens = <Widget>[
      // ============================================================
      // 0 - PROJETOS / DASHBOARD
      // ============================================================
      DashboardScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        workFormats: _workFormats,
        timeLogStore: _timeLogStore,
      ),

      // ============================================================
      // 1 - MODELOS / TRABALHOS
      // ============================================================
      WorkFormatsScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
      ),

      // ============================================================
      // 2 - MÉTRICAS
      // ============================================================
      metrics.MetricsScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        timeLogStore: _timeLogStore,
      ),

      // ============================================================
      // 3 - PROJETOS FINALIZADOS
      // ============================================================
      completed.CompletedProjectsScreen(
        firebaseService: _firebaseService,
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
      ),

      // ============================================================
      // 4 - ORIENTAÇÕES
      // ============================================================
      OrientacaoScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
      ),

      // ============================================================
      // 5 - TAREFAS EXECUTADAS
      // ============================================================
      TarefasScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        timeLogStore: _timeLogStore,
      ),

      // ============================================================
      // 6 - MODELOS DE CHECK LIST
      // ============================================================
      ChecklistFormatsScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
        timeLogStore: _timeLogStore,
      ),

      // ============================================================
      // 7 - SOLICITAÇÕES
      // ============================================================
      SolicitacoesScreen(
        selectedIndex: _selectedIndex,
        onSelectTab: _onSelectTab,
      ),
    ];

    final int safeIndex =
        (_selectedIndex >= 0 && _selectedIndex < screens.length)
            ? _selectedIndex
            : 0;

    return screens[safeIndex];
  }
}
