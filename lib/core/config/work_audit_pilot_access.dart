import 'pilot_feature_access.dart';

class WorkAuditPilotAccess {
  WorkAuditPilotAccess._();
  static bool allows({required String? uid, required String? email}) =>
      PilotFeatureAccess.allows(uid: uid, email: email);
}
