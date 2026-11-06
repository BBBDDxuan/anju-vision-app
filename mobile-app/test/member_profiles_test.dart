import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/app_controller.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/members_api.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'package:elder_safety_mobile/ui/members_screen.dart';
import 'fakes.dart';

const connection = AppSettings(
  baseUrl: 'http://192.168.1.10:8000',
  bearerToken: 'member-test-token',
);
http.Response reply(Object data, [int code = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  code,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> until(bool Function() condition) async {
  for (var n = 0; n < 100; n++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Timed out');
}

void main() {
  test(
    'member API same origin, auth, revision, photo consent and input bounds',
    () async {
      final requests = <http.Request>[];
      final api = MembersApi(
        connection,
        client: MockClient((r) async {
          requests.add(r);
          return reply(
            r.method == 'GET'
                ? {'members': []}
                : {
                    'member': {
                      'id': 'm-1',
                      'number': 1,
                      'name': '奶奶',
                      'revision': 2,
                    },
                  },
          );
        }),
      );
      addTearDown(api.close);
      await api.members();
      final saved = await api.save(
        const MemberProfile(id: 'm-1', number: 1, name: '奶奶', revision: 1),
      );
      expect(saved.revision, 2);
      expect(jsonDecode(requests.last.body)['revision'], 1);
      final photo = Uint8List.fromList([255, 216, 255, 1]);
      await expectLater(
        api.enroll(saved, photo, consent: false),
        throwsA(isA<ApiException>()),
      );
      expect(requests.length, 2);
      await api.enroll(saved, photo, consent: true);
      expect(requests.last.headers['Content-Type'], 'image/jpeg');
      expect(requests.last.bodyBytes, photo);
      await expectLater(
        api.enroll(saved, Uint8List(5 * 1024 * 1024 + 1), consent: true),
        throwsA(isA<ApiException>()),
      );
      for (final r in requests) {
        expect(r.url.origin, 'http://192.168.1.10:8000');
        expect(r.headers['Authorization'], 'Bearer member-test-token');
        expect(r.followRedirects, isFalse);
      }
    },
  );
  test('redirect/auth/conflict errors never leak backend bodies', () async {
    for (final code in [302, 401, 409, 500]) {
      final api = MembersApi(
        connection,
        client: MockClient(
          (_) async => http.Response('secret diagnostic', code),
        ),
      );
      try {
        await api.members();
        fail('must reject');
      } on ApiException catch (e) {
        expect('$e', isNot(contains('secret')));
      } finally {
        api.close();
      }
    }
  });
  test(
    'shared profiles preserve legacy, cache and require face or manual identity',
    () async {
      var remote = [
        const MemberProfile(
          id: 'server-1',
          number: 1,
          name: '奶奶',
          revision: 1,
          faceSampleCount: 3,
          bindings: [
            MemberBinding(
              deviceId: 'fixture-device',
              scope: 'http://192.168.1.10:8000',
            ),
          ],
        ).toJson(),
      ];
      final store = MemorySettingsStore()
        ..settings = connection
        ..householdData = const HouseholdData(
          members: [MemberProfile(id: 'member-1', number: 1, name: '旧档案')],
        );
      final c = SafetyController(
        store: store,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
        membersApiFactory: (settings) => MembersApi(
          settings,
          client: MockClient((r) async {
            if (r.url.path == '/api/faces/status')
              return reply({'enabled': true, 'ready': true});
            if (r.method == 'PUT') {
              final item = Map<String, dynamic>.from(jsonDecode(r.body));
              item['revision'] = (item['revision'] as int) + 1;
              remote = [...remote.where((m) => m['id'] != item['id']), item];
              return reply({'member': item});
            }
            if (r.method == 'DELETE') {
              remote = remote
                  .where((m) => m['id'] != r.url.pathSegments.last)
                  .toList();
              return reply({'deleted': true});
            }
            return reply({'members': remote});
          }),
        ),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await until(() => !c.memberSyncing && c.memberBackendAvailable);
      expect(c.members.single.name, '奶奶');
      expect(c.legacyMembers.single.name, '旧档案');
      expect(
        store
            .householdData!
            .sharedMembers[c.serviceScope]!
            .single
            .faceSampleCount,
        3,
      );
      final event = SafetyEvent.fromJson({
        ...eventJson(id: 'person'),
        'device_id': 'fixture-device',
        'event_type': 'suspected_fall',
      });
      expect(c.memberIdFor(event), isNull);
      final identified = SafetyEvent.fromJson({
        ...event.toJson(),
        'details': {
          'member_id': 'server-1',
          'face_identity': {'status': 'matched'},
        },
      });
      expect(c.memberIdFor(identified), isNull);
      final manual = SafetyEvent.fromJson({
        ...event.toJson(),
        'details': {
          'member_id': 'server-1',
          'manual_association': {
            'status': 'member',
            'provenance': 'manual',
            'member_id': 'server-1',
            'label': '奶奶（人工关联）',
          },
        },
      });
      expect(c.memberIdFor(manual), 'server-1');
      expect(c.associationLabel(manual), '人工关联');
      await c.associateMember(identified, null);
      expect(c.memberIdFor(identified), isNull);
      await c.saveMember(c.members.single.copyWith(name: '王奶奶'));
      expect(c.members.single.name, '王奶奶');
      await c.importLegacyMembers();
      expect(c.members.length, 2);
      expect(c.members.last.id, isNot('member-1'));
      expect(c.household.members.single.name, '旧档案');
      expect(c.legacyMembers, isEmpty);
      await c.importLegacyMembers();
      expect(c.members.length, 2);
      await c.deleteMember('server-1');
      expect(c.memberById('server-1'), isNull);
    },
  );
  test(
    'late old backend response cannot publish profiles to new connection',
    () async {
      final blocked = Completer<http.Response>();
      var calls = 0;
      final store = MemorySettingsStore()..settings = connection;
      final c = SafetyController(
        store: store,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
        membersApiFactory: (settings) => MembersApi(
          settings,
          client: MockClient((r) async {
            if (r.url.path == '/api/faces/status')
              return reply({'enabled': false});
            if (settings.baseUrl == connection.baseUrl) {
              calls++;
              return blocked.future;
            }
            return reply({
              'members': [
                const MemberProfile(id: 'new', number: 1, name: '新后端').toJson(),
              ],
            });
          }),
        ),
      );
      addTearDown(c.dispose);
      final init = c.initialize();
      await until(() => calls > 0);
      await c.applyConnection(
        const AppSettings(
          baseUrl: 'http://192.168.1.20:8000',
          bearerToken: 'other-token',
        ),
      );
      blocked.complete(
        reply({
          'members': [const MemberProfile(id: 'old', number: 1).toJson()],
        }),
      );
      await init;
      await until(() => !c.memberSyncing);
      expect(c.members.single.id, 'new');
      expect(c.memberById('old'), isNull);
    },
  );
  test(
    'failed old profile refresh cannot disable a successful newer save',
    () async {
      final blocked = Completer<http.Response>();
      var waitForOld = false;
      var member = const MemberProfile(
        id: 'm-one',
        number: 1,
        name: '旧名称',
        revision: 1,
      );
      final c = SafetyController(
        store: MemorySettingsStore()..settings = connection,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
        membersApiFactory: (settings) => MembersApi(
          settings,
          client: MockClient((r) async {
            if (r.url.path == '/api/faces/status')
              return reply({'enabled': false});
            if (r.method == 'PUT') {
              member = MemberProfile.fromJson({
                ...jsonDecode(r.body),
                'revision': 2,
              });
              return reply({'member': member.toJson()});
            }
            if (waitForOld) return blocked.future;
            return reply({
              'members': [member.toJson()],
            });
          }),
        ),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await until(() => !c.memberSyncing && c.memberBackendAvailable);
      waitForOld = true;
      final oldRefresh = c.refreshMembers(force: true);
      await Future<void>.delayed(Duration.zero);
      await c.saveMember(member.copyWith(name: '新名称'));
      blocked.complete(http.Response('old failure', 500));
      await oldRefresh;
      expect(c.members.single.name, '新名称');
      expect(c.memberBackendAvailable, isTrue);
      expect(c.canEditMembers, isTrue);
      expect(c.memberSyncError, isNull);
    },
  );

  test(
    'refresh started during a save cannot replace the committed profile',
    () async {
      final saving = Completer<http.Response>(),
          refreshing = Completer<http.Response>();
      var blockRefresh = false, putStarted = false, getStarted = false;
      final original = const MemberProfile(
        id: 'm-race',
        number: 1,
        name: '旧名称',
        revision: 1,
      );
      final c = SafetyController(
        store: MemorySettingsStore()..settings = connection,
        repositoryFactory: (_) => RecordingRepository(),
        videoApiFactory: emptyVideoApi,
        membersApiFactory: (settings) => MembersApi(
          settings,
          client: MockClient((r) async {
            if (r.url.path == '/api/faces/status')
              return reply({'enabled': false});
            if (r.method == 'PUT') {
              putStarted = true;
              return saving.future;
            }
            if (blockRefresh) {
              getStarted = true;
              return refreshing.future;
            }
            return reply({
              'members': [original.toJson()],
            });
          }),
        ),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await until(() => !c.memberSyncing && c.memberBackendAvailable);
      final updated = original.copyWith(name: '新名称', revision: 2);
      final save = c.saveMember(original.copyWith(name: '新名称'));
      await until(() => putStarted);
      blockRefresh = true;
      final refresh = c.refreshMembers(force: true);
      await until(() => getStarted);
      saving.complete(reply({'member': updated.toJson()}));
      await save;
      refreshing.complete(
        reply({
          'members': [original.toJson()],
        }),
      );
      await refresh;
      expect(c.members.single.name, '新名称');
      expect(c.members.single.revision, 2);
    },
  );

  testWidgets('compact list and detail work at 320px with large text', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = SafetyController(
      store: MemorySettingsStore(),
      repositoryFactory: (_) => RecordingRepository(),
      videoApiFactory: emptyVideoApi,
    );
    addTearDown(c.dispose);
    await c.initialize();
    c.setActive(false);
    await c.addMember();
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('成员监护')),
          body: MembersScreen(
            controller: c,
            openEvent: (_) {},
            openDevices: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('成员监护'), findsOneWidget);
    await t.tap(find.text('成员1'));
    await t.pumpAndSettle();
    expect(find.text('成员详情'), findsOneWidget);
    expect(find.text('编辑档案'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('家庭联系人'));
    await t.pumpAndSettle();
    expect(find.text('接收提醒的人'), findsNothing);
    expect(find.text('备用提醒延迟'), findsOneWidget);
    expect(find.textContaining('超时升级'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
