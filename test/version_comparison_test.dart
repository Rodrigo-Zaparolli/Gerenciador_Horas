import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/utils/version_comparison.dart';

void main() {
  test('Only a newer release triggers an update', () {
    expect(isNewerRelease('1.0.1', '1.0.2'), isFalse);
    expect(isNewerRelease('1.0.2', '1.0.2'), isFalse);
    expect(isNewerRelease('1.0.10', '1.0.9'), isTrue);
    expect(isNewerRelease('2.0.0', '1.9.9'), isTrue);
    expect(isNewerRelease('1.0.2+4', '1.0.2+3'), isFalse);
    expect(isNewerRelease('invalid', '1.0.2'), isFalse);
    expect(isNewerRelease('2.0.0-beta', '1.0.2'), isFalse);
  });
}
