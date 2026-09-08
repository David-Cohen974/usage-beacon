#!/usr/bin/env python3
"""Report own-source line coverage without treating it as a correctness score."""
import json
import os
from pathlib import Path

root = Path(__file__).resolve().parent.parent
reports = list((root / '.build').glob('*-apple-macosx/debug/codecov/UsageBeacon.json'))
if not reports:
    raise SystemExit('No coverage report found. Run swift test --enable-code-coverage first.')
report = max(reports, key=lambda path: path.stat().st_mtime)
payload = json.loads(report.read_text())
source_prefix = str(root / 'Sources') + '/'
files = [entry for data in payload['data'] for entry in data['files']
         if entry['filename'].startswith(source_prefix)]
if not files:
    raise SystemExit('Coverage report contains no sources from this checkout.')

lines = ['## Test coverage', '', '| Instrumented own-source area | Covered lines |', '| --- | ---: |']
for name, selected in [('Including UI', files),
                       ('Excluding UI', [f for f in files if '/UI/' not in f['filename']])]:
    total = sum(f['summary']['lines']['count'] for f in selected)
    covered = sum(f['summary']['lines']['covered'] for f in selected)
    lines.append(f'| {name} | {covered}/{total} ({covered / total:.1%}) |')
lines += ['', 'The WidgetKit extension is not exercised by this test target. Line coverage is not a correctness guarantee.', '',
          '| Source | Covered lines |', '| --- | ---: |']
for entry in sorted(files, key=lambda f: f['filename']):
    stats = entry['summary']['lines']
    name = entry['filename'][len(source_prefix):]
    lines.append(f"| {name} | {stats['covered']}/{stats['count']} ({stats['percent']:.1f}%) |")
text = '\n'.join(lines) + '\n'
print(text)
if summary := os.environ.get('GITHUB_STEP_SUMMARY'):
    with open(summary, 'a') as stream:
        stream.write(text)
