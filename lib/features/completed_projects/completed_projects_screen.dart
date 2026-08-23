// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';
import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:url_launcher/url_launcher.dart';

class CompletedProjectsScreen extends StatefulWidget {
  final FirebaseService firebaseService;
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const CompletedProjectsScreen({
    super.key,
    required this.firebaseService,
    required this.selectedIndex,
    required this.onSelectTab,
    required String userName,
  });

  @override
  State<CompletedProjectsScreen> createState() =>
      _CompletedProjectsScreenState();
}

class _CompletedProjectsScreenState extends State<CompletedProjectsScreen> {
  // ============================================================
  // CONTROLES DA TABELA
  // ============================================================

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  final Set<String> _expandedProjectIds = {};

  String _searchQuery = '';

  // ============================================================
  // CONVERSÃO DOS PROJETOS
  // ============================================================

  List<Map<String, dynamic>> _convertProjects(
    List<dynamic> projects,
  ) {
    return projects.map<Map<String, dynamic>>((project) {
      if (project is Map<String, dynamic>) {
        return Map<String, dynamic>.from(project);
      }

      try {
        return {
          'id': project.id,
          'id2': project.id2,
          'client': project.client,
          'serviceType': project.serviceType,
          'stage': project.stage,
          'task': project.task,
          'status': project.status,
          'startDate': project.startDate,
          'estimatedHours': project.estimatedHours,
          'leader': project.leader,
          'hourType': project.hourType,
          'excelLink': project.excelLink,
          'folderPath': project.folderPath,
          'observacao': project.observacao,
          'finalizedAt': project.finalizedAt,
          'subTasks': (project.subTasks ?? [])
              .map<Map<String, dynamic>>(
                (task) => {
                  'subId': task.subId,
                  'stage': task.stage,
                  'status': task.status,
                  'startDate': task.startDate,
                  'planStart': task.planStart,
                  'planEnd': task.planEnd,
                  'estimatedHours': task.estimatedHours,
                  'hourType': task.hourType,
                },
              )
              .toList(),
        };
      } catch (_) {
        return <String, dynamic>{};
      }
    }).toList();
  }

  // ============================================================
  // FILTRO
  // ============================================================

  List<Map<String, dynamic>> _filterProjects(
    List<Map<String, dynamic>> projects,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return projects;
    }

