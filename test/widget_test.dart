import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gerenciador_horas/features/auth/screens/login_screen.dart';

void main() {
  testWidgets(
    'Carrega o login e protege o campo de senha',
    (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(onLoginSuccess: () {}),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byType(LoginScreen),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final fields = tester.widgetList<EditableText>(find.byType(EditableText));
      expect(fields.length, 2);
      expect(fields.last.obscureText, isTrue);
    },
  );
}
