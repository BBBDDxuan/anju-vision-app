// Source-scope/configuration gate for the local updater; not an Android build.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const baseline = '836ea9e91c2b58919accd820ddb95e2ca0ad7024';
const gitExe = process.env.GIT_EXE || 'git';
const git = (...args) => execFileSync(gitExe, ['-c', 'core.excludesFile=', ...args], {cwd: root, encoding: 'utf8'});
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const allowed = new Set([
  '.gitignore',
  'docs/LOCAL_APP_UPDATES.md',
  'mobile-app/tool/check-app-update-scope.mjs',
  'mobile-app/android/app/src/main/AndroidManifest.xml',
  'mobile-app/android/app/src/main/kotlin/com/eldersafety/elder_safety_mobile/MainActivity.kt',
  'mobile-app/android/app/src/main/kotlin/com/eldersafety/elder_safety_mobile/AppUpdateBridge.kt',
  'mobile-app/android/app/src/main/res/xml/update_paths.xml',
  'mobile-app/assets/manual.json',
  'mobile-app/lib/app.dart',
  'mobile-app/lib/ui/settings_screen.dart',
  'mobile-app/lib/services/app_updates.dart',
  'mobile-app/lib/ui/app_update_screen.dart',
  'mobile-app/pubspec.yaml',
  'mobile-app/test/app_updates_test.dart',
]);
const changed = [...new Set([
  ...git('diff', '--name-only', '-z', baseline).split('\0'),
  ...git('ls-files', '--others', '--exclude-standard', '-z').split('\0'),
].filter(Boolean))];
for (const file of changed) {
  assert(allowed.has(file), `Unexpected changed file: ${file}`);
  assert(!/\.(apk|zip|jks|keystore)$/i.test(file), `Private artifact: ${file}`);
}
const pubspec = 'mobile-app/pubspec.yaml';
const originalPubspec = git('show', `${baseline}:${pubspec}`);
assert.equal(read(pubspec).replace(/^version:.*$/m, 'version: BASE').replace(/\r\n/g, '\n'), originalPubspec.replace(/^version:.*$/m, 'version: BASE').replace(/\r\n/g, '\n'));
assert.match(read(pubspec), /^version: 1\.2\.4\+4009\r?$/m);
const activityPath = 'mobile-app/android/app/src/main/kotlin/com/eldersafety/elder_safety_mobile/MainActivity.kt';
const activity = read(activityPath);
const updateLines = activity.split(/\r?\n/).filter(line => /appUpdateBridge/.test(line));
assert.equal(updateLines.length, 5);
assert.equal(activity.split(/\r?\n/).filter(line => !/appUpdateBridge/.test(line)).join('\n'), git('show', `${baseline}:${activityPath}`).replace(/\r\n/g, '\n'));
const manifest = read('mobile-app/android/app/src/main/AndroidManifest.xml');
assert.match(manifest, /android.permission.REQUEST_INSTALL_PACKAGES/);
assert.match(manifest, /android:authorities="\$\{applicationId\}\.app_updates" android:exported="false"/);
const paths = read('mobile-app/android/app/src/main/res/xml/update_paths.xml');
assert.match(paths, /<cache-path\s+name="app_updates"\s+path="updates\/"\s*\/>/);
assert(!/<(?:root|external|files)-path/.test(paths));
const manual = JSON.parse(read('mobile-app/assets/manual.json'));
assert.equal(manual.version, '1.2.4');
console.log(`Local updater scope/config passed (${changed.length} changed paths); Android build and device upgrade require separate validation.`);
