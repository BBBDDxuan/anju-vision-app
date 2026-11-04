import 'package:flutter_test/flutter_test.dart';
import 'package:elder_safety_mobile/models/models.dart';
import 'package:elder_safety_mobile/services/api.dart';
import 'fixtures/safety_repository.dart';

void main() {
  test(
    'test fixture implements authoritative idempotent ack and resolve states',
    () async {
      final repository = FixtureSafetyRepository();
      addTearDown(repository.close);
      final event = await repository.addEvent();
      expect(event.state, 'detected');
      expect(event.severity, 'critical');
      expect(event.eventType, 'suspected_fall');
      await repository.acknowledge(event.id);
      expect((await repository.event(event.id)).state, 'acknowledged');
      await repository.resolve(event.id);
      await repository.acknowledge(event.id);
      await repository.resolve(event.id);
      final resolved = await repository.event(event.id);
      expect(resolved.resolved, isTrue);
      expect(resolved.acknowledged, isTrue);
      final direct = await repository.addEvent();
      await repository.resolve(direct.id);
      expect((await repository.event(direct.id)).acknowledged, isTrue);
      await expectLater(
        repository.event('missing'),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'fixture preferences and events are isolated between test instances',
    () async {
      final first = FixtureSafetyRepository();
      final second = FixtureSafetyRepository();
      addTearDown(first.close);
      addTearDown(second.close);
      const prefs = FamilyPreferences(
        escalationSeconds: 120,
        notificationsEnabled: false,
        contacts: [],
      );
      await first.savePreferences(prefs);
      await first.addEvent();
      expect((await first.preferences()).toJson(), prefs.toJson());
      expect(
        (await second.preferences()).toJson(),
        FamilyPreferences.defaults.toJson(),
      );
      expect((await first.events()).length, 6);
      expect((await second.events()).length, 5);
    },
  );
}
