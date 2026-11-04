import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'fakes.dart';

void main() {
  test(
    'profiles, ambiguous bindings, manual association and persistence',
    () async {
      final store = MemorySettingsStore();
      final c = SafetyController(
        store: store,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await c.initialize();
      await addFixtureMembers(c);
      final event = c.events.firstWhere(isPersonEvent);
      expect(c.household.members.map((m) => m.displayName), [
        '成员1',
        '成员2',
        '成员3',
      ]);
      final binding = MemberBinding(
        deviceId: event.deviceId,
        scope: c.serviceScope,
      );
      await c.saveMember(
        c.household.members[0].copyWith(name: '奶奶', bindings: [binding]),
      );
      expect(c.memberIdFor(event), 'member-1');
      await c.saveMember(c.household.members[1].copyWith(bindings: [binding]));
      expect(c.memberIdFor(event), isNull);
      await c.associateMember(event, 'member-2');
      expect(
        c.recordsForMember('member-2').map((e) => e.id),
        contains(event.id),
      );
      c.dispose();
      final again = SafetyController(
        store: store,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await again.initialize();
      expect(again.household.members.first.displayName, '奶奶');
      expect(again.memberIdFor(event), 'member-2');
      await again.associateMember(event, null);
      expect(again.memberIdFor(event), isNull);
      await again.deleteMember('member-3');
      await again.addMember();
      expect(again.household.members.last.displayName, '成员4');
      again.dispose();
    },
  );
  test('track collisions and storage errors do not change profiles', () async {
    final store = MemorySettingsStore();
    final c = SafetyController(
      store: store,
      repositoryFactory: (_) => RecordingRepository(),
      videoApiFactory: emptyVideoApi,
    );
    await c.initialize();
    await addFixtureMembers(c);
    const b = MemberBinding(
      deviceId: 'device-1',
      scope: 'https://fixture.invalid',
      trackId: '7',
    );
    await c.saveMember(c.household.members[0].copyWith(bindings: [b]));
    await expectLater(
      c.saveMember(c.household.members[1].copyWith(bindings: [b])),
      throwsA(isA<ApiException>()),
    );
    store.failHouseholdSave = true;
    await expectLater(
      c.saveMember(c.household.members[0].copyWith(name: '未保存')),
      throwsA(isA<ApiException>()),
    );
    expect(c.household.members.first.displayName, '成员1');
    c.dispose();
  });
  test(
    'local observations resolve locally and never appear as risks',
    () async {
      final store = MemorySettingsStore();
      final c = SafetyController(
        store: store,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await c.initialize();
      await addFixtureMembers(c);
      final e = SafetyEvent.fromJson({
        ...eventJson(id: 'local-test'),
        'device_id': 'phone-local',
        'event_type': 'pose_observation',
      });
      await c.addLocalEvent(e, memberId: 'member-1');
      expect(
        c.recordsForMember('member-1').map((e) => e.id),
        contains('local-test'),
      );
      expect(c.events.where(isRiskEvent).map((event) => event.id), [
        'fixture-fire',
      ]);
      await c.resolveEvent(e.id);
      expect((await c.loadEvent(e.id)).resolved, isTrue);
      c.dispose();
      final again = SafetyController(
        store: store,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await again.initialize();
      expect((await again.loadEvent(e.id)).resolved, isTrue);
      again.dispose();
    },
  );
}
