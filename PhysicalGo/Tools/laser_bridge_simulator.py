#!/usr/bin/env python3
"""Hardware-free reference consumer for Physical Go laser bridge v1.
Never imports serial/camera modules, moves motors, or illuminates a laser.
Run while Physical Go's Connect laser bridge toggle is enabled.
"""
import argparse
import json
import math
import os
from pathlib import Path
import time
import uuid


class Simulator:
    def __init__(self):
        self.producer = None
        self.sequence = -1
        self.fingerprint = None
        self.state = 'off'
        self.off_since = time.time()
        self.detail = 'No request'
        self.cancelled_through = -1
        self.requires_new_revision = False
        self.lease_token = None
        self.lease_deadline = None

    def off(self, detail, now):
        if self.state != 'off':
            self.off_since = now
        self.state = 'off'
        self.detail = detail

    def consume(self, request, now, monotonic=None):
        mono = time.monotonic() if monotonic is None else monotonic
        if self.state != 'off' and self.lease_deadline is not None and mono >= self.lease_deadline:
            self.cancelled_through=max(self.cancelled_through,self.sequence)
            self.requires_new_revision=True
            self.off('Monotonic lease expired; new revision required',now)
        producer = seq = None
        try:
            assert request['schemaVersion'] == 1
            producer = str(uuid.UUID(request['producer'])).upper()
            seq = request['sequence']
            assert type(seq) is int and seq >= 0
            sent, expiry = request['sentAtUnix'], request['expiresAtUnix']
            assert all(type(v) in (int, float) and math.isfinite(v) for v in (sent, expiry))
            assert sent <= now < expiry and 0 < expiry-sent <= 0.7
            lease_token=(producer,seq,sent,expiry)
            if lease_token != self.lease_token:
                if self.lease_token is not None and lease_token[:2] == self.lease_token[:2]:
                    assert sent > self.lease_token[2]
                self.lease_token=lease_token
                self.lease_deadline=mono+(expiry-now)
            if request.get('streamEpoch') is not None:
                uuid.UUID(request['streamEpoch'])
            action = request['action']
            assert action in ('point', 'off')
            target = request.get('target')
            if target is not None:
                assert target['source'] in ('ai', 'online')
                uuid.UUID(target['session'])
                size, row, col = (target[k] for k in ('size', 'row', 'col'))
                assert all(type(v) is int for v in (size, row, col, target['moveNumber']))
                assert size in (9, 13, 19) and 0 <= row < size and 0 <= col < size
                assert target['moveNumber'] > 0 and type(target['black']) is bool
                assert math.isfinite(target['decisionReceivedAtUnix']) and target['decisionReceivedAtUnix'] <= now
            if action == 'point':
                assert target is not None and request.get('cameraContext')
            fingerprint = json.dumps([action, target, request.get('cameraContext'), request.get('streamEpoch')], sort_keys=True)
            if producer != self.producer:
                # A fresh producer must start with an OFF handshake.
                self.off('New app session; waiting for OFF handshake', now)
                assert action == 'off'
                self.producer, self.sequence, self.fingerprint = producer, -1, None
                self.cancelled_through = -1; self.requires_new_revision = False
            assert seq >= self.sequence
            if seq == self.sequence:
                assert fingerprint == self.fingerprint
            self.sequence, self.fingerprint = seq, fingerprint
            if action == 'off':
                self.off(request.get('reason', 'off'), now)
            else:
                assert seq > self.cancelled_through
                self.requires_new_revision = False
                self.state = 'adequate'
                self.detail = 'Simulated target row %d, column %d; no hardware' % (target['row'], target['col'])
        except (AssertionError, KeyError, ValueError, TypeError, OverflowError):
            if producer == self.producer and type(seq) is int and seq >= 0:
                self.sequence = max(self.sequence, seq)
            self.cancelled_through = max(self.cancelled_through, self.sequence)
            self.requires_new_revision = True
            self.off('Invalid, stale, or changed request; output off', now)
        return self.status(now)

    def status(self, now):
        return dict(schemaVersion=1, producer=self.producer, sequence=self.sequence,
                    updatedAtUnix=now, mode='simulation', state=self.state,
                    laserOn=False, offSinceUnix=self.off_since if self.state == 'off' else None,
                    detail=self.detail, requiresNewRevision=self.requires_new_revision)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path.home()/'Library/Application Support/Physical Go/LaserBridge')
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    import fcntl
    lock = (args.directory/'driver.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    simulator = Simulator()
    last = None
    def publish(status):
        if status['producer'] is None:
            return
        temp = args.directory/('status.%d.tmp' % os.getpid())
        temp.write_text(json.dumps(status)+'\n')
        temp.replace(args.directory/'status.json')
    try:
        while True:
            now = time.time()
            try:
                request = json.loads((args.directory/'request.json').read_text())
                status = simulator.consume(request, now)
            except (OSError, ValueError):
                simulator.cancelled_through=max(simulator.cancelled_through,simulator.sequence)
                simulator.requires_new_revision=True
                simulator.off('Request missing or unreadable', now)
                status = simulator.status(now)
            publish(status)
            event = (status['state'], status['detail'])
            if event != last:
                print(json.dumps(status), flush=True)
                last = event
            time.sleep(.05)
    finally:
        simulator.off('Simulator stopped', time.time())
        publish(simulator.status(time.time()))
        lock.close()


if __name__ == '__main__':
    main()
