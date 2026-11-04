import 'package:flutter/material.dart';
import 'package:elder_safety_mobile/app.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'package:elder_safety_mobile/ui/event_detail_screen.dart';
import 'package:elder_safety_mobile/ui/objects_screen.dart';
import 'fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/models/unified_alert.dart';

import 'unified_alert_test.dart' show ContractRepository, alert;

void main() {
  test(
    'fall selects the post-fall image even if an early context image comes first',
    () {
      final event = unifiedAlertFromJson({
        ...alert('a_fall', 2, source: 'uploaded_recording'),
        'video_offset_ms': 2300,
        'video_end_ms': 6300,
        'evidence': [
          {'url': '/api/alerts/a_fall/evidence/0', 'video_offset_ms': 2300},
          {
            'url': '/api/alerts/a_fall/evidence/1?version=abc',
            'video_offset_ms': 6800,
            'phase': 'post_event',
          },
        ],
      });
      expect(event.evidenceId, '/api/alerts/a_fall/evidence/1?version=abc');
      expect(event.details['start_ms'], 2300);
      expect(event.details['playback_start_ms'], 6800);
      expect(event.details['primary_evidence']['phase'], 'post_event');
    },
  );

  for (final kind in ['help_requested', 'fire_detected']) {
    test(
      '$kind selects active event rather than before or after the event',
      () {
        final event = unifiedAlertFromJson({
          ...alert('a_active', 2, source: 'uploaded_recording'),
          'event_type': kind,
          'evidence': [
            {'url': '/before.jpg', 'video_offset_ms': 2300},
            {
              'url': '/active.jpg',
              'video_offset_ms': 6300,
              'phase': 'during_event',
            },
            {'url': '/after.jpg', 'video_offset_ms': 7000},
          ],
        });
        expect(event.evidenceId, '/active.jpg');
        expect(event.details['playback_start_ms'], 6300);
      },
    );
  }

  test('end-of-video fallback remains explicit', () {
    final event = unifiedAlertFromJson({
      ...alert('a_eof', 2),
      'evidence': [
        {
          'url': '/trigger.jpg',
          'phase': 'trigger_fallback',
          'video_offset_ms': 6300,
        },
      ],
    });
    expect(event.details['primary_evidence']['phase'], 'trigger_fallback');
  });

  test('empty evidence still permits original video playback', () {
    final event = unifiedAlertFromJson({
      ...alert('a_empty', 2, source: 'uploaded_recording'),
      'evidence': [],
      'playback_offset_ms': 6300,
    });
    expect(event.evidenceId, isNull);
    expect(event.details['playback_start_ms'], 6300);
  });

  test('legacy evidence is not given a fabricated post-fall phase', () {
    final event = unifiedAlertFromJson({
      ...alert('a_old', 2, source: 'uploaded_recording'),
      'evidence': [
        {'url': '/first.jpg', 'video_offset_ms': 2300},
        {'url': '/last.jpg', 'video_offset_ms': 6300},
      ],
    });
    expect(event.evidenceId, '/last.jpg');
    expect(event.details['primary_evidence']['phase'], isNull);
  });
  testWidgets(
    'detail shows post-fall caption and replays at that image rather than pre-roll',
    (tester) async {
      await withEmptyVideoHttp(() async {
        final repo = ContractRepository()
          ..records = [
            {
              ...alert('a_phase', 2, source: 'uploaded_recording'),
              'evidence': [
                {
                  'url': '/api/alerts/a_phase/evidence/0?version=abc',
                  'phase': 'post_event',
                  'video_offset_ms': 6800,
                },
              ],
            },
          ]
          ..revision = 2;
        final controller = SafetyController(
          store: MemorySettingsStore()
            ..settings = const AppSettings(
              baseUrl: 'http://10.0.2.2:8000',
              bearerToken: 'fixture',
            ),
          repositoryFactory: (_) => repo,
          videoApiFactory: emptyVideoApi,
        );
        controller.openAlert(
          const AlertLocation(
            backend: 'http://10.0.2.2:8000',
            household: 'default',
            alertId: 'a_phase',
            source: 'uploaded_recording',
          ),
        );
        await tester.pumpWidget(ElderSafetyApp(controller: controller));
        await tester.pumpAndSettle();
        final scrollable = find
            .descendant(
              of: find.byType(EventDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byType(EvidenceVideo),
          220,
          scrollable: scrollable,
        );
        expect(
          tester.widget<EvidenceVideo>(find.byType(EvidenceVideo)).startMs,
          6800,
        );
        await tester.scrollUntilVisible(
          find.text('摔倒后画面 · 原片 6.80 秒'),
          120,
          scrollable: scrollable,
        );
        expect(find.text('摔倒后画面 · 原片 6.80 秒'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    },
  );
}
