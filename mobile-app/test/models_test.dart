import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/push_service.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'fakes.dart';

void main() {
  test(
    'legacy demo flags are ignored while real connection settings survive',
    () {
      for (final oldFlag in [true, false]) {
        final settings = AppSettings.fromJson({
          'demo_mode': oldFlag,
          'base_url': 'https://safety.invalid',
          'bearer_token': 'test-token',
          'contact_id': 'backup',
          'poll_seconds': 30,
        });
        expect(settings.baseUrl, 'https://safety.invalid');
        expect(settings.bearerToken, 'test-token');
        expect(settings.contactId, 'backup');
        expect(settings.pollSeconds, 30);
        expect(settings.validationError, isNull);
        expect(settings.toJson(), isNot(contains('demo_mode')));
        final objects = ObjectServiceConfig.fromJson({
          'demo_mode': oldFlag,
          'base_url': 'https://video.invalid',
          'token': 'test-video-token',
          'use_cloud': true,
        });
        expect(objects.baseUrl, 'https://video.invalid');
        expect(objects.token, 'test-video-token');
        expect(objects.useCloud, isTrue);
        expect(objects.toJson(), isNot(contains('demo_mode')));
      }
    },
  );

  test(
    'empty household and family preferences round-trip without synthetic members',
    () {
      final empty = HouseholdData.initial();
      expect(empty.members, isEmpty);
      expect(empty.nextMemberNumber, 1);
      expect(empty.recentObjects, isEmpty);
      final restored = HouseholdData.fromJson(empty.toJson());
      expect(restored.members, isEmpty);
      expect(restored.nextMemberNumber, 1);
      expect(
        restored.familyPreferences.toJson(),
        FamilyPreferences.defaults.toJson(),
      );
      final prefs = FamilyPreferences(
        escalationSeconds: 180,
        notificationsEnabled: false,
        contacts: FamilyPreferences.defaults.contacts,
      );
      final saved = HouseholdData.fromJson(
        empty.copyWith(familyPreferences: prefs).toJson(),
      );
      expect(saved.familyPreferences.toJson(), prefs.toJson());
      final legacyJson = empty.toJson()..remove('family_preferences');
      expect(
        HouseholdData.fromJson(legacyJson).familyPreferences.toJson(),
        FamilyPreferences.defaults.toJson(),
      );
    },
  );

  test(
    'household migration retains profiles and real objects but drops sample records',
    () {
      final old = HouseholdData(
        members: const [MemberProfile(id: 'member-1', number: 1, name: '奶奶')],
        nextMemberNumber: 4,
        eventMembers: const {'https://safety.invalid|event-1': 'member-1'},
        searches: const ['钥匙'],
        recentObjects: [
          RecentObject(
            id: 'old-sample',
            name: '示例物品',
            source: 'sample',
            recordedAt: DateTime.utc(2026),
          ),
          RecentObject(
            id: 'real-object',
            name: '钥匙',
            source: 'video',
            recordedAt: DateTime.utc(2026),
            videoId: 'v1',
            entityId: 'o1',
            serviceUrl: 'https://video.invalid',
          ),
        ],
      );
      final migrated = HouseholdData.fromJson(old.toJson());
      expect(migrated.members.single.name, '奶奶');
      expect(migrated.nextMemberNumber, 4);
      expect(migrated.eventMembers, old.eventMembers);
      expect(migrated.searches, old.searches);
      expect(
        migrated.recentObjects.single.toJson(),
        old.recentObjects.last.toJson(),
      );
    },
  );

  test(
    'default API uses unified 8000 and structured backend Review is readable',
    () {
      expect(const AppSettings().baseUrl, 'http://127.0.0.1:8000');
      expect(const AppSettings().bearerToken, isEmpty);
      expect(const AppSettings().toJson(), isNot(contains('demo_mode')));
      final event = SafetyEvent.fromJson({
        ...eventJson(),
        'review_summary': {
          'summary': '需家属核实',
          'observations': ['人物接近地面'],
          'limitations': ['画面遮挡'],
          'uncertainty': 'high',
        },
      });
      expect(event.reviewSummary, '需家属核实\n观察：人物接近地面\n局限：画面遮挡\n不确定性：high');
      expect(
        SafetyDevice.fromJson({
          'device_id': 'camera-1',
          'name': '客厅',
          'online': true,
        }).id,
        'camera-1',
      );
      expect(useFirebase, false);
    },
  );

  test('unified event fields are retained; optional values remain unknown', () {
    final event = SafetyEvent.fromJson(eventJson());
    expect(event.id, 'event-1');
    expect(event.confidence, .93);
    expect(event.occurredAt!.isUtc, true);
    expect(event.reviewSummary, '请家属核实');
    expect(event.notificationStatus, 'sent');
    expect(SafetyEvent.fromJson({'event_id': 'partial'}).confidence, isNull);
    expect(SafetyEvent.fromJson({'event_id': 'partial'}).occurredAt, isNull);
  });

  test('history filters intersect and use exclusive next-day boundary', () {
    final high = SafetyEvent.fromJson(eventJson(id: 'high'));
    final low = SafetyEvent.fromJson({
      ...eventJson(id: 'low'),
      'severity': 'info',
      'state': 'resolved',
      'occurred_at': '2026-10-27T01:00:00Z',
    });
    final unknown = SafetyEvent.fromJson({'event_id': 'unknown'});
    expect(const EventFilter().apply([low, high]).map((e) => e.id), [
      'high',
      'low',
    ]);
    expect(
      EventFilter(
        severity: 'critical',
        state: 'detected',
        query: 'DEVICE-1',
        from: DateTime.utc(2026, 10, 28),
        to: DateTime.utc(2026, 10, 29),
      ).apply([low, high, unknown]).single.id,
      'high',
    );
    expect(
      EventFilter(to: DateTime.utc(2026, 10, 28, 1)).apply([high]),
      isEmpty,
    );
  });

  test('URL validation rejects paths, userinfo, query and Bearer prefix', () {
    for (final url in [
      'ftp://host',
      'https://u:p@host',
      'https://host/api/v1',
      'https://host?token=private',
      'https://host/#fragment',
      'not-a-url',
    ]) {
      expect(
        AppSettings(baseUrl: url, bearerToken: 'token').validationError,
        isNotNull,
        reason: url,
      );
    }
    expect(
      const AppSettings(
        baseUrl: 'http://10.0.2.2:8010',
        bearerToken: 'Bearer token',
      ).validationError,
      isNotNull,
    );
    expect(
      const AppSettings(
        baseUrl: 'https://host:8010/',
        bearerToken: 'user-token',
      ).validationError,
      isNull,
    );
  });

  test('push deep links accept the event contract and reject foreign URLs', () {
    expect(eventIdFromData({'event_id': 'event-1'}), 'event-1');
    expect(
      eventIdFromData({'deep_link': 'elder-safety://events/event-2'}),
      'event-2',
    );
    expect(eventIdFromData({'deep_link': '/events/a%2Fb'}), 'a/b');
    expect(
      eventIdFromData({'deep_link': 'https://evil.invalid/events/event-3'}),
      isNull,
    );
    expect(
      eventIdFromData({'deep_link': '/events/event-3?token=private'}),
      isNull,
    );
    expect(eventIdFromData({'event_id': 'bad\nvalue'}), isNull);
    expect(eventIdFromData({'event_id': 42}), isNull);
  });
}
