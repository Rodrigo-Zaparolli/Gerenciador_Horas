import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/data/services/firebase_service.dart';
import 'phase_date_sync_store_test.dart' show PhaseDatabase;
import 'received_work_store_test.dart' show ImportAuth;

void main(){
  test('spreadsheet phase transaction is atomic and preserves all other project fields',()async{
    final db=PhaseDatabase();
    const path='users/owner/projects/2263850';
    final original=<String,dynamic>{'id':'2263850','client':'Impacto','excelLink':'impacto.xlsm','folderPath':'keep',
      'subTasks':[
        {'subId':'2','stage':'Implantação','planStart':'2026-09-10','planEnd':'2026-12-04','estimatedHours':'40:00','status':'TRAB'},
        {'subId':'3','stage':'Pós-Implantação','planStart':'2026-12-07','planEnd':'2026-12-16','estimatedHours':'10:00'},
      ]};
    db.documents[path]=original;
    final service=FirebaseService(database:db,auth:ImportAuth());
    final jobs=<Map<String,dynamic>>[
      {'work':'2','request':'2263850','phase':'Implantação','beforeStart':'2026-09-10','beforeEnd':'2026-12-04','start':'2026-09-10','end':'2026-12-05'},
      {'work':'3','request':'2263850','phase':'Pós-Implantação','beforeStart':'2026-12-07','beforeEnd':'2026-12-16','start':'2026-12-07','end':'2026-12-18'},
    ];
    await expectLater(service.applySpreadsheetPhaseDates(ownerUid:'owner',projectId:'2263850',reference:'wrong.xlsm',jobs:jobs),throwsStateError);
    expect(db.documents[path],original);
    await expectLater(service.applySpreadsheetPhaseDates(ownerUid:'owner',projectId:'2263850',reference:'impacto.xlsm',jobs:[jobs.first,{...jobs.last,'beforeEnd':'2026-01-01'}]),throwsStateError);
    expect(db.documents[path],original);
    await service.applySpreadsheetPhaseDates(ownerUid:'owner',projectId:'2263850',reference:'impacto.xlsm',jobs:jobs);
    final saved=db.documents[path]!;
    expect(saved['excelLink'],'impacto.xlsm');expect(saved['folderPath'],'keep');
    expect(saved['subTasks'][0]['planEnd'],'2026-12-05T00:00:00.000');
    expect(saved['subTasks'][1]['planEnd'],'2026-12-18T00:00:00.000');
    expect(saved['subTasks'][0]['startDate'],'2026-09-10T00:00:00.000');
    expect(saved['subTasks'][1]['startDate'],'2026-12-07T00:00:00.000');
    expect(saved['subTasks'][0]['estimatedHours'],'40:00');expect(saved['subTasks'][0]['status'],'TRAB');
    expect(db.documents.keys,[path]);
  });
}
