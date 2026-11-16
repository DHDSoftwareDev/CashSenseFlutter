#!/usr/bin/env python3
"""Install this source update only onto the reviewed or already-updated files."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def install(project, package):
    project = project.expanduser().resolve()
    if not (project / 'pubspec.yaml').is_file():
        raise ValueError('The project must contain pubspec.yaml.')
    entries = json.loads((package / 'manifest.json').read_text())['files']
    changes = []
    for item in entries:
        rel = Path(item['path'])
        if rel.is_absolute() or '..' in rel.parts:
            raise ValueError('Invalid package path.')
        target = project / rel
        if not target.resolve().is_relative_to(project):
            raise ValueError('A source path points outside the project.')
        incoming = package / 'files' / rel
        if digest(incoming) != item['updated_sha256']:
            raise ValueError('Package verification failed: ' + str(rel))
        actual = digest(target)
        if actual == item['updated_sha256']:
            continue
        if actual not in {item['reviewed_sha256'], item.get('previous_update_sha256', item['reviewed_sha256'])}:
            raise ValueError('Source changed since review; no files installed: ' + str(rel))
        changes.append((target, incoming, rel))
    if not changes:
        print('Already installed: all updated files match.')
        return
    backup_root = project.parent / 'CashSenseSourceBackups'
    backup_root.mkdir(exist_ok=True)
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-')
    backup = Path(tempfile.mkdtemp(prefix='account-transition-' + stamp, dir=backup_root))
    applied = []
    temporary_path = None
    try:
        for target, incoming, rel in changes:
            saved = backup / rel
            if target.exists():
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, saved)
            applied.append((target, saved))
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temporary:
                temporary.write(incoming.read_bytes())
                temporary_path = Path(temporary.name)
            temporary_path.replace(target)
            temporary_path = None
        for target, incoming, rel in changes:
            if digest(target) != digest(incoming):
                raise OSError('Installed file verification failed: ' + str(rel))
    except Exception:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()
        for target, saved in reversed(applied):
            if saved.exists():
                shutil.copy2(saved, target)
            elif target.exists():
                target.unlink()
        raise
    print(f'Installed and verified {len(changes)} source files.')
    print('Original source backup: ' + str(backup))
    print('Simulator and physical-device data were not modified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    args = parser.parse_args()
    try:
        install(args.project, Path(__file__).resolve().parent)
    except Exception as error:
        parser.exit(1, 'STOP: ' + str(error) + '\n')
