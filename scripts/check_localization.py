#!/usr/bin/env python3
"""Check literal L10n keys, placeholder parity and English UI resources.

Chinese OCR aliases, comments, fixtures and user data are deliberately not UI keys.
This lexical check complements runtime localization tests; it is not a Swift parser.
"""
from pathlib import Path
import json, re, subprocess, sys
ROOT = Path(__file__).resolve().parents[1]
def table(lang):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(ROOT / f'Shared/Resources/{lang}.lproj/Localizable.strings')]))
def literal(text, start):
    i, result, count = start + 1, '', 0
    while i < len(text):
        if text[i] == '"': return result, i + 1
        if text[i:i+2] == '\\(':
            depth = 1; i += 2
            while i < len(text) and depth:
                if text[i] == '"': _, i = literal(text, i); continue
                if text[i] == '(': depth += 1
                elif text[i] == ')': depth -= 1
                i += 1
            result += '{' + str(count) + '}'; count += 1
        elif text[i] == '\\' and i + 1 < len(text):
            result += {'n':'\n','r':'\r','t':'\t'}.get(text[i+1],text[i+1]); i += 2
        else: result += text[i]; i += 1
    raise ValueError('Unterminated Swift string')
def main():
    en, zh = table('en'), table('zh-Hans'); failures=[]; checked=0
    for directory in ['App','Shared','WatchApp','WatchWidgets','Widgets','Sources/IntakeCore']:
        for path in (ROOT/directory).glob('*.swift'):
            source=path.read_text()
            for match in re.finditer(r'L10n\.(?:tr|display)\(\s*"',source):
                key,_=literal(source,match.end()-1)
                if not re.search('[\u4e00-\u9fff]',key):continue
                checked+=1
                if key not in en or key not in zh: failures.append(f'{path.relative_to(ROOT)}: missing {key!r}')
    for key,value in en.items():
        if re.search('[\u4e00-\u9fff]',value):failures.append(f'English contains Chinese: {key!r}')
        if sorted(re.findall(r'\{\d+\}',key))!=sorted(re.findall(r'\{\d+\}',value)):failures.append(f'Placeholder mismatch: {key!r}')
    # Optional generated App Intents metadata also contains system editor labels and summaries.
    def metadata_keys(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in ('key', 'formatString') and isinstance(item, str) and re.search('[\u4e00-\u9fff]',item): yield item
                elif isinstance(item, (dict, list)): yield from metadata_keys(item)
        elif isinstance(value, list):
            for item in value: yield from metadata_keys(item)
    for argument in sys.argv[1:]:
        for key in set(metadata_keys(json.loads(Path(argument).read_text()))):
            if key not in en or key not in zh: failures.append(f'App Intents metadata missing: {key!r}')
    for failure in failures: print(failure)
    print(f'Localization audit: {checked} UI key uses, {len(en)} English entries, {len(failures)} failures.')
    return bool(failures)
if __name__=='__main__': sys.exit(main())
