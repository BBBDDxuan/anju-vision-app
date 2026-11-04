import '../android_notices.dart';
import 'alert_gate.dart';

/// B forwards its single authoritative data flow here. This service never
/// requests alerts or changes routes; the application owns both responsibilities.
class UnifiedNotificationService {
  UnifiedNotificationService({required this.gate, required this.android});
  final AlertNotificationGate gate;
  final AndroidNotices android;

  Future<List<UnifiedAlertNotice>> synchronize(
    Iterable<Map<String, dynamic>> snapshots, {
    required bool historical,
    required bool notificationsEnabled,
  }) async {
    final notices = await gate.accept(
      snapshots,
      historical: historical,
      notificationsEnabled: notificationsEnabled,
    );
    for (final notice in notices) {
      try {
        await android.show(notice.id, scope: gate.scope);
      } catch (_) {
        // Return the notice for an in-app warning even when Android refuses it.
        // Permission denial does not cause later list refreshes to ring again.
      }
    }
    return notices;
  }
}
