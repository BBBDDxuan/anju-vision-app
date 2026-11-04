import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/object_api.dart';
import 'fakes.dart';

const contractUrl = String.fromEnvironment('SAFETY_CONTRACT_URL');
const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

class VideoFixture {
  bool failing = false,
      alertsFailing = false,
      acknowledged = false,
      acceptAck = true;
  final actions = <String>['fall', 'help_gesture', 'flame', 'smoke', 'sparks'];
  String frameHost = '';
  final requests = <String>[];
  Map<String, dynamic> payload() => {
    'alerts': [
      for (var i = 0; i < actions.length; i++)
        {
          'id': 'a$i',
          'video_id': 'v1',
          'subject_id': 'p1',
          'action': actions[i],
          'severity': 'urgent',
          'title': '接口验收告警',
          'start_ms': i * 1000,
          'end_ms': i * 1000 + 1000,
          'is_mock': false,
          'epistemic_type': 'observed',
          'acknowledged': i == 0 && acknowledged,
          'evidence_ids': ['e$i'],
        },
      {'id': 'fixture', 'action': 'fall', 'is_mock': true},
    ],
    'evidence': [
      for (var i = 0; i < actions.length; i++)
        {
          'id': 'e$i',
          'frame_ids': ['f$i'],
        },
    ],
    // Reverse order to catch incorrect global-first-frame selection.
    'frames': [
      for (var i = actions.length - 1; i >= 0; i--)
        {'id': 'f$i', 'url': '$frameHost/media/frames/v1/f$i'},
    ],
  };
  ObjectApi api(ObjectServiceConfig config) => ObjectApi(
    config,
    client: MockClient((r) async {
      requests.add('${r.method} ${r.url.path}');
      if (failing) return http.Response('{}', 503, headers: jsonHeaders);
      if (r.url.path == '/api/videos')
        return http.Response(
          jsonEncode({
            'videos': [
              {'id': 'v1', 'name': '接口验收.mp4', 'duration_ms': 87000},
            ],
          }),
          200,
          headers: jsonHeaders,
        );
      if (r.url.path == '/api/videos/v1/alerts') {
        if (alertsFailing)
          return http.Response('{}', 503, headers: jsonHeaders);
        return http.Response(jsonEncode(payload()), 200, headers: jsonHeaders);
      }
      if (r.url.path.endsWith('/acknowledge')) {
        if (acceptAck) acknowledged = true;
        return http.Response(
          jsonEncode({'acknowledged': true}),
          200,
          headers: jsonHeaders,
        );
      }
      if (r.url.path.startsWith('/media/frames/'))
        return http.Response.bytes(
          [255, 216, 255],
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      return http.Response('{}', 404, headers: jsonHeaders);
    }),
  );
}

SafetyRepository live({bool failing = false, Completer<void>? block}) =>
    HttpSafetyRepository(
      baseUrl: 'http://127.0.0.1:8010',
      bearerToken: 'test-only',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/events') && block != null) await block.future;
        if (failing) return http.Response('{}', 503, headers: jsonHeaders);
        if (r.url.path.endsWith('/preferences'))
          return http.Response(
            jsonEncode(FamilyPreferences.defaults.toJson()),
            200,
            headers: jsonHeaders,
          );
        return http.Response('[]', 200, headers: jsonHeaders);
      }),
    );

