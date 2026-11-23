import 'package:cloud_firestore/cloud_firestore.dart';
import 'edesk_integration.dart';

class ZendeskService {
  static Future<Map<String, dynamic>> call(
      String action, Map<String, dynamic> data) async {
    final configured = Uri.parse(await EdeskIntegrationApi.currentUrl());
    final base = const {'127.0.0.1', 'localhost'}.contains(configured.host)
        ? configured.toString()
        : 'http://127.0.0.1:8765';
    final health = await EdeskIntegrationApi.call('/healthz',
        baseUrl: base, authenticated: false);
    if (health['zendeskWorkflow'] != true) {
      throw StateError(
          'Atualize e reinicie a integração local para usar a captura SLA e o Zendesk.');
    }
    return EdeskIntegrationApi.call('/api/zendesk/$action',
        baseUrl: base, body: data, timeout: const Duration(minutes: 5));
  }

  static Future<void> saveReceipt(
          String uid, String projectId, Map<String, dynamic> receipt) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('projects')
          .doc(projectId)
          .collection('zendeskTickets')
          .doc('${receipt['ticketId']}')
          .set({
        'ticketId': receipt['ticketId'],
        'url': receipt['url'],
        'priority': receipt['priority'],
        'draftId': receipt['draftId'],
        'slaRegistered': receipt['slaRegistered'] == true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
