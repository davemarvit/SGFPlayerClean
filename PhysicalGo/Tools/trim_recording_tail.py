#!/usr/bin/env python3
"""Trim a reviewed, repetitive recording tail. Dry run unless --apply is given.

The caller must inspect the images and logs to select the last meaningful frame.
Keep at least 30 seconds after that frame plus the final image. Preserve all
non-image events, references, calibration, and original metadata in an audit.
No automatic visual similarity threshold is sufficient to decide that a subtle
stone movement or a delayed removal is meaningless.
"""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import time
import uuid


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.tmp-' + uuid.uuid4().hex)
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def trim(folder, after_frame, keep_seconds=30, apply=False):
    folder = Path(folder).absolute()
    if keep_seconds < 30 or not math.isfinite(keep_seconds):
        raise ValueError('Keep at least 30 seconds after the reviewed event.')
    for path in [folder, folder/'session.json', folder/'events.jsonl', folder/'frames']:
        if path.is_symlink():
            raise ValueError('Refusing linked archive paths.')
    with os.fdopen(os.open(folder/'.writer.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600), 'r+') as lease:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        manifest = json.loads((folder/'session.json').read_text())
        if manifest.get('schemaVersion') != 1 or manifest.get('status') not in ('complete', 'failed'):
            raise ValueError('Only completed or failed diagnostic recordings can be trimmed.')
        original = (folder/'events.jsonl').read_text()
        rows = [json.loads(line) for line in original.splitlines() if line.strip()]
        frames = [row for row in rows if row.get('event') == 'frame']
        anchor = next(row for row in frames if row['frameID'] == after_frame)
        cutoff = anchor['captureUptime'] + keep_seconds
        if not math.isfinite(cutoff):
            raise ValueError('Invalid camera timestamp.')
        last = max(frames, key=lambda row: row['captureUptime'])
        selected = [row for row in frames if row['captureUptime'] > cutoff and row is not last]
        paths = []
        for row in selected:
            relative = Path(row['image'])
            if len(relative.parts) != 2 or relative.parts[0] != 'frames' or relative.suffix != '.png':
                raise ValueError('Unexpected image path; no images deleted.')
            path = folder/relative
            if path.is_symlink() or not path.is_file():
                raise ValueError('Missing or linked image; no images deleted.')
            paths.append(path)
        result = dict(folder=str(folder), afterFrame=after_frame, keepSeconds=keep_seconds,
                      cutoffUptime=cutoff, finalFrameRetained=last['frameID'],
                      images=[str(p.relative_to(folder)) for p in paths],
                      bytes=sum(p.stat().st_size for p in paths), applied=False)
        if not apply or not paths:
            return result
        audit = folder/('tail-trim-' + uuid.uuid4().hex)
        audit.mkdir()
        (audit/'session-before.json').write_bytes((folder/'session.json').read_bytes())
        (audit/'events-before.jsonl').write_text(original)
        atomic_json(audit/'audit.json', result)
        for row in selected:
            # Replay readers select event==frame. Keep the full original row and
            # correlation ID without inviting them to open a removed image.
            row['event'] = 'image trimmed'
            row['originalEvent'] = 'frame'
            row['retentionReason'] = 'Reviewed repetitive tail; diagnostic post-roll and final image retained'
        rows.append(dict(event='recording tail trimmed', time=time.time(), audit=audit.name,
                         afterFrame=after_frame, keepSeconds=keep_seconds, imagesRemoved=len(paths)))
        temporary = audit/'events-after.jsonl'
        temporary.write_text(''.join(json.dumps(row, sort_keys=True)+'\n' for row in rows))
        os.replace(temporary, folder/'events.jsonl')
        for path in paths:
            path.unlink()
        manifest['trimmedImages'] = manifest.get('trimmedImages', 0) + len(paths)
        manifest['lastTailTrimAudit'] = audit.name
        atomic_json(folder/'session.json', manifest)
        result.update(applied=True, audit=str(audit))
        atomic_json(audit/'audit.json', result)
        return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('--after-frame', type=int, required=True)
    parser.add_argument('--keep-seconds', type=float, default=30)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    print(json.dumps(trim(args.recording, args.after_frame, args.keep_seconds, args.apply), indent=2))
