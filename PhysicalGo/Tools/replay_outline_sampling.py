#!/usr/bin/env python3
"""Offline temporal regression of the fixed outline-mask feature experiment.

No parameter search, app imports, clock commands, or future-frame features.
Both recent games are development evidence. Older rapid-play replay preserves
its hand/gap/capture guards and original timestamp metadata.
"""
import argparse
import json
from pathlib import Path

import numpy as np

from evaluate_unavailable_shadow import Pixels, old_replays
from fresh_game_confidence import ordered_readings
from local_quality_lab import digest, read_image
from outline_sampling_experiment import eligible, geometry
from placement_competition_lab import appearance_features
from recognition_parameter_search import write_json
from unchanged_baseline_lab import Observation, features
from unavailable_shadow_lab import assess, measured_contrast


class OutlinePixels(Pixels):
    def __init__(self, shapes):
        super().__init__()
        self.shapes = shapes
        self.reference_images = {}

    def augment(self, path, calibration, reference, reference_calibration, appearances):
        shapes = eligible(self.shapes.get(str(path), []))
        if not shapes:
            return super().augment(path, calibration, reference, reference_calibration, appearances)
        core, _, gray = self.samples(path, calibration)
        current = read_image(Path(path), calibration)
        key = (str(reference), json.dumps(reference_calibration, sort_keys=True))
        if key not in self.reference_images:
            self.reference_images[key] = read_image(Path(reference), reference_calibration)
        old = self.reference_images[key]
        self.inputs.add(Path(reference))
        old_core, _ = self.reference(reference, reference_calibration)
        excluded = geometry(gray.shape, shapes)[2]
        indices = [index[~excluded[index]] for index in self.sampler.wood]
        flat = np.where(current[1], gray, np.nan).ravel()
        old_flat = np.where(old[1], old[0], np.nan).ravel()
        wood, old_wood = [flat[i] for i in indices], [old_flat[i] for i in indices]
        metrics = features(core, wood, old_core, old_wood)
        appearance = appearance_features(Observation(0, 0, False, False, [], core, metrics), old_core)
        for point, item in enumerate(appearance):
            item['measuredCoreDelta'] = measured_contrast(core[point], old_core[point], item)
        return appearance


def focused(snapshot, windows, output):
    frames, operations = {}, {}
    for line in (snapshot/'capture/events.jsonl').open():
        item = json.loads(line)
        frame = item.get('frameID', -1)
        if not any(first <= frame <= last for _, _, first, last in windows):
            continue
        if item['event'] == 'frame':
            frames[frame] = item
        elif item['event'] == 'operation finished':
            operations[frame] = item
    shapes = {str(snapshot/'capture'/frames[f]['image']): op.get('footprints', [])+op.get('placementFits', [])
              for f, op in operations.items()}
    original, masked = Pixels(), OutlinePixels(shapes)
    rows = []
    for frame, op in sorted(operations.items()):
        meta = frames[frame]
        path, reference = snapshot/'capture'/meta['image'], snapshot/'capture'/meta['referenceImage']
        readings = op.get('unadaptedReadings') or op.get('readings', [])
        if len(readings) != 361:
            continue
        raw = ordered_readings(readings)
        core, wood, _ = original.samples(path, op['calibration'])
        old_core, old_wood = original.reference(reference, meta['referenceCalibration'])
        baseline = appearance_features(Observation(frame, meta['captureUptime'], False, False, [], core,
                                                  features(core, wood, old_core, old_wood)), old_core)
        variants = {name: pixels.augment(path, op['calibration'], reference, meta['referenceCalibration'], baseline)
                    for name, pixels in [('original', original), ('outline_mask', masked)]}
        for name, point, first, last in windows:
            if not first <= frame <= last:
                continue
            row = {'case': name, 'frame': frame, 'point': point, 'capturedAt': meta['captureUptime'],
                   'hand': op.get('handOutline', {}).get('obstructed'), 'outcome': op['outcome'],
                   'lightingBlocked': bool(op.get('lightingBlocked') or op.get('exposureFailure')),
                   'reading': raw[point], 'clockAuthority': False}
            for variant, values in variants.items():
                row[variant] = assess('contrast_black', point, raw[point], values[point], shapes[str(path)])
            rows.append(row)
    write_json(output/'focused-observations.json', rows)
    result = {}
    for name, point, _, _ in windows:
        selected = [r for r in rows if r['case'] == name]
        def strong(r, variant):
            return (r['hand'] is False and not r['lightingBlocked'] and r['outcome'] == 'delivered to recorder'
                    and r['reading']['occupancy'] == 'black' and r[variant]['support'] >= .65)
        result[name] = {'point': point, 'observations': len(selected),
                        'originalStrongClearFrames': [r['frame'] for r in selected if strong(r, 'original')],
                        'maskedStrongClearFrames': [r['frame'] for r in selected if strong(r, 'outline_mask')],
                        'lostStrongClearFrames': [r['frame'] for r in selected if strong(r, 'original') and not strong(r, 'outline_mask')],
                        'scope': 'Point support over time; not a legal move decoder or timing authority.'}
    write_json(output/'focused-summary.json', result)
    return result, original.inputs | masked.inputs | {snapshot/'capture/events.jsonl'}