void main() {
  test(
    'original backend safety API, evidence frame and acknowledgement roundtrip',
    () async {
      final api = ObjectApi(const ObjectServiceConfig(baseUrl: contractUrl));
      addTearDown(api.close);
      final events = await api.safetyEvents();
      expect(events.length, 1);
      final event = events.single;
      expect(event.fromVideo, isTrue);
      expect(event.eventType, 'suspected_fall');
      expect((await api.frame(event.evidenceId!)).take(2), [255, 216]);
      await api.acknowledgeSafety(event);
      expect((await api.safetyEvents()).single.acknowledged, isTrue);
    },
    skip: contractUrl.isEmpty
        ? 'Requires isolated original backend fixture'
        : false,
  );

  test(
    'video mapping excludes smoke/sparks/mock and links each alert to its own evidence',
    () async {
      final fixture = VideoFixture();
      final api = fixture.api(const ObjectServiceConfig());
      addTearDown(api.close);
      final events = await api.safetyEvents();
      expect(events.map((e) => e.eventType), [
        'suspected_fall',
        'help_requested',
        'fire_detected',
      ]);
      expect(events.map((e) => e.evidenceId), [
        '/media/frames/v1/f0',
        '/media/frames/v1/f1',
        '/media/frames/v1/f2',
      ]);
      expect(
        events.every((e) => e.fromVideo && e.severity == 'critical'),
        isTrue,
      );
      expect(events.every((e) => e.occurredAt == null), isTrue);
      final again = await api.safetyEvents();
      expect(again.map((e) => e.id), events.map((e) => e.id));
      expect(await api.frame(events[1].evidenceId!), [255, 216, 255]);
      expect(fixture.requests.every((r) => !r.contains('/query')), isTrue);
    },
  );
  test('evidence cannot send service tokens to another origin', () async {
    final fixture = VideoFixture()..frameHost = 'https://elsewhere.invalid';
    final api = fixture.api(const ObjectServiceConfig(token: 'test-only'));
    addTearDown(api.close);
    await expectLater(
      api.safetyEventsFor(const Recording(id: 'v1', name: 'test')),
      throwsA(isA<ApiException>()),
    );
    expect(fixture.requests.any((r) => r.contains('/media/frames/')), isFalse);
  });
  test(
    'live failure does not hide video alerts or their acknowledgement/evidence',
    () async {
      final fixture = VideoFixture();
      final c = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => live(failing: true),
        videoApiFactory: fixture.api,
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.error, isNotNull);
      expect(c.videoError, isNull);
      expect(c.events.length, 3);
      expect(await c.evidenceFor(c.events.first), [255, 216, 255]);
      await c.acknowledgeEvent('video:v1:a0');
      expect((await c.loadEvent('video:v1:a0')).acknowledged, isTrue);
      await expectLater(
        c.resolveEvent('video:v1:a0'),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'legacy compatibility: video notices do not flood on history or reconnect',
    () async {
      final fixture = VideoFixture();
      final c = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => live(),
        videoApiFactory: fixture.api,
      );
      final notices = <EventNotice>[];
      final sub = c.notices.stream.listen(notices.add);
      addTearDown(() async {
        await sub.cancel();
        c.dispose();
      });
      await c.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(notices, isEmpty);
      fixture.actions.add('help_gesture');
      await c.refresh();
      await c.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(notices.map((n) => n.eventId), ['video:v1:a5']);
      fixture.failing = true;
      await c.refresh();
      expect(c.videoError, isNotNull);
      expect(c.events.length, 4);
      fixture.failing = false;
      await c.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(c.videoError, isNull);
      expect(notices.length, 1);
    },
  );
  test(
    'unconfigured unified app persists local preferences without fabricated alerts',
    () async {
      final fixture = VideoFixture();
      final store = MemorySettingsStore();
      final c = SafetyController(store: store, videoApiFactory: fixture.api);
      await c.initialize();
      expect(c.devices, isEmpty);
      expect(c.error, contains('统一后端'));
      expect(fixture.requests, isEmpty);
      await c.saveFamilyPreferences(
        const FamilyPreferences(
          escalationSeconds: 60,
          notificationsEnabled: false,
          contacts: [FamilyContact(id: 'primary', name: '家属')],
        ),
      );
      expect(c.preferences.notificationsEnabled, isFalse);
      c.dispose();
      final again = SafetyController(
        store: store,
        videoApiFactory: fixture.api,
      );
      addTearDown(again.dispose);
      await again.initialize();
      expect(again.preferences.notificationsEnabled, isFalse);
      expect(again.preferences.contacts.single.name, '家属');
    },
  );
  test(
    'acknowledgement needs authoritative readback, not only successful POST',
    () async {
      final fixture = VideoFixture()..acceptAck = false;
      final c = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => live(),
        videoApiFactory: fixture.api,
      );
      addTearDown(c.dispose);
      await c.initialize();
      await expectLater(
        c.acknowledgeEvent('video:v1:a0'),
        throwsA(isA<ApiException>()),
      );
      expect((await c.loadEvent('video:v1:a0')).acknowledged, isFalse);
    },
  );
  test(
    'ack readback survives a later failed video refresh without reverting cache',
    () async {
      final fixture = VideoFixture();
      final c = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => live(),
        videoApiFactory: fixture.api,
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.events.length, 3);
      expect(c.events.every((event) => !event.acknowledged), isTrue);
      await c.acknowledgeEvent('video:v1:a0');
      expect(
        c.events.firstWhere((event) => event.id == 'video:v1:a0').acknowledged,
        isTrue,
      );
      expect(fixture.requests.where((request) => request.startsWith('POST ')), [
        'POST /api/videos/v1/alerts/a0/acknowledge',
      ]);
      expect(fixture.requests.last, 'GET /api/videos/v1/alerts');
      fixture.alertsFailing = true;
      await c.refresh();
      expect(c.videoError, isNotNull);
      expect(c.events.length, 3);
      expect(
        c.events.firstWhere((event) => event.id == 'video:v1:a0').acknowledged,
        isTrue,
      );
      expect(
        c.events
            .where((event) => event.id != 'video:v1:a0')
            .every((event) => !event.acknowledged),
        isTrue,
      );
    },
  );
  test('video events publish before a slow live source completes', () async {
    final fixture = VideoFixture();
    final block = Completer<void>();
    final c = SafetyController(
      store: MemorySettingsStore(),
      repositoryFactory: (_) => live(block: block),
      videoApiFactory: fixture.api,
    );
    final videoPublished = Completer<void>();
    c.addListener(() {
      if (c.events.isNotEmpty && !videoPublished.isCompleted) {
        videoPublished.complete();
      }
    });
    final initialized = c.initialize();
    try {
      // Wait for publication itself, without depending on machine scheduling.
      await videoPublished.future.timeout(const Duration(seconds: 5));
      expect(c.events.length, 3);
      expect(c.loading, isTrue);
      block.complete();
      await initialized;
      expect(c.loading, isFalse);
    } finally {
      if (!block.isCompleted) block.complete();
      await initialized;
      c.dispose();
    }
  });
  test(
    'one failed video retains cached alerts without hiding successful videos',
    () async {
      var failure = false;
      final fixture = VideoFixture();
      final api = ObjectApi(
        const ObjectServiceConfig(),
        client: MockClient((r) async {
          if (r.url.path == '/api/videos')
            return http.Response(
              jsonEncode({
                'videos': [
                  {'id': 'v1', 'name': 'good'},
                  {'id': 'v2', 'name': 'temporary failure'},
                ],
              }),
              200,
              headers: jsonHeaders,
            );
          if (r.url.path == '/api/videos/v2/alerts' && failure)
            return http.Response('{}', 503, headers: jsonHeaders);
          return http.Response(
            jsonEncode(fixture.payload()),
            200,
            headers: jsonHeaders,
          );
        }),
      );
      addTearDown(api.close);
      expect((await api.safetyEvents()).length, 6);
      failure = true;
      expect((await api.safetyEvents()).length, 6);
      expect(api.safetyWarnings.length, 1);
    },
  );
}
