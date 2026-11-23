import 'package:gerenciador_horas/features/project_emails/email_body_preview.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/core/platform/local_user_state.dart';
import 'package:gerenciador_horas/core/theme/app_theme.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/project_emails/project_email_modal.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/email_recipient_fields.dart';
import 'package:gerenciador_horas/features/project_emails/products_image_field.dart';
import 'project_email_modal_test.dart' show MemoryEmailStore;
import 'products_image_field_test.dart' show png;

void main() {
  testWidgets('Only the current workbook supplies recipients; empty reimport clears them', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryEmailStore();
    for (final kind in ProjectEmailKind.values) {
      store.drafts['owner-a/123/${kind.name}'] = {'contacts': [
        EmailContact(email: 'antigo@example.com', destination: 'Para').toJson()
      ], 'recipientSelectionManual': true};
    }
    var empty = false;
    Uint8List workbook() {
      final book = excel.Excel.createExcel();
      final sheet = book['Informações de entrada'];
      sheet.appendRow([excel.TextCellValue('CLIENTE')]);
      sheet.appendRow([excel.TextCellValue('Proprietário'), excel.TextCellValue('Cliente atual'),
        excel.TextCellValue(empty ? '' : 'atual@example.com')]);
      return Uint8List.fromList(book.encode()!);
    }
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body: ProjectEmailModal(
      project: ProjectModel.fromJson({'id': '123', 'client': 'Cliente', 'serviceType': 'Enterprise'}),
      store: store, workbookLoader: () async => workbook(),
    ))));
    await tester.pumpAndSettle();
    List<EmailContact> contacts() => tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
    expect(contacts().map((c)=>c.email), ['atual@example.com']);
    expect(contacts().any((c)=>c.email=='antigo@example.com'),isFalse);
    Future<void> loadWorkbook() async {
      await tester.ensureVisible(find.text('Selecionar planilha'));
      await tester.tap(find.text('Selecionar planilha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (find.text('Importar').evaluate().isNotEmpty) await tester.tap(find.text('Importar'));
      await tester.pumpAndSettle();
    }
    await loadWorkbook();
    expect(contacts().map((c) => c.email), ['atual@example.com']);
    expect(contacts().single.destination, 'Não incluir');
    empty = true;
    await loadWorkbook();
    expect(contacts().where((c) => validEmail(c.email)), isEmpty);
    expect(tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).allowedEmails, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  setUp(() => LocalUserState.memory = {});
  tearDown(() => LocalUserState.memory = null);
  for (final origin in const [ProjectEmailKind.initial, ProjectEmailKind.internal, ProjectEmailKind.finalization]) {
    testWidgets('workbook imported in ${origin.name} remains available in all three models', (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = excel.Excel.createExcel();
      final sheet = book['Informações de entrada'];
      for (final row in [
        ['CLIENTE'], ['Proprietário', 'Cliente planilha', 'cliente@example.com'],
        ['CYNCLY'], ['Exec. de Relacionamento', 'ER planilha', 'er@example.com'],
      ]) {
        sheet.appendRow(row.map(excel.TextCellValue.new).toList());
      }
      final store = MemoryEmailStore();
      sheet.updateCell(excel.CellIndex.indexByString('G17'), excel.TextCellValue('cliente@example.com'));
      sheet.updateCell(excel.CellIndex.indexByString('G39'), excel.TextCellValue('er@example.com'));
      sheet.updateCell(excel.CellIndex.indexByString('F17'), excel.TextCellValue('Cliente planilha'));
      sheet.updateCell(excel.CellIndex.indexByString('F39'), excel.TextCellValue('ER planilha'));
      for (final kind in const [ProjectEmailKind.initial, ProjectEmailKind.internal, ProjectEmailKind.finalization]) {
        store.drafts['owner-a/123/${kind.name}'] = {'contacts': [], 'recipientsConfigured': true};
      }
      final project = ProjectModel(id: '123', id2: '', client: 'Cliente', serviceType: 'Enterprise',
        stage: '', task: '', status: 'TRAB', startDate: DateTime(2026, 10, 15),
        estimatedHours: '08:00', leader: '', hourType: 'Hs Cobradas');
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: Scaffold(body:
        ProjectEmailModal(project: project, store: store,
          workbookLoader: () async => Uint8List.fromList(book.encode()!)))));
      await tester.pumpAndSettle();
      final originChip = find.widgetWithText(ChoiceChip, origin.label);
      await tester.ensureVisible(originChip);
      await tester.tap(originChip);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Selecionar planilha'));
      await tester.tap(find.text('Selecionar planilha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (find.text('Importar').evaluate().isNotEmpty) { await tester.tap(find.text('Importar')); }
      await tester.pumpAndSettle();
      for (final kind in const [ProjectEmailKind.initial, ProjectEmailKind.internal, ProjectEmailKind.finalization]) {
        final chip = find.widgetWithText(ChoiceChip, kind.label);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        final contacts = tester.widget<EmailRecipientFields>(find.byType(EmailRecipientFields)).contacts;
        expect(contacts.map((contact) => contact.email).toSet(),
          kind.isInternal ? {'er@example.com'} : containsAll(['cliente@example.com', 'er@example.com']));
        if (kind.isInternal) {
          expect(contacts.every((c) => c.destination == 'Para'), true);
        }
        if (kind == ProjectEmailKind.finalization) {
          expect(contacts.where((c) => c.destination == 'Para').map((c) => c.email), ['cliente@example.com']);
          expect(contacts.where((c) => c.destination == 'Cc').map((c) => c.email), ['er@example.com']);
        }
        // Remove any preselection so every imported address must be offered by +.
        for (final label in ['Para', 'Cc']) {
          final container = find.byKey(ValueKey('recipient-container-$label'));
          final chips = find.descendant(of: container, matching: find.byType(InputChip));
          for (final chip in tester.widgetList<InputChip>(chips).toList()) {
            chip.onDeleted!();
          }
        }
        await tester.pumpAndSettle();
        final add = find.byTooltip('Adicionar em Para');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(find.text('Cliente planilha — cliente@example.com'), findsOneWidget);
        expect(find.text('ER planilha — er@example.com'), findsOneWidget);
        await tester.tapAt(const Offset(1430, 10));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final regenerate in [true, false]) {
    testWidgets(
        'sheet import regenerates=$regenerate preserves proposal print and summary',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = excel.Excel.createExcel();
      final sheet = book['Informações de entrada'];
      for (final row in [
        ['Nome do sistema', 'Sistema atualizado'],
        ['ID da Biblioteca', '4431'],
        ['NS para instalação', '80200790'],
        ['Versão / Revisão', '2026.1'],
        ['CYNCLY'],
        [
          'Consultor de Implantação',
          'Consultor',
          'consultor@example.com',
          '54 9999-9999'
        ],
      ]) {
        sheet.appendRow(row.map(excel.TextCellValue.new).toList());
      }
      sheet.cell(excel.CellIndex.indexByString('C27')).value = excel.TextCellValue('Sistema atualizado');
      sheet.cell(excel.CellIndex.indexByString('C29')).value = excel.TextCellValue('4431');
      final store = MemoryEmailStore();
      store.templates['owner-a/internal'] = {
        'subject': 'Encerramento {sistema}',
        'body':
            'Sistema: {sistema}\nBiblioteca: {biblioteca}\nNS: {ns}\nVersão: {versao}\nTelefone: {telefone_consultor}\nProdutos adquiridos pelo cliente:\n{produtos}\nResumo da implantação:\n{resumo}\nAtt,\n{consultor}'
      };
      store.drafts['owner-a/123/internal'] = {
        'fields': {'resumo': 'Resumo digitado pelo usuário'},
        'contacts': [],
        'productsImage': base64Encode(png),
        'body': 'Mensagem editada manualmente.\nAtt,\nRodrigo'
      };
      final project = ProjectModel(
          id: '123',
          id2: '',
          client: 'Cliente',
          serviceType: 'Enterprise',
          stage: '',
          task: '',
          status: 'TRAB',
          startDate: DateTime(2026, 10, 13),
          estimatedHours: '08:00',
          leader: '',
          hourType: 'Hs Cobradas');
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
              body: ProjectEmailModal(
                  project: project,
                  store: store,
                  workbookLoader: () async =>
                      Uint8List.fromList(book.encode()!)))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encerramento Interno'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Selecionar planilha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selecionar planilha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue);
      if (!regenerate) {
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pump(const Duration(milliseconds: 300));
      }
      if (find.text('Importar').evaluate().isNotEmpty) { await tester.tap(find.text('Importar')); }
      await tester.pumpAndSettle();
      final body = tester.widget<EmailBodyPreview>(find.byType(EmailBodyPreview)).body;
      if (regenerate) {
        expect(body, contains('Sistema: Sistema atualizado'));
        expect(body, contains('NS: 80200790'));
        expect(body, isNot(contains('Telefone: 54 9999-9999')));
        expect(body, isNot(contains('Mensagem editada manualmente.')));
      } else {
        expect(body, contains('Mensagem editada manualmente.'));
      }
      expect(body, contains('Resumo digitado pelo usuário'));
      await tester.ensureVisible(find.text('Produtos adquiridos — print'));
      await tester.tap(find.text('Produtos adquiridos — print'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Image>(find.byKey(
              const ValueKey('email-products-image-preview'))).image,
          isA<MemoryImage>());
      expect(
          tester
              .widget<ProductsImageField>(find.byType(ProductsImageField))
              .image,
          orderedEquals(png));
      await tester.tap(find.text('Salvar neste projeto'));
      await tester.pumpAndSettle();
      final saved = store.drafts['owner-a/123/internal']!;
      expect(saved['fields']['ns'], '80200790');
      expect(saved['productsImage'], base64Encode(png));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
