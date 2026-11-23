// ignore_for_file: subtype_of_sealed_class
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gerenciador_horas/data/services/time_log_store.dart';
import 'package:gerenciador_horas/domain/models/dashboard_models.dart';
import 'time_log_query_test.dart' show TestAuth;

class Database extends Fake implements FirebaseFirestore {
 final records=<String,Map<String,dynamic>>{};
 @override CollectionReference<Map<String,dynamic>> collection(String path)=>Collection(this,path);
}
class Collection extends Fake implements CollectionReference<Map<String,dynamic>> {
 Collection(this.db,this.path);
 final Database db;
 @override final String path;
 @override DocumentReference<Map<String,dynamic>> doc([String? id])=>Reference(db,'$path/$id');
}
class Reference extends Fake implements DocumentReference<Map<String,dynamic>> {
 Reference(this.db,this.path);
 final Database db;
 @override final String path;
 @override CollectionReference<Map<String,dynamic>> collection(String child)=>Collection(db,'$path/$child');
 @override Future<void> set(Map<String,dynamic> data,[SetOptions? options]) async {db.records[path]={...?db.records[path],...data};}
 @override Future<DocumentSnapshot<Map<String,dynamic>>> get([GetOptions? options]) async=>Snapshot(db.records.containsKey(path));
}
class Snapshot extends Fake implements DocumentSnapshot<Map<String,dynamic>> {
 Snapshot(this.exists);
 @override final bool exists;
}
void main(){
 for(final description in <String?>[null,'','   ']) {
  test('Persists and registers hours without a comment: $description',() async {
   final db=Database(); final store=TimeLogStore(firestore:db,auth:TestAuth());
   final log=TimeLog(id:'hour',targetId:'123_4',date:DateTime(2026,11,17),startTime:'08:00',endTime:'09:00',durationFormatted:'01:00',isRegistered:false,taskName:'Task',description:description);
   await store.addFirebaseLog('123',log);
   await store.register(log);
   final saved=db.records['users/a/projects/123/time_logs/hour']!;
   expect(saved['description'],''); expect(saved['isRegistered'],isTrue);
   expect(store.logs.single.isRegistered,isTrue);
   expect(saved['durationFormatted'],'01:00');
   store.dispose();
  });
 }
}
