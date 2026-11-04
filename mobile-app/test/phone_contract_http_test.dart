import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'package:elder_safety_mobile/services/media_api.dart';
import 'package:elder_safety_mobile/models/household.dart';

const backend = String.fromEnvironment('B_CONTRACT_URL');
const videoPath = String.fromEnvironment('B_CONTRACT_VIDEO');
const fixtureToken = 'b-contract-fixture-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

void main() {
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
