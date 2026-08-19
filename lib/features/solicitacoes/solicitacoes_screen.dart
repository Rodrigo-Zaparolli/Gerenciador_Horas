import 'package:flutter/material.dart';
import 'package:gerenciador_horas/shared/widgets/cabecalho.dart';

class SolicitacoesScreen extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const SolicitacoesScreen({
    super.key,
    required this.selectedIndex,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF13131A),
      appBar: Cabecalho(
        selectedIndex: selectedIndex,
        onSelectTab: onSelectTab,
        searchQuery: '',
        onSearchChanged: (value) {
          // Implementar filtro de pesquisa se necessário
        },
        userName: '',
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pasta de Solicitações',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1B2A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Nenhuma solicitação encontrada.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
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
}
