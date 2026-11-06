import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/media_api.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/members_api.dart';
import 'package:elder_safety_mobile/services/settings_store.dart';

const backend = String.fromEnvironment('B_CONTRACT_URL');
const videoPath = String.fromEnvironment('B_CONTRACT_VIDEO');
const fixtureToken = 'b-contract-fixture-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

void main() {
  test(
    'A real HTTP face contract: shared profiles, consent, matching, clear and delete',
    () async {
      final api = MembersApi(
        const AppSettings(baseUrl: backend, bearerToken: fixtureToken),
      );
      addTearDown(api.close);
      var member = await api.save(
        const MemberProfile(
          id: 'b-face-contract',
          number: 31,
          name: '接口测试家人',
          labelColor: '#12ab34',
          labelLetter: '测',
        ),
      );
      final photo = Uint8List.fromList([
        255,
        216,
        255,
        1,
      ]); // Synthetic features in fixture only.
      await expectLater(
        api.enroll(member, photo, consent: false),
        throwsA(isA<ApiException>()),
      );
      await api.enroll(member, photo, consent: true);
      member = (await api.members()).singleWhere((m) => m.id == member.id);
      expect(member.faceSampleCount, 1);
      expect(member.labelLetter, '测');
      var result = await api.recognize(photo);
      expect((result['faces'] as List).single['member_id'], member.id);
      final beforeTrial = member.revision;
      expect(
        (await api.members()).singleWhere((m) => m.id == member.id).revision,
        beforeTrial,
      );
      await api.clearFaces(member.id);
      member = (await api.members()).singleWhere((m) => m.id == member.id);
      expect(member.faceSampleCount, 0);
      expect(member.revision, greaterThan(beforeTrial));
      result = await api.recognize(photo);
      expect((result['faces'] as List).single['status'], 'unknown');
      await api.delete(member);
      expect((await api.members()).any((m) => m.id == member.id), isFalse);
    },
    skip: backend.isEmpty ? 'Requires isolated synthetic face fixture' : false,
  );

  test(
    'A real HTTP contract: two clients, source IDs, evidence, ack and resolve',
    () async {
      final one = UnifiedHttpSafetyRepository(
        baseUrl: backend,
        bearerToken: fixtureToken,
      );
      final two = UnifiedHttpSafetyRepository(
        baseUrl: backend,
        bearerToken: fixtureToken,
      );
      addTearDown(one.close);
      addTearDown(two.close);
      final syncOne = UnifiedAlertSynchronizer(one),
          syncTwo = UnifiedAlertSynchronizer(two);
      final first = await syncOne.synchronize();
      await syncTwo.synchronize();
      expect(first.events.map((e) => e.details['source']).toSet(), {
        'live_camera',
        'uploaded_recording',
      });
      expect(first.events.map((e) => e.id).toSet().length, 2);
      final live = first.events.singleWhere((e) => !e.fromVideo);
      final bytes = await one.mediaImage(live.evidenceId!);
      expect(bytes.take(2), [255, 216]);
      final ack = await one.handleAlert(live.id, resolve: false);
      await syncTwo.synchronize();
      expect(
        syncTwo.events.singleWhere((e) => e.id == live.id).acknowledged,
        isTrue,
      );
      expect(
        (await two.handleAlert(live.id, resolve: false)).revision,
        ack.revision,
      );
      await one.handleAlert(live.id, resolve: true);
      expect((await two.handleAlert(live.id, resolve: false)).resolved, isTrue);
    },
    skip: backend.isEmpty
        ? 'Requires isolated A phone_contract_fixture.py, never production'
        : false,
  );

  test(
    'A real HTTP contract: chunk upload, library, objects job and result',
    () async {
      final api = MediaApi(
        const ObjectServiceConfig(baseUrl: backend, token: fixtureToken),
      );
      addTearDown(api.close);
      final id = await api.uploadVideo(
        File(videoPath),
        'B-SYNTHETIC-CONTRACT.mp4',
        cancellation: UploadCancellation(),
        onProgress: (sent, total) {},
      );
      expect((await api.recordings()).any((v) => v.id == id), isTrue);
      final job = await api.analyze(id, 'objects');
      final jobId = (job['id'] ?? job['job_id']).toString();
      Map<String, dynamic> progress = {};
      for (var n = 0; n < 100; n++) {
        progress = await api.job(jobId);
        if (!['queued', 'running'].contains(progress['status'])) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(
        progress['status'],
        'completed',
        reason: progress['error']?.toString(),
      );
      final result = await api.memory(id);
      expect(result.data['is_mock'], isTrue);
      expect(result.entities, isNotEmpty);
    },
    skip: backend.isEmpty || videoPath.isEmpty
        ? 'Requires temporary synthetic video and A fixture'
        : false,
  );
}
