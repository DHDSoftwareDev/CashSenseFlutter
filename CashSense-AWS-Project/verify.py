#!/usr/bin/env python3
"""Offline package verification. Never contacts AWS or stores."""
from pathlib import Path
import zipfile, subprocess, sys, os
os.environ.update(AWS_EC2_METADATA_DISABLED="true", AWS_ACCESS_KEY_ID="OFFLINE_TEST_ONLY", AWS_SECRET_ACCESS_KEY="OFFLINE_TEST_ONLY", AWS_REGION="us-east-1")
root=Path(__file__).resolve().parent
for archive in sorted(root.glob('*-deployment.zip')):
    name=archive.name.removesuffix('-deployment.zip')
    with zipfile.ZipFile(archive) as z:
        bad=z.testzip()
        if bad: raise RuntimeError(f'CRC failure: {bad}')
        for item in z.infolist():
            p=Path(item.filename)
            if p.is_absolute() or '..' in p.parts:raise RuntimeError('Unsafe ZIP member')
        z.extractall(root/'source'/name)
    folder=root/'source'/name
    for script in folder.glob('*.mjs'):
        subprocess.run(['node','--check',str(script)],check=True)
    # Import without invoking; no credentials or network requests are needed.
    if name not in ['CashSense-RegisterDevice','CashSense-BackupInit','CashSense-BackupLatest','CashSense-BackupComplete']: subprocess.run(['node','--import',str(root/'tests'/'network-guard.mjs'),'--input-type=module','-e',f'await import({(folder / "index.mjs").as_uri()!r});'],check=True,cwd=root)
    print(f'PASS CRC/syntax/import: {archive.name}',flush=True)
result=subprocess.run(['node','--import',str(root/'tests'/'network-guard.mjs'),'--test',*[str(p) for p in sorted((root/'tests').glob('*.test.mjs'))]],cwd=root)
sys.exit(result.returncode)
