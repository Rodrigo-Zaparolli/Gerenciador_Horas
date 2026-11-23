import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/edesk_service.dart';
import 'package:gerenciador_horas/domain/models/project_model.dart';
import 'package:gerenciador_horas/features/projects/dialogs/spreadsheet_phase_send_dialog.dart';

void main() {
  testWidgets('reviews saved phases before send, excludes other requests and prevents repeated sends', (tester) async {
    final project = ProjectModel.fromJson({'id':'2263850','client':'Cliente', 'subTasks':[
      {'subId':'1','stage':'Implantação','edeskPhaseName':'PROMOB - Implantação Plugin Desenvolvimento','planStart':'2026-09-10','planEnd':'2026-12-05'},
      {'subId':'2','stage':'Pós-Implantação','planStart':'2026-12-07','planEnd':'2026-12-16'},
      {'subId':'3','stage':'Outra solicitação','edeskSolicitacao':'999','planStart':'2026-12-07','planEnd':'2026-12-16'},
      {'subId':'4','stage':'Sem datas'},
    ]});
    var sends = 0;
    final result = Completer<EdeskSendResult>();
    await tester.pumpWidget(MaterialApp(home: Builder(builder:(context) => TextButton(
      onPressed: () => showSpreadsheetPhaseSend(context, project:project, authorized:()=>true,
        sender:(phases) {
          sends++;
          expect(phases, [{'nome':'PROMOB - Implantação Plugin Desenvolvimento','dataInicial':'10/09/2026','dataFinal':'05/12/2026'}]);
          return result.future;
        }), child:const Text('Abrir')))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(sends,0);
    expect(find.text('Outra solicitação'),findsNothing);
    await tester.tap(find.text('Pós-Implantação'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar selecionadas (1)'));
    await tester.pump();
    expect(sends,1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Enviando…')).onPressed,isNull);
    result.complete(const EdeskSendResult(confirmed:false,statusCode:500,message:'Falha de confirmação',responseBody:''));
    await tester.pumpAndSettle();
    expect(find.text('Falha de confirmação'),findsOneWidget);
    expect(find.text('Enviar selecionadas (1)'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
