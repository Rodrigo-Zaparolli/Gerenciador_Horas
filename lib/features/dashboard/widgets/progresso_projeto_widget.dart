import 'package:flutter/material.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';

class ProgressoProjetoWidget extends StatelessWidget {
  final ProjectModel activeProject;
  final List<TimeLog> timeLogs;
  final double Function(String) parseTimeToHours;
  final String Function(double) formatHours;
  final String Function(DateTime) formatDateShort;

  const ProgressoProjetoWidget({
    super.key,
    required this.activeProject,
    required this.timeLogs,
    required this.parseTimeToHours,
    required this.formatHours,
    required this.formatDateShort,
  });

  @override
  Widget build(BuildContext context) {
    final totalProjectHours = parseTimeToHours(activeProject.estimatedHours);

    final workedHours =
        _getExecutedHoursForProject(activeProject.id.toString());

    final remainingHours =
        (totalProjectHours - workedHours).clamp(0.0, double.infinity);

    final percentRealized = totalProjectHours > 0
        ? ((workedHours / totalProjectHours) * 100).clamp(0.0, 100.0).round()
        : 0;

    final subTasks = activeProject.subTasks ?? [];

    double maxSubEstimated = 1.0;

    for (final sub in subTasks) {
      final est = parseTimeToHours(sub.estimatedHours);

      if (est > maxSubEstimated) {
        maxSubEstimated = est;
      }
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // ============================================================
          // ESQUERDA
          // ============================================================
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 23,
                      height: 23,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0099FF).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.work_outline_rounded,
                        color: Color(0xFF0099FF),
                        size: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${activeProject.id} ${activeProject.client}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0099FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 2),

