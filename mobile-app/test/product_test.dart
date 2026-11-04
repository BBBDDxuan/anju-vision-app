import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'fakes.dart';
import 'package:elder_safety_mobile/ui/media_hub_screen.dart';

Future<void> openFeature(WidgetTester t, String title) async {
  final entry = find.byKey(ValueKey('home-$title'));
  await t.scrollUntilVisible(
    entry,
    220,
    scrollable: find
        .descendant(
          of: find.byKey(const PageStorageKey('home')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await t.pumpAndSettle();
  await t.tap(entry);
  await t.pumpAndSettle();
}

void main() {
  test(
    'search history survives restart without inventing recent objects',
    () async {
      final store = MemorySettingsStore();
      final first = SafetyController(
        store: store,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(first.dispose);
      await first.initialize();
      await first.rememberSearch('钥匙');
      await first.rememberSearch('眼镜');
      await first.rememberSearch('钥匙');
      final again = SafetyController(
        store: store,
        videoApiFactory: emptyVideoApi,
      );
      addTearDown(again.dispose);
      await again.initialize();
      expect(again.household.searches, ['钥匙', '眼镜']);
      expect(again.household.recentObjects, isEmpty);
      expect(again.events, isEmpty);
    },
  );
  testWidgets(
    'three areas separate events and support object search',
    (t) async => withEmptyVideoHttp(() async {
      t.view.physicalSize = const Size(420, 920);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await addFixtureMembers(c);
      await t.pumpWidget(ElderSafetyApp(controller: c));
      await t.pumpAndSettle();
      expect(c.household.members.map((m) => m.displayName), [
        '成员1',
        '成员2',
        '成员3',
      ]);
      expect(find.text('家的动态，一眼安心'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('首页'),
        ),
        findsOneWidget,
      );
      await openFeature(t, '成员监护');
      await t.tap(find.text('家庭联系人').first);
      await t.pumpAndSettle();
      expect(find.text('接收提醒的人'), findsOneWidget);
      await t.tap(find.byType(BackButton).first);
      await t.pumpAndSettle();
      await openFeature(t, '家中风险');
      expect(find.text('家庭风险概览'), findsOneWidget);
      expect(find.text('人物事件'), findsNothing);
      await t.tap(find.byType(BackButton).first);
      await t.pumpAndSettle();
      await openFeature(t, '物品寻找');
      await t.enterText(find.byType(TextField).first, '钥匙');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await t.pumpAndSettle();
      expect(c.household.searches, contains('钥匙'));
      expect(find.text('背包'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );
  testWidgets(
    'member profile can be edited from its card',
    (t) async => withEmptyVideoHttp(() async {
      t.view.physicalSize = const Size(420, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await addFixtureMembers(c);
      await t.pumpWidget(ElderSafetyApp(controller: c));
      await t.pumpAndSettle();
      await openFeature(t, '成员监护');
      await t.tap(find.text('成员1').first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('编辑档案'));
      await t.pumpAndSettle();
      await t.tap(find.text('编辑档案'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, '奶奶');
      await t.ensureVisible(find.text('保存档案'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存档案'));
      await t.pumpAndSettle();
      expect(c.household.members.first.displayName, '奶奶');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );
  testWidgets(
    'small display with large text and tablet remain usable',
    (t) async => withEmptyVideoHttp(() async {
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final c = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await addFixtureMembers(c);
      await t.pumpWidget(ElderSafetyApp(controller: c));
      await t.pumpAndSettle();
      for (final title in ['成员监护', '家中风险', '物品寻找']) {
        await openFeature(t, title);
        expect(t.takeException(), isNull, reason: title);
        await t.tap(find.byType(BackButton).first);
        await t.pumpAndSettle();
      }
      for (final label in ['设备', '消息', '我的', '首页']) {
        await t.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: label);
      }
      t.view.physicalSize = const Size(900, 1000);
      await t.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );
  testWidgets(
    'camera workspace is usable on a small display and has no photo analysis',
    (t) async => withEmptyVideoHttp(() async {
      t.view.physicalSize = const Size(320, 780);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final c = SafetyController(
        store: MemorySettingsStore(),
        videoApiFactory: emptyVideoApi,
      );
      await c.initialize();
      await t.pumpWidget(
        MaterialApp(home: MediaHubScreen(controller: c, camera: true)),
      );
      await t.pump(const Duration(seconds: 1));
      expect(find.text('局域网摄像头'), findsOneWidget);
      expect(find.text('照片分析'), findsNothing);
      expect(find.text('拍照'), findsNothing);
      expect(t.takeException(), isNull);
      await t.drag(find.byType(ListView).first, const Offset(0, -550));
      await t.pump();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      c.dispose();
    }),
  );
}
