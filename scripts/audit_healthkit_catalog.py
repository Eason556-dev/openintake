#!/usr/bin/env python3
"""Compare EVERY public Dietary quantity identifier with the core nutrition catalogue.
No personal health data is accessed. Run with an installed Apple SDK.
"""
import argparse, csv, re, subprocess
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--sdk', default='iphoneos')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
sdk = Path(subprocess.check_output(['xcrun', '--sdk', args.sdk, '--show-sdk-path'], text=True).strip())
header = sdk / 'System/Library/Frameworks/HealthKit.framework/Headers/HKTypeIdentifiers.h'
rows = []
for line in header.read_text().splitlines():
    match = re.search(r'HKQuantityTypeIdentifier const (HKQuantityTypeIdentifierDietary\w+).*?// (.*)', line)
    if match:
        rows.append((match[1], match[2]))
root = Path(__file__).resolve().parents[1]
enum = (root/'Sources/IntakeCore/Models.swift').read_text().split('public enum Nutrient:')[1].split('public var healthKitIdentifier')[0]
names = []
for cases in re.findall(r'case (.*)', enum):
    names.extend(x.strip() for x in cases.split(','))
core = {'HKQuantityTypeIdentifierDietary'+name[0].upper()+name[1:] for name in names}
non_mass = {'HKQuantityTypeIdentifierDietaryEnergyConsumed', 'HKQuantityTypeIdentifierDietaryWater'}
expected = {row[0] for row in rows}
assert expected, 'SDK catalogue not found'
assert core == expected, f'Missing: {expected-core-non_mass}; Extra: {core-expected}'
assert all('g, Cumulative' == unit for ident, unit in rows if ident in core - non_mass), 'Mass contract changed'
print(f'SDK nutrition catalogue: {len(rows)} types; core nutrition mappings: {len(core)}; energy/water use kcal/mL. PASS')
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w') as f:
        writer = csv.writer(f); writer.writerow(['Apple identifier','SDK unit / aggregation','App nutrition mapping'])
        writer.writerows((ident,unit,ident in core) for ident,unit in rows)
