import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/services/android_notices.dart';
import 'package:elder_safety_mobile/ui/settings_screen.dart';
import 'fakes.dart';

const notificationChannel = MethodChannel('elder_safety/notifications');
Map<String, Object> statusMap({
  bool permission = true,
  bool app = true,
  bool channel = true,
}) => {
  'permission_required': true,
  'permission_granted': permission,
  'app_enabled': app,
  'channel_enabled': channel,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationChannel, null);
  });

  test(
    'notification bridge reads permission results and opens native settings',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationChannel, (call) async {
            calls.add(call);
            if (call.method == 'status') return statusMap(permission: false);
            if (call.method == 'requestPermission')
              return statusMap(channel: false);
            return null;
          });
      final bridge = AndroidNotices();
      addTearDown(bridge.dispose);
      final initial = (await bridge.status())!;
      expect(initial.permissionRequired, isTrue);
      expect(initial.permissionGranted, isFalse);
      expect(initial.enabled, isFalse);
      final granted = (await bridge.requestPermission())!;
      expect(granted.permissionGranted, isTrue);
      expect(granted.channelEnabled, isFalse);
      expect(granted.enabled, isFalse);
      await bridge.openNotificationSettings();
      await bridge.openChannelSettings();
      await bridge.openAppSettings();
      expect(calls.map((call) => call.method), [
        'status',
        'requestPermission',
        'openNotificationSettings',
        'openChannelSettings',
        'openAppSettings',
      ]);
      expect(calls.every((call) => call.arguments == null), isTrue);
    },
  );

  test(
    'missing platform status never masquerades as permission granted',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationChannel, (_) async => null);
      final bridge = AndroidNotices();
      addTearDown(bridge.dispose);
      await expectLater(bridge.status(), throwsA(isA<StateError>()));
      await expectLater(bridge.requestPermission(), throwsA(isA<StateError>()));
    },
  );

  testWidgets(
    'notification sheet refreshes after permission and settings round trip',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String>[];
      var permission = false;
      var app = true;
      var channel = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationChannel, (call) async {
            calls.add(call.method);
            if (call.method == 'requestPermission') permission = true;
            if (call.method == 'status' || call.method == 'requestPermission') {
              return statusMap(
                permission: permission,
                app: app,
                channel: channel,
              );
            }
            return null;
          });
      final c = SafetyController(
        store: MemorySettingsStore(),
        videoApiFactory: emptyVideoApi,
      );
      try {
        await c.initialize();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SettingsScreen(controller: c)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('通知管理'));
        await tester.tap(find.text('通知管理'));
        await tester.pumpAndSettle();
        expect(calls, ['status']);
        expect(find.text('Android 13+ 通知权限：未开启'), findsOneWidget);
        await tester.ensureVisible(find.text('申请通知权限'));
        await tester.tap(find.text('申请通知权限'));
        await tester.pumpAndSettle();
        expect(calls.where((call) => call == 'requestPermission').length, 1);
        expect(find.text('Android 13+ 通知权限：已开启'), findsOneWidget);
        expect(find.text('申请通知权限'), findsNothing);
        await tester.ensureVisible(find.text('系统通知设置'));
        await tester.tap(find.text('系统通知设置'));
        await tester.pumpAndSettle();
        expect(calls, contains('openNotificationSettings'));
        app = false;
        channel = false;
        final previousStatusCalls = calls
            .where((call) => call == 'status')
            .length;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(
          calls.where((call) => call == 'status').length,
          previousStatusCalls + 1,
        );
        expect(find.text('应用通知总开关：未开启'), findsOneWidget);
        expect(find.text('居家危险提醒渠道：未开启'), findsOneWidget);
        app = true;
        channel = true;
        await tester.ensureVisible(find.text('刷新通知状态'));
        await tester.tap(find.text('刷新通知状态'));
        await tester.pumpAndSettle();
        expect(
          calls.where((call) => call == 'status').length,
          previousStatusCalls + 2,
        );
        expect(find.text('应用通知总开关：已开启'), findsOneWidget);
        expect(find.text('居家危险提醒渠道：已开启'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        // Widget invariants run before addTearDown; stop polling here.
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        await tester.pump();
      }
    },
  );

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      '320px connection advanced polling field stays usable at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = SafetyController(
          store: MemorySettingsStore(),
          videoApiFactory: emptyVideoApi,
        );
        try {
          await c.initialize();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: SettingsScreen(controller: c)),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('连接服务'), 200);
          await tester.tap(find.text('连接服务'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('高级设置'));
          await tester.tap(find.text('高级设置'));
          await tester.pumpAndSettle();
          final polling = find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == '间隔（秒）',
          );
          expect(polling, findsOneWidget);
          await tester.ensureVisible(polling);
          await tester.pumpAndSettle();
          expect(find.text('前台刷新间隔'), findsOneWidget);
          await tester.enterText(polling, '30');
          expect(tester.widget<TextField>(polling).controller!.text, '30');
          final bounds = tester.getRect(polling);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(tester.takeException(), isNull);
        } finally {
          // Widget invariants run before addTearDown; stop polling here.
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          await tester.pump();
        }
      },
    );
  }
}
