import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/ui/manual_screen.dart';
import 'package:elder_safety_mobile/ui/media_hub_screen.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadManual();
  });
  testWidgets(
    'devices keep camera and video routes; My keeps members and manual',
    (t) async => withEmptyVideoHttp(() async {
      t.view.physicalSize = const Size(420, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = SafetyController(
        store: MemorySettingsStore(),
        videoApiFactory: emptyVideoApi,
      );
      await t.pumpWidget(ElderSafetyApp(controller: c));
      await t.pumpAndSettle();
      Future<void> tab(String title) async {
        await t.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(title),
          ),
        );
        await t.pumpAndSettle();
      }

      await tab('设备');
      await t.tap(find.text('实时摄像头').hitTestable().first);
      await t.pumpAndSettle();
      expect(find.byType(MediaHubScreen), findsOneWidget);
      expect(find.text('局域网摄像头'), findsOneWidget);
      await t.tap(find.byType(BackButton).first);
      await t.pumpAndSettle();
      await t.tap(find.text('上传视频 / 录像库'));
      await t.pumpAndSettle();
      expect(find.text('选择并上传 MP4 视频'), findsOneWidget);
      await t.tap(find.byType(BackButton).first);
      await t.pumpAndSettle();
      await tab('消息');
      expect(find.text('守护消息'), findsOneWidget);
      await tab('我的');
      await t.tap(find.text('被监护人员'));
      await t.pumpAndSettle();
      expect(find.text('人员档案、设备范围与每一次观察'), findsNothing);
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(find.text('家庭联系人'), findsWidgets);
      await t.tap(find.byType(BackButton).first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('使用帮助'));
      await t.pumpAndSettle();
      await t.tap(find.text('使用帮助'));
      await t.pumpAndSettle();
      expect(find.byType(ManualScreen), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets('offline manual loads full content and searches chapters', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: ManualScreen()));
    await t.pumpAndSettle();
    expect(find.text('01  版本与功能地图'), findsOneWidget);
    await t.enterText(find.byType(TextField), '192.168.137.39');
    await t.pumpAndSettle();
    expect(find.text('07  连接局域网实时摄像头'), findsOneWidget);
    expect(find.text('01  版本与功能地图'), findsNothing);
    await t.enterText(find.byType(TextField), '不存在的功能关键词xyz');
    await t.pumpAndSettle();
    expect(find.text('没有匹配章节'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
