import 'package:flutter_test/flutter_test.dart';
import '../../lib/services/notifications/alert_gate.dart';
import 'gate_scenarios.dart' show MemoryNoticeStore, snapshot;

void main() {
  test(
    'registered family accounts independently get a new handled alert',
    () async {
      final store = MemoryNoticeStore();
      final first = AlertNotificationGate(
        store: store,
        scope: 'family',
        accountId: 'first',
      );
      final second = AlertNotificationGate(
        store: store,
        scope: 'family',
        accountId: 'second',
      );
      for (final gate in [first, second]) {
        expect(await gate.accept([snapshot(1)], historical: true), isEmpty);
      }
      expect(
        await first.accept([snapshot(2)], historical: false),
        hasLength(1),
      );
      final handled = snapshot(
        2,
        revision: 2,
        handling: 'acknowledged',
        notification: 'cancelled',
      );
      expect(await second.accept([handled], historical: false), hasLength(1));
      expect(await first.accept([handled], historical: false), isEmpty);
      expect(await second.accept([handled], historical: false), isEmpty);
      expect(
        await second.accept([
          snapshot(3, notification: 'skipped_history'),
        ], historical: false),
        isEmpty,
      );
    },
  );
}
