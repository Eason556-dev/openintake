#!/usr/bin/env python3
"""Check Git publish candidates without printing matched credentials or personal data.

Includes tracked files even when ignored, plus non-ignored untracked files.
Heuristic guard only: review novel credential formats and health fixtures manually.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    'email address (use non-personal documentation instead)': r'[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}',
    'personal home path': r'/(?:Users|home)/[A-Za-z0-9_.-]+/',
    'physical Apple device identifier': r'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b',
    'literal Apple team setting': r'\b(?:DEVELOPMENT_TEAM|DevelopmentTeam)"?\s*=\s*"?[A-Z0-9]{10}\b',
    'literal signing profile setting': r'\bPROVISIONING_PROFILE(?:_SPECIFIER)?"?\s*=\s*"?[^\s;"$][^;\n]*',
    'personal signing identity': r'Apple (?:Development|Distribution|Developer):[^\n;]+',
    'literal bearer token': r'(?i)\bBearer\s+[A-Za-z0-9._~-]{20,}',
    'Google API key': r'\bAIza[A-Za-z0-9_-]{30,}\b',
    'private key': r'-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----',
    'known API token': r'\b(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})\b',
    'literal credential assignment': r'''(?i)\b(?:api[_-]?key|password|access[_-]?token|client[_-]?secret)["']?\s*[:=]\s*["'][A-Za-z0-9_+/=-]{12,}["']''',
}
FORBIDDEN_SUFFIXES = {'.p8', '.p12', '.pfx', '.pem', '.key', '.cer', '.mobileprovision', '.provisionprofile', '.ipa', '.xcuserstate', '.xcactivitylog'}


def issues(path, data):
    p = Path(path)
    result = []
    if (p.suffix.lower() in FORBIDDEN_SUFFIXES or p.name.startswith('.env')
        or p.name == 'library.json' or p.name.startswith('library.json.')
        or path == 'Config/Local.xcconfig' or 'xcuserdata' in p.parts
        or any(x.endswith('.xcarchive') for x in p.parts)):
        result.append('private/local artifact')
    # Compressed binary pixels can coincidentally resemble tokens. PNG metadata is
    # handled below; known credential artifacts remain forbidden regardless of bytes.
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        text = ''
    for label, pattern in PATTERNS.items():
        for m in re.finditer(pattern, text):
            result.append(f'line {text.count(chr(10), 0, m.start()) + 1}: {label}')
    # PNG textual/EXIF chunks may carry author, location or original source paths.
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        offset = 8
        while offset + 12 <= len(data):
            size = int.from_bytes(data[offset:offset + 4], 'big')
            kind = data[offset + 4:offset + 8]
            if kind in (b'tEXt', b'zTXt', b'iTXt', b'eXIf'):
                result.append('image metadata needs removal/review')
            offset += size + 12
    if data.startswith(b'\xff\xd8'):
        offset = 2
        while offset + 4 <= len(data):
            if data[offset] != 255: break
            marker = data[offset + 1]
            if marker == 0xDA: break
            size = int.from_bytes(data[offset + 2:offset + 4], 'big')
            if size < 2 or offset + 2 + size > len(data): break
            if marker == 0xFE or (0xE0 <= marker <= 0xEF and marker not in (0xE0,0xE2,0xEE)):
                result.append('JPEG identifying metadata needs removal/review')
            offset += 2 + size
    return result


def main():
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
    count = failures = 0
    for name in sorted(set(filter(None, names))):
        p = ROOT / name
        if p.is_symlink():
            print(f'{name}: symbolic link requires public-file review')
            failures += 1
            continue
        if not p.is_file():
            continue
        count += 1
        for issue in issues(name, p.read_bytes()):
            print(f'{name}: {issue} [value omitted]')
            failures += 1
    print(f'Public-file check: {count} files, {failures} findings. Ignored local files are not publication candidates.')
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
