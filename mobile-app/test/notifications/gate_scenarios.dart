import 'dart:convert';

import '../../lib/services/notifications/alert_gate.dart';
import '../../lib/services/notifications/push_payload.dart';

class MemoryNoticeStore implements NoticeStateStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String scope) async => values[scope];
  @override
  Future<void> write(String scope, String value) async {
    if (fail) throw StateError('synthetic storage failure');
    values[scope] = value;
  }
}

class ReceiptMemoryStore extends MemoryNoticeStore
    implements BackgroundNoticeReceipts {
  final receipts = <String>{};
  @override
  Future<bool> wasReceived(String scope, String id) async =>
      receipts.contains('$scope/$id');
}

Map<String, dynamic> snapshot(
  int id, {
  int revision = 1,
  String review = 'confirmed',
  String handling = 'unacknowledged',
  String notification = 'pending',
  String source = 'live_camera',
}) => {
  'id': 'a_${id.toRadixString(16).padLeft(40, '0')}',
  'revision': revision,
  'source': source,
  'review_status': review,
  'handling_status': handling,
  'notification_status': notification,
};
void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<int> runGateScenarios() async {
  var count = 0;
  final store = MemoryNoticeStore();
  final gate = AlertNotificationGate(
    store: store,
    scope: 'http://192.168.1.2:8000|default',
  );
  check(
    (await gate.accept([snapshot(1)], historical: true)).isEmpty,
    'history silent',
  );
  count++;
  check(
    (await gate.accept([snapshot(1, revision: 2)], historical: false)).isEmpty,
    'history stays silent on revision',
  );
  count++;
  check(
    (await gate.accept([snapshot(2)], historical: false)).length == 1,
    'new alert emitted',
  );
  count++;
  check(
    (await gate.accept([snapshot(2)], historical: false)).isEmpty,
    'duplicate silent',
  );
  count++;
  check(
    (await gate.accept([
      snapshot(2, revision: 3, handling: 'acknowledged'),
    ], historical: false)).isEmpty,
    'ack is not a new alert',
  );
  count++;
  check(
    (await gate.accept([snapshot(2, revision: 2)], historical: false)).isEmpty,
    'older revision cannot replay',
  );
  count++;
  final restart = AlertNotificationGate(store: store, scope: gate.scope);
  check(
    (await restart.accept([
      snapshot(2, revision: 4),
    ], historical: false)).isEmpty,
    'restart preserves dedup',
  );
  count++;
  check(
    (await restart.accept([
          snapshot(3, source: 'uploaded_recording'),
        ], historical: false)).length ==
        1,
    'recording source supported',
  );
  count++;
  for (final invalid in [
    snapshot(4, review: 'pending'),
    snapshot(5, review: 'withdrawn'),
    snapshot(6, handling: 'resolved'),
    snapshot(7, notification: 'skipped_history'),
  ]) {
    check(
      (await restart.accept([invalid], historical: false)).isEmpty,
      'ineligible event silent',
    );
    count++;
  }
  check(
    (await restart.accept(
      [snapshot(8)],
      historical: false,
      notificationsEnabled: false,
    )).isEmpty,
    'switch disabled',
  );
  count++;
  check(
    (await restart.accept([
      snapshot(8, revision: 2),
    ], historical: false)).isEmpty,
    'enable does not replay muted event',
  );
  count++;
  final parallel = await Future.wait([
    restart.accept([snapshot(9)], historical: false),
    restart.accept([snapshot(9)], historical: false),
  ]);
  check(parallel.expand((x) => x).length == 1, 'concurrent refresh emits once');
  count++;
  store.fail = true;
  var failed = false;
  try {
    await restart.accept([snapshot(10)], historical: false);
  } catch (_) {
    failed = true;
  }
  check(failed, 'storage failure surfaced');
  store.fail = false;
  check(
    (await restart.accept([snapshot(10)], historical: false)).length == 1,
    'storage failure not consumed',
  );
  count++;
  final other = AlertNotificationGate(
    store: store,
    scope: 'http://192.168.1.3:8000|default',
  );
  check(
    (await other.accept([snapshot(2)], historical: false)).length == 1,
    'backend isolation',
  );
  count++;
  final pending = PendingAlertOpen();
  pending.add(scope: gate.scope, id: snapshot(2)['id'] as String);
  check(
    pending.take('wrong-backend') == null &&
        pending.take(gate.scope) == snapshot(2)['id'] &&
        pending.take(gate.scope) == null,
    'cold click scoped and consumed once',
  );
  count++;
  pending.add(scope: gate.scope, id: 'https://untrusted.invalid');
  check(pending.take(gate.scope) == null, 'external links rejected');
  count++;
  store.values['corrupt'] = jsonEncode({'version': 42, 'seen': []});
  failed = false;
  try {
    await AlertNotificationGate(
      store: store,
      scope: 'corrupt',
    ).accept([snapshot(11)], historical: false);
  } catch (_) {
    failed = true;
  }
  check(failed, 'corrupt state fails closed');
  count++;
  failed = false;
  try {
    await restart.accept([
      {'id': 'source-local-id'},
    ], historical: false);
  } catch (_) {
    failed = true;
  }
  check(failed, 'non unified candidate rejected');
  count++;
  check(
    (await restart.accept([
          snapshot(4, revision: 2),
        ], historical: false)).length ==
        1,
    'pending becomes confirmed exactly once',
  );
  count++;
  check(
    notificationScope('http://192.168.1.2:8000/') ==
        'http://192.168.1.2:8000|default',
    'scope canonicalization',
  );
  count++;
  failed = false;
  try {
    notificationScope('https://user:private@example.invalid');
  } catch (_) {
    failed = true;
  }
  check(failed, 'credentials never enter scope');
  count++;
  check(
    (await restart.accept([
      snapshot(7, revision: 2),
    ], historical: false)).isEmpty,
    'skipped history never replays',
  );
  count++;
  check(
    (await restart.accept([
          snapshot(12, notification: 'cancelled'),
        ], historical: false)).isEmpty &&
        (await restart.accept([
          snapshot(12, revision: 2),
        ], historical: false)).isEmpty,
    'cancelled stays consumed',
  );
  count++;
  final receipts = ReceiptMemoryStore();
  final receivedId = snapshot(13)['id'] as String;
  receipts.receipts.add(gate.scope + '/' + receivedId);
  final backgroundGate = AlertNotificationGate(
    store: receipts,
    scope: gate.scope,
  );
  check(
    (await backgroundGate.accept([snapshot(13)], historical: false)).isEmpty,
    'background receipt prevents foreground re-ring',
  );
  count++;
  check(
    (await AlertNotificationGate(
      store: receipts,
      scope: gate.scope,
    ).accept([snapshot(13, revision: 2)], historical: false)).isEmpty,
    'background receipt survives restart',
  );
  count++;
  check(
    (await AlertNotificationGate(
          store: receipts,
          scope: other.scope,
        ).accept([snapshot(13)], historical: false)).length ==
        1,
    'background receipt isolated by backend',
  );
  count++;
  final payload = <String, dynamic>{
    'anju_type': 'unified_alert',
    'alert_id': receivedId,
    'scope': gate.scope,
  };
  check(scopedPushAlert(payload)?.id == receivedId, 'valid scoped FCM payload');
  count++;
  for (final bad in [
    {...payload, 'scope': 'http://user:private@example.invalid|default'},
    {...payload, 'scope': 'http://192.168.1.2:8000/|default'},
    {...payload, 'scope': 'http://192.168.1.2:8000|other'},
    {...payload, 'alert_id': 'raw-source'},
    {...payload, 'alert_id': receivedId + '\n'},
    {...payload, 'anju_type': 'unknown'},
    {
      'message_type': 'unified_alert',
      'alert_id': receivedId,
      'scope': gate.scope,
    },
  ]) {
    check(
      scopedPushAlert(bad) == null,
      'malformed or legacy-unscoped push rejected',
    );
    count++;
  }
  return count;
}

Future<void> main() async {
  final count = await runGateScenarios();
  print(
    'PASS: $count notification-core scenarios (synthetic, not phone delivery)',
  );
}
