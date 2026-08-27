import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> verificarAtualizacaoAutomatica(BuildContext context) async {
  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String currentVersion = packageInfo.version;

    final response = await http
        .get(
          Uri.parse(
              'https://raw.githubusercontent.com/Rodrigo-Zaparolli/Gerenciador_Horas/main/version.json'),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final String latestVersion = data['version'];
      final String installerUrl = data['installerUrl'];

      if (!context.mounted) return;

      if (latestVersion != currentVersion) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2D2D44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.system_update_rounded,
                    color: Color(0xFF00FFCC), size: 24),
                SizedBox(width: 10),
                Text(
                  'Atualização Disponível',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            content: Text(
              'Uma nova versão ($latestVersion) do Gerenciador de Horas está disponível para download.\n\nDeseja atualizar agora?',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Depois',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FFCC),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  final Uri url = Uri.parse(installerUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  'Atualizar Agora',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }
    }
  } catch (e) {
    // Ignora erros de rede na inicialização silenciosa
  }
}
