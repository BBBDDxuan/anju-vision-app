import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/object_api.dart';
import 'package:elder_safety_mobile/services/api.dart';

void main() {
  test(
    'video validation errors retain code and never masquerade as host rejection',
    () async {
      for (final code in [
        'INVALID_MP4',
        'VIDEO_ROTATION',
        'VIDEO_DURATION',
        'VIDEO_RESOLUTION',
        'VIDEO_STREAM',
        'MEDIA_PROBE_FAILED',
        'INVALID_METADATA',
      ]) {
        final api = ObjectApi(
          const ObjectServiceConfig(),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': {'code': code, 'message': 'untrusted-secret'},
              }),
              400,
            ),
          ),
        );
        addTearDown(api.close);
        await expectLater(
          api.postJson('/api/uploads/test/complete'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', code)
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains(code),
                    isNot(contains('白名单')),
                    isNot(contains('untrusted-secret')),
                  ),
                ),
          ),
        );
      }
    },
  );
  test(
    'only actual invalid host response reports a host allowlist failure',
    () async {
      for (final body in ['Invalid host header', '<html>Bad Request</html>']) {
        final api = ObjectApi(
          const ObjectServiceConfig(),
          client: MockClient((_) async => http.Response(body, 400)),
        );
        addTearDown(api.close);
        await expectLater(
          api.recordings(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              body == 'Invalid host header'
                  ? contains('白名单')
                  : isNot(contains('白名单')),
            ),
          ),
        );
      }
    },
  );
  test(
    'original recording routes, evidence and explicit no-cloud query',
    () async {
      final calls = <http.Request>[];
      final api = ObjectApi(
        const ObjectServiceConfig(
          baseUrl: 'http://127.0.0.1:8000',
          token: 'test-token',
        ),
        client: MockClient((r) async {
          calls.add(r);
          expect(r.headers['Authorization'], 'Bearer test-token');
          if (r.url.path == '/api/videos')
            return http.Response(
              jsonEncode({
                'videos': [
                  {'id': 'v1', 'name': 'test'},
                ],
              }),
              200,
            );
          if (r.url.path.endsWith('/events'))
            return http.Response('{"entities":[],"events":[]}', 200);
          if (r.url.path.endsWith('/query')) {
            expect(jsonDecode(r.body), {
              'question': '钥匙在哪里',
              'entity_id': 'obj-1',
              'use_model': false,
            });
            return http.Response('{"answer":"test"}', 200);
          }
          if (r.url.path.endsWith('/replay')) {
            expect(r.url.queryParameters['entity_id'], 'obj-1');
            return http.Response('{"entries":[]}', 200);
          }
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      expect((await api.recordings()).single.id, 'v1');
      await api.memory('v1');
      await api.query('v1', '钥匙在哪里', entityId: 'obj-1');
      await api.replay('v1', 'obj-1');
      expect(await api.frame('/media/frames/v1/f1'), [1, 2, 3]);
      expect(calls.map((r) => r.url.path), [
        '/api/videos',
        '/api/videos/v1/events',
        '/api/videos/v1/query',
        '/api/videos/v1/replay',
        '/media/frames/v1/f1',
      ]);
      expect(
        () => api.uri('https://foreign.example/frame'),
        throwsA(isA<ApiException>()),
      );
      expect(api.videoUri('v1').path, '/media/videos/v1');
      api.close();
    },
  );
  test('cloud opt-in reaches original request flag', () async {
    final api = ObjectApi(
      const ObjectServiceConfig(useCloud: true),
      client: MockClient((r) async {
        expect(jsonDecode(r.body)['use_model'], isTrue);
        return http.Response('{}', 200);
      }),
    );
    await api.query('v1', 'cup');
    api.close();
  });
  test(
    'last observed objects and evidence frames preserve original identifiers',
    () {
      final memory = VideoMemory('v1', {
        'entities': [
          {'id': 'o1', 'label': '钥匙', 'entity_type': 'object'},
          {'id': 'p1', 'entity_type': 'person'},
          {'id': 't1', 'label': '餐桌', 'entity_type': 'place'},
        ],
        'events': [
          {
            'subject_id': 'o1',
            'target_id': 't1',
            'epistemic_type': 'observed',
            'end_ms': 12500,
            'action': 'on',
          },
          {'subject_id': 'o1', 'epistemic_type': 'inferred', 'end_ms': 20000},
        ],
        'frames': [
          {'id': 'f1', 'url': '/media/frames/v1/f1'},
        ],
        'evidence': [
          {
            'id': 'ev1',
            'frame_ids': ['f1'],
          },
        ],
      });
      final item = memory.objectRecords('http://localhost:8000').single;
      expect(item.entityId, 'o1');
      expect(item.videoMs, 12500);
      expect(item.location, '餐桌');
      expect(memory.framesForEvidence(['ev1']).single['id'], 'f1');
    },
  );
}
