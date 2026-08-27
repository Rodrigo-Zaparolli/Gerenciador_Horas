import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Função pública para exibir o diálogo "Sobre o Desenvolvedor" e verificação de atualizações
void showCustomAuthorDialog(BuildContext context) async {
  // Pega a versão atual do app instalada no dispositivo em tempo real
  String currentVersion = '1.0.0';
  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    currentVersion = packageInfo.version;
  } catch (e) {
    // Mantém o padrão caso ocorra algum erro
  }

  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF2D2D44), // Padrão de cor do seu app
        title: const Text(
          'Sobre o Desenvolvedor',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sistema desenvolvido por:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rodrigo Zaparolli',
              style: TextStyle(
                color: Color(0xFF00FFCC),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Versão atual: $currentVersion',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // Botão para verificar atualizações online
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF00FFCC),
            ),
            onPressed: () {
              Navigator.pop(context); // Fecha o dialog sobre
              _checkForUpdatesFromDialog(
                  context, currentVersion); // Roda a checagem
            },
            icon: const Icon(Icons.system_update, size: 18),
            label: const Text('Verificar Atualizações'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FFCC),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    },
  );
}

// Função auxiliar que faz a checagem da versão no servidor
Future<void> _checkForUpdatesFromDialog(
    BuildContext context, String currentVersion) async {
  // Mostra um indicador de carregamento rápido
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(
      child: CircularProgressIndicator(color: Color(0xFF00FFCC)),
    ),
  );

  try {
    // Substitua pelo link real do seu arquivo version.json hospedado na internet
    final response =
        await http.get(Uri.parse('https://seu-site.com/version.json'));

    // Fecha o indicador de carregamento
    if (context.mounted) Navigator.pop(context);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final String latestVersion = data['version'];
      final String installerUrl = data['installerUrl'];

      if (!context.mounted) return;

      if (latestVersion != currentVersion) {
        // Se houver versão nova, mostra o aviso para baixar
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2D2D44),
            title: const Text('Nova Atualização Disponível!',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'A versão $latestVersion está disponível para download.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFCC)),
                onPressed: () async {
                  Navigator.pop(context);
                  final Uri url = Uri.parse(installerUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('Baixar Agora',
                    style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
      } else {
        // Se já estiver na última versão
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seu aplicativo já está na versão mais recente!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  } catch (e) {
    // Fecha o carregamento caso dê erro de rede
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Não foi possível verificar as atualizações. Verifique sua conexão.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
