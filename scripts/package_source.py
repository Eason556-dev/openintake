#!/usr/bin/env python3
"""Create a deterministic, audited source-only release. Never package the working directory wholesale."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import zipfile
from check_public_files import issues

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--out', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', args.version):
        parser.error('Use a semantic version, such as 0.7.2')
    # Tracked plus non-ignored untracked files; ignored developer overrides never enter the archive.
    names = subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
    contents = {}
    for name in sorted(set(filter(None,names))):
        path = ROOT / name
        if path.is_symlink(): raise SystemExit(f'Refusing symbolic link: {name}')
        if not path.is_file(): continue
        data = path.read_bytes()
        found = issues(name,data)
        if found: raise SystemExit(f'Public-file audit failed: {name} ({len(found)} findings; values omitted)')
        if name.startswith(('dist/','.git/')) or name.endswith(('.zip','.tar.gz')):
            raise SystemExit(f'Refusing generated archive: {name}')
        contents[name] = data
    required = ['README.md','README.zh-CN.md','LICENSE','OpenIntake.xcodeproj/project.pbxproj','Config/Local.example.xcconfig']
    for name in required:
        if name not in contents: raise SystemExit(f'Missing required release file: {name}')
    manifest = {'version':args.version,'kind':'unsigned-source-only','files':{
        name:hashlib.sha256(data).hexdigest() for name,data in contents.items()}}
    contents['SOURCE_MANIFEST.json'] = (json.dumps(manifest,indent=2,sort_keys=True)+'\n').encode()
    args.out.mkdir(parents=True,exist_ok=True)
    archive = args.out / f'OpenIntake-{args.version}-source.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as output:
        for name,data in sorted(contents.items()):
            entry = zipfile.ZipInfo(f'OpenIntake-{args.version}-source/{name}',date_time=(2026,1,1,0,0,0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = (0o100755 if name.endswith('.sh') else 0o100644) << 16
            output.writestr(entry,data)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_suffix('.zip.sha256')
    checksum.write_text(f'{digest}  {archive.name}\n')
    # Verify archive contents independently before reporting success.
    with zipfile.ZipFile(archive) as output:
        if output.testzip() is not None: raise SystemExit('ZIP integrity check failed')
        prefix = f'OpenIntake-{args.version}-source/'
        saved = json.loads(output.read(prefix+'SOURCE_MANIFEST.json'))
        for name,digest in saved['files'].items():
            if hashlib.sha256(output.read(prefix+name)).hexdigest()!=digest:
                raise SystemExit(f'Archive manifest mismatch: {name}')
    print(f'Created {archive.name}: {len(manifest["files"])} audited source files, {archive.stat().st_size} bytes')
    print(f'SHA-256: {hashlib.sha256(archive.read_bytes()).hexdigest()}')

if __name__=='__main__': main()
