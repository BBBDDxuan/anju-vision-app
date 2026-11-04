// Verify C ownership; non-C files must match the original source or B published hashes.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const baseline=JSON.parse(fs.readFileSync(path.join(root,'docs/c-notifications/baseline.json'),'utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const allowed=p=>/^(docs\/c-notifications\/|\.github\/workflows\/mobile-[^/]+\.ya?ml$|mobile-app\/(tool\/|lib\/services\/notifications\/|test\/notifications\/|test\/android_notices_test\.dart$|lib\/services\/(push_service|android_notices)\.dart$|lib\/firebase_bootstrap\.dart$|android\/|pubspec\.(yaml|lock)$|README\.md$|\.gitignore$))/.test(p);
const git=args=>execFileSync('git',['-c','core.quotepath=false','-C',root,...args],{encoding:'utf8'}).trim().split('\n').filter(Boolean);
const b=JSON.parse(fs.readFileSync(path.join(root,baseline.b_manifest),'utf8'));
if(b.backend_commit!==baseline.backend_commit||b.baseline_app_commit!==baseline.base_commit)throw Error('Upstream baseline mismatch');
const expected={...baseline.files};
for(const change of b.changes){
 if(allowed(change.path)||!change.path.startsWith('mobile-app/'))throw Error('B manifest overlaps C ownership');
 expected[change.path]=change.sha256;
}
// The user explicitly requested this focused A/B evidence fix on 2026-11-04.
// Keep the original B manifest intact; only these exact task file hashes may differ.
const phaseScope=JSON.parse(fs.readFileSync(path.join(root,'docs/c-notifications/evidence-selection-scope.json'),'utf8'));
const phasePaths=['mobile-app/lib/models/unified_alert.dart','mobile-app/lib/ui/event_detail_screen.dart','mobile-app/test/evidence_selection_test.dart'];
if(JSON.stringify(Object.keys(phaseScope.files).sort())!==JSON.stringify(phasePaths.sort()))throw Error('Unexpected evidence exception scope');
const approved=p=>phaseScope.files[p]&&fs.existsSync(path.join(root,p))&&hash(path.join(root,p))===phaseScope.files[p];
const violations=[];
let preserved=0;
for(const [p,digest] of Object.entries(expected)){
 if(allowed(p)||approved(p))continue;
 if(!fs.existsSync(path.join(root,p))||hash(path.join(root,p))!==digest)violations.push(p);
 else preserved++;
}
const changed=[...git(['diff','--name-only',baseline.base_commit]),...git(['ls-files','--others','--exclude-standard'])];
for(const p of changed){
 if(allowed(p)||approved(p))continue;
 if(expected[p]&&fs.existsSync(path.join(root,p))&&hash(path.join(root,p))===expected[p])continue;
 violations.push(p);
}
if(violations.length){console.error('ABC SCOPE VIOLATION:',[...new Set(violations)]);process.exit(1);}
console.log(JSON.stringify({passed:true,base_commit:baseline.base_commit,non_C_files_verified:preserved,B_files_verified:b.changes.length,B_commit:baseline.b_commit,changed_or_imported_paths:changed.length,user_requested_evidence_paths:phasePaths.length},null,2));
