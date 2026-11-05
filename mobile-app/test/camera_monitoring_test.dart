import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/camera_connection.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/media_api.dart';
import 'package:elder_safety_mobile/ui/camera_screen.dart';
import 'package:elder_safety_mobile/ui/native_camera_view.dart';
import 'fakes.dart';

const config = ObjectServiceConfig(
  baseUrl: 'http://192.168.1.2:8000',
  token: 'synthetic-monitor-token',
);
const camera = CameraConnection(
  host: '192.168.137.39',
  username: 'local@user',
  password: 'synthetic:# /?',
  path: 'stream1&channel=2',
);

void main() {
  test(
    'monitoring API sends credentials only in authenticated POST body',
    () async {
      final paths = <String>[];
      final api = MediaApi(
        config,
        client: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          expect(
            request.headers['Authorization'],
            'Bearer synthetic-monitor-token',
          );
          expect(request.url.userInfo, isEmpty);
          expect(request.url.query, isEmpty);
          if (request.method == 'POST' &&
              request.url.path == '/api/monitoring/camera') {
            expect(jsonDecode(request.body), camera.toJson());
          } else {
            expect(request.body, isEmpty);
          }
          return http.Response('{"state":"starting","monitoring":true}', 200);
        }),
      );
      addTearDown(api.close);
      await api.connectCamera(camera);
      await api.cameraStatus();
      await api.cameraCommand('start');
      await api.cameraCommand('stop');
      expect(paths, [
        'POST /api/monitoring/camera',
        'GET /api/monitoring/camera',
        'POST /api/monitoring/camera/start',
        'POST /api/monitoring/camera/stop',
      ]);
      expect(() => api.cameraCommand('delete'), throwsA(isA<ApiException>()));
      expect(
        () => api.connectCamera(const CameraConnection()),
        throwsA(isA<ApiException>()),
      );
      expect(paths.length, 4);
    },
  );

  testWidgets(
    'starting monitoring and pausing or leaving preview never sends stop',
    (tester) async {
      final controller = SafetyController(
        store: MemorySettingsStore(),
        videoApiFactory: emptyVideoApi,
      );
      await controller.initialize();
      final requests = <String>[];
      var running = false;
      MediaApi api() => MediaApi(
        config,
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/start')) running = true;
          return http.Response(
            jsonEncode({
              'state': running ? 'running' : 'stopped',
              'monitoring': running,
              'events': [],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraScreen(controller: controller, mediaApiFactory: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = find.text('启动已保存的后端监护');
      await tester.scrollUntilVisible(
        start,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.endsWith('/start')), hasLength(1));
      expect(find.textContaining('正在识别'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final count = requests.length;
      await tester.pump(const Duration(seconds: 12));
      expect(requests.length, count);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(requests.length, greaterThan(count));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 12));
      expect(requests.where((r) => r.endsWith('/stop')), isEmpty);
      controller.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'failed backend connection does not save camera or start preview',
    (tester) async {
      final controller = SafetyController(
        store: MemorySettingsStore(),
        videoApiFactory: emptyVideoApi,
      );
      await controller.initialize();
      final requests = <String>[];
      MediaApi api() => MediaApi(
        config,
        client: MockClient((request) async {
          requests.add(request.method);
          if (request.method == 'POST') {
            expect(jsonDecode(request.body)['host'], camera.host);
            return http.Response(
              '{"error":{"code":"CAMERA_UNREACHABLE"}}',
              503,
            );
          }
          return http.Response('{"state":"stopped","events":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraScreen(controller: controller, mediaApiFactory: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final host = find.widgetWithText(TextField, '摄像头局域网 IP');
      await tester.scrollUntilVisible(
        host,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(host, camera.host);
      final password = find.widgetWithText(TextField, '摄像头设备密码');
      await tester.scrollUntilVisible(
        password,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(password, camera.password);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final connect = find.text('连接摄像头并开启后端监护');
      await tester.scrollUntilVisible(
        connect,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(requests.where((r) => r == 'POST'), hasLength(1));
      expect(controller.household.camera.host, isEmpty);
      expect(find.byType(NativeCameraView), findsNothing);
      final message = find.textContaining('电脑后端无法连接摄像头');
      await tester.scrollUntilVisible(
        message,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(message, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.pump();
    },
  );
}
