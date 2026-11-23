import '../dashboard/dialogs/external_comment_date_dialog.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../data/services/file_download.dart';
import 'package:gerenciador_horas/shared/widgets/redesign_components.dart';
import 'package:gerenciador_horas/core/theme/app_visuals.dart';
import 'package:gerenciador_horas/core/theme/app_appearance.dart';
import 'package:gerenciador_horas/core/config/plugin_tracking_access.dart';
import 'package:gerenciador_horas/data/services/project_update_service.dart';
import 'dart:async';
import 'tracking_rows.dart';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:gerenciador_horas/core/theme/cores_app.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class SolicitacoesScreen extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const SolicitacoesScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
    required String userName,
  });

  @override
  State<SolicitacoesScreen> createState() => _SolicitacoesScreenState();
}

class _SolicitacoesScreenState extends State<SolicitacoesScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  int? _selectedProjetoIndex;
  int? _selectedPluginIndex;

  List<Map<String, dynamic>> _projetosRows = [];
  List<Map<String, dynamic>> _pluginsRows = [];

  String _requestSearch = '';
  String? _requestStatus;
  DateTimeRange? _requestPeriod;
  int _requestPage = 0;
  int _requestsPerPage = 10;
  bool _isLoading = true;
  int _projectSyncVersion = 0;
  final Map<String, StreamSubscription<ProjectCommentUpdate?>>
      _commentSubscriptions = {};
  final Map<String, ProjectCommentUpdate?> _latestComments = {};

  void _watchComments(String id) {
    if (_commentSubscriptions.containsKey(id)) return;
    _commentSubscriptions[id] = ProjectUpdateService(_userId, firestore: _db)
        .watchLastComment(id)
        .listen((latest) {
      _latestComments[id] = latest;
      if (!mounted) return;
      setState(() {
        for (final row in [..._projetosRows, ..._pluginsRows]) {
          if (row['id'] == id) {
            row['ultimaAtualizacao'] = latest?.date;
            row['ultimoComentario'] = latest?.text ?? '';
            row['comentarioId'] = latest?.id;
          }
        }
      });
    },
            onError: (Object error) =>
                debugPrint('Erro ao acompanhar comentarios: $error'));
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _projetosSubscription;

  // ============================================================
  // USUÁRIO ATUAL
  // ============================================================

  User? get _currentUser => _auth.currentUser;
  bool get _canTrackPlugins => PluginTrackingAccess.allows(
      uid: _currentUser?.uid, email: _currentUser?.email);

  String get _userId {
    final user = _currentUser;

    if (user == null) {
      throw Exception('Usuário não autenticado.');
    }

    return user.uid;
  }

  // ============================================================
  // REFERÊNCIA DOS PROJETOS REAIS
  // ============================================================

  CollectionReference<Map<String, dynamic>> get _projectsCollection {
    return _db.collection('users').doc(_userId).collection('projects');
  }

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _escutarProjetos();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _projetosSubscription?.cancel();
    for (final subscription in _commentSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  // ============================================================
  // ESCUTAR PROJETOS REAIS
  // ============================================================

  void _escutarProjetos() {
    try {
      _projetosSubscription?.cancel();

      _projetosSubscription = _projectsCollection.snapshots().listen(
        (snapshot) async {
          await _sincronizarProjetos(snapshot);
        },
        onError: (error) {
          debugPrint(
            'Erro no stream de projetos: $error',
          );

          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        },
      );
    } catch (e, st) {
      debugPrint(
        'Erro ao iniciar stream de projetos: $e',
      );

      debugPrint('$st');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // SINCRONIZAR PROJETOS
  //
  // A mesma coleção projects alimenta as duas tabelas.
  //
  // Desenvolvimento Plugin
  //     -> tabela Plugins
  //
  // Demais serviços
  //     -> tabela Projetos
  // ============================================================

  Future<void> _sincronizarProjetos(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final version = ++_projectSyncVersion;
    final accountId = _currentUser?.uid;
    final canTrackPlugins = _canTrackPlugins;
    if (!mounted || accountId == null) return;
    final activeDocuments = snapshot.docs
        .where((doc) => isActiveTrackingProject(doc.data()))
        .map((doc) => doc.id)
        .toSet();
    // A completed/deleted project must disappear immediately, even when a
    // remaining project's comment lookup is slow or offline.
    setState(() {
      final projects = retainActiveTrackingRows(_projetosRows, activeDocuments);
      final plugins = retainActiveTrackingRows(_pluginsRows, activeDocuments);
      if (projects.length != _projetosRows.length) _selectedProjetoIndex = null;
      if (plugins.length != _pluginsRows.length) _selectedPluginIndex = null;
      _projetosRows = projects;
      _pluginsRows = plugins;
      if (activeDocuments.isEmpty) _isLoading = false;
    });
    try {
      debugPrint('========================================');
      debugPrint('SINCRONIZAÇÃO DE SOLICITAÇÕES');
      debugPrint(
        'Projetos encontrados: ${snapshot.docs.length}',
      );

      final activeIds = snapshot.docs
          .where((doc) => isActiveTrackingProject(doc.data()))
          .map((doc) => doc.data()['id']?.toString().trim().isNotEmpty == true
              ? doc.data()['id'].toString().trim()
              : doc.id)
          .toSet();
      for (final id in _commentSubscriptions.keys.toList()) {
        if (!activeIds.contains(id)) {
          await _commentSubscriptions.remove(id)?.cancel();
          _latestComments.remove(id);
        }
      }
      final commentResults = await Future.wait(activeIds
          .map((id) async => MapEntry(id, await _getUltimoComentario(id))));
      final commentsById = Map.fromEntries(commentResults);
      final List<Map<String, dynamic>> projetosRows = [];
      final List<Map<String, dynamic>> pluginsRows = [];

      for (final doc in snapshot.docs) {
        final project = doc.data();

        final status = project['status']?.toString().trim() ?? '';

        final serviceType = project['serviceType']?.toString().trim() ?? '';

        debugPrint(
          'Projeto: ${doc.id} | '
          'cliente=${project['client']} | '
          'serviceType=$serviceType | '
          'status=$status',
        );

        // ========================================================
        // PROJETO FINALIZADO
        // ========================================================

        if (!isActiveTrackingProject(project)) {
          debugPrint(
            'Projeto ${doc.id} ignorado: TRAB_FIM',
          );

          continue;
        }

        // ========================================================
        // IDENTIFICAÇÃO
        // ========================================================

        final projectId = project['id']?.toString().trim().isNotEmpty == true
            ? project['id'].toString().trim()
            : doc.id;

        final cliente = project['client']?.toString().trim() ?? '';

        final lider = project['leader']?.toString().trim() ?? '';

        final stage = project['stage']?.toString().trim() ?? '';

        final task = project['task']?.toString().trim() ?? '';

        final id2 = project['id2']?.toString().trim() ?? '';

        final acoes = project['acoes']?.toString().trim() ?? '';

        // ========================================================
        // VERIFICAR SE É DESENVOLVIMENTO DE PLUGIN
        // ========================================================

        final ehPlugin = _ehDesenvolvimentoPlugin(
          serviceType,
        );

        // ========================================================
        // MAIOR PLAN END
        // ========================================================

        final maiorPlanEnd = _getMaiorPlanEnd(
          project['subTasks'],
        );

        // ========================================================
        // SOLICITAÇÃO
        // ========================================================

        final solicitacao = _getSolicitacaoProjeto(
          project,
        );

        // ========================================================
        // ÚLTIMO COMENTÁRIO
        // ========================================================

        final ultimoComentario = commentsById[projectId];

        DateTime? dataUltimaAtualizacao;

        if (ultimoComentario != null) {
          dataUltimaAtualizacao = _parseDataFirestore(
            ultimoComentario['dataHora'],
          );

          dataUltimaAtualizacao ??= _parseDataFirestore(
            ultimoComentario['updatedAt'],
          );

          dataUltimaAtualizacao ??= _parseDataFirestore(
            ultimoComentario['data'],
          );
        }

        final ultimoComentarioTexto =
            ultimoComentario?['comentario']?.toString() ?? '';

        // ========================================================
        // DADOS BASE DA LINHA
        // ========================================================

        final row = {
          // ID REAL DO DOCUMENTO FIRESTORE
          'docId': doc.id,

          // ID DO PROJETO
          'id': projectId,

          'cliente': cliente,
          'solicitacao': solicitacao,
          'lider': lider,
          'status': status,
          'stage': stage,
          'task': task,
          'serviceType': serviceType,
          'id2': id2,

          // NOVO CAMPO EDITÁVEL
          'acoes': acoes,

          'planEnd': maiorPlanEnd,

          'ultimoComentario': ultimoComentarioTexto,
          'ultimaAtualizacao': dataUltimaAtualizacao,
          'comentarioId': ultimoComentario?['id'],

          // DADOS ORIGINAIS
          'projectData': project,
        };

        // ========================================================
        // SEPARAÇÃO AUTOMÁTICA
        // ========================================================

        if (ehPlugin && canTrackPlugins) {
          debugPrint(
            '  -> PLUGIN',
          );

          pluginsRows.add(row);
        } else {
          debugPrint(
            '  -> PROJETO',
          );

          projetosRows.add(row);
        }
      }

      // ==========================================================
      // ORDENAR PROJETOS
      // ==========================================================

      projetosRows.sort(
        (a, b) {
          final clienteA = a['cliente']?.toString().toLowerCase() ?? '';

          final clienteB = b['cliente']?.toString().toLowerCase() ?? '';

          return clienteA.compareTo(clienteB);
        },
      );

      // ==========================================================
      // ORDENAR PLUGINS
      // ==========================================================

      pluginsRows.sort(
        (a, b) {
          final clienteA = a['cliente']?.toString().toLowerCase() ?? '';

          final clienteB = b['cliente']?.toString().toLowerCase() ?? '';

          return clienteA.compareTo(clienteB);
        },
      );

      if (!mounted ||
          version != _projectSyncVersion ||
          _currentUser?.uid != accountId) {
        return;
      }

      setState(() {
        _projetosRows = projetosRows;
        _pluginsRows = pluginsRows;
        for (final row in [..._projetosRows, ..._pluginsRows]) {
          final id = row['id'] as String;
          if (_latestComments.containsKey(id)) {
            final latest = _latestComments[id];
            row['ultimaAtualizacao'] = latest?.date;
            row['ultimoComentario'] = latest?.text ?? '';
            row['comentarioId'] = latest?.id;
          }
        }

        if (_selectedProjetoIndex != null &&
            _selectedProjetoIndex! >= projetosRows.length) {
          _selectedProjetoIndex = null;
        }

        if (_selectedPluginIndex != null &&
            _selectedPluginIndex! >= pluginsRows.length) {
          _selectedPluginIndex = null;
        }

        _isLoading = false;
      });

      debugPrint(
        'Projetos exibidos: ${projetosRows.length}',
      );

      debugPrint(
        'Plugins exibidos: ${pluginsRows.length}',
      );

      debugPrint('========================================');
    } catch (e, st) {
      debugPrint(
        'Erro ao sincronizar projetos: $e',
      );

      debugPrint('$st');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // IDENTIFICAR DESENVOLVIMENTO DE PLUGIN
  // ============================================================

  bool _ehDesenvolvimentoPlugin(
    String serviceType,
  ) {
    return serviceType.toLowerCase().trim() == 'desenvolvimento plugin';
  }

  // ============================================================
  // FORMATAÇÃO DE DATA
  // ============================================================

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/'
        '${data.month.toString().padLeft(2, '0')}/'
        '${data.year}';
  }

  // ============================================================
  // CONVERTER DATA DD/MM/YYYY
  // ============================================================

  DateTime? _parseData(String dataStr) {
    try {
      final parts = dataStr.split('/');

      if (parts.length != 3) {
        return null;
      }

      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  // ============================================================
  // CONVERTER DATA DO FIRESTORE
  // ============================================================

  DateTime? _parseDataFirestore(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(
        value.trim(),
      );
    }

    return null;
  }

  // ============================================================
  // DIAS SEM ATUALIZAÇÃO
  // ============================================================

  String _calcularDiasSemAtualizacao(
    String dataAtualizacaoStr,
  ) {
    final dataAtualizacao = _parseData(
      dataAtualizacaoStr,
    );

    if (dataAtualizacao == null) {
      return '0';
    }

    return ProjectUpdateService.daysSince(dataAtualizacao, DateTime.now())
        .toString();
  }

  // ============================================================
  // ATUALIZAÇÃO OBRIGATÓRIA
  // ============================================================

  String _calcularAtualizacaoObrigatoria(
    DateTime dataBase,
  ) {
    return _formatarData(ProjectUpdateService.nextUpdate(dataBase));
  }

  // ============================================================
  // STATUS DO PROJETO
  // ============================================================

  String _formatarStatusProjeto(
    String status,
  ) {
    switch (status) {
      case 'INI_PRO':
        return 'Inicial';

      case 'TRAB':
        return 'Andamento';

      case 'EA':
        return 'Em espera';

      case 'TRAB_STOP':
        return 'Parado';

      case 'TRAB_FIM':
        return 'Finalizado';

      default:
        return status.isEmpty ? '—' : status;
    }
  }

  // ============================================================
  // MAIOR PLAN END DAS TAREFAS
  // ============================================================

  DateTime? _getMaiorPlanEnd(
    dynamic subTasks,
  ) {
    if (subTasks is! List) {
      return null;
    }

    DateTime? maior;

    for (final item in subTasks) {
      if (item is! Map) {
        continue;
      }

      final data = _parseDataFirestore(
        item['planEnd'],
      );

      if (data == null) {
        continue;
      }

      if (maior == null || data.isAfter(maior)) {
        maior = data;
      }
    }

    return maior;
  }

  // ============================================================
  // SOLICITAÇÃO DO PROJETO
  // ============================================================

  String _getSolicitacaoProjeto(
    Map<String, dynamic> project,
  ) {
    final subTasks = project['subTasks'];

    if (subTasks is List) {
      for (final item in subTasks) {
        if (item is! Map) {
          continue;
        }

        final solicitacao = item['edeskSolicitacao']?.toString().trim() ?? '';

        if (solicitacao.isNotEmpty) {
          return solicitacao;
        }
      }
    }

    final solicitacaoProjeto =
        project['edeskSolicitacao']?.toString().trim() ?? '';

    if (solicitacaoProjeto.isNotEmpty) {
      return solicitacaoProjeto;
    }

    return project['id']?.toString() ?? '';
  }

  // ============================================================
  // ÚLTIMO COMENTÁRIO E-DESK
  // ============================================================

  Future<Map<String, dynamic>?> _getUltimoComentario(
    String projectId,
  ) async {
    if (!mounted) return null;
    _watchComments(projectId);
    final cached = _latestComments[projectId];
    if (_latestComments.containsKey(projectId)) {
      return cached == null
          ? null
          : {
              'id': cached.id,
              'comentario': cached.text,
              'dataHora': cached.date
            };
    }
    final fetched = await ProjectUpdateService(_userId, firestore: _db)
        .lastComment(projectId);
    final latest = _latestComments.containsKey(projectId)
        ? _latestComments[projectId]
        : fetched;
    return latest == null
        ? null
        : {'id': latest.id, 'comentario': latest.text, 'dataHora': latest.date};
  }

  // ============================================================
  // EDITAR CAMPO DO PROJETO
  // ============================================================

  Future<void> _editarCampoProjeto({
    required Map<String, dynamic> row,
    required String campo,
    required String titulo,
    required String valorAtual,
  }) async {
    final controller = TextEditingController(
      text: valorAtual,
    );

    final novoValor = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        AppAppearance.watch(dialogContext);

        return AlertDialog(
          backgroundColor: CoresDashboard.card,
          title: Text(
            titulo,
            style: TextStyle(
              color: CoresApp.textoPrincipal,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(
                color: CoresApp.textoPrincipal,
              ),
              decoration: InputDecoration(
                hintText: 'Digite o valor',
                hintStyle: TextStyle(
                  color: CoresApp.textoSecundario.withValues(alpha: 0.7),
                ),
                filled: true,
                fillColor: CoresDashboard.tabelaFundo,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: CoresDashboard.tabelaBorda,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: CoresApp.primaria,
                  ),
                ),
              ),
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(
                  value.trim(),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: CoresApp.textoSecundario,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  controller.text.trim(),
                );
              },
              child: const Text(
                'Salvar',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (novoValor == null) {
      return;
    }

    final docId = row['docId']?.toString() ?? '';

    if (docId.isEmpty) {
      debugPrint(
        'Não foi possível salvar $campo: docId vazio.',
      );

      return;
    }

    try {
      await _projectsCollection.doc(docId).update({
        campo: novoValor,
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$titulo atualizado com sucesso.',
          ),
          duration: const Duration(
            seconds: 2,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Erro ao atualizar campo $campo: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar $titulo: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: Colors.transparent,

      // ========================================================
      // CABEÇALHO
      // ========================================================

      appBar: Cabecalho(
        selectedIndex: widget.selectedIndex,
        onSelectTab: widget.onSelectTab,
        searchQuery: '',
        onSearchChanged: (value) {},
        userName: '',
      ),

      // ========================================================
      // CORPO
      // ========================================================

      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: CoresApp.sucesso,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppPageHero(
                      title: 'Pasta de Solicitações',
                      subtitle:
                          'Acompanhe as solicitações de projetos e plugins.',
                      icon: Icons.assignment_outlined,
                      trailing: _buildRequestCounters()),

                  const SizedBox(
                    height: 16,
                  ),

                  // ==================================================
                  // PROJETOS
                  // ==================================================

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: AppVisuals.panel(prominent: true),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _requestToolbar(),
                        const SizedBox(height: 12),
                        _buildTabelaProjetos(),
                        _requestFooter(),
                      ],
                    ),
                  ),

                  if (_canTrackPlugins) const SizedBox(height: 20),

                  // ==================================================
                  // PLUGINS
                  // ==================================================

                  if (_canTrackPlugins)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: AppVisuals.panel(prominent: true),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.extension_rounded,
                                size: 16,
                                color: CoresApp.primaria,
                              ),
                              const SizedBox(
                                width: 6,
                              ),
                              Text(
                                'Acompanhamento Plugins em Desenvolvimento',
                                style: TextStyle(
                                  color: CoresApp.textoPrincipal,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(
                            height: 10,
                          ),
                          _buildTabelaPlugins(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
  // ============================================================
  // TABELA PROJETOS
  // ============================================================

  List<Map<String, dynamic>> get _visibleRequests {
    final query = _requestSearch.trim().toLowerCase();
    return _projetosRows.where((row) {
      if (query.isNotEmpty &&
          !'${row['id']} ${row['cliente']} ${row['solicitacao']}'
              .toLowerCase()
              .contains(query)) return false;
      if (_requestStatus != null && row['status'] != _requestStatus)
        return false;
      final period = _requestPeriod;
      if (period != null) {
        final date = row['planEnd'];
        if (date is! DateTime) return false;
        final day = DateTime(date.year, date.month, date.day);
        if (day.isBefore(period.start) || day.isAfter(period.end)) return false;
      }
      return true;
    }).toList();
  }

  int get _safeRequestPage => _requestPage.clamp(
      0, (_visibleRequests.length - 1).clamp(0, 100000000) ~/ _requestsPerPage);
  List<Map<String, dynamic>> get _pagedRequests => _visibleRequests
      .skip(_safeRequestPage * _requestsPerPage)
      .take(_requestsPerPage)
      .toList();
  Future<void> _chooseRequestPeriod() async {
    final period = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDateRange: _requestPeriod);
    if (period != null && mounted)
      setState(() {
        _requestPeriod = period;
        _requestPage = 0;
      });
  }

  Future<void> _exportRequests() async {
    String cell(dynamic value) {
      final raw = value?.toString() ?? '';
      final safe = RegExp(r'^[=+@\-\t\r]').hasMatch(raw) ? "'$raw" : raw;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final text = <List<dynamic>>[
      ['Solicitação', 'Cliente', 'Vencimento', 'Status', 'Líder'],
      for (final row in _visibleRequests)
        [
          row['id'],
          row['cliente'],
          row['planEnd'] is DateTime ? _formatarData(row['planEnd']) : '',
          _formatarStatusProjeto(row['status']?.toString() ?? ''),
          row['lider']
        ],
    ].map((row) => row.map(cell).join(';')).join('\r\n');
    if (kIsWeb) {
      downloadBytes(
          fileName: 'solicitacoes.csv',
          bytes: Uint8List.fromList(utf8.encode('\ufeff$text')),
          mimeType: 'text/csv;charset=utf-8');
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Tabela copiada para a área de transferência.')));
    }
  }

  Widget _requestToolbar() => LayoutBuilder(builder: (context, c) {
        final heading = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_outlined, color: CoresApp.destaque, size: 34),
          const SizedBox(width: 12),
          Flexible(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Acompanhamento de Projetos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: CoresApp.textoPrincipal,
                        fontSize: 21,
                        fontWeight: FontWeight.w700)),
                Text('Solicitações de projetos e suas atualizações.',
                    style: TextStyle(
                        color: CoresApp.textoSecundario, fontSize: 12)),
              ])),
        ]);
        final tools = Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: c.maxWidth >= 1000
                      ? (c.maxWidth -
                              760 -
                              ((_requestStatus != null ||
                                      _requestPeriod != null)
                                  ? 58
                                  : 0))
                          .clamp(180.0, 440.0)
                      : (c.maxWidth - 20).clamp(180.0, 440.0),
                  child: TextField(
                      onChanged: (v) => setState(() {
                            _requestSearch = v;
                            _requestPage = 0;
                          }),
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText:
                              'Buscar por cliente, solicitação ou número...'))),
              PopupMenuButton<String>(
                  onSelected: (v) => setState(() {
                        _requestStatus = v == 'all' ? null : v;
                        _requestPage = 0;
                      }),
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'all', child: Text('Todos os status')),
                        for (final status in [
                          'INI_PRO',
                          'TRAB',
                          'EA',
                          'TRAB_STOP',
                          'TRAB_FIM'
                        ])
                          PopupMenuItem(
                              value: status,
                              child: Text(_formatarStatusProjeto(status)))
                      ],
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: AppVisuals.panel(radius: 10),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_alt_outlined, size: 18),
                            SizedBox(width: 7),
                            Text('Filtrar')
                          ]))),
              OutlinedButton.icon(
                  onPressed: _chooseRequestPeriod,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                      _requestPeriod == null ? 'Período' : 'Período definido')),
              OutlinedButton.icon(
                  onPressed: _exportRequests,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Exportar')),
              if (_requestStatus != null || _requestPeriod != null)
                IconButton(
                    tooltip: 'Limpar filtros',
                    onPressed: () => setState(() {
                          _requestStatus = null;
                          _requestPeriod = null;
                          _requestPage = 0;
                        }),
                    icon: const Icon(Icons.filter_alt_off_outlined)),
            ]);
        if (c.maxWidth >= 1000)
          return Row(children: [
            Expanded(child: heading),
            const SizedBox(width: 18),
            tools
          ]);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [heading, const SizedBox(height: 12), tools]);
      });
  Widget _requestFooter() {
    final total = _visibleRequests.length;
    final pages = ((total + _requestsPerPage - 1) ~/ _requestsPerPage)
        .clamp(1, 100000000);
    return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [
              Text('Total: $total solicitações',
                  style:
                      TextStyle(color: CoresApp.textoPrincipal, fontSize: 14)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Itens por página: '),
                DropdownButton<int>(
                    value: _requestsPerPage,
                    items: [
                      for (final size in [5, 10, 20, 50])
                        DropdownMenuItem(value: size, child: Text('$size'))
                    ],
                    onChanged: (v) {
                      if (v != null)
                        setState(() {
                          _requestsPerPage = v;
                          _requestPage = 0;
                        });
                    }),
                IconButton(
                    tooltip: 'Página anterior',
                    onPressed: _safeRequestPage > 0
                        ? () =>
                            setState(() => _requestPage = _safeRequestPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left)),
                Text('${_safeRequestPage + 1} / $pages'),
                IconButton(
                    tooltip: 'Próxima página',
                    onPressed: _safeRequestPage < pages - 1
                        ? () =>
                            setState(() => _requestPage = _safeRequestPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right)),
              ]),
            ]));
  }

  Widget _buildRequestCounters() {
    final rows = [..._projetosRows, if (_canTrackPlugins) ..._pluginsRows];
    final stopped = rows.where((r) => r['status'] == 'TRAB_STOP').length;
    final running = rows.where((r) => r['status'] == 'TRAB').length;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = rows.where((r) {
      final date = r['planEnd'];
      if (date is! DateTime) return false;
      final days =
          DateTime(date.year, date.month, date.day).difference(today).inDays;
      return days >= 0 && days <= 7;
    }).length;
    return SizedBox(
        width: 830,
        child: Row(children: [
          Expanded(
              child: AppMetricCard(
                  icon: Icons.folder_outlined,
                  label: 'Solicita\u00e7\u00f5es',
                  value: '${rows.length}',
                  description: 'no per\u00edodo')),
          const SizedBox(width: 10),
          Expanded(
              child: AppMetricCard(
                  icon: Icons.pause_circle_outline,
                  label: 'Paradas',
                  value: '$stopped',
                  accent: CoresApp.sucesso)),
          const SizedBox(width: 10),
          Expanded(
              child: AppMetricCard(
                  icon: Icons.play_arrow_outlined,
                  label: 'Em andamento',
                  value: '$running')),
          const SizedBox(width: 10),
          Expanded(
              child: AppMetricCard(
                  icon: Icons.event_outlined,
                  label: 'Vencem em 7 dias',
                  value: '$due',
                  accent: AppVisuals.violet)),
        ]));
  }

  Widget _buildTabelaProjetos() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioTabela,
        ),
        border: Border.all(
          color: CoresDashboard.tabelaBorda,
        ),
        color: CoresDashboard.tabelaFundo,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 12,
          horizontalMargin: 12,
          dataRowMaxHeight: 44,
          dataRowMinHeight: 36,
          headingRowHeight: 40,
          headingRowColor: WidgetStateProperty.all(
            CoresDashboard.cabecalhoTabela,
          ),
          columns: [
            DataColumn(
              label: Text(
                'Cliente + Solicitação',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Vencimento',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Status',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Líder',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Último Coment.',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Dias s/Atual',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Atualiz. Obrigatória',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Ações',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
          rows: List.generate(
            _pagedRequests.length,
            (visibleIndex) {
              final row = _pagedRequests[visibleIndex];
              final index = _projetosRows.indexOf(row);

              final cliente = row['cliente']?.toString() ?? '';

              final solicitacao = row['solicitacao']?.toString() ?? '';

              final status = row['status']?.toString() ?? '';

              final statusFormatado = _formatarStatusProjeto(status);

              final lider = row['lider']?.toString() ?? '';

              final planEnd = row['planEnd'] as DateTime?;

              final ultimaAtualizacao = row['ultimaAtualizacao'] as DateTime?;

              final ultimaAtualizacaoStr = ultimaAtualizacao != null
                  ? _formatarData(
                      ultimaAtualizacao,
                    )
                  : '';

              final diasSemAtualizacao = ultimaAtualizacao != null
                  ? _calcularDiasSemAtualizacao(
                      ultimaAtualizacaoStr,
                    )
                  : '0';

              final atualizacaoObrigatoria = ultimaAtualizacao != null
                  ? _calcularAtualizacaoObrigatoria(
                      ultimaAtualizacao,
                    )
                  : '—';

              final isParado = status == 'TRAB_STOP';

              final isCancelado = cliente.toUpperCase().contains('CANCELADO');

              final isHighlight = isParado || isCancelado;

              final isSelected = _selectedProjetoIndex == index;

              final textColor = isHighlight
                  ? CoresDashboard.atrasado
                  : CoresApp.textoSecundario;

              final acoes = row['acoes']?.toString() ?? '';

              return DataRow(
                selected: isSelected,
                color: WidgetStateProperty.resolveWith<Color?>(
                  (states) {
                    if (isSelected) {
                      return CoresDashboard.tabelaLinhaSelecionada;
                    }

                    if (states.contains(
                      WidgetState.hovered,
                    )) {
                      return CoresDashboard.tabelaHover;
                    }

                    return null;
                  },
                ),
                onSelectChanged: (selected) {
                  setState(() {
                    _selectedProjetoIndex = selected == true ? index : null;
                  });
                },
                cells: [
                  // ==================================================
                  // CLIENTE + SOLICITAÇÃO
                  // ==================================================

                  DataCell(
                    Text(
                      solicitacao.isEmpty ? cliente : '$cliente • $solicitacao',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                        fontWeight:
                            isHighlight ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),

                  // ==================================================
                  // VENCIMENTO
                  // ==================================================

                  DataCell(
                    Text(
                      planEnd != null
                          ? _formatarData(
                              planEnd,
                            )
                          : '—',
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                      ),
                    ),
                  ),

                  // ==================================================
                  // STATUS
                  // ==================================================

                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isHighlight
                            ? CoresDashboard.atrasado.withValues(alpha: 0.15)
                            : CoresDashboard.statusAndamento
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          TamanhosApp.raioBadge,
                        ),
                      ),
                      child: Text(
                        statusFormatado,
                        style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonteStatus,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresDashboard.statusAndamento,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // LÍDER
                  // ==================================================

                  DataCell(
                    Text(
                      lider.isEmpty ? '—' : lider,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                      ),
                    ),
                  ),

                  // ==================================================
                  // ÚLTIMO COMENTÁRIO
                  // ==================================================

                  DataCell(
                    SizedBox(
                      width: 180,
                      child: Tooltip(
                        message: row['ultimoComentario']?.toString() ?? '',
                        child: Text(
                          ultimaAtualizacaoStr.isEmpty
                              ? '—'
                              : ultimaAtualizacaoStr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonte,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                    showEditIcon: true,
                    onTap: () => ExternalCommentDateDialog.show(context, row['id'].toString()),
                  ),

                  // ==================================================
                  // DIAS SEM ATUALIZAÇÃO
                  // ==================================================

                  DataCell(
                    Text(
                      diasSemAtualizacao,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // ==================================================
                  // ATUALIZAÇÃO OBRIGATÓRIA
                  // ==================================================

                  DataCell(
                    Text(
                      atualizacaoObrigatoria,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                      ),
                    ),
                  ),

                  // ==================================================
                  // AÇÕES EDITÁVEL
                  // ==================================================

                  DataCell(
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _editarCampoProjeto(
                          row: row,
                          campo: 'acoes',
                          titulo: 'Ações',
                          valorAtual: acoes,
                        );
                      },
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 100,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                acoes.isEmpty ? 'Editar' : acoes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: TamanhosApp.tabelaFonte,
                                  color: acoes.isEmpty
                                      ? CoresApp.primaria
                                      : textColor,
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 4,
                            ),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: CoresApp.primaria,
                            ),
                          ],
                        ),
                      ),
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

  // ============================================================
  // TABELA PLUGINS
  // ============================================================

  Widget _buildTabelaPlugins() {
    if (!_canTrackPlugins) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          TamanhosApp.raioTabela,
        ),
        border: Border.all(
          color: CoresDashboard.tabelaBorda,
        ),
        color: CoresDashboard.tabelaFundo,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 12,
          horizontalMargin: 12,
          dataRowMaxHeight: 44,
          dataRowMinHeight: 36,
          headingRowHeight: 40,
          headingRowColor: WidgetStateProperty.all(
            CoresDashboard.cabecalhoTabela,
          ),
          columns: [
            DataColumn(
              label: Text(
                'Solicitação + Cliente',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Entrega',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Status',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Consultor',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Atualização',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Dia S/Atual',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Atualiz. Obrigatória',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'NS',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Plugin',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
            DataColumn(
              label: Text(
                'Ações',
                style: TextStyle(
                  fontSize: TamanhosApp.tabelaFonteCabecalho,
                  fontWeight: FontWeight.bold,
                  color: CoresApp.textoPrincipal,
                ),
              ),
            ),
          ],
          rows: List.generate(
            _pluginsRows.length,
            (index) {
              final row = _pluginsRows[index];

              final cliente = row['cliente']?.toString() ?? '';

              final solicitacao = row['solicitacao']?.toString() ?? '';

              final entrega = row['planEnd'] as DateTime?;

              // ==================================================
              // STATUS
              // ==================================================

              final status = row['status']?.toString() ?? '';

              final statusFormatado = _formatarStatusProjeto(
                status,
              );

              // ==================================================
              // CONSULTOR
              // ==================================================

              final consultor = row['lider']?.toString() ?? '';

              // ==================================================
              // ATUALIZAÇÃO
              // ==================================================

              final ultimaAtualizacao = row['ultimaAtualizacao'] as DateTime?;

              final ultimaAtualizacaoStr = ultimaAtualizacao != null
                  ? _formatarData(
                      ultimaAtualizacao,
                    )
                  : '';

              final diasSemAtualizacao = ultimaAtualizacao != null
                  ? _calcularDiasSemAtualizacao(
                      ultimaAtualizacaoStr,
                    )
                  : '0';

              final atualizacaoObrigatoria = ultimaAtualizacao != null
                  ? _calcularAtualizacaoObrigatoria(
                      ultimaAtualizacao,
                    )
                  : '—';

              // ==================================================
              // NS
              // ==================================================

              final ns = row['id2']?.toString() ?? '';

              // ==================================================
              // PLUGIN
              // ==================================================

              final plugin = row['task']?.toString() ?? '';

              // ==================================================
              // AÇÕES
              // ==================================================

              final acoes = row['acoes']?.toString() ?? '';

              // ==================================================
              // DESTAQUES
              // ==================================================

              final isParado = status == 'TRAB_STOP';

              final isCancelado = cliente.toUpperCase().contains('CANCELADO');

              final isHighlight = isParado || isCancelado;

              final isSelected = _selectedPluginIndex == index;

              final textColor = isHighlight
                  ? CoresDashboard.atrasado
                  : CoresApp.textoSecundario;

              return DataRow(
                selected: isSelected,
                color: WidgetStateProperty.resolveWith<Color?>(
                  (states) {
                    if (isSelected) {
                      return CoresDashboard.tabelaLinhaSelecionada;
                    }

                    if (states.contains(
                      WidgetState.hovered,
                    )) {
                      return CoresDashboard.tabelaHover;
                    }

                    return null;
                  },
                ),
                onSelectChanged: (selected) {
                  setState(() {
                    _selectedPluginIndex = selected == true ? index : null;
                  });
                },
                cells: [
                  // ==================================================
                  // SOLICITAÇÃO + CLIENTE
                  // ==================================================

                  DataCell(
                    Text(
                      solicitacao.isEmpty ? cliente : '$solicitacao • $cliente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                        fontWeight:
                            isHighlight ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),

                  // ==================================================
                  // ENTREGA
                  // ==================================================

                  DataCell(
                    Text(
                      entrega != null
                          ? _formatarData(
                              entrega,
                            )
                          : '—',
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                      ),
                    ),
                  ),

                  // ==================================================
                  // STATUS
                  // ==================================================

                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isHighlight
                            ? CoresDashboard.atrasado.withValues(alpha: 0.15)
                            : CoresDashboard.statusAndamento
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          TamanhosApp.raioBadge,
                        ),
                      ),
                      child: Text(
                        statusFormatado,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: TamanhosApp.tabelaFonteStatus,
                          color: isHighlight
                              ? CoresDashboard.atrasado
                              : CoresDashboard.statusAndamento,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // CONSULTOR
                  // ==================================================

                  DataCell(
                    Text(
                      consultor.isEmpty ? '—' : consultor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                      ),
                    ),
                  ),

                  // ==================================================
                  // ATUALIZAÇÃO
                  // ==================================================

                  DataCell(
                    SizedBox(
                      width: 110,
                      child: Tooltip(
                        message: row['ultimoComentario']?.toString() ?? '',
                        child: Text(
                          ultimaAtualizacaoStr.isEmpty
                              ? '—'
                              : ultimaAtualizacaoStr,
                          style: TextStyle(
                            fontSize: TamanhosApp.tabelaFonte,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                    showEditIcon: true,
                    onTap: () => ExternalCommentDateDialog.show(context, row['id'].toString()),
                  ),

                  // ==================================================
                  // DIAS SEM ATUALIZAÇÃO
                  // ==================================================

                  DataCell(
                    Text(
                      diasSemAtualizacao,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // ==================================================
                  // ATUALIZAÇÃO OBRIGATÓRIA
                  // ==================================================

                  DataCell(
                    Text(
                      atualizacaoObrigatoria,
                      style: TextStyle(
                        fontSize: TamanhosApp.tabelaFonte,
                        color: textColor,
                      ),
                    ),
                  ),

                  // ==================================================
                  // NS EDITÁVEL
                  // ==================================================

                  DataCell(
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _editarCampoProjeto(
                          row: row,
                          campo: 'id2',
                          titulo: 'NS',
                          valorAtual: ns,
                        );
                      },
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 70,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                ns.isEmpty ? 'Editar' : ns,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: TamanhosApp.tabelaFonte,
                                  color: ns.isEmpty
                                      ? CoresApp.primaria
                                      : textColor,
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 4,
                            ),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: CoresApp.primaria,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // PLUGIN EDITÁVEL
                  // ==================================================

                  DataCell(
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _editarCampoProjeto(
                          row: row,
                          campo: 'task',
                          titulo: 'Plugin',
                          valorAtual: plugin,
                        );
                      },
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 100,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                plugin.isEmpty ? 'Editar' : plugin,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: TamanhosApp.tabelaFonte,
                                  color: plugin.isEmpty
                                      ? CoresApp.primaria
                                      : textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 4,
                            ),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: CoresApp.primaria,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ==================================================
                  // AÇÕES EDITÁVEL
                  // ==================================================

                  DataCell(
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _editarCampoProjeto(
                          row: row,
                          campo: 'acoes',
                          titulo: 'Ações',
                          valorAtual: acoes,
                        );
                      },
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 100,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                acoes.isEmpty ? 'Editar' : acoes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: TamanhosApp.tabelaFonte,
                                  color: acoes.isEmpty
                                      ? CoresApp.primaria
                                      : textColor,
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 4,
                            ),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: CoresApp.primaria,
                            ),
                          ],
                        ),
                      ),
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
