// B/C integration check: C's original B-hash freeze applies to C development,
// whereas B now legitimately edits its own entrypoints to assemble C's modules.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
const root = fileURLToPath(new URL('../../', import.meta.url));
// The 2026-11-05 main merge retains C's event-phase evidence fixes.
const baseline = '97815f01856e340fdb4a63b54b3a0d71a11ab275';
const git = args => execFileSync('git', ['-c', 'core.quotepath=false', '-C', root, ...args], {encoding: 'utf8'}).trim();
const allowed = new Set([
  'mobile-app/lib/main.dart', 'mobile-app/lib/app.dart',
  'mobile-app/lib/app_controller.dart', 'mobile-app/assets/manual.json',
  'mobile-app/lib/ui/settings_screen.dart', 'mobile-app/lib/ui/manual_screen.dart',
  'mobile-app/pubspec.yaml',
  'mobile-app/lib/services/app_notification_binding.dart',
  'mobile-app/test/notification_integration_test.dart',
]);
// B's branch adds only these handoff records; the source ZIP is excluded.
const businessDocs = new Set([
  'docs/b-app/B到C接入说明.md', 'docs/b-app/README.md',
  'docs/b-app/SHA256SUMS.txt', 'docs/b-app/b-app-business.patch',
  'docs/b-app/change-manifest.json', 'docs/b-app/交接说明.md',
  'docs/b-app/交给A的问题.md', 'docs/b-app/验证与真机记录.md',
  'docs/b-app/验证记录/b-a-ffmpeg-compatibility.txt',
  'docs/b-app/验证记录/b-analyze.log', 'docs/b-app/验证记录/b-tests.log',
]);
const paths = new Set([
  ...git(['diff', '--name-only', baseline]).split('\n'),
  ...git(['ls-files', '--others', '--exclude-standard']).split('\n'),
].filter(Boolean));
for (const path of paths) assert(allowed.has(path) || businessDocs.has(path) ||
  path.startsWith('docs/b-c-integration/') ||
  path.startsWith('docs/c-notifications/builds/'), `Unexpected integration modification: ${path}`);
assert.equal(git(['ls-files', '--', 'docs/b-app/artifacts/B-App业务改动_20261104.zip']), '');
const protectedPaths = [
  'mobile-app/android', 'mobile-app/pubspec.lock',
  'mobile-app/lib/services/notifications', 'mobile-app/lib/services/push_service.dart',
  'mobile-app/lib/services/android_notices.dart', 'mobile-app/lib/firebase_bootstrap.dart',
  'mobile-app/test/notifications', 'mobile-app/tool',
  'mobile-app/lib/models/unified_alert.dart',
  'mobile-app/lib/ui/event_detail_screen.dart',
  'mobile-app/test/evidence_selection_test.dart',
  'docs/c-notifications/evidence-selection-scope.json',
];
assert.equal(git(['diff', '--name-only', baseline, '--', ...protectedPaths]), '');
const originalPubspec = git(['show', `${baseline}:mobile-app/pubspec.yaml`]);
const currentPubspec = fs.readFileSync(path.join(root, 'mobile-app/pubspec.yaml'), 'utf8').trim();
assert.equal(currentPubspec.replace(/^version:.*$/m, 'version: CHECKED').replaceAll('\r\n', '\n'),
  originalPubspec.replace(/^version:.*$/m, 'version: CHECKED').replaceAll('\r\n', '\n'));
assert.match(currentPubspec, /^version: 1\.2\.2\+4007$/m);
assert.equal(git(['check-ignore', 'mobile-app/android/key.properties']), 'mobile-app/android/key.properties');
console.log(JSON.stringify({passed: true, c_baseline: baseline, changed_paths: [...paths], c_modules_native_rtsp_and_lockfile_unchanged: true}, null, 2));
