bool isSharePointFolderLink(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      uri.host.endsWith('.sharepoint.com');
}

/// Display the customer name for materials links without changing the URL.
Map<String, String> emailClientLinkLabels(String body, Map<String, String> names,
    {required String clientName}) {
  final result = Map<String, String>.from(names);
  final client = clientName.trim();
  if (client.isEmpty || client.contains('[PREENCHER:')) return result;
  for (final match in RegExp(r'https?://[^\s<>]+').allMatches(body)) {
    final url = match[0]!;
    final line = body.substring(0, match.start).split('\n').last.toLowerCase();
    if (isSharePointFolderLink(url) && line.contains('materiais')) {
      result[url] = client;
    }
  }
  return result;
}

List<String> sharePointLinksInBody(String body) => RegExp(r'https?://[^\s<>]+')
    .allMatches(body)
    .map((m) => m[0]!)
    .where(isSharePointFolderLink)
    .toSet()
    .toList();

Map<String, String> validSharePointNames(Object? raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.key is String &&
              isSharePointFolderLink(entry.key as String) &&
              entry.value is String &&
              (entry.value as String).trim().isNotEmpty &&
              (entry.value as String).length <= 512)
            entry.key as String: (entry.value as String).trim(),
      }
    : {};

String emailLinkDisplayText(String body, Map<String, String> names) =>
    body.replaceAllMapped(RegExp(r'https?://[^\s<>]+'), (match) {
      final url = match[0]!;
      return isSharePointFolderLink(url) && names[url]?.isNotEmpty == true
          ? '📁 ${names[url]}'
          : url;
    });
