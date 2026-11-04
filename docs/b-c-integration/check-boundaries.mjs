// B/C integration check: C's original B-hash freeze applies to C development,
// whereas B now legitimately edits its own entrypoints to assemble C's modules.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
const root = fileURLToPath(new URL('../../', import.meta.url));
const baseline = '778a2b7b07907d1bafcb4162264bb41e519bd294';
const git = args => execFileSync('git', ['-c', 'core.quotepath=false', '-C', root, ...args], {encoding: 'utf8'}).trim();
const allowed = new Set([
  'mobile-app/lib/main.dart', 'mobile-app/lib/app.dart',
  'mobile-app/lib/app_controller.dart', 'mobile-app/assets/manual.json',
  'mobile-app/lib/ui/settings_screen.dart', 'mobile-app/lib/ui/manual_screen.dart',
  'mobile-app/pubspec.yaml',
  'mobile-app/lib/services/app_notification_binding.dart',
  'mobile-app/test/notification_integration_test.dart',
]);
const paths = new Set([
  ...git(['diff', '--name-only', baseline]).split('\n'),
  ...git(['ls-files', '--others', '--exclude-standard']).split('\n'),
].filter(Boolean));
for (const path of paths) assert(allowed.has(path) ||
  path.startsWith('docs/b-c-integration/') ||
  path.startsWith('docs/c-notifications/builds/'), `Unexpected integration modification: ${path}`);
const protectedPaths = [
  'mobile-app/android', 'mobile-app/pubspec.lock',
  'mobile-app/lib/services/notifications', 'mobile-app/lib/services/push_service.dart',
  'mobile-app/lib/services/android_notices.dart', 'mobile-app/lib/firebase_bootstrap.dart',
  'mobile-app/test/notifications', 'mobile-app/tool',
];
assert.equal(git(['diff', '--name-only', baseline, '--', ...protectedPaths]), '');
const originalPubspec = git(['show', `${baseline}:mobile-app/pubspec.yaml`]);
const currentPubspec = fs.readFileSync(path.join(root, 'mobile-app/pubspec.yaml'), 'utf8').trim();
assert.equal(currentPubspec.replace(/^version:.*$/m, 'version: CHECKED').replaceAll('\r\n', '\n'),
  originalPubspec.replace(/^version:.*$/m, 'version: CHECKED').replaceAll('\r\n', '\n'));
assert.match(currentPubspec, /^version: 1\.2\.2\+4007$/m);
assert.equal(git(['check-ignore', 'mobile-app/android/key.properties']), 'mobile-app/android/key.properties');
console.log(JSON.stringify({passed: true, c_baseline: baseline, changed_paths: [...paths], c_modules_native_rtsp_and_lockfile_unchanged: true}, null, 2));
