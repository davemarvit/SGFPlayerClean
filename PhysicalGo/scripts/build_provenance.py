"""Detect release-source changes before an application is signed.

This is a boundary check for the existing release builder, not an immutable
resource snapshot. Shared regressions use private source copies instead.
"""
from dataclasses import dataclass
import fcntl
import hashlib
from pathlib import Path


def acquire_release_lock(build):
    """Caller retains this descriptor through signing; process exit releases it."""
    lock = (Path(build) / 'release-build.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
    except BaseException:
        lock.close()
        raise
    return lock


def file_state(path):
    path = Path(path)
    before = path.stat()
    data = path.read_bytes()
    after = path.stat()
    def stamp(info):
        return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns
    if stamp(before) != stamp(after):
        raise RuntimeError(f'Source changed while reading build input: {path}')
    return (*stamp(after), hashlib.sha256(data).hexdigest()), data


@dataclass(frozen=True)
class SourceState:
    paths: tuple
    fingerprints: tuple
    content_hash: str

    @classmethod
    def capture(cls, paths):
        paths = tuple(Path(p).resolve() for p in paths)
        fingerprints = []
        digest = hashlib.sha256()
        for path in paths:
            fingerprint, data = file_state(path)
            fingerprints.append(fingerprint)
            digest.update(data)
        result = cls(paths, tuple(fingerprints), digest.hexdigest())
        result.assert_unchanged(paths)
        return result

    def assert_unchanged(self, paths):
        paths = tuple(Path(p).resolve() for p in paths)
        if paths != self.paths:
            raise RuntimeError('Application source inventory/order changed; refusing to sign this build')
        for path, expected in zip(self.paths, self.fingerprints):
            try:
                current, _ = file_state(path)
            except OSError as error:
                raise RuntimeError(f'Application source unavailable; refusing to sign: {path}') from error
            if current != expected:
                raise RuntimeError(f'Application source changed; refusing to sign: {path}')
