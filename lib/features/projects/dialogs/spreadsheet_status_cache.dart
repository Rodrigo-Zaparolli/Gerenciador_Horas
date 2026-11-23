import 'package:flutter/foundation.dart';

/// Only calculations of the saved workbook belong in its durable snapshot.
Map<String, dynamic>? savedSpreadsheetStatus(
    Map<String, dynamic>? snapshot, Map<String, String> sheets) {
  if (snapshot == null ||
      snapshot['statusPreview'] is! Map ||
      snapshot['statusPreviewRevision'] != snapshot['revision'] ||
      snapshot['statusPreviewSheets'] is! Map ||
      !mapEquals({
        for (final entry in (snapshot['statusPreviewSheets'] as Map).entries)
          if (!entry.key.toString().startsWith('catalog'))
            entry.key: entry.value
      }, {
        for (final entry in sheets.entries)
          if (!entry.key.startsWith('catalog')) entry.key: entry.value
      })) {
    return null;
  }
  return Map<String, dynamic>.from(snapshot['statusPreview'] as Map);
}

Map<String, dynamic> withSavedSpreadsheetStatus(Map<String, dynamic> snapshot,
        Map<String, String> sheets, Map<String, dynamic> status) =>
    {
      ...snapshot,
      'statusPreview': status,
      'statusPreviewRevision': snapshot['revision'],
      'statusPreviewSheets': {
        for (final entry in sheets.entries)
          if (!entry.key.startsWith('catalog')) entry.key: entry.value
      },
    };
