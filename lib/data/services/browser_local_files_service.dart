import 'dart:convert';
import 'native_local_files_service.dart';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../core/platform/browser_files.dart';

Future<Uint8List> readBrowserFileWithRecovery({
  required Future<Uint8List> Function() browserRead,
  required Future<Uint8List> Function() nativeRead,
}) async {
  try {
    return await browserRead();
  } catch (_) {
    // Read-only recovery; native grants still have to match account and project.
    return nativeRead();
  }
}

class BrowserLocalFiles {
  static bool isReference(String? value) {
    try {
      final uri = Uri.tryParse(value ?? '');
      return uri != null &&
          {'browser-file', 'browser-folder', 'desktop-file', 'desktop-folder'}
              .contains(uri.scheme) &&
          uri.host == 'local' &&
          uri.pathSegments.length == 3 &&
          !uri.hasQuery &&
          !uri.hasFragment &&
          RegExp(r'^[0-9a-f-]{36}$').hasMatch(uri.pathSegments[1]);
    } on FormatException {
      return false;
    }
  }

  static String label(String reference) => isReference(reference)
      ? Uri.parse(reference).pathSegments.last
      : reference;
  static Future<Map<String, dynamic>> call(String action,
      {String? reference, String? name, List<String> path = const []}) async {
    final uid =
        Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
    final result = await browserFilesCall({
      'action': action,
      'uid': uid,
      'reference': reference,
      'name': name,
      'path': path,
    });
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError(
          'A conta mudou. Selecione a pasta ou arquivo novamente.');
    }
    return result;
  }

  static Future<String?> pickFolder({String? createName}) async =>
      // A failed health probe must not turn a project binding into a
      // browser-only handle that cannot carry its original Windows path.
      (await NativeLocalFiles.call(
          createName == null ? 'pick-folder' : 'create-folder',
          name: createName))['reference'] as String?;
  static Future<String?> pickFile() async =>
      (await NativeLocalFiles.call('pick-file'))['reference'] as String?;
  static Future<Uint8List> read(String reference, {String? projectId}) async {
    if (Uri.parse(reference).scheme.startsWith('desktop-')) {
      return NativeLocalFiles.read(reference, projectId: projectId);
    }
    final owner =
        Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser?.uid;
    return readBrowserFileWithRecovery(
      browserRead: () async => base64Decode(
          (await call('read', reference: reference))['base64'] as String),
      nativeRead: () {
        if (owner == null || FirebaseAuth.instance.currentUser?.uid != owner) {
          throw StateError('A conta mudou. Abra o trabalho novamente.');
        }
        return NativeLocalFiles.read(reference, projectId: projectId);
      },
    );
  }
}
