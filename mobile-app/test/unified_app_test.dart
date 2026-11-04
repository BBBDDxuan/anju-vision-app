import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/unified_alert.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'package:elder_safety_mobile/ui/event_detail_screen.dart';
import 'package:elder_safety_mobile/ui/objects_screen.dart';
import 'fakes.dart';
import 'unified_alert_test.dart' show ContractRepository, alert;

void main() {
  testWidgets(
    'one connection form has one origin/token and keeps advanced settings',
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
      await t.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('我的'),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('连接服务'));
      await t.pumpAndSettle();
      await t.tap(find.text('连接服务'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, '统一后端地址'), findsOneWidget);
      expect(find.widgetWithText(TextField, '统一访问令牌'), findsOneWidget);
      expect(find.text('安全后端（可选）'), findsNothing);
      expect(find.text('录像服务地址'), findsNothing);
      expect(find.text('检查连接'), findsOneWidget);
      expect(find.text('保存连接'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets(
    'cold notification opens global alert detail with correct video offset',
    (t) async => withEmptyVideoHttp(() async {
      final repo = ContractRepository()
        ..records = [
          {
            ...alert('a_video', 1, source: 'uploaded_recording'),
            'evidence': [],
          },
        ]
        ..revision = 1;
      final c = SafetyController(
        store: MemorySettingsStore()
          ..settings = const AppSettings(
            baseUrl: 'http://10.0.2.2:8000',
            bearerToken: 'fixture',
          ),
        repositoryFactory: (_) => repo,
        videoApiFactory: emptyVideoApi,
      );
      c.openAlert(
        const AlertLocation(
          backend: 'http://10.0.2.2:8000',
          household: 'default',
          alertId: 'a_video',
          source: 'uploaded_recording',
        ),
      );
      await t.pumpWidget(ElderSafetyApp(controller: c));
      await t.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsOneWidget);
      await t.scrollUntilVisible(
        find.byType(EvidenceVideo),
        220,
        scrollable: find
            .descendant(
              of: find.byType(EventDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      final video = t.widget<EvidenceVideo>(find.byType(EvidenceVideo));
      expect(video.startMs, 1200);
      expect(video.playbackPath, '/media/videos/video-1');
      expect(video.api.config.baseUrl, 'http://10.0.2.2:8000');
      expect(find.text('标记已解决'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );

  testWidgets(
    'foreign backend notification does not open same-named alert',
    (t) async => withEmptyVideoHttp(() async {
      final repo = ContractRepository()
        ..records = [
          {...alert('a_x', 1), 'evidence': []},
        ]
        ..revision = 1;
      final c = SafetyController(
        store: MemorySettingsStore()
          ..settings = const AppSettings(
            baseUrl: 'http://10.0.2.2:8000',
            bearerToken: 'fixture',
          ),
        repositoryFactory: (_) => repo,
        videoApiFactory: emptyVideoApi,
      );
      c.openAlert(
        const AlertLocation(
          backend: 'http://192.168.1.99:8000',
          household: 'default',
          alertId: 'a_x',
          source: 'live_camera',
        ),
      );
      await t.pumpWidget(ElderSafetyApp(controller: c));
      await t.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsNothing);
      expect(find.text('这条通知属于其他后端或家庭，请切换到原连接后查看'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }),
  );
}
