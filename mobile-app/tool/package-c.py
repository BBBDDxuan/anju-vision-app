"""Optional local mobile-source export; package/ is ignored and never uploaded.
The canonical C backend is maintained separately in the website repository.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/c-notifications/package'
BASE = json.loads((ROOT / 'docs/c-notifications/baseline.json').read_text(encoding='utf8'))['base_commit']


def include(name):
    if not name.startswith(('mobile-app/', 'docs/c-notifications/')):
        return False
    if name.startswith(('docs/c-notifications/package/', 'docs/c-notifications/builds/')):
        return False
    parts = Path(name).parts
    if any(p in {'.git', '.dart_tool', 'build', '__pycache__', '.pytest_cache', 'node_modules', 'tools', 'logs', 'reports'} for p in parts):
        return False
    if Path(name).name in {'.env', 'key.properties', 'local.properties', 'google-services.json', 'GoogleService-Info.plist', 'firebase_options.dart'}:
        raise RuntimeError('Credential/config file unexpectedly selected; refusing package')
    if Path(name).suffix.lower() in {'.pem', '.key', '.jks', '.keystore', '.apk', '.zip', '.sqlite3', '.db', '.pyc'}:
        raise RuntimeError('Private or generated file unexpectedly selected; refusing package')
    return True


def main():
    raw = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-co', '--exclude-standard', '-z'])
    names = sorted({p.decode('utf8') for p in raw.split(b'\0') if p and include(p.decode('utf8'))})
    if not names:
        raise RuntimeError('No source files found')
    files = []
    for name in names:
        candidate = ROOT / name
        if candidate.is_symlink() or not candidate.is_file() or not candidate.resolve().is_relative_to(ROOT.resolve()):
            raise RuntimeError('Non-regular source path rejected')
        files.append((name, candidate.read_bytes()))
    manifest = {
        'kind': 'local-mobile-source-only', 'requires_app_base': BASE,
        'version': '1.2.2+7', 'apk_included': False, 'real_phone_tested': False,
        'files': {name: hashlib.sha256(data).hexdigest() for name, data in files},
    }
    OUT.mkdir(parents=True, exist_ok=True)
    archive = OUT / 'AnjuVision-1.2.2-C-source.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in files:
            z.writestr(name, data)
        z.writestr('C-SOURCE-MANIFEST.json', json.dumps(manifest, ensure_ascii=False, indent=2))
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise RuntimeError('ZIP integrity failure')
        for name, digest in manifest['files'].items():
            if hashlib.sha256(z.read(name)).hexdigest() != digest:
                raise RuntimeError('Archived file hash mismatch')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (OUT / 'SHA256.txt').write_text(digest + '  ' + archive.name + '\n', encoding='ascii')
    print(json.dumps({'archive': str(archive), 'sha256': digest, 'files': len(files), 'bytes': archive.stat().st_size, 'integrity_verified': True}, ensure_ascii=False))


if __name__ == '__main__':
    main()
