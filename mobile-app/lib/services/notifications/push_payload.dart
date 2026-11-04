import 'alert_gate.dart';

/// FCM contains only stable IDs and non-sensitive routing metadata.
/// 'message_type' is reserved by FCM; use the application-owned 'anju_type'.
({String scope, String id})? scopedPushAlert(Map<String, dynamic> data) {
  final id = data['alert_id'], scope = data['scope'];
  if (data['anju_type'] != 'unified_alert' ||
      id is! String ||
      !isUnifiedAlertId(id) ||
      scope is! String ||
      !isNotificationScope(scope))
    return null;
  return (scope: scope, id: id);
}
