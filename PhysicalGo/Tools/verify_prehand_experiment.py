#!/usr/bin/env python3
"""Verify preserved inputs, feature parity, unchanged app and experiment traces."""
import argparse
import gzip
import hashlib
import json
import plistlib
from pathlib import Path
import sys

from local_quality_lab import digest
from recognition_parameter_search import write_json


def main(args):
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root))
    from scripts.build_sources import resolve_sources
    sources = [root.parent/'SGFPlayerClean/Models'/n for n in ('OGSModels.swift', 'OGSScoringState.swift', 'SGFPlayerEngine.swift')]
    sources = resolve_sources(root, sources+sorted((root/'Sources').glob('*.swift')))
    source_hash = hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest()
    app = Path.home()/'Applications/Physical Go.app/Contents/Info.plist'
    installed_hash = plistlib.loads(app.read_bytes())['PhysicalGoSourceHash']
    assert source_hash == installed_hash == '9b02ccc36ff2ba159ab01f9df195b81c6bed7df86e6dbb409337865db85cdba5'
    frozen = {'unavailable_shadow_lab.py': '1b1c596928568f7932c620249bfcb6ca31d7a996d6ee94f1f7faa13f2e1563f1',
              'unavailable_shadow_protocol.json': '5be0e6b384955c3e07ce2bf43bd983a493225a01489bb336b30ca96367ccdd0c',
              'placement_competition_lab.py': '116bb835f93252ba0978ae39175228a07dbb461b07e167f5d7b10f3326a581ff'}
    for name, expected in frozen.items():
        assert digest(Path(__file__).with_name(name)) == expected
    files = {}
    for manifest in args.stage.rglob('manifest.json'):
        for path, expected in json.loads(manifest.read_text())['inputs'].items():
            key = Path(path).resolve()
            if key in files:
                assert files[key] == expected, str(key)
            files[key] = expected
    preserved = {}
    for snapshot in args.snapshot:
        rows = json.loads((snapshot/'preservation.json').read_text())['files']
        for r in rows:
            path = (snapshot/r['path']).resolve()
            assert path.stat().st_size == r['bytes'], str(path)
            if path in files:
                assert files[path] == r['sha256'], str(path)
            files[path] = r['sha256']
        preserved[snapshot.name] = len(rows)
    for p, expected in files.items():
        assert digest(p) == expected, str(p)
    parity = {}
    for game, geometry in zip(('65', '85'), args.geometry):
        observations = {r['frame']: r for r in map(json.loads, gzip.open(args.stage/f'game{game}-cache/observations.jsonl.gz', 'rt'))}
        count = 0
        for row in json.loads((geometry/'geometry-evidence.json').read_text()):
            current = observations.get(row['frame'])
            if current is None or str(row['point']) not in current['original']:
                continue
            for variant in ('original', 'outline_mask'):
                a, b = current[variant][str(row['point'])], row[variant]
                # Earlier available-appearance rows did not always retain the
                # redundant measured delta. Compare every shared actual metric.
                for key in ('gain', 'coreError', 'woodError', 'woodPixels', 'signedCoreDelta'):
                    assert a[key] == b[key], (game, row['frame'], row['point'], variant, key, a[key], b[key])
                if 'measuredCoreDelta' in b:
                    assert a['measuredCoreDelta'] == b['measuredCoreDelta']
                count += 1
        parity[game] = count
    result = {'status': 'verified; no live promotion', 'appSourceHash': source_hash,
              'installedAppSourceHash': installed_hash, 'frozenPolicyHashes': frozen,
              'preservedFiles': preserved, 'uniqueInputHashesChecked': len(files),
              'exactSparseDensePointVariantComparisons': parity,
              'scope': 'Recognition timing remains observation timing. Native clock/capture suites are recorded separately.'}
    write_json(args.output, result)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage', type=Path, required=True)
    parser.add_argument('--snapshot', type=Path, action='append', required=True)
    parser.add_argument('--geometry', type=Path, action='append', required=True, help='65 then 85 dense geometry results')
    parser.add_argument('--output', type=Path, required=True)
    main(parser.parse_args())
