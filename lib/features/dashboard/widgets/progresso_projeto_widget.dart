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

    // Soma dinâmica de todas as horas cadastradas nas sub-etapas do projeto
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ========================================================
          // COLUNA ESQUERDA: COMPACTADA (flex: 4)
          // ========================================================
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${activeProject.id} ${activeProject.client}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0099FF),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeProject.serviceType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.date_range,
                        size: 11, color: Colors.white54),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Início - Fim: 09/04/26 - 11/08/26',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniInfo('Total', formatHours(totalProjectHours),
                          Colors.white),
                      _buildMiniInfo('Trab.', formatHours(workedHours),
                          Colors.greenAccent),
                      _buildMiniInfo('Rest.', formatHours(remainingHours),
                          Colors.orangeAccent),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17231B),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                  ),
                  child: Text(
                    '% Realizado hs: $percentRealized%',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.white.withOpacity(0.06),
          ),

          const SizedBox(width: 12),

          // ========================================================
          // COLUNA DIREITA: AMPLIADA PARA AS BARRAS (flex: 8)
          // ========================================================
          Expanded(
            flex: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Etapas do Projeto',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: subTasks.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhuma etapa cadastrada',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10.5,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          physics: const ClampingScrollPhysics(),
                          itemCount: subTasks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
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

                            return Row(
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Text(
                                    '${sub.stage} - $percent% - $dateRangeStr',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 6,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: widthFactor,
                                      child: Container(
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.04),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withOpacity(0.08)),
                                        ),
                                        child: Stack(
                                          alignment: Alignment.centerLeft,
                                          children: [
                                            FractionallySizedBox(
                                              widthFactor: fillFactor,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0099FF)
                                                      .withOpacity(0.4),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                              ),
                                            ),
                                            Center(
                                              child: Text(
                                                formatHours(executed),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
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

  Widget _buildMiniInfo(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8.5),
        ),
        Text(
          value,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

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
        bool alreadyCounted = subTasks.any(
            (sub) => log.targetId.toString() == '${projectId}_${sub.subId}');
        if (!alreadyCounted) {
          total += parseTimeToHours(log.durationFormatted);
        }
      }
    }
    return total;
  }

  double _getExecutedHoursForTarget(String targetId) {
    double total = 0;
    for (final log
        in timeLogs.where((l) => l.targetId.toString() == targetId)) {
      total += parseTimeToHours(log.durationFormatted);
    }
    return total;
  }
}
