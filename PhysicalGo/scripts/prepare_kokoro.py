#!/usr/bin/env python3
"""Prepare a pinned, self-contained Kokoro model and lexicon. Never called at runtime."""
from pathlib import Path
import hashlib, json, plistlib, shutil, tarfile, tempfile, urllib.request
root=Path(__file__).resolve().parents[1]
models=root/'Resources/Kokoro'
archive_sha='0d24bbf80526456bd8640f9f484cd1c333aee8a936e618ac44e619eafb79aec9'
if not all((models/p).exists() for p in ['kokoro_frontend.mlmodelc','kokoro_backend.mlmodelc','voices/af_heart.bin']):
    models.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='physical-go-voice-') as folder:
        archive=Path(folder)/'models.tar.gz'
        urllib.request.urlretrieve('https://github.com/Jud/kokoro-coreml/releases/download/models-2026-03-23/kokoro-models.tar.gz',archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=archive_sha:raise RuntimeError('Kokoro archive checksum mismatch')
        with tarfile.open(archive) as package:package.extractall(models,filter='data')
for p in list(models.rglob('._*')):p.unlink()
for p in (models/'voices').iterdir():
    if p.name!='af_heart.bin':p.unlink()
bundle=root/'Resources/KokoroResources.bundle';bundle.mkdir(parents=True,exist_ok=True)
for p in (root/'Vendor/KokoroCoreML/Sources/Resources').iterdir():shutil.copy2(p,bundle/p.name)
# Application vocabulary augments the pinned upstream dictionary. Unknown words
# otherwise fall back to letter names (not a neural pronunciation guess).
overrides=json.loads((root/'Resources/KokoroPronunciations.json').read_text())
if not all(isinstance(word,str) and isinstance(phonemes,str) and phonemes for word,phonemes in overrides.items()):
    raise ValueError('Invalid Kokoro pronunciation override')
gold=bundle/'us_gold.json'
lexicon=json.loads(gold.read_text());lexicon.update(overrides)
gold.write_text(json.dumps(lexicon,ensure_ascii=False,indent=2)+'\n')
(bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.davemarvit.PhysicalGo.KokoroResources','CFBundleName':'KokoroResources','CFBundlePackageType':'BNDL'}))
shutil.copy2(root/'Vendor/KokoroCoreML/LICENSE',models/'LICENSE')
shutil.copy2(root/'Vendor/KokoroCoreML/provenance.json',models/'provenance.json')
