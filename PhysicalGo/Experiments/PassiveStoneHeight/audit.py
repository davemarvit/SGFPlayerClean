"""Offline identifiability audit. No camera, runtime, profile or motion output."""
import argparse
import hashlib
import json
import math
from pathlib import Path


def field_fit(points, offsets):
    """OLS d(P)=k*(P-mean(P))+mean(d), separating constant offset."""
    n = len(points)
    if n < 2 or len(offsets) != n:
        raise ValueError("At least two paired observations are required")
    if any(not math.isfinite(v) for row in points + offsets for v in row):
        raise ValueError("Nonfinite observation")
    pbar = [sum(p[j] for p in points) / n for j in (0, 1)]
    dbar = [sum(d[j] for d in offsets) / n for j in (0, 1)]
    leverage = sum((p[j] - pbar[j]) ** 2 for p in points for j in (0, 1))
    if leverage == 0:
        raise ValueError("Repeated frames at one position do not identify a spatial field")
    k = sum((p[j] - pbar[j]) * (d[j] - dbar[j])
            for p, d in zip(points, offsets) for j in (0, 1)) / leverage
    return {"k": k, "center": pbar, "meanOffset": dbar,
            "spatialLeverage": leverage}


def prediction(fit, p):
    return [fit["meanOffset"][j] + fit["k"] * (p[j] - fit["center"][j])
            for j in (0, 1)]


def residual(d, estimated):
    return math.hypot(*(d[j] - estimated[j] for j in (0, 1)))


def shape_ratio(thickness, radius, theta_degrees):
    """Orthographic, axisymmetric ellipsoid; theta is angle from board normal."""
    theta = math.radians(theta_degrees)
    return math.sqrt(math.cos(theta) ** 2 + (thickness / (2 * radius)) ** 2
                     * math.sin(theta) ** 2)


def checks():
    p = [[3, 3], [15, 3], [3, 9], [15, 9], [3, 15], [15, 15]]
    camera = [14, 23]
    d = [[.006 * (x[j] - camera[j]) + [.03, -.07][j] for j in (0, 1)] for x in p]
    assert abs(field_fit(p, d)["k"] - .006) < 1e-12
    assert abs(field_fit(p, [[.03, -.07]] * 6)["k"]) < 1e-12
    # A zero-height placement trend can produce exactly the same field.
    placement_only = [[.006 * (x[j] - camera[j]) + [.03, -.07][j]
                       for j in (0, 1)] for x in p]
    assert placement_only == d
    # Duplicating static images changes neither slope nor independent placements.
    assert abs(field_fit(p * 8, d * 8)["k"] - .006) < 1e-12
    try:
        field_fit([[9, 9]] * 8, [[0, 0]] * 8)
    except ValueError:
        pass
    else:
        raise AssertionError("Coincident support must abstain")
    assert shape_ratio(8, 11, 0) == 1
    assert abs(shape_ratio(22, 11, 55) - 1) < 1e-12
    assert shape_ratio(9, 11, 55) > shape_ratio(8, 11, 55)
    return 8


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("study", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    report = {"status": "offlineDiagnosticOnly", "physicalThicknessIdentified": False,
              "grantsMotion": False, "controlsPassed": checks(), "colors": []}
    for color in ("black", "white"):
        path = args.study / color / "results.json"
        doc = json.loads(path.read_text())
        fit_rows = [r for r in doc["aggregated"] if r["supported"] and not r["heldOut"]]
        held = [r for r in doc["aggregated"] if r["supported"] and r["heldOut"]]
        fit = field_fit([r["point"] for r in fit_rows],
                        [r["bodyCenterOffset"] for r in fit_rows])
        report["colors"].append({"color": color, "source": str(path),
            "sourceSHA256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "independentCenteredPositions": len(fit_rows), "fit": fit,
            "heldOut": [{"point": r["point"],
                         "uncorrected": residual(r["bodyCenterOffset"], [0, 0]),
                         "meanOffsetOnly": residual(r["bodyCenterOffset"], fit["meanOffset"]),
                         "spatialField": residual(r["bodyCenterOffset"], prediction(fit, r["point"]))}
                        for r in held]})
    report["illustrativeEllipsoidOnly"] = [
        {"angleFromBoardNormalDegrees": angle,
         "diameterPixels": 40, "diameterMm": 22, "thicknessMm": 8,
         "minorDiameterChangeForOneMmExtraThicknessPixels":
             40 * (shape_ratio(9, 11, angle) - shape_ratio(8, 11, angle))}
        for angle in (0, 35, 55)]
    # Idealized independent component noise; not an error bound on real data.
    report["illustrativePlacementCountForOneMmEffectiveHeightSE"] = [
        {"componentScatterCells": sigma, "cameraHeightRowPitches": 26,
         "assumedRowPitchMm": 23, "rmsSpreadCells": 6,
         "independentPlacements": math.ceil((26 * 23 * sigma / 6) ** 2)}
        for sigma in (.05, .10)]
    report["limitations"] = ["Current-grid body estimator only; prior static centered scenes, not causal play replay.",
        "OLS field is diagnostic and must not waive placement flags or train from pending moves.",
        "Shape calculation assumes an ellipsoid and orthographic projection, not measured Go stone shape.",
        "Placement-count calculation excludes systematic placement, grid, shape and camera errors."]
    with args.output.open("x") as f:
        json.dump(report, f, indent=2)
        f.write("\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