def main(args):
    if args.output.resolve().is_relative_to(Path(__file__).resolve().parents[2]):
        raise ValueError('Use external storage')
    args.output.mkdir(parents=True, exist_ok=False)
    write_json(args.output/'plan.json', {'status': 'OFFLINE DEVELOPMENT ONLY',
        'feature': 'Frozen outline-mask parameters from outline_sampling_experiment.py; no tuning.',
        'policies': 'Unchanged existing contrast/neutral controls.',
        'safeguards': 'Preserve hand/gap/exposure/capture/opposite-color guards, timestamps and no-clock-authority.',
        'limits': 'Focused windows have no new full-frame ground truth. Missed-hand injections are faults, not proof of an empty view.'})
    sequence = json.loads(args.sequence.read_text())
    metadata = {f['frameID']: f for f in sequence['frames']}
    boards = json.loads((args.corpus/'timeline/boards.json').read_text())
    shape_map = {b['image']: metadata.get(int(b['id']), {}).get('footprints', [])+metadata.get(int(b['id']), {}).get('placementFits', []) for b in boards}
    summaries, inputs = {}, {args.sequence, args.corpus/'timeline/boards.json',
                             args.previous/'observations.jsonl', args.previous/'appearance-evidence.jsonl'}
    for name, pixels in [('original', Pixels()), ('outline_mask', OutlinePixels(shape_map))]:
        folder = args.output/name
        folder.mkdir()
        summaries[name] = old_replays(args.previous, sequence, args.corpus, pixels, folder)
        inputs |= pixels.inputs
    keys = ('state', 'selected', 'firstSeen', 'firstSupported', 'confirmedAt', 'witnesses',
            'recordedFrameTiming', 'clockAuthority', 'reasons')
    comparisons = {}
    for policy in ('neutral', 'contrast_black'):
        original = [json.loads(l) for l in (args.output/'original'/f'rapid-{policy}.jsonl').open()]
        masked = [json.loads(l) for l in (args.output/'outline_mask'/f'rapid-{policy}.jsonl').open()]
        assert len(original) == len(masked)
        changes = []
        for a, b in zip(original, masked):
            assert (a['scenario'], a['context'], a['frame']) == (b['scenario'], b['context'], b['frame'])
            assert a['result']['recordedFrameTiming'] == b['result']['recordedFrameTiming']
            assert b['result']['clockAuthority'] is False
            if any(a['result'][k] != b['result'][k] for k in keys):
                changes.append({'scenario': a['scenario'], 'context': a['context'], 'frame': a['frame'],
                                'original': a['result'], 'masked': b['result']})
        write_json(args.output/f'{policy}-changes.json', changes)
        comparisons[policy] = {'rows': len(original), 'changedDecisionTimingRows': len(changes)}
    focus = {}
    for name, snapshot, windows in [
        ('game85', args.game85, [('real-black13', 23, 449, 518), ('edge341a', 56, 330, 355),
                               ('edge341b', 94, 330, 355), ('edge605', 189, 590, 620),
                               ('edge978', 246, 965, 995), ('edge1981', 265, 1965, 1995)]),
        ('game65', args.game65, [('real-black21', 73, 520, 575), ('edge1281', 75, 1230, 1330)])]:
        folder = args.output/name
        folder.mkdir()
        focus[name], sources = focused(snapshot, windows, folder)
        inputs |= sources
    result = {'status': 'offline only', 'rapidReplay': summaries, 'comparisons': comparisons, 'focused': focus}
    write_json(args.output/'summary.json', result)
    inputs.update(Path(__file__).with_name(n) for n in ('replay_outline_sampling.py', 'outline_sampling_experiment.py',
        'evaluate_unavailable_shadow.py', 'unavailable_shadow_lab.py', 'unavailable_shadow_protocol.json',
        'placement_competition_lab.py', 'placement_competition_protocol.json', 'unchanged_baseline_lab.py', 'local_quality_lab.py', 'local_quality_labels.json'))
    write_json(args.output/'manifest.json', {'inputs': {str(p): digest(p) for p in sorted(inputs)}})
    print(json.dumps({'comparisons': comparisons, 'focused': focus}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('output', 'previous', 'sequence', 'corpus', 'game85', 'game65'):
        parser.add_argument('--'+name, type=Path, required=True)
    main(parser.parse_args())
