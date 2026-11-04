import 'package:flutter_test/flutter_test.dart';

import 'gate_scenarios.dart';

void main() {
  test('persistent scoped notice gate covers history, repeats, restart, concurrency and failure', () async {
    expect(await runGateScenarios(), 37);
  });
}
