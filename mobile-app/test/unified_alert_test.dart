import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/models/unified_alert.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'package:elder_safety_mobile/services/object_api.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'fakes.dart';

Map<String, dynamic> alert(
  String id,
  int revision, {
  String source = 'live_camera',
  String handling = 'unacknowledged',
  String review = 'confirmed',
}) => {
  'id': id,
  'revision': revision,
  'source': source,
  'source_event_id': 'raw-$id',
  'camera_id': source == 'live_camera' ? 'camera-1' : null,
  'video_id': source == 'uploaded_recording' ? 'video-1' : null,
  'event_type': 'suspected_fall',
  'severity': 'critical',
  'review_status': review,
  'review_reason': 'CONTRACT FIXTURE ONLY',
  'handling_status': handling,
  'occurred_at': source == 'live_camera' ? '2026-11-04T03:00:00Z' : null,
  'created_at': '2026-11-04T04:00:00Z',
  'video_offset_ms': source == 'uploaded_recording' ? 1200 : null,
  'evidence': [
    {'url': '/api/alerts/$id/evidence/0', 'media_type': 'image/jpeg'},
  ],
  'playback_url': source == 'uploaded_recording'
      ? '/media/videos/video-1'
      : null,
};
Map<String, dynamic> page(
  List<Map<String, dynamic>> events,
  int cursor, {
  int offset = 0,
  bool more = false,
}) => {
  'alerts': events,
  'total': events.length,
  'offset': offset,
  'has_more': more,
  'snapshot_cursor': cursor,
};
Map<String, dynamic> changes(
  List<Map<String, dynamic>> events,
  int cursor, {
  bool more = false,
  int? server,
}) => {
  'alerts': events,
  'next_cursor': cursor,
  'server_cursor': server ?? cursor,
  'has_more': more,
};

class ContractRepository extends RecordingRepository
    implements UnifiedAlertRepository {
  @override
  String backendUrl = 'http://10.0.2.2:8000';
  List<Map<String, dynamic>> records = [];
  int revision = 0;
  Future<Map<String, dynamic>> Function(int)? onPage, onChanges;
  int? failAtOffset;
  int pages = 0, deltas = 0;
  @override
  Future<Map<String, dynamic>> connection() async => {
    'contract_version': '2026-11-04.v1',
    'household': 'default',
  };
  @override
  Future<Map<String, dynamic>> alertPage({
    int offset = 0,
    int limit = 100,
  }) async {
    pages++;
    if (failAtOffset == offset) throw const ApiException('offline');
    return onPage?.call(offset) ?? page(records, revision, offset: offset);
  }

  @override
  Future<Map<String, dynamic>> alertChanges(
    int after, {
    int limit = 100,
  }) async {
    deltas++;
    return onChanges?.call(after) ??
        changes(
          records.where((e) => (e['revision'] as int) > after).toList(),
          revision,
        );
  }

  @override
  Future<SafetyEvent> event(String id) async =>
      unifiedAlertFromJson(records.singleWhere((e) => e['id'] == id));
  @override
  Future<SafetyEvent> handleAlert(String id, {required bool resolve}) async {
    final previous = records.singleWhere((e) => e['id'] == id);
    final updated = {
      ...previous,
      'revision': ++revision,
      'handling_status': resolve || previous['handling_status'] == 'resolved'
          ? 'resolved'
          : 'acknowledged',
    };
    records = records.map((e) => e['id'] == id ? updated : e).toList();
    return unifiedAlertFromJson(updated);
  }

  @override
  Uri mediaUri(String path) => Uri.parse('$backendUrl$path');
  @override
  Future<Uint8List> mediaImage(String path) async => Uint8List.fromList([1]);
}

