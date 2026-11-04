import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/android_notices.dart';
import '../../lib/services/notifications/alert_gate.dart';
import '../../lib/services/notifications/notification_service.dart';

import 'gate_scenarios.dart';

const bridgeChannel = MethodChannel('elder_safety/notifications');

class DisabledAndroid extends AndroidNotices {
  int calls = 0;
  @override
  Future<void> show(String id, {String? scope}) async {
    calls++;
    throw PlatformException(code: 'NOTIFICATIONS_DISABLED');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridgeChannel, null);
  });
  test(
    'cold-start notification returns original backend scope and stable ID',
    () async {
      final bridge = AndroidNotices();
      final received = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridgeChannel, (call) async {
            if (call.method == 'initialAlert')
              return {
                'scope': 'http://192.168.1.2:8000|default',
                'event_id': snapshot(1)['id'],
              };
            return null;
          });
      await bridge.initialize(
        (_) => fail('Scoped notification must not enter legacy route'),
        onOpenScoped: (scope, id) {
          received.add(scope);
          received.add(id);
        },
      );
      expect(received, ['http://192.168.1.2:8000|default', snapshot(1)['id']]);
      await bridge.dispose();
    },
  );
  test('failed bridge initialization can retry without losing single-owner protection', () async {
    final bridge = AndroidNotices();
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridgeChannel, (call) async {
          if (call.method == 'initialize' && attempts++ == 0)
            throw PlatformException(code: 'SYNTHETIC_FAILURE');
          return null;
        });
    await expectLater(
      bridge.initialize((_) {}),
      throwsA(isA<PlatformException>()),
    );
    await bridge.initialize((_) {});
    expect(attempts, 2);
    await bridge.dispose();
  });
  test('permission denial preserves in-app notice without repeated system attempts', () async {
    final native = DisabledAndroid();
    final service = UnifiedNotificationService(
      gate: AlertNotificationGate(
        store: MemoryNoticeStore(),
        scope: 'http://192.168.1.2:8000|default',
      ),
      android: native,
    );
    expect(
      await service.synchronize(
        [snapshot(1)],
        historical: false,
        notificationsEnabled: true,
      ),
      hasLength(1),
    );
    expect(
      await service.synchronize(
        [snapshot(1, revision: 2)],
        historical: false,
        notificationsEnabled: true,
      ),
      isEmpty,
    );
    expect(native.calls, 1);
  });
}
