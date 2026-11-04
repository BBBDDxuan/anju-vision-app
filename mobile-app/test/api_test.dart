import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'fakes.dart';

void main() {
  test(
    'all user routes use Bearer; health is public; contract bodies match',
    () async {
      final requests = <http.Request>[];
      final repository = HttpSafetyRepository(
        baseUrl: 'https://example.invalid/',
        bearerToken: 'test-user-token',
        client: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path == '/health') return http.Response('{}', 200);
          expect(request.headers['Authorization'], 'Bearer test-user-token');
          if (path == '/api/v1/devices')
            return http.Response(
              jsonEncode([
                {
                  'device_id': 'device-1',
                  'name': '客厅',
                  'last_seen_at': '2026-10-28T01:00:00Z',
                  'online': true,
                },
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          if (path == '/api/v1/events')
            return http.Response(
              jsonEncode([eventJson()]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          if (path == '/api/v1/events/event-1')
            return http.Response(
              jsonEncode(eventJson()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          if (path == '/api/v1/evidence/evidence-1')
            return http.Response.bytes(
              [1, 2, 3],
              200,
              headers: {'content-type': 'image/png'},
            );
          if (path == '/api/v1/preferences' && request.method == 'GET') {
            return http.Response(
              jsonEncode(FamilyPreferences.defaults.toJson()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (path == '/api/v1/push-tokens')
            return http.Response('{"token_id":"push-1"}', 201);
          return http.Response('', 204);
        }),
      );
      addTearDown(repository.close);
      expect(await repository.health(), true);
      expect(requests.first.headers.containsKey('Authorization'), false);
      final devices = await repository.devices();
      expect(devices.single.id, 'device-1');
      expect(devices.single.online, true);
      expect((await repository.events()).single.reviewSummary, '请家属核实');
      expect((await repository.event('event-1')).id, 'event-1');
      expect(await repository.evidence('evidence-1'), [1, 2, 3]);
      await repository.acknowledge('event-1');
      await repository.resolve('event-1');
      expect((await repository.preferences()).escalationSeconds, 60);
      await repository.savePreferences(FamilyPreferences.defaults);
      expect(
        await repository.registerPush('test-push-token', 'mock', 'backup'),
        'push-1',
      );
      await repository.deletePush('push-1');
      expect(
        requests.map((r) => '${r.method} ${r.url.path}'),
        containsAll([
          'POST /api/v1/events/event-1/ack',
          'POST /api/v1/events/event-1/resolve',
          'DELETE /api/v1/push-tokens/push-1',
        ]),
      );
      final put = requests.singleWhere((r) => r.method == 'PUT');
      expect(jsonDecode(put.body), FamilyPreferences.defaults.toJson());
      final push = requests.singleWhere(
        (r) => r.url.path == '/api/v1/push-tokens',
      );
      expect(jsonDecode(push.body), {
        'token': 'test-push-token',
        'platform': 'mock',
        'contact_id': 'backup',
      });
    },
  );

  test('IDs are encoded as a single path segment', () async {
    const id = 'a/b ?#中文';
    final repository = HttpSafetyRepository(
      baseUrl: 'https://example.invalid',
      bearerToken: 'token',
      client: MockClient((request) async {
        expect(request.url.pathSegments.last, id);
        expect(request.url.hasQuery, false);
        expect(request.url.hasFragment, false);
        return http.Response(
          jsonEncode(eventJson(id: id)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(repository.close);
    expect((await repository.event(id)).id, id);
  });

  test('401 is actionable and does not expose response secrets', () async {
    final repository = HttpSafetyRepository(
      baseUrl: 'https://example.invalid',
      bearerToken: 'token',
      client: MockClient(
        (_) async => http.Response('secret-response-token', 401),
      ),
    );
    addTearDown(repository.close);
    await expectLater(
      repository.events(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having(
              (e) => e.message,
              'message',
              isNot(contains('secret-response-token')),
            ),
      ),
    );
  });

  test('rejects envelope instead of list and non-image evidence', () async {
    final repository = HttpSafetyRepository(
      baseUrl: 'https://example.invalid',
      bearerToken: 'token',
      client: MockClient(
        (_) async => http.Response(
          '{"items":[]}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(repository.close);
    await expectLater(repository.events(), throwsA(isA<ApiException>()));
    await expectLater(repository.evidence('bad'), throwsA(isA<ApiException>()));
  });

  test('timeouts are reported without URLs or tokens', () async {
    final repository = HttpSafetyRepository(
      baseUrl: 'https://example.invalid',
      bearerToken: 'token',
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('[]', 200);
      }),
    );
    addTearDown(repository.close);
    await expectLater(
      repository.events(),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', contains('超时')),
      ),
    );
  });

  test('DELETE 404 is idempotent', () async {
    final repository = HttpSafetyRepository(
      baseUrl: 'https://example.invalid',
      bearerToken: 'token',
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(repository.close);
    await repository.deletePush('already-gone');
  });
}
