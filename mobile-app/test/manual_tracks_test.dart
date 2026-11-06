import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/members_api.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'package:elder_safety_mobile/ui/manual_tracks_panel.dart';
import 'package:elder_safety_mobile/ui/member_avatar.dart';
import 'fakes.dart';

http.Response response(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets('labels use only color and letter even with a legacy photo', (
    tester,
  ) async {
    const member = MemberProfile(
      id: 'm',
      number: 1,
      name: '家人',
      labelColor: '#123456',
      labelLetter: 'A',
      avatarDataUrl: 'data:image/png;base64,irrelevant',
    );
    expect(MemberProfile.fromJson(member.toJson()).labelColor, '#123456');
    expect(member.copyWith(name: '家人二').labelLetter, 'A');
    await tester.pumpWidget(
      const MaterialApp(home: MemberAvatar(member: member)),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundColor,
      const Color(0xff123456),
    );
  });

  testWidgets(
    'manual selection uses current session; new file starts pending and closes old session',
    (tester) async {
      const settings = AppSettings(
        baseUrl: 'http://192.168.1.10:8000',
        bearerToken: 'synthetic-manual-token',
      );
      final requests = <http.Request>[];
      var sessionNumber = 0;
      var tag = <String, dynamic>{
        'status': 'pending',
        'label': '待确认',
        'member_id': null,
      };
      Map<String, dynamic> snapshot() => {
        'session_id': 's$sessionNumber',
        'source': 'synthetic',
        'segments': <Object>[],
        'tracks': [
          {
            'id': 'person-1',
            'version': 'v$sessionNumber',
            'active': true,
            'crop': '',
            'crop_ms': 1000,
            'association': tag,
          },
        ],
      };
      final c = SafetyController(
        store: MemorySettingsStore()..settings = settings,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
        membersApiFactory: (s) => MembersApi(
          s,
          client: MockClient(
            (r) async => response({
              'members': [
                const MemberProfile(id: 'a', number: 1, name: '成员 A').toJson(),
              ],
            }),
          ),
        ),
      );
      await c.initialize();
      await tester.runAsync(() async {
        for (var n = 0; n < 100 && c.memberSyncing; n++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      });
      MembersApi api() => MembersApi(
        settings,
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('video-sessions')) {
            sessionNumber++;
            tag = {'status': 'pending', 'label': '待确认', 'member_id': null};
          }
          if (r.method == 'PUT') {
            expect(jsonDecode(r.body), {
              'version': 'v1',
              'status': 'member',
              'member_id': 'a',
            });
            tag = {'status': 'member', 'label': '成员 A（人工关联）', 'member_id': 'a'};
          }
          return response(snapshot());
        }),
      );
      Widget page(String id) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManualTracksPanel(
              controller: c,
              videoId: id,
              positionMs: () => 1000,
              apiFactory: api,
            ),
          ),
        ),
      );
      Future<void> settleRequests() async {
        for (var n = 0; n < 12; n++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
      }

      await tester.pumpWidget(page('video-one'));
      await settleRequests();
      expect(find.text('person-1'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('成员 A').last);
      await settleRequests();
      expect(find.text('成员 A（人工关联）'), findsOneWidget);
      await tester.pumpWidget(page('video-two'));
      await settleRequests();
      expect(find.text('成员 A（人工关联）'), findsNothing);
      expect(
        requests.any(
          (r) => r.method == 'DELETE' && r.url.path == '/api/manual-tracks/s1',
        ),
        isTrue,
      );
      expect(
        requests.where((r) => r.url.path.endsWith('video-sessions')).length,
        2,
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/s2/position')).length,
        1,
      );
      for (final request in requests) {
        expect(request.url.origin, settings.baseUrl);
        expect(
          request.headers['Authorization'],
          'Bearer synthetic-manual-token',
        );
        expect(request.body, isNot(contains('embedding')));
      }
      await tester.pumpWidget(const SizedBox());
      await settleRequests();
      c.dispose();
    },
  );
}