    return projects.where((project) {
      final id = project['id']?.toString().toLowerCase() ?? '';
      final id2 = project['id2']?.toString().toLowerCase() ?? '';
      final client = project['client']?.toString().toLowerCase() ?? '';
      final serviceType =
          project['serviceType']?.toString().toLowerCase() ?? '';
      final leader = project['leader']?.toString().toLowerCase() ?? '';
      final stage = project['stage']?.toString().toLowerCase() ?? '';

      return id.contains(query) ||
          id2.contains(query) ||
          client.contains(query) ||
          serviceType.contains(query) ||
          leader.contains(query) ||
          stage.contains(query);
    }).toList();
  }

  // ============================================================
  // CONVERSÃO DE DATAS
  // ============================================================

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    try {
      if (value.runtimeType.toString() == 'Timestamp') {
        return value.toDate();
      }
    } catch (_) {}

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  String _stringValue(
    Map<String, dynamic> project,
    String key, [
    String defaultValue = '',
  ]) {
    final value = project[key];

    if (value == null) {
      return defaultValue;
    }

    return value.toString();
  }

  List<Map<String, dynamic>> _getSubTasks(
    Map<String, dynamic> project,
  ) {
    final value = project['subTasks'];

    if (value == null || value is! List) {
      return [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '-';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().substring(2)}';
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) {
      return '-';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().substring(2)} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // CORES DOS STATUS
  // ============================================================

  Color _getStatusColor(String status) {
    switch (status) {
      case 'TRAB_FIM':
        return CoresDashboard.statusFinalizado;

      case 'TRAB':
        return CoresDashboard.statusTrabalhando;

      case 'EA':
        return CoresDashboard.statusAndamento;

      case 'INI_PRO':
        return CoresDashboard.statusInicial;

      default:
        return CoresApp.textoSecundario;
    }
  }

  // ============================================================
  // CABEÇALHO DAS COLUNAS
  // ============================================================

  Widget _buildTableHeader(String text) {
    return Text(
      text,
      style: TextStyle(
        color: CoresApp.textoSecundario,
        fontSize: TamanhosApp.tabelaFonteCabecalho,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  // ============================================================
  // TEXTO DAS CÉLULAS
  // ============================================================

  Widget _buildCellText(
    String text, {
    Color? color,
    FontWeight fontWeight = FontWeight.normal,
    double? fontSize,
  }) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? CoresApp.textoSecundario,
        fontSize: fontSize ?? TamanhosApp.tabelaFonte,
        fontWeight: fontWeight,
      ),
    );
  }

  // ============================================================
  // BADGE DO ID
  // ============================================================

  Widget _buildProjectIdBadge({
    required String id,
    required bool hasSubtasks,
    required bool isExpanded,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(
        TamanhosApp.raioBotao,
      ),
      onTap: hasSubtasks ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            child: hasSubtasks
                ? Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: CoresApp.destaque,
                    size: TamanhosApp.iconeTabela,
                  )
                : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: CoresApp.destaque.withOpacity(0.09),
              borderRadius: BorderRadius.circular(
                TamanhosApp.raioBadge,
              ),
              border: Border.all(
                color: CoresApp.destaque.withOpacity(0.35),
                width: TamanhosApp.espessuraBorda,
              ),
            ),
            child: Text(
              id,
              style: TextStyle(
                color: CoresApp.destaque,
                fontSize: TamanhosApp.tabelaFonte,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BADGE DE FINALIZADO
  // ============================================================

  Widget _buildCompletedStatusBadge() {
    final color = CoresDashboard.statusFinalizado;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioBadge,
        ),
        border: Border.all(
          color: color.withOpacity(0.65),
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            'TRAB_FIM',
            style: TextStyle(
              color: color,
              fontSize: TamanhosApp.tabelaFonteStatus,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BADGE DA SUBTAREFA
  // ============================================================

  Widget _buildTaskStatusBadge(String status) {
    final color = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: color.withOpacity(0.55),
          width: TamanhosApp.espessuraBorda,
        ),
      ),
      child: Text(
        status.isEmpty ? '-' : status,
        style: TextStyle(
          color: color,
          fontSize: TamanhosApp.tabelaFonteStatus,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ============================================================
  // ABRIR LINK / ARQUIVO / PASTA
  // ============================================================

  Future<bool> _openResource(String value) async {
    final cleanValue = value.trim();

    if (cleanValue.isEmpty) {
      return false;
    }

    try {
      Uri? uri;

      if (cleanValue.startsWith('http://') ||
          cleanValue.startsWith('https://')) {
        uri = Uri.tryParse(cleanValue);
      } else if (cleanValue.startsWith('file://')) {
        uri = Uri.tryParse(cleanValue);
      } else {
        uri = Uri.file(cleanValue);
      }

      if (uri == null) {
        return false;
      }

      if (await canLaunchUrl(uri)) {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {}

    return false;
  }

  // ============================================================
  // BOTÃO DE ARQUIVO
  // ============================================================

  Widget _buildResourceButton({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool available,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: available ? onPressed : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: available
              ? color.withOpacity(0.07)
              : CoresApp.textoPrincipal.withOpacity(0.025),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: available
                ? color.withOpacity(0.25)
                : CoresDashboard.tabelaBorda,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: available
                    ? color.withOpacity(0.12)
                    : CoresApp.textoPrincipal.withOpacity(0.035),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                color: available
                    ? color
                    : CoresApp.textoSecundario.withOpacity(0.45),
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: available
                          ? CoresApp.textoPrincipal
                          : CoresApp.textoSecundario.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    available ? subtitle : 'Não cadastrado para este projeto',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CoresApp.textoSecundario,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (available)
              Icon(
                Icons.open_in_new_rounded,
                color: color,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // AÇÕES DO PROJETO FINALIZADO
  // ============================================================

  Widget _buildActionControls(
    Map<String, dynamic> project,
  ) {
    final excelLink = _stringValue(
      project,
      'excelLink',
    ).trim();

    final folderPath = _stringValue(
      project,
      'folderPath',
    ).trim();

    final hasExcel = excelLink.isNotEmpty;
    final hasFolder = folderPath.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 3,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: CoresApp.textoPrincipal.withOpacity(0.018),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasExcel || hasFolder)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.link_rounded,
                color: CoresApp.destaqueVerde,
                size: TamanhosApp.iconeAcao,
              ),
              tooltip: 'Abrir arquivo/link',
              onPressed: () async {
                if (hasExcel) {
                  final uri = Uri.tryParse(excelLink);

                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );

                    return;
                  }
                }

                if (hasFolder) {
                  final uri = Uri.tryParse(folderPath);

                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                }
              },
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.undo_rounded,
              color: CoresApp.destaqueVerde,
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: 'Reabrir projeto',
            onPressed: () {
              _reopenProject(project);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.visibility_rounded,
              color: CoresApp.destaque,
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: 'Visualizar trabalho',
            onPressed: () {
              _viewProject(project);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: CoresApp.erro,
              size: TamanhosApp.iconeAcao,
            ),
            tooltip: 'Excluir do histórico',
            onPressed: () {
              _deleteProjectFromHistory(project);
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // REABRIR PROJETO FINALIZADO
  // ============================================================

  Future<void> _reopenProject(
    Map<String, dynamic> project,
  ) async {
    final String id = project['id']?.toString().trim() ?? '';

    if (id.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.tabelaFundo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CoresDashboard.tabelaBorda,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CoresApp.destaqueVerde.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.undo_rounded,
                  color: CoresApp.destaqueVerde,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reabrir projeto?',
                  style: TextStyle(
                    color: CoresApp.textoPrincipal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'O projeto "$id" voltará para os projetos ativos.\n\n'
            'As etapas, horários, arquivo Excel e pasta vinculada '
            'serão preservados.',
            style: TextStyle(
              color: CoresApp.textoSecundario,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.destaqueVerde,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(
                Icons.undo_rounded,
                size: 17,
              ),
              label: const Text(
                'Reabrir',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.firebaseService.reopenCompletedProject(id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: CoresApp.destaqueVerde,
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Projeto $id reaberto e devolvido aos projetos ativos.',
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: CoresApp.erro,
          content: Text(
            'Erro ao reabrir o projeto $id: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // EXCLUIR SOMENTE DO HISTÓRICO DE FINALIZADOS
  // ============================================================

  Future<void> _deleteProjectFromHistory(
    Map<String, dynamic> project,
  ) async {
    final id = project['id']?.toString().trim() ?? '';

    if (id.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.tabelaFundo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Excluir do histórico?',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'O trabalho "$id" será excluído do histórico '
            'de projetos finalizados.\n\n'
            'Essa ação não poderá ser desfeita.',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.firebaseService.deleteCompletedProject(id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Trabalho $id excluído do histórico.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao excluir o trabalho: $e',
          ),
          backgroundColor: CoresApp.erro,
        ),
      );
    }
  }

  // ============================================================
  // EXCLUIR PROJETO (COMPLETO)
  // ============================================================

  Future<void> _deleteProject(
    Map<String, dynamic> project,
  ) async {
    final id = project['id']?.toString().trim() ?? '';

    if (id.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: CoresDashboard.tabelaFundo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Excluir projeto?',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'O projeto "$id" será completamente excluído do sistema.\n\n'
            'Essa ação não poderá ser desfeita.',
            style: TextStyle(
              color: CoresApp.textoSecundario,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: CoresApp.erro,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.firebaseService.deleteProject(id);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Projeto $id excluído com sucesso.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao excluir o projeto: $e',
          ),
          backgroundColor: CoresApp.erro,
        ),
      );
    }
  }

  // ============================================================
  // LINHA DO PROJETO
  // ============================================================

  DataRow _buildProjectRow(
    Map<String, dynamic> project,
  ) {
    final id = _stringValue(project, 'id');

    final id2 = _stringValue(
      project,
      'id2',
      '0',
    );

    final client = _stringValue(
      project,
      'client',
    );

    final serviceType = _stringValue(
      project,
      'serviceType',
    );

    final observation = _stringValue(
      project,
      'observacao',
    );

    final estimatedHours = _stringValue(
      project,
      'estimatedHours',
      '00:00',
    );

    final leader = _stringValue(
      project,
      'leader',
    );

    final hourType = _stringValue(
      project,
      'hourType',
      'Hs Cobradas',
    );

    final startDate = _parseDate(
      project['startDate'],
    );

    final finalizedAt = _parseDate(
      project['finalizedAt'],
    );

    final subTasks = _getSubTasks(project);

    final bool isExpanded = _expandedProjectIds.contains(id);

    final endDates = subTasks
        .map(
          (task) => _parseDate(
            task['planEnd'],
          ),
        )
        .whereType<DateTime>()
        .toList();

    DateTime? endDate;

    if (endDates.isNotEmpty) {
      endDates.sort();
      endDate = endDates.last;
    }

    endDate ??= finalizedAt;

    final String period = '${_formatDate(startDate)} - ${_formatDate(endDate)}';

    return DataRow(
      color: WidgetStateProperty.all(
        CoresDashboard.tabelaLinhaRegistrada,
      ),
      cells: [
        DataCell(
          _buildProjectIdBadge(
            id: id,
            hasSubtasks: subTasks.isNotEmpty,
            isExpanded: isExpanded,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedProjectIds.remove(id);
                } else {
                  _expandedProjectIds.add(id);
                }
              });
            },
          ),
        ),
        DataCell(
          _buildCellText(
            id2,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            client,
            color: CoresApp.textoPrincipal,
            fontWeight: FontWeight.w600,
          ),
        ),
        DataCell(
          _buildCellText(
            serviceType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            observation.isEmpty ? '-' : observation,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCompletedStatusBadge(),
        ),
        DataCell(
          _buildCellText(
            period,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            estimatedHours,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            leader,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            hourType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildActionControls(project),
        ),
      ],
    );
  }

  // ============================================================
  // LINHA DA SUBTAREFA
  // ============================================================

  DataRow _buildSubTaskRow({
    required Map<String, dynamic> project,
    required Map<String, dynamic> task,
  }) {
    final subId = _stringValue(
      task,
      'subId',
    );

    final stage = _stringValue(
      task,
      'stage',
    );

    final status = _stringValue(
      task,
      'status',
      'TRAB_FIM',
    );

    final estimatedHours = _stringValue(
      task,
      'estimatedHours',
      '00:00',
    );

    final hourType = _stringValue(
      task,
      'hourType',
      _stringValue(
        project,
        'hourType',
        'Hs Cobradas',
      ),
    );

    final startDate = _parseDate(
      task['startDate'],
    );

    final planEnd = _parseDate(
      task['planEnd'],
    );

    return DataRow(
      color: WidgetStateProperty.all(
        CoresDashboard.tabelaLinhaEtapa,
      ),
      cells: [
        const DataCell(
          SizedBox(width: 24),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: CoresApp.textoPrincipal.withOpacity(0.035),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              subId,
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: TamanhosApp.tabelaFonteSecundaria,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(
          Padding(
            padding: const EdgeInsets.only(
              left: 12,
            ),
            child: _buildCellText(
              _stringValue(
                project,
                'client',
              ),
              color: CoresApp.textoSecundario.withOpacity(0.65),
            ),
          ),
        ),
        DataCell(
          _buildCellText(
            _stringValue(
              project,
              'serviceType',
            ),
            color: CoresApp.textoSecundario.withOpacity(0.65),
          ),
        ),
        DataCell(
          _buildCellText(
            stage,
            color: CoresApp.textoPrincipal,
            fontWeight: FontWeight.w600,
          ),
        ),
        DataCell(
          _buildTaskStatusBadge(status),
        ),
        DataCell(
          _buildCellText(
            '${_formatDate(startDate)} - ${_formatDate(planEnd)}',
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            estimatedHours,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          _buildCellText(
            hourType,
            color: CoresApp.textoSecundario,
          ),
        ),
        DataCell(
          Icon(
            Icons.check_circle_rounded,
            color: CoresApp.sucesso,
            size: 19,
          ),
        ),
        const DataCell(
          SizedBox.shrink(),
        ),
      ],
    );
  }

  // ============================================================
  // GERA AS LINHAS DA TABELA
  // ============================================================

  List<DataRow> _generateRows(
    List<Map<String, dynamic>> projects,
  ) {
    final List<DataRow> rows = [];

    for (final project in projects) {
      final id = _stringValue(
        project,
        'id',
      );

      rows.add(
        _buildProjectRow(project),
      );

      if (_expandedProjectIds.contains(id)) {
        final subTasks = _getSubTasks(project);

        for (final task in subTasks) {
          rows.add(
            _buildSubTaskRow(
              project: project,
              task: task,
            ),
          );
        }
      }
    }

    return rows;
  }

  // ============================================================
  // ESTADO VAZIO
  // ============================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 60,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: CoresApp.sucesso.withOpacity(0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: CoresApp.sucesso.withOpacity(0.20),
              ),
            ),
            child: Icon(
              Icons.task_alt_rounded,
              color: CoresApp.sucesso,
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum trabalho finalizado',
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _searchQuery.trim().isEmpty
                ? 'Os trabalhos concluídos aparecerão aqui automaticamente.'
                : 'Nenhum trabalho concluído corresponde à pesquisa.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CoresApp.textoSecundario,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TABELA COMPLETA COM VISUAL MAIS MODERNO E ELEGANTE
  // ============================================================

  Widget _buildCompletedProjectsTable(
    List<Map<String, dynamic>> completedProjects,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: CoresDashboard.tabelaFundo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CoresApp.borda,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [CoresApp.primaria, CoresApp.sucesso],
                ),
              ),
            ),
            Expanded(
              child: completedProjects.isEmpty
                  ? _buildEmptyState()
                  : Scrollbar(
                      controller: _verticalController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _verticalController,
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: MediaQuery.of(context).size.width - 40,
                            ),
                            child: DataTable(
                              showCheckboxColumn: false,
                              columnSpacing: 18.0,
                              horizontalMargin: 18.0,
                              headingRowHeight: 52,
                              dataRowMinHeight: 32,
                              dataRowMaxHeight: 40,
                              dividerThickness: 0.5,
                              headingRowColor: WidgetStateProperty.all(
                                CoresDashboard.tabelaCabecalho,
                              ),
                              dataRowColor: WidgetStateProperty.resolveWith(
                                (states) {
                                  if (states.contains(
                                    WidgetState.hovered,
                                  )) {
                                    return CoresDashboard.tabelaHover;
                                  }

                                  return null;
                                },
                              ),
                              columns: [
                                DataColumn(
                                  label: _buildTableHeader('ID'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Nº'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader('Cliente'),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Tipo de Serviço',
                                  ),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Informações',
                                  ),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Status',
                                  ),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Data Início / Fim',
                                  ),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Hs Estimadas',
                                  ),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Líder Prj',
                                  ),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Tipo HS',
                                  ),
                                ),
                                DataColumn(
                                  label: _buildTableHeader(
                                    'Ações',
                                  ),
                                ),
                              ],
                              rows: _generateRows(
                                completedProjects,
                              ),
                            ),
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

  // ============================================================
  // VISUALIZAR PROJETO
  // ============================================================

  void _viewProject(
    Map<String, dynamic> project,
  ) {
    final id = project['id']?.toString() ?? '-';
    final client = project['client']?.toString() ?? '-';
    final serviceType = project['serviceType']?.toString() ?? '-';
    final leader = project['leader']?.toString() ?? '-';
    final estimatedHours = project['estimatedHours']?.toString() ?? '00:00';
    final excelLink = project['excelLink']?.toString().trim() ?? '';
    final folderPath = project['folderPath']?.toString().trim() ?? '';

    final startDate = _parseDate(
      project['startDate'],
    );

    final finalizedAt = _parseDate(
      project['finalizedAt'],
    );

    final subTasks = _getSubTasks(
      project,
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 560,
            ),
            decoration: BoxDecoration(
              color: CoresTelas.fundoModal,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CoresApp.borda,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    18,
                    16,
                    16,
                  ),
                  decoration: BoxDecoration(
                    color: CoresTelas.fundoModalSecundario,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: CoresApp.borda,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: CoresApp.sucesso.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: CoresApp.sucesso.withOpacity(0.3),
                          ),
                        ),
                        child: Icon(
                          Icons.task_alt_rounded,
                          color: CoresApp.sucesso,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trabalho finalizado',
                              style: TextStyle(
                                color: CoresApp.textoPrincipal,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Projeto $id',
                              style: TextStyle(
                                color: CoresApp.textoSecundario,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar',
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          color: CoresApp.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Informações do projeto',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: CoresTelas.campoFormulario.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: CoresApp.borda,
                            ),
                          ),
                          child: Column(
                            children: [
                              _infoRow('ID', id),
                              _infoRow('Cliente', client),
                              _infoRow('Tipo de Serviço', serviceType),
                              _infoRow('Líder', leader),
                              _infoRow('Horas Estimadas', estimatedHours),
                              _infoRow('Data Início', _formatDate(startDate)),
                              _infoRow(
                                'Finalizado em',
                                _formatDateTime(finalizedAt),
                              ),
                              _infoRow(
                                'Etapas',
                                subTasks.length.toString(),
                                isLast: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: CoresApp.sucesso.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: CoresApp.sucesso.withOpacity(0.24),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: CoresApp.sucesso,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'TRAB_FIM',
                                style: TextStyle(
                                  color: CoresApp.sucesso,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Concluído',
                                style: TextStyle(
                                  color: CoresApp.textoSecundario,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Arquivos do projeto',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Abra os arquivos e a pasta vinculados a este trabalho.',
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildResourceButton(
                          icon: Icons.table_chart_rounded,
                          color: CoresApp.destaqueVerde,
                          title: 'Arquivo Excel',
                          subtitle: excelLink.isEmpty
                              ? 'Não há arquivo Excel cadastrado.'
                              : excelLink,
                          available: excelLink.isNotEmpty,
                          onPressed: () async {
                            final opened = await _openResource(excelLink);

                            if (!mounted) {
                              return;
                            }

                            if (!opened) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Não foi possível abrir o arquivo Excel.',
                                  ),
                                  backgroundColor: CoresApp.erro,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 9),
                        _buildResourceButton(
                          icon: Icons.folder_open_rounded,
                          color: CoresApp.destaque,
                          title: 'Pasta do projeto',
                          subtitle: folderPath.isEmpty
                              ? 'Não há pasta cadastrada.'
                              : folderPath,
                          available: folderPath.isNotEmpty,
                          onPressed: () async {
                            final opened = await _openResource(folderPath);

                            if (!mounted) {
                              return;
                            }

                            if (!opened) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Não foi possível abrir a pasta do projeto.',
                                  ),
                                  backgroundColor: CoresApp.erro,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    14,
                  ),
                  decoration: BoxDecoration(
                    color: CoresTelas.fundoModalSecundario,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(18),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: CoresApp.borda,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                        },
                        child: Text(
                          'Fechar',
                          style: TextStyle(
                            color: CoresApp.destaque,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // LINHA DE INFORMAÇÃO DO MODAL
  // ============================================================

  Widget _infoRow(
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLast ? 0 : 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: TextStyle(
                color: CoresApp.textoSecundario,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: CoresApp.textoPrincipal,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresApp.fundo,
      appBar: Cabecalho(
        selectedIndex: widget.selectedIndex,
        onSelectTab: widget.onSelectTab,
        searchQuery: _searchQuery,
        onSearchChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        userName: '',
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0B0F19),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: widget.firebaseService.getCompletedProjectsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(
                    color: CoresApp.primaria,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: CoresDashboard.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: CoresApp.erro.withOpacity(0.30),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: CoresApp.erro,
                          size: 42,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Erro ao carregar trabalhos finalizados',
                          style: TextStyle(
                            color: CoresApp.textoPrincipal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CoresApp.textoSecundario,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final List<dynamic> rawProjects = snapshot.data != null
                  ? List<dynamic>.from(
                      snapshot.data!,
                    )
                  : <dynamic>[];

              final allProjects = _convertProjects(rawProjects);
              final completedProjects = _filterProjects(allProjects);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              color: CoresApp.sucesso,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Projetos Finalizados',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: CoresApp.textoPrincipal,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: CoresApp.sucesso.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: CoresApp.sucesso.withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_outline_rounded,
                              color: CoresApp.sucesso,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${completedProjects.length} CONCLUÍDO(S)',
                              style: const TextStyle(
                                color: CoresApp.sucesso,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _buildCompletedProjectsTable(
                      completedProjects,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
