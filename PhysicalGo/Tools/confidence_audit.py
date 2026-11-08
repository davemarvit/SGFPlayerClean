#!/usr/bin/env python3
"""Paired offline audit. See ConfidenceAudit.md for the label format and examples."""
import argparse
import csv
import hashlib
import json
import math
import statistics
import subprocess
import tempfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests/Fixtures"
MEAN = statistics.mean


def build_engine(executable):
    shared = ROOT.parent / "SGFPlayerClean/Models"
    files = [shared / name for name in ("OGSModels.swift", "OGSScoringState.swift", "SGFPlayerEngine.swift")]
    files += [ROOT / "Sources" / name for name in
              ("BoardVision.swift", "StoneGeometry.swift", "BoardAppearanceDetector.swift", "AutoGridDetector.swift")]
    subprocess.run(["xcrun", "swiftc", "-O", "-whole-module-optimization", "-D", "PHYSICAL_GO",
                    *files, ROOT / "Tools/ConfidenceReplay.swift", "-o", executable], check=True)


def run(engine, *args):
    return json.loads(subprocess.check_output([engine, *args]))


def write_table(path, rows):
    if not rows:
        return
    with path.open("x", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def read_labels(file):
    labels = defaultdict(list)
    keys = set()
    with file.open(newline="") as f:
        for row in csv.DictReader(f):
            for field in ("frame", "point"):
                row[field] = int(row[field])
            key = row["session"], row["frame"], row["point"]
            if key in keys or row["truth"] not in {"empty", "black", "white"} or not row["episode"]:
                raise ValueError(f"Invalid or duplicate label: {key}")
            keys.add(key)
            labels[row["session"]].append(row)
    if not labels:
        raise ValueError("No labels")
    return labels


def measure(row, side, frame, prefix):
    point = row["point"]
    readings = frame[prefix]
    if not 0 <= point < len(readings):
        raise ValueError(f"Point outside board: {point}")
    reading = readings[point]
    row[side] = reading["occupancy"]
    row[side+"_score"] = reading["confidence"]
    fits = [s for s in frame[prefix+"Shapes"] if
            s["row"] == reading["row"] and s["col"] == reading["col"]]
    fit = max(fits, key=lambda f: f["quality"], default=None)
    row[side+"_fit"] = fit["quality"] if fit else None
    for axis, index in (("x", "col"), ("y", "row")):
        row[side+"_d"+axis] = fit["center"][axis] - reading[index] if fit else None


def group_measures(rows, side):
    def rate(pred):
        return MEAN(int(pred(r)) for r in rows)
    occupied = rows[0]["truth"] != "empty"
    strong = [r for r in rows if r[side] == r["truth"] and occupied and
              (r[side+"_fit"] or 0) >= .86]
    # Spread about the median fitted center measures repeatability, not physical center error.
    jitter = None
    if len(strong) >= 2:
        x, y = (statistics.median(r[side+k] for r in strong) for k in ("_dx", "_dy"))
        jitter = statistics.median(math.hypot(r[side+"_dx"]-x, r[side+"_dy"]-y) for r in strong)
    return {side+"_correct_rate": rate(lambda r:r[side] == r["truth"]),
            side+"_uncertain_rate": rate(lambda r:r[side] == "uncertain"),
            side+"_confident_wrong_rate": rate(lambda r:r[side] not in {r["truth"], "uncertain"} and r[side+"_score"] >= .9),
            side+"_outline_rate": len(strong)/len(rows) if occupied else None,
            side+"_median_center_jitter": jitter}


def summarize(rows):
    groups = defaultdict(list)
    for row in rows:
        groups[(row["session"], row["split"], row["point"], row["episode"], row["truth"])].append(row)
    episodes = []
    for (session, split, point, episode, truth), views in sorted(groups.items()):
        matched = [r["new_score"]-r["old_score"] for r in views if r["old"]==r["new"]==truth]
        episodes.append(dict(paired_correct_score_delta=MEAN(matched) if matched else None, session=session, split=split, point=point, episode=episode, truth=truth,
                             observations=len(views), **group_measures(views, "old"), **group_measures(views, "new")))
    report = {}
    for split in sorted({r["split"] for r in rows}):
        subset = [r for r in rows if r["split"] == split]
        units = [e for e in episodes if e["split"] == split]
        common = [r for r in subset if r["old"] == r["new"] == r["truth"]]
        changes = [r["new_score"] - r["old_score"] for r in common]
        metrics = {}
        for side in ("old", "new"):
            states = Counter("correct" if r[side]==r["truth"] else
                             "uncertain" if r[side]=="uncertain" else "wrong" for r in subset)
            states["confident_wrong"] = sum(r[side] not in {r["truth"],"uncertain"} and r[side+"_score"]>=.9 for r in subset)
            bands = {}
            for low, high in ((0,.75),(.75,.90),(.90,1.01)):
                decisions = [r for r in subset if r[side]!="uncertain" and low <= r[side+"_score"] < high]
                bands[str(low)] = dict(calls=len(decisions), correct=sum(r[side]==r["truth"] for r in decisions))
            metrics[side] = dict(counts=dict(states), decision_score_bands=bands)
            for metric in ("correct_rate", "confident_wrong_rate", "outline_rate", "uncertain_rate"):
                values = [e[side+"_"+metric] for e in units if e[side+"_"+metric] is not None]
                metrics[side]["episode_mean_"+metric] = MEAN(values) if values else None
        fit_changes = [r["new_fit"]-r["old_fit"] for r in common if r["truth"]!="empty"
                       and r["old_fit"] is not None and r["new_fit"] is not None]
        deltas = [e["paired_correct_score_delta"] for e in units if e["paired_correct_score_delta"] is not None]
        report[split] = dict(common_correct_outline_up=sum(d>1e-8 for d in fit_changes),
                             common_correct_outline_down=sum(d< -1e-8 for d in fit_changes),
                             common_correct_outline_same=sum(abs(d)<=1e-8 for d in fit_changes),
                             strong_wrong_outlines={side:sum((r[side+"_fit"] or 0)>=.86 and r[side]!=r["truth"]
                                                        for r in subset) for side in ("old","new")},
                             paired_correct_episode_delta=MEAN(deltas) if deltas else None,
                             episodes_up=sum(d>1e-8 for d in deltas), episodes_down=sum(d< -1e-8 for d in deltas),
                             same_wrong_call_score_up=sum(r["old"]==r["new"] and r["old"] not in {r["truth"],"uncertain"}
                                                          and r["new_score"]>r["old_score"]+1e-8 for r in subset),
                             labeled_readings=len(subset), episodes=len(units), metrics=metrics,
                             both_correct_score_up=sum(c>1e-8 for c in changes),
                             both_correct_score_down=sum(c< -1e-8 for c in changes),
                             both_correct_score_same=sum(abs(c)<=1e-8 for c in changes),
                             correct_to_other=sum(r["old"]==r["truth"]!=r["new"] for r in subset))
    return episodes, report


def recorder_audit(engine, journal, reference):
    moves = run(engine, "moves", reference)
    groups = defaultdict(set)
    observed = Counter()
    first_candidate = {}
    inherited = set()
    confirmation_waits = []
    with Path(journal).open() as f:
        for line in f:
            r = json.loads(line)
            if r.get("event") in {"paused", "resumed", "start", "restored saved game"}:
                first_candidate.clear()
                inherited = {int(r["moveCount"])+1+i for i in range(len(r.get("tentativeConfidence", [])))}
            if r.get("event") != "observation" or r.get("state") != "recording":
                continue
            stamp = r.get("uptime")
            for number in list(first_candidate):
                if number <= int(r["moveCount"]) and stamp is not None:
                    confirmation_waits.append(stamp-first_candidate.pop(number))
            for offset, candidate in enumerate(r.get("tentativeConfidence", [])):
                index = int(r["moveCount"]) + offset
                point = candidate.get("point")
                if point is None or index >= len(moves):
                    observed["unscorable"] += 1
                    continue
                level = candidate["level"]
                groups[(index+1, level)].add(point)
                observed["scorable"] += 1
                if point == moves[index] and index+1 not in inherited and stamp is not None:
                    first_candidate.setdefault(index+1,stamp)
    bands = {}
    for level in ("low","medium","high"):
        samples = [(points, moves[i-1]) for (i, band), points in groups.items() if band == level]
        bands[level] = dict(distinct_moves=len(samples), always_agreed_with_reference=sum(p == {ref} for p,ref in samples),
                            ever_disagreed=sum(p != {ref} for p,ref in samples))
    return dict(journal=str(journal), reference=str(reference), observations=dict(observed), bands=bands,
                newly_observed_then_saved=len(confirmation_waits),
                median_first_correct_candidate_to_save_seconds=statistics.median(confirmation_waits) if confirmation_waits else None)


def grid_audit(engine):
    folder = FIXTURES / "GridOutlineFailure"
    landmarks = json.loads((folder/"expected.json").read_text())
    results = []
    for name, corners in landmarks.items():
        if not name.endswith(".png"):
            continue
        for size in (landmarks["boardSize"],9):
            found = run(engine,"grid",folder/name,str(size))
            distances = None
            if found and size == landmarks["boardSize"]:
                distances = [math.dist(a,b) for a,b in zip(found["pixels"],corners,strict=True)]
            results.append(dict(image=name, requested_size=size, expected_grid=size==landmarks["boardSize"],
                                found=found is not None, quality=found["quality"] if found else None,
                                corner_errors_px=distances, tolerance_px=landmarks["tolerancePixels"]))
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new report directory")
    parser.add_argument("--labels", type=Path, default=FIXTURES/"ConfidenceAudit/labels.csv")
    parser.add_argument("--archives", type=Path, default=ROOT/"Captures/Diagnostics")
    parser.add_argument("--baseline-engine", type=Path, help="ConfidenceReplay compiled against the baseline detector")
    parser.add_argument("--engine", type=Path, help="use an already built current ConfidenceReplay")
    parser.add_argument("--recorder", nargs=2, action="append", metavar=("JOURNAL","REFERENCE_SGF"), default=[])
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output directory already exists")
    args.output.parent.mkdir(parents=True,exist_ok=True)
    labels = read_labels(args.labels)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as tmp:
        engine = args.engine.resolve() if args.engine else Path(tmp)/"ConfidenceReplay"
        if not args.engine:
            build_engine(engine)
        artifacts = Path(tmp)/"report"
        artifacts.mkdir()
        rows, sources = [], {}
        for session, samples in labels.items():
            paths = [p for p in args.archives.iterdir() if p.is_dir() and p.name.split()[-1]==session]
            if len(paths) != 1:
                raise ValueError(f"Expected one archive for {session}, found {len(paths)}")
            folder = paths[0]
            ids = ",".join(map(str,sorted({r["frame"] for r in samples})))
            current = {f["id"]: f for f in run(engine,"frames",folder,ids)}
            baseline = ({f["id"]: f for f in run(args.baseline_engine.resolve(),"frames",folder,ids)}
                        if args.baseline_engine else current)
            manifest = json.loads((folder/"session.json").read_text())
            sources[session] = dict(archive=folder.name, recorded_version=manifest.get("appVersion"),
                                    recorded_source_hash=manifest.get("sourceHash"))
            for sample in samples:
                row = sample.copy()
                measure(row, "old", baseline[row["frame"]], "new" if args.baseline_engine else "old")
                measure(row, "new", current[row["frame"]], "new")
                rows.append(row)
        episodes, report = summarize(rows)
        write_table(artifacts/"readings.csv", rows)
        write_table(artifacts/"episodes.csv", episodes)
        def digest(path):
            return hashlib.sha256(Path(path).read_bytes()).hexdigest()
        data = dict(baseline="supplied engine" if args.baseline_engine else "session's archived readings",
                    baseline_engine_sha256=digest(args.baseline_engine) if args.baseline_engine else None,
                    current_engine_sha256=digest(engine), labels_sha256=digest(args.labels),
                    sessions=sources, detector=report, grid=grid_audit(engine),
                    recorder=[recorder_audit(engine, *pair) for pair in args.recorder])
        (artifacts/"summary.json").write_text(json.dumps(data,indent=2)+"\n")
        artifacts.rename(args.output)
    print(args.output/"summary.json")


if __name__=="__main__":
    main()
