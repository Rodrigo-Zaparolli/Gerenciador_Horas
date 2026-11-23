// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'package:gerenciador_horas/features/completed_projects/completed_projects_screen.dart';
import 'support/redesign_firebase.dart';

void main() {
  testWidgets('service filter and clear preserve completed records without writes', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FirebasePlatform.instance = VisualCore();
    FirebaseAuthPlatform.instance = VisualAuth();
    final db = VisualFirestore()..seed();
    final original = db.documents['users/visual-fixture/completed_projects/900002']!;
    db.documents['users/visual-fixture/completed_projects/900003'] = {
      ...original, 'id': '900003', 'client': 'Outro cliente', 'serviceType': 'Enterprise',
    };
    FirebaseFirestorePlatform.instance = db;
    await Firebase.initializeApp();
    await tester.pumpWidget(MaterialApp(home: CompletedProjectsScreen(
      firebaseService: FirebaseService(), selectedIndex: 3, onSelectTab: (_) {}, userName: 'Teste')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tipo de Serviço'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enterprise').last);
    await tester.pumpAndSettle();
    expect(find.text('Outro cliente'), findsOneWidget);
    expect(find.textContaining('900002').evaluate().where((e) => e.widget is Text), isEmpty);
    await tester.tap(find.text('Limpar'));
    await tester.pumpAndSettle();
    expect(find.text('Outro cliente'), findsOneWidget);
    expect(find.text('900002'), findsOneWidget);
    expect(db.writes, 0);
  });
}