class SyncStore extends MemorySettingsStore implements AlertSyncStore {
  Map<String, Map<String, dynamic>> caches = {};
  @override
  Future<Map<String, dynamic>?> loadAlertSync(String scope) async =>
      caches[scope];
  @override
  Future<void> saveAlertSync(
    String scope,
    Map<String, dynamic> snapshot,
  ) async {
    caches[scope] = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  test(
    'ack during initial baseline cannot be replaced by a stale initial page',
    () async {
      final repo = ContractRepository()
        ..records = [alert('a_x', 1)]
        ..revision = 1;
      final blocked = Completer<Map<String, dynamic>>();
      repo.onChanges = (_) => blocked.future;
      final sync = UnifiedAlertSynchronizer(repo);
      final initial = sync.synchronize();
      await Future<void>.delayed(Duration.zero);
      await sync.accept(
        unifiedAlertFromJson(alert('a_x', 3, handling: 'resolved')),
      );
      blocked.complete(changes([], 1));
      await initial;
      expect(sync.events.single.resolved, isTrue);
      expect(sync.events.single.revision, 3);
      repo.close();
    },
  );
  test(
    'old two-origin settings migrate without reusing the internal user token',
    () async {
      final store = MemorySettingsStore()
        ..settings = AppSettings.fromJson({
          'base_url': 'http://192.168.1.8:8010',
          'bearer_token': 'old-private-user-token',
        })
        ..householdData = HouseholdData.initial().copyWith(
          members: [
            const MemberProfile(id: 'member-1', number: 1, name: 'Preserved'),
          ],
        );
      final c = SafetyController(store: store, videoApiFactory: emptyVideoApi);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.settings.baseUrl, 'http://192.168.1.8:8000');
      expect(c.settings.bearerToken, isEmpty);
      expect(c.household.objects.baseUrl, c.settings.baseUrl);
      expect(store.settings.connectionVersion, 2);
      expect(c.household.members.single.name, 'Preserved');
      expect(c.storageWarning, contains('迁移'));
    },
  );
  test(
    'transcode errors are distinct from host allowlist failures and never echo bodies',
    () async {
      final api = ObjectApi(
        const ObjectServiceConfig(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'TRANSCODE_FAILED',
                'message': 'private-server-detail',
              },
            }),
            400,
          ),
        ),
      );
      addTearDown(api.close);
      try {
        await api.getJson('/api/health');
        fail('Expected failure');
      } on ApiException catch (e) {
        expect(e.code, 'TRANSCODE_FAILED');
        expect(e.message, contains('转码'));
        expect(e.message, isNot(contains('private-server-detail')));
      }
    },
  );
  test(
    'late response from old backend cannot replace the new backend snapshot',
    () async {
      final old = ContractRepository()
        ..records = [alert('a_old', 1)]
        ..revision = 1;
      final next = ContractRepository()
        ..backendUrl = 'http://10.0.2.2:8001'
        ..records = [alert('a_new', 1)]
        ..revision = 1;
      final store = SyncStore()
        ..settings = const AppSettings(
          baseUrl: 'http://10.0.2.2:8000',
          bearerToken: 'fixture',
        );
      final c = SafetyController(
        store: store,
        repositoryFactory: (s) => s.baseUrl.endsWith('8001') ? next : old,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(c.dispose);
      await c.initialize();
      final blocked = Completer<Map<String, dynamic>>();
      old.onChanges = (_) => blocked.future;
      final inFlight = c.refresh();
      await Future<void>.delayed(Duration.zero);
      await c.applyConnection(
        const AppSettings(
          baseUrl: 'http://10.0.2.2:8001',
          bearerToken: 'fixture',
        ),
      );
      blocked.complete(changes([alert('a_old', 2)], 2));
      await inFlight;
      expect(c.events.single.id, 'a_new');
      expect(c.alertScope, 'http://10.0.2.2:8001|default');
    },
  );
  test(
    'uploaded wall-clock remains unknown and handling/review are separate',
    () {
      final e = unifiedAlertFromJson(
        alert('a_video', 4, source: 'uploaded_recording', handling: 'resolved'),
      );
      expect(e.occurredAt, isNull);
      expect(e.createdAt, isNotNull);
      expect(e.details['start_ms'], 1200);
      expect(e.fromVideo, isTrue);
      expect(e.resolved, isTrue);
      expect(e.acknowledged, isTrue);
      expect(e.reviewStatus, 'confirmed');
      expect(SafetyEvent.fromJson(e.toJson()).revision, 4);
    },
  );
  test('notification locator is scoped, serializable and credential-free', () {
    final loc = AlertLocation.tryParse({
      'backend': 'http://10.0.2.2:8000/',
      'household': 'default',
      'alert_id': 'a_x',
      'source': 'live_camera',
    });
    expect(loc!.scope, 'http://10.0.2.2:8000|default');
    expect(
      AlertLocation.tryParse({
        ...loc.toJson(),
        'backend': 'http://user:password@host',
      }),
      isNull,
    );
    expect(
      AlertLocation.tryParse({...loc.toJson(), 'source': 'unknown'}),
      isNull,
    );
    expect(jsonEncode(loc.toJson()).contains('token'), isFalse);
  });
  test(
    'baseline uses first page cursor and catches concurrent changes without notifying history',
    () async {
      final repo = ContractRepository();
      final offsets = <int>[];
      final cursors = <int>[];
      repo.onPage = (offset) async {
        offsets.add(offset);
        return offset == 0
            ? page([alert('a_live', 1)], 1, more: true)
            : page(
                [alert('a_video', 2, source: 'uploaded_recording')],
                9,
                offset: offset,
              );
      };
      repo.onChanges = (after) async {
        cursors.add(after);
        return changes([alert('a_live', 3, handling: 'resolved')], 3);
      };
      final saved = <Map<String, dynamic>>[];
      final sync = UnifiedAlertSynchronizer(
        repo,
        persist: (value) async => saved.add(value),
      );
      final result = await sync.synchronize();
      expect(offsets, [0, 1]);
      expect(cursors, [1]);
      expect(result.initial, isTrue);
      expect(result.cursor, 3);
      expect(
        result.events.singleWhere((e) => e.id == 'a_live').resolved,
        isTrue,
      );
      expect(saved.single['cursor'], 3);
      expect(saved.single['events'], hasLength(2));
      repo.close();
    },
  );
  test('failed partial initial page publishes no cache or cursor', () async {
    final repo = ContractRepository()..failAtOffset = 1;
    repo.onPage = (offset) async => page([alert('a_x', 1)], 1, more: true);
    var writes = 0;
    final sync = UnifiedAlertSynchronizer(
      repo,
      persist: (_) async {
        writes++;
      },
    );
    await expectLater(sync.synchronize(), throwsA(isA<ApiException>()));
    expect(sync.events, isEmpty);
    expect(sync.cursor, 0);
    expect(writes, 0);
    repo.close();
  });
  test(
    'delta failure does not skip data; older revision cannot undo an ack',
    () async {
      final repo = ContractRepository()
        ..records = [alert('a_x', 1)]
        ..revision = 1;
      final sync = UnifiedAlertSynchronizer(repo);
      await sync.synchronize();
      repo.onChanges = (_) async =>
          throw const ApiException('401', statusCode: 401);
      await expectLater(sync.synchronize(), throwsA(isA<ApiException>()));
      expect(sync.cursor, 1);
      await sync.accept(
        unifiedAlertFromJson(alert('a_x', 8, handling: 'resolved')),
      );
      repo.onChanges = (_) async => changes([alert('a_x', 2)], 8);
      final result = await sync.synchronize();
      expect(result.initial, isFalse);
      expect(result.events.single.resolved, isTrue);
      expect(result.events.single.revision, 8);
      repo.close();
    },
  );
  test(
    'ack response racing an in-flight delta retains highest revision',
    () async {
      final repo = ContractRepository()
        ..records = [alert('a_x', 1)]
        ..revision = 1;
      final sync = UnifiedAlertSynchronizer(repo);
      await sync.synchronize();
      final block = Completer<Map<String, dynamic>>();
      repo.onChanges = (_) => block.future;
      final running = sync.synchronize();
      await Future<void>.delayed(Duration.zero);
      await sync.accept(
        unifiedAlertFromJson(alert('a_x', 4, handling: 'resolved')),
      );
      block.complete(changes([alert('a_x', 2)], 2));
      await running;
      expect(sync.events.single.resolved, isTrue);
      expect(sync.events.single.revision, 4);
      repo.close();
    },
  );
  test(
    'restart restores mirror with cursor; server reset re-baselines authoritatively',
    () async {
      final repo = ContractRepository()
        ..records = [alert('a_x', 9)]
        ..revision = 9;
      Map<String, dynamic>? cache;
      await UnifiedAlertSynchronizer(
        repo,
        persist: (v) async {
          cache = v;
        },
      ).synchronize();
      final resumed = UnifiedAlertSynchronizer(repo)..restore(cache);
      await resumed.synchronize();
      expect(repo.pages, 1);
      repo.records = [alert('a_reset', 1)];
      repo.revision = 1;
      final result = await resumed.synchronize();
      expect(result.initial, isTrue);
      expect(result.events.single.id, 'a_reset');
      expect(result.cursor, 1);
      repo.close();
    },
  );
  test(
    'HTTP API adds auth to unified detail/actions and only same-origin evidence',
    () async {
      final seen = <String>[];
      final repo = UnifiedHttpSafetyRepository(
        baseUrl: 'http://127.0.0.1:8000',
        bearerToken: 'fixture-token',
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer fixture-token');
          seen.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/evidence/0'))
            return http.Response.bytes(
              [1, 2],
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          if (request.url.path == '/api/connection')
            return http.Response(
              jsonEncode({
                'contract_version': '2026-11-04.v1',
                'household': 'default',
              }),
              200,
            );
          return http.Response(jsonEncode(alert('a_x', 3)), 200);
        }),
      );
      await repo.health();
      await repo.event('a_x');
      await repo.handleAlert('a_x', resolve: true);
      await repo.mediaImage('/api/alerts/a_x/evidence/0');
      expect(
        () => repo.mediaUri('https://other.example/image'),
        throwsA(isA<ApiException>()),
      );
      expect(seen, contains('POST /api/alerts/a_x/resolve'));
      repo.close();
    },
  );
  test(
    'two controllers share authoritative handling state and publish one business stream',
    () async {
      final backend = ContractRepository()
        ..records = [alert('a_x', 1)]
        ..revision = 1;
      final one = SafetyController(
        store: SyncStore()
          ..settings = const AppSettings(
            baseUrl: 'http://10.0.2.2:8000',
            bearerToken: 'fixture',
          ),
        repositoryFactory: (_) => backend,
        videoApiFactory: emptyVideoApi,
      );
      final two = SafetyController(
        store: MemorySettingsStore()
          ..settings = const AppSettings(
            baseUrl: 'http://10.0.2.2:8000',
            bearerToken: 'fixture',
          ),
        repositoryFactory: (_) => backend,
        videoApiFactory: emptyVideoApi,
      );
      final snapshots = <AlertSyncSnapshot>[];
      final notices = <EventNotice>[];
      one.alertSnapshots.stream.listen(snapshots.add);
      one.notices.stream.listen(notices.add);
      await one.initialize();
      await two.initialize();
      expect(one.events.single.id, two.events.single.id);
      await one.resolveEvent('a_x');
      await two.refresh();
      expect(two.events.single.resolved, isTrue);
      expect(notices, isEmpty);
      expect(snapshots.first.initial, isTrue);
      expect(snapshots.first.complete, isTrue);
      one.dispose();
      two.dispose();
    },
  );
}
