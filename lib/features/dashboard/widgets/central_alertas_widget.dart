import 'package:flutter/material.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';

class CentralAlertasWidget extends StatelessWidget {
  final List<ProjectModel> projects;
  final String Function(DateTime) formatDateShort;

  const CentralAlertasWidget({
    super.key,
    required this.projects,
    required this.formatDateShort,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final List<_AlertItem> alertItems = [];

    for (var project in projects) {
      if (project.subTasks != null && project.subTasks!.isNotEmpty) {
        for (var task in project.subTasks!) {
          // Se o status for TRAB_FIM, ignora este item.
          if (task.status == 'TRAB_FIM') {
            continue;
          }

          final planEnd = task.planEnd ?? task.startDate;

          final normalizedEnd =
              DateTime(planEnd.year, planEnd.month, planEnd.day);

          final differenceDays = normalizedEnd.difference(today).inDays;

          // Exibe atrasados ou os que vencem nos próximos 5 dias.
          if (differenceDays <= 5) {
            alertItems.add(
              _AlertItem(
                id: project.id,
                id2: task.subId,
                client: project.client,
                serviceType: project.serviceType,
                stage: task.stage,
                planStart: task.planStart ?? task.startDate,
                planEnd: planEnd,
                status: task.status,
                differenceDays: differenceDays,
              ),
            );
          }
        }
      } else {
        // Se o projeto principal estiver concluído, ignora.
        if (project.status == 'TRAB_FIM') {
          continue;
        }

        final planEnd = project.startDate;

        final normalizedEnd =
            DateTime(planEnd.year, planEnd.month, planEnd.day);

        final differenceDays = normalizedEnd.difference(today).inDays;

        if (differenceDays <= 5) {
          alertItems.add(
            _AlertItem(
              id: project.id,
              id2: project.id2,
              client: project.client,
              serviceType: project.serviceType,
              stage: project.stage,
              planStart: project.startDate,
              planEnd: planEnd,
              status: project.status,
              differenceDays: differenceDays,
            ),
          );
        }
      }
    }

    // Mais atrasados primeiro.
    alertItems.sort(
      (a, b) => a.differenceDays.compareTo(b.differenceDays),
    );

    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ============================================================
          // CABEÇALHO
          // ============================================================
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Projetos com datas a vencer nos próximos dias',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '(${alertItems.length} alertas)',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // ============================================================
          // LISTA DE ALERTAS
          // ============================================================
          Expanded(
            child: alertItems.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum projeto ou etapa com prazo crítico no momento. Tudo em ordem!',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ScrollConfiguration(
                    behavior: const _SemScrollbarBehavior(),
                    child: ListView.builder(
                      primary: false,
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: alertItems.length,
                      itemBuilder: (context, index) {
                        final item = alertItems[index];

                        // Vermelho se já passou do prazo.
                        // Laranja se ainda está dentro do prazo crítico.
                        final bool isAtrasado = item.differenceDays < 0;

                        final Color rowBgColor = index % 2 == 0
                            ? const Color(0xFF12121B)
                            : const Color(0xFF161622);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: rowBgColor,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withOpacity(0.04),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // ==================================================
                              // ID
                              // ==================================================
                              SizedBox(
                                width: 70,
                                child: Text(
                                  item.id,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),

                              // ==================================================
                              // Nº
                              // ==================================================
                              SizedBox(
                                width: 40,
                                child: Text(
                                  item.id2,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),

                              // ==================================================
                              // CLIENTE
                              // ==================================================
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.client,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              // ==================================================
                              // TIPO DE SERVIÇO
                              // ==================================================
                              Expanded(
                                flex: 2,
                                child: Text(
                                  item.serviceType,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              // ==================================================
                              // ETAPA
                              // ==================================================
                              Expanded(
                                flex: 2,
                                child: Text(
                                  item.stage,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              // ==================================================
                              // DATA INICIAL
                              // ==================================================
                              SizedBox(
                                width: 90,
                                child: Text(
                                  formatDateShort(item.planStart),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),

                              // ==================================================
                              // DATA FINAL
                              // ==================================================
                              Container(
                                width: 90,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isAtrasado
                                      ? const Color(0xFFB71C1C)
                                      : const Color(0xFFF57F17),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  formatDateShort(item.planEnd),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),

                              const SizedBox(width: 12),

                              // ==================================================
                              // STATUS
                              // ==================================================
                              Container(
                                width: 70,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isAtrasado
                                      ? const Color(0xFF880E4F)
                                      : const Color(0xFFEF6C00),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isAtrasado ? 'Atrasado' : 'Ativo',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// COMPORTAMENTO DE SCROLL SEM SCROLLBAR
// ============================================================

class _SemScrollbarBehavior extends MaterialScrollBehavior {
  const _SemScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

// ============================================================
// MODELO INTERNO DOS ALERTAS
// ============================================================

class _AlertItem {
  final String id;
  final String id2;
  final String client;
  final String serviceType;
  final String stage;
  final DateTime planStart;
  final DateTime planEnd;
  final String status;
  final int differenceDays;

  _AlertItem({
    required this.id,
    required this.id2,
    required this.client,
    required this.serviceType,
    required this.stage,
    required this.planStart,
    required this.planEnd,
    required this.status,
    required this.differenceDays,
  });
}
