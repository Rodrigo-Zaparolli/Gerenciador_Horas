import 'package:flutter/material.dart';

class WorkHourWidget extends StatelessWidget {
  final Map<String, double> hoursData;
  final String Function(double) formatHours;

  const WorkHourWidget({
    super.key,
    required this.hoursData,
    required this.formatHours,
  });

  @override
  Widget build(BuildContext context) {
    // Caso não haja dados, exibe um estado vazio elegante
    if (hoursData.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF161622),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: const Center(
          child: Text(
            'Nenhum registro de tempo encontrado',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161622),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: hoursData.entries.map((entry) {
          final label = entry.key;
          final val = entry.value;
          final heightPct = (val / 10.0).clamp(0.05, 1.0);

          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                formatHours(val),
                style: const TextStyle(color: Colors.white70, fontSize: 8),
              ),
              const SizedBox(height: 4),
              Container(
                width: 10,
                height: 80 * heightPct,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 8),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
