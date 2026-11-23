import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/data/services/recoverable_draft.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;

void main() {
  const url = 'https://cyncly.sharepoint.com/:f:/s/Client/opaque-token?e=example';
  const title = 'Enterprise Produção Completa - BR Cantanhede Moveis';
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  for (final changeAccount in [false, true]) {
    testWidgets('SharePoint lookup preserves message and checks account: $changeAccount', (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryEmailStore();
      store.drafts['owner-a/123/initial'] = {'body': 'Mensagem manual.\nMateriais: $url'};
      final result = Completer<Map<String, dynamic>>();
      var calls = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProjectEmailModal(
        project: ProjectModel.fromJson({'id':'123','client':'BR Cantanhede Moveis','serviceType':'Enterprise'}),
        store: store, sharePointResolver: (args) {
          calls++;
          expect(args['owner'], 'owner-a');
          expect(args['links'], [url]);
          expect(args['interactive'], true);
          return result.future;
        }))));
      await tester.pumpAndSettle();
      final button = find.text('Buscar nomes no SharePoint');
      await tester.ensureVisible(button); await tester.tap(button); await tester.pump();
      expect(calls, 1);
      if (changeAccount) store.currentUserId = 'owner-b';
      result.complete({'names': {url: title}, 'errors': []});
      await tester.pumpAndSettle();
      final preview = tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview));
      expect(preview.body, 'Mensagem manual.\nMateriais: $url');
      expect(preview.linkLabels[url], changeAccount ? isNull : 'BR Cantanhede Moveis');
      if (!changeAccount) {
        final recovered = RecoverableDraft.read('owner-a', 'email.123.initial')!;
        expect((recovered['sharePointNames'] as Map)[url], title);
        expect(recovered.containsKey('access_token'), false);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
