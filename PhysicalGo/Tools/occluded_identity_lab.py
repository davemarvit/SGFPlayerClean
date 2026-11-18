"""Offline identity hypotheses across a hand visit; never certifies clock presses.

Match bounded outlines, not intersection labels. Each old identity and each fresh
outline must have a unique eligible partner. Retain unmatched identities. Repeated
post-hand evidence supports an association, not proof of physical identity under
occlusion. Native capture/turn facts remain separate authorities.
"""
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class Disk:
    color: str
    x: float
    y: float
    rx: float
    ry: float
    quality: float
    points: frozenset[int]


@dataclass(frozen=True)
class Anchor:
    identity: str
    disk: Disk
    witnesses: tuple[str, ...]
    first: float
    last: float


def distance(a, b):
    return math.hypot(a.x-b.x, a.y-b.y)


def disks_from_row(row, size=19):
    """Preserve fractional centers and merge duplicate fits of the same outline.

    Color comes from original raw readings. Unknown-color outlines abstain; no
    color is borrowed from the supplied game. No centering cutoff is imposed.
    """
    result = []
    for shape in row['shapes']:
        point = shape['row']*size+shape['col']
        color, confidence = row['raw'][point]
        x, y = shape['center']['x'], shape['center']['y']
        rx, ry, quality = shape['radiusCol'], shape['radiusRow'], shape['quality']
        if (color not in ('black', 'white') or confidence < .9 or quality < .9 or
                not all(math.isfinite(v) for v in (x, y, rx, ry, quality)) or
                not .30 <= rx <= .65 or not .30 <= ry <= .65):
            continue
        disk = Disk(color, x, y, rx, ry, quality, frozenset([point]))
        match = next((i for i, old in enumerate(result) if old.color == color and
                      distance(old, disk) < .18 and abs(rx-old.rx) < .12 and abs(ry-old.ry) < .12), None)
        if match is None:
            result.append(disk)
        else:
            old = result[match]
            best = disk if disk.quality > old.quality else old
            result[match] = Disk(color, best.x, best.y, best.rx, best.ry, best.quality, old.points|disk.points)
    return tuple(result)


class OccludedIdentityBridge:
    def __init__(self, anchors, *, epoch, maximum_motion=.65, maximum_gap=.75):
        anchors = tuple(anchors)
        if len({a.identity for a in anchors}) != len(anchors):
            raise ValueError('Duplicate identity anchors')
        if any(len(set(a.witnesses)) < 3 or a.last-a.first < .4 for a in anchors):
            raise ValueError('Anchors need sustained independent pre-hand observations')
        self.anchors = {a.identity: a for a in anchors}
        self.epoch, self.maximum_motion, self.maximum_gap = epoch, maximum_motion, maximum_gap
        self.last = max((a.last for a in anchors), default=None)
        self.seen = set(w for a in anchors for w in a.witnesses)
        self.hand_seen = False
        self.interrupted = None
        self.retired = set()
        self.runs = {}
        self.hypotheses = {}
        self.audit = []

    def observe(self, identity, time, disks, *, hand, epoch, lighting_ok=True,
                gap_before=False, captured=()):
        if identity in self.seen:
            return
        if not math.isfinite(time) or (self.last is not None and time <= self.last):
            raise ValueError('Recording timestamps must increase')
        gap = gap_before or (self.last is not None and time-self.last > self.maximum_gap)
        self.last = time
        self.seen.add(identity)
        self.retired.update(captured)
        for token in self.retired:
            self.runs.pop(token, None)
            self.hypotheses.pop(token, None)
        if gap or epoch != self.epoch:
            self.interrupted = 'missing recording evidence' if gap else 'camera/setup changed'
        if hand is not False or not lighting_ok or self.interrupted:
            self.runs.clear()
            # Last clear associations remain historical evidence; they are no
            # longer a fresh result a background caller may apply.
            self.hypotheses.clear()
            self.hand_seen |= hand is True
            self.audit.append({'view': identity, 'time': time, 'state': 'retained without reassignment',
                               'reason': self.interrupted or ('hand or unknown hand state' if hand is not False else 'lighting')})
            return
        if not self.hand_seen:
            return  # A missing hand flag cannot manufacture a covered episode.
        active = {i: a for i, a in self.anchors.items() if i not in self.retired}
        by_identity, by_disk = {}, {}
        for token, anchor in active.items():
            for index, disk in enumerate(disks):
                if (disk.color == anchor.disk.color and distance(disk, anchor.disk) <= self.maximum_motion and
                        abs(disk.rx-anchor.disk.rx) <= .12 and abs(disk.ry-anchor.disk.ry) <= .12):
                    by_identity.setdefault(token, []).append(index)
                    by_disk.setdefault(index, []).append(token)
        matches = {token: indices[0] for token, indices in by_identity.items()
                   if len(indices) == 1 and len(by_disk[indices[0]]) == 1}
        # A coherent displacement of several independent anchors is possible
        # camera/board movement, not many simultaneous stone cleanups.
        motions = [(disks[d].x-active[i].disk.x, disks[d].y-active[i].disk.y) for i, d in matches.items()]
        if len(motions) >= 4:
            dx, dy = sorted(v[0] for v in motions)[len(motions)//2], sorted(v[1] for v in motions)[len(motions)//2]
            if math.hypot(dx, dy) > .12 and sum(math.hypot(x-dx, y-dy) < .09 for x, y in motions)/len(motions) >= .7:
                self.interrupted = 'possible camera/board movement'
                self.runs.clear()
                self.hypotheses.clear()
                return
        for token in active:
            if token not in matches:
                self.runs.pop(token, None)
                self.hypotheses.pop(token, None)
                continue
            disk = disks[matches[token]]
            run = self.runs.get(token)
            if run is None or distance(run['disk'], disk) > .12:
                run = {'disk': disk, 'first': time, 'witnesses': []}
                self.hypotheses.pop(token, None)
            # Compare to the run's FIRST outline to prevent creeping drift.
            run['witnesses'].append(identity)
            run['witnesses'] = run['witnesses'][-8:]
            self.runs[token] = run
            if len(run['witnesses']) >= 3 and time-run['first'] >= .8:
                self.hypotheses[token] = {
                    'identity': token, 'color': disk.color, 'center': [disk.x, disk.y],
                    'candidatePoints': sorted(disk.points),
                    'displacement': distance(active[token].disk, disk),
                    'firstClearSupport': run['first'], 'confirmedAt': time,
                    'witnesses': list(run['witnesses']), 'lastWitness': identity,
                    'epoch': epoch, 'status': 'supported association hypothesis',
                    'clockAuthority': False, 'physicalIdentityProven': False,
                }
        self.audit.append({'view': identity, 'time': time, 'state': 'clear reassessment',
                           'supported': sorted(self.hypotheses),
                           'unresolved': sorted(set(active)-set(self.hypotheses)),
                           'retiredByCapture': sorted(self.retired)})

    def result(self):
        return {'hypotheses': dict(self.hypotheses),
                'unresolved': sorted(set(self.anchors)-self.retired-set(self.hypotheses)),
                'retired': sorted(self.retired), 'interrupted': self.interrupted,
                'clockCommands': [], 'newTurnEvents': []}
