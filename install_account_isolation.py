#!/usr/bin/env python3
"""Install reviewed source only, with hash checks and external backups."""
import argparse, datetime, hashlib, json, os, shutil, tempfile
from pathlib import Path

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', required=True)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    project = Path(args.project).expanduser().resolve()
    package = Path(__file__).resolve().parent
    manifest = json.loads((package / 'manifest.json').read_text())
    if not (project / 'pubspec.yaml').is_file():
        raise SystemExit('STOP: Flutter project not found.')
    changes = []
    for relative, info in manifest.items():
        target, source = project / relative, package / relative
        if target.is_symlink(): raise SystemExit('STOP: symlink target: ' + relative)
        if digest(source) != info['updated']: raise SystemExit('STOP: package hash mismatch: ' + relative)
        current = digest(target) if target.exists() else None
        if current == info['updated']: continue
        if current not in info['originals']:
            raise SystemExit('STOP: project file changed since review: ' + relative)
        changes.append(relative)
    if args.dry_run:
        print('Preflight passed:', len(changes), 'source/check files would change. No files written.')
        return
    if not changes:
        print('Already installed. No changes needed.'); return
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup = Path.home() / 'CashSense-Source-Backups' / project.name / ('Account-Isolation-' + stamp)
    if backup == project or project in backup.parents:
        raise SystemExit('STOP: source backup must be outside the project.')
    for relative in changes:
        target = project / relative
        if target.exists():
            saved = backup / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, saved)
    written = []
    try:
        for relative in changes:
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            fd, temp = tempfile.mkstemp(prefix='.cashsense-', dir=target.parent)
            try:
                with os.fdopen(fd, 'wb') as stream: stream.write((package / relative).read_bytes())
                os.replace(temp, target)
            finally:
                if os.path.exists(temp): os.unlink(temp)
            written.append(relative)
            print('Updated:', relative)
    except BaseException:
        for relative in reversed(written):
            target, saved = project / relative, backup / relative
            if saved.exists(): shutil.copy2(saved, target)
            else: target.unlink(missing_ok=True)
        raise
    print('Original source backup:', backup)
    print('Next: flutter analyze, then dart run checks/account_storage_check.dart. Fully stop and relaunch the simulator app; do not hot reload.')
    print('No AWS resources or financial records were changed.')
if __name__ == '__main__': main()