                Padding(
                  padding: const EdgeInsets.only(left: 29),
                  child: Text(
                    activeProject.serviceType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.52),
                      fontSize: 9,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                Row(
                  children: [
                    Icon(
                      Icons.date_range_outlined,
                      size: 10,
                      color: Colors.white.withOpacity(0.35),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Início - Fim: 09/04/26 - 11/08/26',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.40),
                          fontSize: 8,
                        ),
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // ======================================================
                // TOTAL / TRAB / REST
                // ======================================================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.025),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.045),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMiniInfo(
                          'Total',
                          formatHours(totalProjectHours),
                          Colors.white,
                        ),
                      ),
                      _buildDivider(),
                      Expanded(
                        child: _buildMiniInfo(
                          'Trab.',
                          formatHours(workedHours),
                          Colors.greenAccent,
                        ),
                      ),
                      _buildDivider(),
                      Expanded(
                        child: _buildMiniInfo(
                          'Rest.',
                          formatHours(remainingHours),
                          Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 11,
                      color: Colors.greenAccent,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        'Realizado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.40),
                          fontSize: 8,
                        ),
                      ),
                    ),
                    Text(
                      '$percentRealized%',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // ============================================================
          // DIVISOR
          // ============================================================
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 2),
            color: Colors.white.withOpacity(0.06),
          ),

          const SizedBox(width: 8),

          // ============================================================
          // DIREITA
          // ============================================================
          Expanded(
            flex: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ------------------------------------------------------
                // CABEÇALHO
                // ------------------------------------------------------
                SizedBox(
                  height: 20,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_tree_outlined,
                        size: 13,
                        color: Color(0xFF0099FF),
                      ),
                      const SizedBox(width: 4),
                      const Flexible(
                        child: Text(
                          'Etapas do Projeto',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (subTasks.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${subTasks.length}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.30),
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // ------------------------------------------------------
                // LISTA
                // ------------------------------------------------------
                Expanded(
                  child: subTasks.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhuma etapa cadastrada',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          itemCount: subTasks.length,
                          itemBuilder: (context, index) {
                            final sub = subTasks[index];

                            final targetId = '${activeProject.id}_${sub.subId}';

                            final executed =
                                _getExecutedHoursForTarget(targetId);

                            final estimated =
                                parseTimeToHours(sub.estimatedHours);

                            final percent = estimated > 0
                                ? ((executed / estimated) * 100)
                                    .clamp(0.0, 100.0)
                                    .round()
                                : 0;

                            final ratio = maxSubEstimated > 0
                                ? (estimated / maxSubEstimated)
                                : 0.0;

                            final widthFactor =
                                (0.35 + (0.65 * ratio)).clamp(0.35, 1.0);

                            final fillFactor = estimated > 0
                                ? (executed / estimated).clamp(0.0, 1.0)
                                : 0.0;

                            const dateRangeStr = '13/04 - 14/04';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: SizedBox(
                                height: 29,
                                child: Row(
                                  children: [
                                    // ==========================================
                                    // INFORMAÇÕES DA ETAPA
                                    // ==========================================
                                    Expanded(
                                      flex: 5,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 3,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: percent >= 100
                                                  ? Colors.greenAccent
                                                  : const Color(0xFF0099FF),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Nome da etapa
                                                SizedBox(
                                                  height: 11,
                                                  child: Text(
                                                    sub.stage,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),

                                                const SizedBox(height: 1),

                                                // Percentual + data
                                                Row(
                                                  children: [
                                                    Text(
                                                      '$percent%',
                                                      style: TextStyle(
                                                        color: percent >= 100
                                                            ? Colors.greenAccent
                                                            : const Color(
                                                                0xFF35B5FF,
                                                              ),
                                                        fontSize: 7,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        dateRangeStr,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withOpacity(
                                                            0.28,
                                                          ),
                                                          fontSize: 6.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: 5),

                                    // ==========================================
                                    // BARRA
                                    // ==========================================
                                    Expanded(
                                      flex: 5,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor: widthFactor,
                                          child: SizedBox(
                                            height: 16,
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                // Fundo
                                                Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withOpacity(0.035),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      4,
                                                    ),
                                                    border: Border.all(
                                                      color: Colors.white
                                                          .withOpacity(0.055),
                                                    ),
                                                  ),
                                                ),

                                                // Progresso
                                                FractionallySizedBox(
                                                  widthFactor: fillFactor,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFF0099FF,
                                                      ).withOpacity(0.48),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        3,
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                // Horas
                                                Center(
                                                  child: FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      formatHours(executed),
                                                      maxLines: 1,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 7,
                                                        fontWeight:
                                                            FontWeight.w800,
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
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MINI INFORMAÇÃO
  // ============================================================
  Widget _buildMiniInfo(
    String label,
    String value,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.36),
            fontSize: 7,
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DIVISOR
  // ============================================================
  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 17,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withOpacity(0.06),
    );
  }

  // ============================================================
  // HORAS EXECUTADAS DO PROJETO
  // ============================================================
  double _getExecutedHoursForProject(String projectId) {
    double total = 0;

    final subTasks = activeProject.subTasks ?? [];

    // Soma as horas de cada sub-etapa baseada no targetId correspondente
    for (final sub in subTasks) {
      final targetId = '${projectId}_${sub.subId}';

      total += _getExecutedHoursForTarget(targetId);
    }

    // Também valida logs diretos caso existam salvos com o projectId
    for (final log in timeLogs) {
      if (log.projectId.toString() == projectId) {
        final alreadyCounted = subTasks.any(
          (sub) => log.targetId.toString() == '${projectId}_${sub.subId}',
        );

        if (!alreadyCounted) {
          total += parseTimeToHours(log.durationFormatted);
        }
      }
    }

    return total;
  }

  // ============================================================
  // HORAS EXECUTADAS DA ETAPA
  // ============================================================
  double _getExecutedHoursForTarget(String targetId) {
    double total = 0;

    for (final log
        in timeLogs.where((l) => l.targetId.toString() == targetId)) {
      total += parseTimeToHours(log.durationFormatted);
    }

    return total;
  }
}
