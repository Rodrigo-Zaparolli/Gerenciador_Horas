/// The schedule summary and task checklist have different worksheet roles.
String catalogChecklistSheet(Map<String, String> settings) {
  final chosen = settings['catalogChecklistSheet']?.trim() ?? '';
  final schedule = settings['catalogSheet']?.trim().toLowerCase() ?? '';
  if (chosen.isEmpty ||
      chosen.toLowerCase() == schedule ||
      chosen.toLowerCase() == 'cronograma treinamento catalog') {
    return 'Checklist-Catalog';
  }
  return chosen;
}

List<String> catalogChecklistOptions(Iterable<String> available) => available
    .where((name) =>
        name.toLowerCase().contains('checklist') &&
        name.toLowerCase().contains('catalog'))
    .toSet()
    .toList();

Set<String> configuredCatalogGuides(Map<String, String> settings) =>
    settings['catalogEnabled'] == 'true' &&
            settings['catalogSource'] != 'external'
        ? {
            settings['catalogSheet'] ?? 'Cronograma Treinamento Catalog',
            catalogChecklistSheet(settings)
          }
        : {};
