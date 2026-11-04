import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/models/household.dart';
import 'package:elder_safety_mobile/services/object_api.dart';

const service = String.fromEnvironment('ORIGINAL_OBJECT_QA_URL');
void main() {
  test(
    'live original backend query, memory, replay, frame and video address',
    () async {
      final api = ObjectApi(const ObjectServiceConfig(baseUrl: service));
      try {
        final recording = (await api.recordings()).firstWhere(
          (r) => r.id == 'qa-video',
        );
        final memory = await api.memory(recording.id);
        final object = memory.objectRecords(service).single;
        expect(object.name, '钥匙');
        final answer = await api.query(
          recording.id,
          '钥匙最后在哪里？',
          entityId: object.entityId,
        );
        expect(answer['answer'].toString(), contains('测试桌面'));
        final replay = await api.replay(recording.id, object.entityId);
        expect(replay['entries'], isNotEmpty);
        final frame = memory.frames.first;
        final bytes = await api.frame(frame['url'] as String);
        expect(bytes.take(2), [255, 216]);
        expect(api.videoUri(recording.id).path, '/media/videos/qa-video');
      } finally {
        api.close();
      }
    },
    skip: service.isEmpty
        ? 'Run only against tool/original_api_fixture.py'
        : false,
  );
}
