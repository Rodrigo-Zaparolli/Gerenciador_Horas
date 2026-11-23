// Test-only in-memory plugin adapters. Any write fails; no network is used.
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';

class VisualCore extends FirebasePlatform {
  final fixture = FirebaseAppPlatform(
      '[DEFAULT]',
      const FirebaseOptions(
          apiKey: 'fixture-only',
          appId: 'fixture-only',
          messagingSenderId: 'fixture',
          projectId: 'fixture-only'));
  @override
  List<FirebaseAppPlatform> get apps => [fixture];
  @override
  FirebaseAppPlatform app([String name = '[DEFAULT]']) => fixture;
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      fixture;
}

class VisualAuth extends FirebaseAuthPlatform {
  late final fixture = VisualUser(this);
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues(
          {InternalUserDetails? currentUser, String? languageCode}) =>
      this;
  @override
  UserPlatform get currentUser => fixture;
  @override
  Stream<UserPlatform?> authStateChanges() => Stream.value(fixture);
  @override
  Stream<UserPlatform?> userChanges() => Stream.value(fixture);
  @override
  Stream<UserPlatform?> idTokenChanges() => Stream.value(fixture);
}

class VisualFactor extends MultiFactorPlatform {
  VisualFactor(super.auth);
}

class VisualUser extends UserPlatform {
  VisualUser(FirebaseAuthPlatform auth)
      : super(
            auth,
            VisualFactor(auth),
            InternalUserDetails(
                userInfo: InternalUserInfo(
                    uid: 'visual-fixture',
                    email: 'fixture@example.invalid',
                    displayName: 'Consultor de teste',
                    isAnonymous: false,
                    isEmailVerified: true),
                providerData: []));
}

class VisualFirestore extends FirebaseFirestorePlatform {
  bool empty = false;
  bool failReads = false;
  int writes = 0;
  final Map<String, Map<String, dynamic>> documents = {};
  void seed() {
    final now = DateTime.now();
    Map<String, dynamic> project(String id, {bool completed = false}) => {
          'id': id,
          'client': 'Cliente de validação $id',
          'serviceType': 'Consultoria',
          'status': completed ? 'TRAB_FIM' : 'INI_PRO',
          'estimatedHours': '16:00',
          'startDate': now,
          'leader': 'Líder de teste',
          'hourType': 'Hs Cobradas',
          'finalizedAt': completed ? now : null,
          'subTasks': [
            {
              'subId': '2',
              'stage': 'Contato Inicial',
              'status': 'INI_PRO',
              'startDate': now,
              'planStart': now,
              'planEnd': now.add(const Duration(days: 30)),
              'estimatedHours': '08:00',
              'hourType': 'Hs Cobradas'
            }
          ]
        };
    documents.addAll({
      'users/visual-fixture/projects/900001': project('900001'),
      'users/visual-fixture/completed_projects/900002':
          project('900002', completed: true),
      'users/visual-fixture/work_formats/001': {
        'id': '001',
        'name': 'Consultoria',
        'steps': ['Contato Inicial', 'Consultoria']
      },
      'users/visual-fixture/checklist_formats/001': {
        'id': '001',
        'name': 'Checklist de validação',
        'items': [
          {'name': 'Conferir projeto', 'order': '1', 'completed': false}
        ]
      },
      'users/visual-fixture/orientacoes/001': {
        'titulo': 'Orientação de validação',
        'texto': 'Conteúdo de teste preservado integralmente.',
        'imagens': []
      },
      'users/visual-fixture/projects/900001/time_logs/a': {
        'targetId': '900001_2',
        'projectId': '900001',
        'date': now,
        'hours': 1.5,
        'description': 'Apontamento de validação',
        'startTime': '08:00',
        'endTime': '09:30',
        'durationFormatted': '01:30',
        'isRegistered': true,
        'projectName': 'Cliente de validação',
        'taskName': 'Contato Inicial',
        'typeHs': 'Hs Cobradas'
      },
    });
  }

  void deny() {
    writes++;
    throw StateError('Writes are forbidden in visual tests');
  }

