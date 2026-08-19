import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/app/app.dart';

void main() {
  testWidgets(
    'Carrega a tela principal do Gerenciador de Horas',
    (WidgetTester tester) async {
      await tester.pumpWidget(const GerenciadorHorasApp());

      expect(
        find.byType(GerenciadorHorasApp),
        findsOneWidget,
      );
    },
  );
}
