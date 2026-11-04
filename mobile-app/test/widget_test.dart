import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/app.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/ui/event_detail_screen.dart';
import 'fakes.dart';

void main() {
  testWidgets(
    'unconfigured app starts with empty data without Firebase',
    (tester) async => withEmptyVideoHttp(() async {
      final controller = SafetyController(
        store: MemorySettingsStore(),
        videoApiFactory: emptyVideoApi,
      );
      await tester.pumpWidget(ElderSafetyApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('成员监护'), findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('home-成员监护')));
      await tester.tap(find.byKey(const ValueKey('home-成员监护')));
      await tester.pumpAndSettle();
      expect(find.text('被监护人员'), findsWidgets);
      expect(controller.household.members, isEmpty);
      expect(controller.events, isEmpty);
      expect(controller.devices, isEmpty);
      expect(find.text('成员1'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }),
  );

  testWidgets(
    'detail ack and confirmed resolve read back authoritative states',
    (tester) async => withEmptyVideoHttp(() async {
      final controller = SafetyController(
        store: MemorySettingsStore(),
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            controller: controller,
            eventId: 'fixture-fall',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ack = find.text('我已收到');

      await tester.tap(ack);
      await tester.pumpAndSettle();
      expect(
        (await controller.repository.event('fixture-fall')).state,
        'acknowledged',
      );
      final resolve = find.text('标记已解决');

      await tester.tap(resolve);
      // The screen intentionally animates its busy indicator while awaiting the
      // confirmation dialog, so waiting for every animation to settle cannot end.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('标记事件已解决？'), findsOneWidget);
      expect(
        (await controller.repository.event('fixture-fall')).resolved,
        false,
      );
      await tester.tap(find.text('已核实，解决'));
      await tester.pumpAndSettle();
      expect(
        (await controller.repository.event('fixture-fall')).resolved,
        true,
      );
      expect(
        (await controller.repository.event('fixture-fall')).acknowledged,
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.pump();
    }),
  );
}
