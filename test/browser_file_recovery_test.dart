import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/browser_local_files_service.dart';

void main() {
  test('Valid browser file stays on its original reader', () async {
    var nativeReads = 0;
    final result = await readBrowserFileWithRecovery(
      browserRead: () async => Uint8List.fromList([1, 2]),
      nativeRead: () async {
        nativeReads++;
        return Uint8List(0);
      },
    );
    expect(result, [1, 2]);
    expect(nativeReads, 0);
  });
  test('Lost browser handle uses native recovery exactly once', () async {
    var nativeReads = 0;
    final result = await readBrowserFileWithRecovery(
      browserRead: () async => throw StateError('Handle perdido'),
      nativeRead: () async {
        nativeReads++;
        return Uint8List.fromList([3]);
      },
    );
    expect(result, [3]);
    expect(nativeReads, 1);
  });
  test('Failed recovery preserves the actionable native error', () async {
    await expectLater(
        readBrowserFileWithRecovery(
          browserRead: () async => throw StateError('Handle perdido'),
          nativeRead: () async => throw StateError(
              'Selecione novamente o arquivo no editor deste computador.'),
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('Selecione novamente'))));
  });
  test('Damaged URI does not crash reference detection', () {
    expect(
        BrowserLocalFiles.isReference(
            'desktop-file://local/owner/12345678-1234-1234-1234-123456789abc/%FF'),
        false);
  });
}