  /// Richer synthetic records only for visual comparison with the references.
  void seedGallery() {
    const models = ['Enterprise','Professional','Consultoria','Implantação Plugin','Treinamento Catalog','Desenvolvimento Plugin','Atividades Internas','Revitalização','Implantação + Desenvolvimento','Treinamento + Consultoria','Plugin'];
    for (var i=0;i<models.length;i++) {
      final id = '${i+1}'.padLeft(3,'0');
      documents['users/visual-fixture/work_formats/$id'] = {'id':id,'name':models[i],'steps':List.generate(i==6?12:4,(j)=>'Etapa ${j+1}')};
    }
    const titles = ['Cobrança ADV','Solicitação NS uso interno','Solicitação NS cliente','Procedimentos do projeto','Documentação Plugin','Orientações de atendimento','NS Plugins','Cronograma do projeto'];
    for(var i=0;i<titles.length;i++) {
      documents['users/visual-fixture/orientacoes/${i+1}'] = {'titulo':titles[i],'texto':'Orientação de demonstração. Consulte os procedimentos e informações necessários para realizar esta atividade.','imagens':[]};
    }
    documents.remove('users/visual-fixture/orientacoes/001');
    final prototype = documents['users/visual-fixture/projects/900001']!;
    for(var i=0;i<3;i++) {
      final id='${900001+i}';
      final now=DateTime.now();
      documents['users/visual-fixture/projects/$id']={...prototype,'id':id,'client':'EMPRESA DE DEMONSTRAÇÃO ${i+1}','serviceType':i==2?'Consultoria':'Promob Enterprise',
        'subTasks': [for(var j=0;j<6;j++) {'subId':'${j+1}','stage':['Gerenciamento de Projetos','Contato Inicial','Levantamento de Escopo','Desenvolvimento','Implantação','Pós-Implantação'][j], 'status':'INI_PRO','startDate':now,'planStart':now,'planEnd':now.add(Duration(days:i==2?-3:3+i)),'estimatedHours':'08:00','hourType':'Hs Cobradas'}]};
    }
    final completed=documents['users/visual-fixture/completed_projects/900002']!;
    for(var i=0;i<8;i++) {
      final id='${910001+i}';documents['users/visual-fixture/completed_projects/$id']={...completed,'id':id,'client':'Empresa concluída de demonstração ${i+1}'};
    }
  }

  @override
  FirebaseFirestorePlatform delegateFor(
          {required FirebaseApp app, required String databaseId}) =>
      this;
  @override
  CollectionReferencePlatform collection(String path) =>
      VisualCollection(this, path);
  @override
  DocumentReferencePlatform doc(String path) => VisualDocument(this, path);
}

final visualMetadata =
    InternalSnapshotMetadata(hasPendingWrites: false, isFromCache: false);
mixin VisualQuery on QueryPlatform {
  String get visualPath;
  VisualFirestore get source => firestore as VisualFirestore;
  @override
  Future<QuerySnapshotPlatform> get(
      [GetOptions options = const GetOptions()]) async {
    if (source.failReads) throw StateError('Fixture read failure');
    final rows = source.empty
        ? <DocumentSnapshotPlatform>[]
        : source.documents.entries
            .where((e) =>
                e.key.startsWith('$visualPath/') &&
                !e.key.substring(visualPath.length + 1).contains('/'))
            .map((e) => DocumentSnapshotPlatform(
                source, e.key, e.value, visualMetadata))
            .toList();
    return QuerySnapshotPlatform(
        rows, [], SnapshotMetadataPlatform(false, false));
  }

  @override
  Stream<QuerySnapshotPlatform> snapshots(
          {bool includeMetadataChanges = false,
          required ListenSource listenSource}) =>
      Stream.fromFuture(get());
  @override
  QueryPlatform where(List<List<dynamic>> conditions) => this;
  @override
  QueryPlatform whereFilter(FilterPlatformInterface filter) => this;
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) => this;
  @override
  QueryPlatform limit(int limit) => this;
  @override
  QueryPlatform limitToLast(int limit) => this;
}

class VisualCollection extends CollectionReferencePlatform with VisualQuery {
  VisualCollection(VisualFirestore source, String path) : super(source, path) {
    parameters.addAll({
      'where': <List<dynamic>>[],
      'orderBy': <List<dynamic>>[],
      'limit': null,
      'limitToLast': null,
      'startAt': null,
      'startAfter': null,
      'endAt': null,
      'endBefore': null
    });
  }
  @override
  String get visualPath => path;
  @override
  DocumentReferencePlatform doc([String? path]) =>
      VisualDocument(source, '${this.path}/${path ?? 'new'}');
}

class VisualDocument extends DocumentReferencePlatform {
  VisualDocument(VisualFirestore source, String path) : super(source, path);
  VisualFirestore get source => firestore as VisualFirestore;
  @override
  Future<DocumentSnapshotPlatform> get(
      [GetOptions options = const GetOptions()]) async {
    if (source.failReads) throw StateError('Fixture read failure');
    return DocumentSnapshotPlatform(source, path,
        source.empty ? null : source.documents[path], visualMetadata);
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots(
          {bool includeMetadataChanges = false,
          required ListenSource listenSource}) =>
      Stream.fromFuture(get());
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async =>
      source.deny();
  @override
  Future<void> update(Map<FieldPath, dynamic> data) async => source.deny();
  @override
  Future<void> delete() async => source.deny();
}
