import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'package:elder_safety_mobile/services/push_service.dart';

class Store implements SettingsStore {
  Map<String, dynamic>? registration;
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
  @override
  Future<Map<String, dynamic>?> loadPushRegistration() async =>
      registration == null ? null : Map<String, dynamic>.from(registration!);
  @override
  Future<void> savePushRegistration(Map<String, dynamic>? value) async {
    registration = value == null ? null : Map<String, dynamic>.from(value);
  }
}

class Repository extends Fake implements SafetyRepository {
  final registrations = <String, String>{};
  final deleted = <String>[];
  bool failRegister = false, failDelete = false;
  int sequence = 0;
  @override
  Future<String> registerPush(
    String token,
    String platform,
    String contactId,
  ) async {
    if (failRegister) throw const ApiException('synthetic failure');
    return registrations.putIfAbsent(token, () => 'own-${++sequence}');
  }

  @override
  Future<void> deletePush(String id) async {
    if (failDelete) throw const ApiException('synthetic failure');
    if (!registrations.containsValue(id))
      throw const ApiException('not found', statusCode: 404);
    registrations.removeWhere((_, value) => value == id);
    deleted.add(id);
  }
}

class Gateway implements PushGateway {
  final tokens = StreamController<String>.broadcast();
  final opens = StreamController<String>.broadcast();
  final foreground = StreamController<String>.broadcast();
  String token = 'synthetic-new';
  bool permissionGranted = true;
  @override
  String get platform => 'android';
  @override
  Stream<String> get tokenRefreshes => tokens.stream;
  @override
  Stream<String> get openedEvents => opens.stream;
  @override
  Stream<String> get foregroundEvents => foreground.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> requestToken() async => permissionGranted ? token : null;
  @override
  Future<void> setEnabled(bool value) async {}
  @override
  Future<void> dispose() async {
    await tokens.close();
    await opens.close();
    await foreground.close();
  }
}

void main() {
  test(
    'rotation preserves old token on failure and deletes only own registration',
    () async {
      final store = Store(), repository = Repository(), gateway = Gateway();
      final coordinator = PushCoordinator(
        store: store,
        gateway: gateway,
        onOpen: (_) {},
        onForeground: (_) {},
        onStatus: (_) {},
      );
      const settings = AppSettings(
        baseUrl: 'http://192.168.1.2:8000',
        bearerToken: 'synthetic-test-token',
      );
      repository.registrations['other-phone'] = 'other-id';
      await coordinator.configure(repository, settings, true);
      final old = store.registration!['token_id'];
      gateway.token = 'synthetic-rotated';
      repository.failRegister = true;
      await expectLater(
        coordinator.configure(repository, settings, true),
        throwsA(isA<ApiException>()),
      );
      expect(repository.registrations.values, contains(old));
      repository.failRegister = false;
      await coordinator.configure(repository, settings, true);
      expect(repository.deleted, contains(old));
      expect(repository.registrations['other-phone'], 'other-id');
      await coordinator.unregister();
      expect(repository.registrations, {'other-phone': 'other-id'});
      expect(store.registration, isNull);
      await coordinator.dispose();
    },
  );
  test(
    'interrupted stale-token cleanup retries on same-token configure',
    () async {
      final store = Store(), repository = Repository(), gateway = Gateway();
      final coordinator = PushCoordinator(
        store: store,
        gateway: gateway,
        onOpen: (_) {},
        onForeground: (_) {},
        onStatus: (_) {},
      );
      const settings = AppSettings(
        baseUrl: 'http://192.168.1.2:8000',
        bearerToken: 'synthetic-test-token',
      );
      await coordinator.configure(repository, settings, true);
      gateway.token = 'synthetic-rotated';
      repository.failDelete = true;
      await expectLater(
        coordinator.configure(repository, settings, true),
        throwsA(isA<ApiException>()),
      );
      expect(store.registration!['stale_token_ids'], isNotEmpty);
      repository.failDelete = false;
      await coordinator.configure(repository, settings, true);
      expect(store.registration!['stale_token_ids'], isEmpty);
      expect(repository.registrations.length, 1);
      await coordinator.dispose();
    },
  );
  test(
    'unified FCM payload resolves stable alert ID rather than source event',
    () {
      final id = 'a_${'1' * 40}';
      expect(
        eventIdFromData({
          'anju_type': 'unified_alert',
          'alert_id': id,
          'event_id': 'raw-source',
        }),
        id,
      );
      expect(
        eventIdFromData({
          'anju_type': 'unified_alert',
          'alert_id': 'raw-source',
        }),
        isNull,
      );
    },
  );
  test(
    'permission denial removes only own registration and never reports success',
    () async {
      final store = Store(), repository = Repository(), gateway = Gateway();
      final statuses = <String>[];
      final coordinator = PushCoordinator(
        store: store,
        gateway: gateway,
        onOpen: (_) {},
        onForeground: (_) {},
        onStatus: statuses.add,
      );
      const settings = AppSettings(
        baseUrl: 'http://192.168.1.2:8000',
        bearerToken: 'synthetic-test-token',
      );
      repository.registrations['other-phone'] = 'other-id';
      await coordinator.configure(repository, settings, true);
      gateway.permissionGranted = false;
      await coordinator.configure(repository, settings, true);
      expect(repository.registrations, {'other-phone': 'other-id'});
      expect(store.registration, isNull);
      expect(statuses.last, contains('未登记'));
      await coordinator.dispose();
    },
  );
  test(
    'unchanged token is restored after server registration table reset',
    () async {
      final store = Store(), repository = Repository(), gateway = Gateway();
      final coordinator = PushCoordinator(
        store: store,
        gateway: gateway,
        onOpen: (_) {},
        onForeground: (_) {},
        onStatus: (_) {},
      );
      const settings = AppSettings(
        baseUrl: 'http://192.168.1.2:8000',
        bearerToken: 'synthetic-test-token',
      );
      await coordinator.configure(repository, settings, true);
      repository.registrations.clear();
      await coordinator.configure(repository, settings, true);
      expect(
        repository.registrations[gateway.token],
        store.registration!['token_id'],
      );
      expect(store.registration!['stale_token_ids'], isEmpty);
      await coordinator.dispose();
    },
  );
}
