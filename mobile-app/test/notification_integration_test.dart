import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/unified_alert.dart';
import 'package:elder_safety_mobile/services/android_notices.dart';
import 'package:elder_safety_mobile/services/app_notification_binding.dart';
import 'package:elder_safety_mobile/services/notifications/alert_gate.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'fakes.dart';
import 'unified_alert_test.dart' show ContractRepository, alert;

const origin = 'http://10.0.2.2:8000';
const scope = '$origin|default';
final id1 = 'a_${'1' * 40}', id2 = 'a_${'2' * 40}';

class NoticeStore implements NoticeStateStore {
  final values = <String, String>{};
  Completer<void>? blockedWrite;
  @override
  Future<String?> read(String scope) async => values[scope];
  @override
  Future<void> write(String scope, String value) async {
    await blockedWrite?.future;
    values[scope] = value;
  }
}

class NativePresenter extends AndroidNotices {
  final shown = <String>[];
  @override
  Future<void> show(String id, {String? scope}) async =>
      shown.add('$scope|$id');
}

AlertSyncSnapshot snapshot(
  List<Map<String, dynamic>> records, {
  bool initial = false,
  String backend = origin,
}) => AlertSyncSnapshot(
  backend: backend,
  household: 'default',
  cursor: 2,
  initial: initial,
  events: records.map(unifiedAlertFromJson).toList(),
  changed: const [],
  active: true,
  notificationsEnabled: true,
);

void main() {
  test(
    'family account shows a notification only when a new candidate is confirmed',
    () async {
      final store = NoticeStore(), native = NativePresenter();
      final binding = AppNotificationBinding(
        android: native,
        currentScope: () => scope,
        canPresent: (_) => true,
        accountId: 'family-member',
        store: store,
      );
      addTearDown(binding.dispose);
      await binding.accept(snapshot([alert(id1, 1)], initial: true));
      final pending = {...alert(id2, 1), 'review_status': 'pending'};
      expect(await binding.accept(snapshot([pending])), isEmpty);
      expect(native.shown, isEmpty);

      final confirmed = snapshot([alert(id2, 2)]);
      expect((await binding.accept(confirmed)).single.id, id2);
      expect(native.shown, ['$scope|$id2']);
      expect(await binding.accept(confirmed), isEmpty);
      expect(native.shown, ['$scope|$id2']);
    },
  );

  test(
    'B full snapshots reach C: history silent, new alert once across restart',
    () async {
      final store = NoticeStore(), native = NativePresenter();
      AppNotificationBinding binding() => AppNotificationBinding(
        android: native,
        currentScope: () => scope,
        canPresent: (_) => true,
        store: store,
      );
      final first = binding();
      expect(
        await first.accept(snapshot([alert(id1, 1)], initial: true)),
        isEmpty,
      );
      final all = snapshot([
        alert(id1, 1),
        alert(id2, 2, source: 'uploaded_recording'),
      ]);
      expect((await first.accept(all)).single.id, id2);
      expect(await first.accept(all), isEmpty);
      first.dispose();
      expect(await binding().accept(all), isEmpty);
      expect(native.shown, ['$scope|$id2']);
    },
  );

  test(
    'backend switch during durable write cannot display old scoped alert',
    () async {
      final store = NoticeStore(), native = NativePresenter();
      var current = scope;
      final binding = AppNotificationBinding(
        android: native,
        store: store,
        currentScope: () => current,
        canPresent: (_) => true,
      );
      store.blockedWrite = Completer<void>();
      final pending = binding.accept(snapshot([alert(id1, 1)]));
      await Future<void>.delayed(Duration.zero);
      current = 'http://192.168.1.8:8000|default';
      store.blockedWrite!.complete();
      expect(await pending, isEmpty);
      expect(native.shown, isEmpty);
      expect(await binding.accept(snapshot([alert(id2, 2)])), isEmpty);
    },
  );

  test(
    'switching notifications off during dedup write suppresses display',
    () async {
      final store = NoticeStore(), native = NativePresenter();
      var enabled = true;
      final binding = AppNotificationBinding(
        android: native,
        store: store,
        currentScope: () => scope,
        canPresent: (_) => enabled,
      );
      store.blockedWrite = Completer<void>();
      final pending = binding.accept(snapshot([alert(id1, 1)]));
      await Future<void>.delayed(Duration.zero);
      enabled = false;
      store.blockedWrite!.complete();
      expect(await pending, isEmpty);
      expect(native.shown, isEmpty);
    },
  );

  test(
    'unified controller registers C push and aborts switch on failed detach',
    () async {
      final store = MemorySettingsStore()
        ..settings = const AppSettings(
          baseUrl: origin,
          bearerToken: 'synthetic',
        );
      final repo = ContractRepository();
      final gateway = FakePushGateway();
      final c = SafetyController(
        store: store,
        gateway: gateway,
        repositoryFactory: (_) => repo,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(gateway.requests, 1);
      expect(store.registration?['base_url'], origin);
      repo.failDelete = true;
      await expectLater(
        c.applyConnection(
          const AppSettings(
            baseUrl: 'http://192.168.1.8:8000',
            bearerToken: 'other',
          ),
        ),
        throwsException,
      );
      expect(c.settings.baseUrl, origin);
      expect(store.settings.baseUrl, origin);
      expect(store.registration, isNotNull);
      repo.failDelete = false;
      await c.applyConnection(
        const AppSettings(baseUrl: origin, bearerToken: 'new'),
      );
      expect(repo.calls.any((call) => call.startsWith('delete:')), isTrue);
      expect(store.registration?['base_url'], origin);
    },
  );

  test(
    'cold scoped native click resolves actual uploaded source after initialization',
    () async {
      final repo = ContractRepository()
        ..records = [alert(id1, 1, source: 'uploaded_recording')]
        ..revision = 1;
      final c = SafetyController(
        store: MemorySettingsStore()
          ..settings = const AppSettings(
            baseUrl: origin,
            bearerToken: 'synthetic',
          ),
        repositoryFactory: (_) => repo,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(c.dispose);
      await c.openScopedAlert(scope, id1);
      expect(c.takePendingAlertOpens(), isEmpty);
      await c.initialize();
      await Future<void>.delayed(Duration.zero);
      final location = c.takePendingAlertOpens().single;
      expect(location.alertId, id1);
      expect(location.source, 'uploaded_recording');
      expect(location.scope, scope);
      await c.openScopedAlert('http://192.168.1.9:8000|default', id1);
      expect(c.takePendingAlertOpens(), isEmpty);
    },
  );

  test(
    'FCM click uses unified global detail rather than legacy event routing',
    () async {
      final repo = ContractRepository()
        ..records = [alert(id2, 1)]
        ..revision = 1;
      final gateway = FakePushGateway()..initialEvent = id2;
      final c = SafetyController(
        store: MemorySettingsStore()
          ..settings = const AppSettings(
            baseUrl: origin,
            bearerToken: 'synthetic',
          ),
        gateway: gateway,
        repositoryFactory: (_) => repo,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(c.dispose);
      final legacy = <String>[];
      final sub = c.openEvents.stream.listen(legacy.add);
      addTearDown(sub.cancel);
      await c.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(c.takePendingAlertOpens().single.alertId, id2);
      expect(legacy, isEmpty);
    },
  );
}
