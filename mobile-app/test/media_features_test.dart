import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/models/camera_connection.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/media_api.dart';
import 'package:elder_safety_mobile/services/workspace_proxy.dart';

void main() {
  const config = ObjectServiceConfig(
    baseUrl: 'http://127.0.0.1:8000',
    token: 'fixture-token',
  );
  test(
    'camera validates LAN endpoint and encodes credentials without changing dual path',
    () {
      const camera = CameraConnection(
        host: '192.168.137.39',
        username: 'local@user',
        password: 'a:# /?',
        path: 'stream1&channel=2',
      );
      expect(camera.validationError, isNull);
      expect(camera.streamUri.host, '192.168.137.39');
      expect(camera.streamUri.path, '/stream1&channel=2');
      expect(camera.streamUri.userInfo, 'local%40user:a%3A%23%20%2F%3F');
      expect(
        CameraConnection.fromJson(camera.toJson()).password,
        camera.password,
      );
      for (final host in [
        '8.8.8.8',
        '127.0.0.1',
        '192.168.0.999',
        '172.32.0.1',
        'evil.example',
      ]) {
        expect(
          CameraConnection(host: host, password: 'fixture').validationError,
          isNotNull,
        );
      }
      expect(
        const CameraConnection(
          host: '10.0.2.2',
          password: 'fixture',
          path: '../secret',
        ).validationError,
        isNotNull,
      );
    },
  );
  test(
    'chunked upload preserves bytes, auth and exact progress without buffering full file',
    () async {
      final dir = await Directory.systemTemp.createTemp('anju-upload-');
      addTearDown(() => dir.delete(recursive: true));
      final data = List<int>.generate(10017, (i) => i % 251);
      final file = await File('${dir.path}/fixture.mp4').writeAsBytes(data);
      final chunks = <int>[];
      final progress = <int>[];
      final api = MediaApi(
        config,
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer fixture-token');
          if (r.url.path == '/api/uploads') {
            expect(jsonDecode(r.body)['size'], data.length);
            return http.Response('{"upload_id":"u1","chunk_bytes":4096}', 200);
          }
          if (r.url.path.endsWith('/chunks')) {
            expect(int.parse(r.url.queryParameters['offset']!), chunks.length);
            expect(r.bodyBytes.length, lessThanOrEqualTo(4096));
            chunks.addAll(r.bodyBytes);
            return http.Response(jsonEncode({'received': chunks.length}), 200);
          }
          expect(r.url.path, '/api/uploads/u1/complete');
          return http.Response('{"video_id":"v1"}', 200);
        }),
      );
      addTearDown(api.close);
      expect(
        await api.uploadVideo(
          file,
          'fixture.mp4',
          cancellation: UploadCancellation(),
          onProgress: (n, t) {
            expect(t, data.length);
            progress.add(n);
          },
        ),
        'v1',
      );
      expect(chunks, data);
      expect(progress, [0, 4096, 8192, 10017]);
    },
  );
  test(
    'cancel and incorrect server offsets clean upload session; never complete',
    () async {
      final dir = await Directory.systemTemp.createTemp('anju-cancel-');
      addTearDown(() => dir.delete(recursive: true));
      final file = await File(
        '${dir.path}/fixture.mp4',
      ).writeAsBytes(List.filled(30, 1));
      for (final cancel in [true, false]) {
        final paths = <String>[];
        final cancellation = UploadCancellation();
        final api = MediaApi(
          config,
          client: MockClient((r) async {
            paths.add(r.url.path);
            if (r.url.path == '/api/uploads')
              return http.Response('{"upload_id":"u","chunk_bytes":10}', 200);
            if (r.url.path.endsWith('/chunks'))
              return http.Response('{"received":0}', 200);
            return http.Response('{}', 200);
          }),
        );
        await expectLater(
          api.uploadVideo(
            file,
            'fixture.mp4',
            cancellation: cancellation,
            onProgress: (n, t) {
              if (cancel) cancellation.cancel();
            },
          ),
          throwsA(isA<ApiException>()),
        );
        expect(paths.last, '/api/uploads/u/cancel');
        expect(paths.any((p) => p.endsWith('/complete')), false);
        api.close();
      }
    },
  );
  test('analysis modes explicit; resume preserves original job mode', () async {
    final calls = <http.Request>[];
    final api = MediaApi(
      config,
      client: MockClient((r) async {
        calls.add(r);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);
    await api.analyze('v1', 'safety');
    await api.analyze('v1', 'objects');
    await api.pause('v1');
    await api.resume('v1');
    expect(calls.map((r) => r.url.query), [
      'mode=safety',
      'mode=objects',
      '',
      '',
    ]);
    expect(() => api.analyze('v1', 'photo'), throwsA(isA<ApiException>()));
  });
  test(
    'workspace proxy authenticates session, streams auth/range, blocks redirects and retains camera denial',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <String>[];
      server.listen((r) async {
        expect(r.headers.value('authorization'), 'Bearer fixture-token');
        received.add(r.uri.path);
        if (r.uri.path == '/redirect') {
          r.response.statusCode = 302;
          r.response.headers.set('location', 'https://example.org/');
        } else if (r.uri.path == '/api/camera/start') {
          r.response.statusCode = 403;
          r.response.write('local only');
        } else {
          expect(r.headers.value('range'), 'bytes=0-3');
          expect(r.headers.value('origin'), 'http://127.0.0.1:${server.port}');
          expect(r.cookies.where((c) => c.name == 'anju_workspace'), isEmpty);
          r.response.statusCode = 206;
          await r.response.addStream(r);
        }
        await r.response.close();
      });
      final proxy = WorkspaceProxy(
        ObjectServiceConfig(
          baseUrl: 'http://127.0.0.1:${server.port}',
          token: 'fixture-token',
        ),
      );
      final entry = await proxy.start();
      addTearDown(proxy.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final denied = await (await client.getUrl(
        entry.resolve('/workspace'),
      )).close();
      expect(denied.statusCode, 403);
      await denied.drain<void>();
      expect(received, isEmpty);
      final handshake = await client.getUrl(entry);
      handshake.followRedirects = false;
      final welcome = await handshake.close();
      expect(welcome.statusCode, 302);
      final cookie = welcome.cookies.single;
      expect(cookie.httpOnly, true);
      expect(cookie.sameSite, SameSite.strict);
      await welcome.drain<void>();
      Future<HttpClientResponse> request(String path) async {
        final r = await client.postUrl(entry.resolve(path));
        r.cookies.add(cookie);
        r.headers.set('range', 'bytes=0-3');
        r.headers.set('origin', entry.origin);
        r.add([1, 2, 3, 4]);
        return r.close();
      }

      final echoed = await request('/api/uploads/u/chunks');
      expect(echoed.statusCode, 206);
      expect(await echoed.fold<List<int>>([], (a, b) => a..addAll(b)), [
        1,
        2,
        3,
        4,
      ]);
      final camera = await request('/api/camera/start');
      expect(camera.statusCode, 403);
      await camera.drain<void>();
      final redirect = await request('/redirect');
      expect(redirect.statusCode, 502);
      await redirect.drain<void>();
    },
  );
}
