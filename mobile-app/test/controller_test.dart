import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'fakes.dart';

void main() {
  test(
    'blank security token never creates a live repository or fake data',
    () async {
      final gateway = FakePushGateway();
      final c = SafetyController(
        store: MemorySettingsStore(),
        gateway: gateway,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.refresh();
      expect(c.initialized, isTrue);
      expect(c.error, contains('统一后端'));
      expect(c.videoError, isNull);
      expect(c.events, isEmpty);
      expect(c.devices, isEmpty);
      expect(c.household.members, isEmpty);
      expect(c.household.recentObjects, isEmpty);
      expect(() => c.repository, throwsA(isA<ApiException>()));
      expect(gateway.initializations, 0);
      expect(gateway.requests, 0);
      await c.applyConnection(const AppSettings(pollSeconds: 20));
      expect(c.events, isEmpty);
      expect(() => c.repository, throwsA(isA<ApiException>()));
      expect(gateway.requests, 0);
    },
  );

  test(
    'video-only family preferences persist locally across restart',
    () async {
      final store = MemorySettingsStore();
      final c = SafetyController(store: store, videoApiFactory: emptyVideoApi);
      addTearDown(c.dispose);
      await c.initialize();
      final prefs = FamilyPreferences(
        escalationSeconds: 120,
        notificationsEnabled: false,
        contacts: const [
          FamilyContact(id: 'primary', name: '家属甲'),
          FamilyContact(id: 'backup', name: '家属乙'),
        ],
      );
      await c.saveFamilyPreferences(prefs);
      expect(c.preferences.toJson(), prefs.toJson());
      expect(store.householdData!.familyPreferences.toJson(), prefs.toJson());
      expect(() => c.repository, throwsA(isA<ApiException>()));
      final again = SafetyController(
        store: store,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(again.dispose);
      await again.initialize();
      expect(again.preferences.toJson(), prefs.toJson());
      expect(again.events, isEmpty);
      store.failHouseholdSave = true;
      await expectLater(
        again.saveFamilyPreferences(FamilyPreferences.defaults),
        throwsA(isA<ApiException>()),
      );
      expect(again.preferences.toJson(), prefs.toJson());
      expect(store.householdData!.familyPreferences.toJson(), prefs.toJson());
    },
  );

  test(
    'explicit fixture startup, one notice per new event, notification switch',
    () async {
      final store = MemorySettingsStore();
      final repo = RecordingRepository();
      final controller = SafetyController(
        store: store,
        repositoryFactory: (_) => repo,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(controller.dispose);
      final notices = <EventNotice>[];
      final subscription = controller.notices.stream.listen(notices.add);
      addTearDown(subscription.cancel);
      await controller.initialize();
      expect(controller.error, isNull);
      expect(controller.devices.length, 2);
      expect(controller.events.length, 4);
      expect(
        controller.events.where((event) => event.eventType == 'smoke_detected'),
        isEmpty,
      );
      await repo.addEvent();
      await controller.refresh();
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notices.length, 1);
      await controller.saveFamilyPreferences(
        const FamilyPreferences(
          escalationSeconds: 60,
          notificationsEnabled: false,
          contacts: [],
        ),
      );
      await repo.addEvent();
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notices.length, 1);
    },
  );

  test('foreground push and polling share one event notice', () async {
    final repo = RecordingRepository();
    final gateway = FakePushGateway();
    final store = MemorySettingsStore()
      ..settings = const AppSettings(
        baseUrl: 'https://example.invalid',
        bearerToken: 'test-user',
      );
    final c = SafetyController(
      videoApiFactory: emptyVideoApi,
      store: store,
      gateway: gateway,
      repositoryFactory: (_) => repo,
    );
    addTearDown(c.dispose);
    final notices = <EventNotice>[];
    final sub = c.notices.stream.listen(notices.add);
    addTearDown(sub.cancel);
    await c.initialize();
    final first = await repo.addEvent();
    gateway.foreground.add(first.id);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await c.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(notices.length, 1);
    final second = await repo.addEvent();
    await c.refresh();
    gateway.foreground.add(second.id);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(notices.length, 2);
  });

  test(
    'missing platform storage exposes warning and empty state, not sample data',
    () async {
      final controller = SafetyController(
        videoApiFactory: emptyVideoApi,
        store: MemorySettingsStore()..failLoad = true,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.initialized, true);
      expect(controller.storageWarning, isNotNull);
      expect(controller.error, contains('统一后端'));
      expect(controller.events, isEmpty);
      expect(controller.devices, isEmpty);
      expect(controller.household.members, isEmpty);
      expect(controller.household.nextMemberNumber, 1);
      expect(() => controller.repository, throwsA(isA<ApiException>()));
    },
  );

  test(
    'late response from the old connection cannot replace new data',
    () async {
      final old = RecordingRepository();
      final next = RecordingRepository();
      await next.resolve('fixture-fall');
      var count = 0;
      final controller = SafetyController(
        videoApiFactory: emptyVideoApi,
        store: MemorySettingsStore(),
        repositoryFactory: (_) => count++ == 0 ? old : next,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final stale = await old.events();
      old.blockedEvents = Completer<List<SafetyEvent>>();
      final pending = controller.refresh();
      await controller.applyConnection(const AppSettings(pollSeconds: 20));
      old.blockedEvents!.complete(stale);
      await pending;
      expect(
        controller.events.singleWhere((e) => e.id == 'fixture-fall').resolved,
        true,
      );
      expect(old.closeCalls, 1);
    },
  );

  test(
    'failed storage save preserves old repository and closes candidate',
    () async {
      final store = MemorySettingsStore();
      final old = RecordingRepository();
      final candidate = RecordingRepository();
      var count = 0;
      final controller = SafetyController(
        videoApiFactory: emptyVideoApi,
        store: store,
        repositoryFactory: (_) => count++ == 0 ? old : candidate,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      store.failSave = true;
      await expectLater(
        controller.applyConnection(const AppSettings(pollSeconds: 30)),
        throwsA(isA<ApiException>()),
      );
      expect(controller.repository, same(old));
      expect(controller.settings.pollSeconds, 15);
      expect(candidate.closeCalls, 1);
      expect(controller.configuring, false);
    },
  );
}
