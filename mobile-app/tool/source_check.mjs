// Dependency-free consistency checks; this is NOT a Dart parser or Flutter test.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const walk = dir => fs.readdirSync(dir, {withFileTypes: true}).flatMap(e =>
  e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
const dartFiles = [...walk(path.join(root, 'lib')), ...walk(path.join(root, 'test'))]
  .filter(p => p.endsWith('.dart'));
const manifest = read('pubspec.yaml');
let imports = 0;
for (const file of dartFiles) {
  const text = fs.readFileSync(file, 'utf8');
  assert(!/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(text), 'Control character: ' + file);
  for (const match of text.matchAll(/(?:import|export|part)\b[^'"\r\n]*['"]([^'"]+)['"]/g)) {
    const uri = match[1];
    imports++;
    if (uri.startsWith('dart:')) continue;
    if (uri.startsWith('package:elder_safety_mobile/')) {
      assert(fs.existsSync(path.join(root, 'lib', uri.slice('package:elder_safety_mobile/'.length))), uri);
    } else if (uri.startsWith('package:')) {
      const name = uri.slice(8).split('/')[0];
      assert(new RegExp('^  ' + name + ':', 'm').test(manifest), 'Undeclared package: ' + name);
    } else {
      assert(fs.existsSync(path.resolve(path.dirname(file), uri)), 'Missing relative import: ' + uri);
    }
  }
}
assert(!/^\s*(import|export|part).*firebase_options\.dart/m.test(read('lib/firebase_bootstrap.dart')));
assert(!read('lib/firebase_bootstrap.dart').includes("import 'firebase_options.dart'"));
assert(/bool\.fromEnvironment\(\s*'USE_FIREBASE',\s*defaultValue:\s*false,?\s*\)/.test(read('lib/services/push_service.dart')));
assert(read('lib/services/settings_store.dart').includes('http://127.0.0.1:8000'));
assert(read('lib/models/unified_alert.dart').includes('class AlertSyncSnapshot'));
assert(read('lib/app_controller.dart').includes('alertSnapshots'));
assert(!read('lib/services/api.dart').includes(':8000'));
assert(read('lib/models/household.dart').includes('http://127.0.0.1:8000'));
assert(read('lib/models/household.dart').includes('this.useCloud = false'));
assert(read('lib/models/models.dart').includes("field(json, 'device_id'"));
assert(read('lib/models/models.dart').includes("reviewText(json['review_summary'])"));
for (const state of ['detected', 'notified', 'acknowledged', 'resolved']) {
  assert(read('lib/ui/widgets.dart').includes("'" + state + "'"));
}
for (const file of ['README.md', 'tool/scaffold_platforms.ps1', 'test/controller_test.dart',
  'test/widget_test.dart', 'test/fixture_repository_test.dart']) assert(fs.existsSync(path.join(root, file)), file);
for (const file of walk(path.join(root, 'lib')).filter(p => p.endsWith('.dart'))) {
  const source = fs.readFileSync(file, 'utf8');
  assert(!/demoMode|DemoSafetyRepository|simulateEvent/.test(source), 'Production demo code: ' + file);
}
assert(!read('lib/ui/widgets.dart').includes("'smoke_detected' =>"));
console.log(JSON.stringify({status:'passed', dartFiles:dartFiles.length, importsChecked:imports,
  checks:['relative/package imports', 'declared packages', 'no missing generated Firebase import',
    'Firebase default disabled', 'unified API port 8000 and B snapshot interface', 'backend field/state mappings', 'required files'],
  notExecuted:['Dart parsing/compiler', 'flutter pub get', 'flutter analyze', 'flutter test', 'platform builds']}, null, 2));

assert(!manifest.includes('image_picker:'));
assert(!manifest.includes('onnxruntime:'));
for (const file of ['lib/ui/camera_screen.dart','lib/ui/video_workspace_screen.dart','lib/services/media_api.dart']) assert(fs.existsSync(path.join(root,file)));
