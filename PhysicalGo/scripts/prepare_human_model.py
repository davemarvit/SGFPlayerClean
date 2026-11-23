#!/usr/bin/env python3
"""Install the official KataGo HumanSL weights with a pinned SHA-256."""
from pathlib import Path
import hashlib
import urllib.request

URL = 'https://github.com/lightvector/KataGo/releases/download/v1.15.0/b18c384nbt-humanv0.bin.gz'
SHA256 = '637746e44f0efe00ad1245a50aa9bbf0716efe364c43965ead97bd6835d84ab5'
path = Path(__file__).resolve().parents[1] / 'Resources/AI/b18c384nbt-humanv0.bin.gz'

def digest(file):
    with file.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

if path.exists() and digest(path) == SHA256:
    print('HumanSL model verified:', path)
else:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.download')
    try:
        urllib.request.urlretrieve(URL, temporary)
        if digest(temporary) != SHA256:
            raise SystemExit('HumanSL checksum mismatch; existing model preserved.')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    print('HumanSL model installed:', path)
