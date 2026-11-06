import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/members_api.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';
import 'package:elder_safety_mobile/ui/member_avatar.dart';

void main() {
  const member = MemberProfile(
    id: 'avatar-test',
    number: 1,
    name: '测试成员',
    relationship: '家人',
    notes: '测试备注',
    revision: 3,
    avatarDataUrl: 'data:image/jpeg;base64,YWJj',
  );
  test(
    'avatar survives offline profile serialization without changing fields',
    () {
      final cached = HouseholdData.fromJson(
        HouseholdData(members: const [member]).toJson(),
      );
      expect(cached.members.single.avatarDataUrl, member.avatarDataUrl);
      expect(
        cached.members.single.copyWith(name: '新名字').avatarDataUrl,
        member.avatarDataUrl,
      );
      expect(cached.members.single.relationship, '家人');
      expect(cached.members.single.notes, '测试备注');
      expect(
        MemberProfile.fromJson({'id': 'old', 'number': 1}).avatarDataUrl,
        '',
      );
    },
  );
  test(
    'avatar upload/delete use household endpoint and current revision; text edits preserve avatar',
    () async {
      final requests = <http.Request>[];
      final api = MembersApi(
        const AppSettings(
          baseUrl: 'http://192.168.1.10:8000',
          bearerToken: 'test-token',
        ),
        client: MockClient((r) async {
          requests.add(r);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({'member': member.copyWith(revision: 4).toJson()}),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      final photo = Uint8List.fromList([255, 216, 255, 1]);
      final saved = await api.saveAvatar(member, photo);
      expect(saved.revision, 4);
      expect(
        requests.last.url.path,
        '/api/household/members/avatar-test/avatar',
      );
      expect(requests.last.url.queryParameters['revision'], '3');
      expect(requests.last.headers['Content-Type'], 'image/jpeg');
      expect(requests.last.headers['Authorization'], 'Bearer test-token');
      expect(requests.last.bodyBytes, photo);
      expect(requests.last.followRedirects, isFalse);
      await api.save(saved);
      expect(
        jsonDecode(requests.last.body).containsKey('avatar_data_url'),
        isFalse,
      );
      await api.saveAvatar(saved, null);
      expect(requests.last.method, 'DELETE');
      expect(requests.last.url.queryParameters['revision'], '4');
      final before = requests.length;
      await expectLater(
        api.saveAvatar(saved, Uint8List(2 * 1024 * 1024 + 1)),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.saveAvatar(saved, Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ApiException>()),
      );
      expect(requests.length, before);
    },
  );
  testWidgets(
    'missing or invalid ordinary avatar keeps readable name fallback',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MemberAvatar(
              member: MemberProfile(id: 'x', number: 2, name: '家人'),
            ),
          ),
        ),
      );
      expect(find.text('家'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MemberAvatar(
              member: MemberProfile(
                id: 'x',
                number: 2,
                name: '家人',
                avatarDataUrl: 'https://untrusted.example/photo.jpg',
              ),
            ),
          ),
        ),
      );
      expect(find.text('家'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
}
