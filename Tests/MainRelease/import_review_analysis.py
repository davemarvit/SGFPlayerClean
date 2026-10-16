#!/usr/bin/env python3
"""Stage verified legacy analysis copies. Originals, preferences and backups are never modified.

v3 did not record engine identity. Migration therefore checks retained app assets,
current default-engine settings and executable age; runtime additionally checks
positions, rules and komi. This is conservative provenance, not proof of all past
settings. Custom engine/model configurations are skipped. Run without --apply first.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import tempfile
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        f.write(data)
        temporary = Path(f.name)
    temporary.replace(path)


def prepare(main_app, cache_root, preferences_root, review_archives, executable, apply=False):
    resources = main_app / 'Contents/Resources'
    assets = {name: (resources / name).read_bytes() for name in ('kata1-b18.bin.gz', 'analysis.cfg')}
    identity = digest(('katago-cache-v4\n' + '\n'.join([
        digest(executable.read_bytes()), digest(assets['kata1-b18.bin.gz']), digest(assets['analysis.cfg'])])).encode())
    domains = [
        ('main', 'com.davemarvit.SGFPlayerClean', 'SGFPlayerClean', None),
        ('ogs-review', 'com.davemarvit.SGFPlayerClean.ogs-review', 'com.davemarvit.SGFPlayerClean.ogs-review', '02-SGF Player OGS Review.zip'),
        ('offline-review', 'com.davemarvit.SGFPlayerClean.offline-review', 'com.davemarvit.SGFPlayerClean.offline-review', '01-SGF Player Offline Review.zip')]
    report = {'engineIdentity': identity, 'applied': apply, 'sources': []}
    main_preferences = preferences_root / 'com.davemarvit.SGFPlayerClean.plist'
    main_settings = plistlib.loads(main_preferences.read_bytes()) if main_preferences.exists() else {}
    if any(main_settings.get(key) for key in ('customKataGoPath', 'customAIModelPath')):
        raise ValueError('Main app uses custom engine/model settings; no legacy caches imported')
    for label, domain, folder, archive_name in domains:
        result = {'source': label, 'copiedFiles': [], 'skippedFiles': []}
        report['sources'].append(result)
        prefs = preferences_root / (domain + '.plist')
        settings = plistlib.loads(prefs.read_bytes()) if prefs.exists() else {}
        if any(settings.get(key) for key in ('customKataGoPath', 'customAIModelPath')):
            result['skippedReason'] = 'Custom engine/model settings cannot be verified'; continue
        if archive_name:
            with zipfile.ZipFile(review_archives / archive_name) as archive:
                for name, current in assets.items():
                    matches = [n for n in archive.namelist() if not n.startswith('__MACOSX/') and n.endswith('/Contents/Resources/' + name)]
                    if len(matches) != 1 or digest(archive.read(matches[0])) != digest(current):
                        raise ValueError(f'{label}: retained {name} differs from main app')
        target = cache_root / 'SGFPlayerClean/AICache/ReviewImports' / label
        hashes = {}
        for source in sorted((cache_root / folder / 'AICache').glob('v3-*.json')):
            data = source.read_bytes()
            if source.stat().st_mtime < executable.stat().st_mtime:
                result['skippedFiles'].append(source.name); continue
            try:
                value = json.loads(data)
                if not all(value.get(k) for k in ('analyses', 'fingerprints', 'contextFingerprint')):
                    raise ValueError('Incomplete legacy cache')
            except (ValueError, TypeError):
                result['skippedFiles'].append(source.name); continue
            hashes[source.name] = digest(data)
            result['copiedFiles'].append(source.name)
            if apply:
                atomic_write(target / source.name, data)
        manifest = {'engineIdentity': identity, 'files': hashes,
                    'provenance': 'Matched retained model/config, default engine settings, executable predates cache; positions validated on load.'}
        if apply:
            # Manifest is written last: interrupted migration cannot approve partial files.
            atomic_write(target / 'manifest.json', (json.dumps(manifest, indent=2) + '\n').encode())
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--main-app', type=Path, required=True)
    parser.add_argument('--review-archives', type=Path, required=True)
    parser.add_argument('--cache-root', type=Path, default=Path.home() / 'Library/Caches')
    parser.add_argument('--preferences-root', type=Path, default=Path.home() / 'Library/Preferences')
    parser.add_argument('--executable', type=Path, default=Path('/opt/homebrew/bin/katago'))
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    print(json.dumps(prepare(args.main_app, args.cache_root, args.preferences_root, args.review_archives,
                             args.executable, args.apply), indent=2))
