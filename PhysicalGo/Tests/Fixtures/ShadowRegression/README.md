# Historical recognition regression set

Version 1 retains 34 full-resolution camera frames from five games, their empty-board references, the calibrations used for those frames, and 455 visually reviewed intersection labels. The original frame and reference PNGs are byte-for-byte copies, stored once per SHA-256 digest. The bundle occupies about 124 MiB. No files on the Desktop, diagnostic session folders, camera, or running app are needed for the frozen comparison.

From the repository root, with Python 3, NumPy and OpenCV installed, run

    python3 PhysicalGo/Tools/shadow_regression.py PhysicalGo/.build/shadow-evaluation-1

Choose a new output directory for each run. The runner validates the corpus checksums and writes a row for every labeled decision, a split summary, and hashes of the inputs and experiment code. [Reference results](results/v1/summary.json) · [Paired predictions](results/v1/paired.csv)

## What was retained

* The development set contains the D2 crowded-white failure, erroneous empty intersections and stones along the edge, and the G1 hand interruption. Six readings are labeled occluded. They are scored separately as stone calls under obstruction; occupancy at a hidden point is not treated as known.
* The holdout contains a different game with stones placed and captured at A11, A12 and B11, and the later B13–B16 crowded-placement game. It includes earlier and later views of the same intersections, empty points at the board margin, and clear controls.
* The additional challenge contains 72 readings from a fifth game. Locations were selected using the archived detector’s uncertainty near adjacent stones, plus controls, and labeled from the photos. It was added after the primary comparison, to probe shadowed wood separately. The experimental rules were unchanged.
* The 153 exemplar files contain paired board-normalized image and empty-reference patches. They come from isolated, strongly detected stones in the same session. The experiment requires three usable observations from each exemplar location and uses only observations from before the test frame under the same reference and view orientation. Evaluated locations cannot enter the exemplar set. These are automatic learning inputs, not human-labeled answers.

The manifest records session IDs, source filenames, pixel assets, grid transforms, thresholds, and timestamps. The first half of an exemplar PNG is the live RGB patch and the second half is the reference. Both are sampled on the grid used by `stone_profiles.py`. `labels.csv` uses zero-based row-major intersection indices. An episode groups repeated views of an occupied placement or an empty interval at the same point. Version 1 measures occupancy / intersection assignment; it does not label exact physical stone centers or complete move chronology.

## Comparing a new approach

Use the same native pixels and calibration. Join predictions by session, frame, and point. Keep empty, black, white, uncertain and occluded distinct. Report how many wrong or uncertain decisions became correct, how many correct decisions regressed, and the mean accuracy when each labeled episode gets one vote. This is a deliberately difficult regression set. Its accuracy is not an estimate of the percentage of moves the app will record in a tournament.

The frozen baseline is Physical Go 0.50 applied to these pixels, including frames originally recorded by older app versions. To generate a new native baseline on the Mac, compile the ConfidenceReplay adapter against the detector you want to evaluate:

    python3 -c "from pathlib import Path; import sys; sys.path.insert(0,'PhysicalGo/Tools'); from confidence_audit import build_engine; build_engine(Path('PhysicalGo/.build/shadow-engine'))"
    python3 PhysicalGo/Tools/shadow_regression.py PhysicalGo/.build/shadow-evaluation-2 --engine PhysicalGo/.build/shadow-engine

For an independent implementation, `v1/manifest.json`, `v1/labels.csv` and the PNGs are sufficient. The adapter also accepts `corpus FIXTURE_DIRECTORY` to export detector readings and fitted outlines directly. Corrections or new cases should go in a subsequent version. Keep the v1 images, splits, labels and results intact. Reserve new games when tuning against the published holdout.

## First experiment

The outline variant only revisits empty or uncertain readings. It requires one plausible stone body near the point with width, height and area consistent with at least two earlier isolated stone positions of that color in the same part of the board. A pooled control uses earlier examples of the same color anywhere on the board. The shadow variant additionally requires the darkness and direction measured outside the silhouette to agree with those examples. It can also recognize exposed, darkened wood beside a stone when both grid lines survive and the learned shadow points toward that intersection. Neither variant changes the production detector.

| Split | Scorable readings | Physical Go 0.50 correct | Outline correct | Outline with shadow correct |
| --- | ---: | ---: | ---: | ---: |
| Development | 181 | 168 | 169 | 168 |
| Holdout | 196 | 164 | 167 | 164 |
| Additional neighbor challenge | 72 | 49 | 49 | 49 |

The pooled and regional outline controls returned identical decisions on all 455 labels. These gains cannot be attributed specifically to learning separate near- and far-side profiles.

The outline variant recovered White E3 in development, and White B16 (two frames) and E18 on the holdout. The shadow agreement requirement vetoed all four corrections. No variant introduced a new wrong call in these samples. The shadow-based empty-point rule made no changes. All three variants still called a stone in two of the six occluded readings. On the additional challenge the baseline had 23 uncertain readings; the proposed rules resolved none of them.

The outline-only gain on the holdout was 3/196, or 1.5 percentage points. With one vote per episode, accuracy went from 82.3% to 85.3%. The shadow variant’s gain over production was zero. A shadow margin in the paired CSV is a heuristic pass/fail margin, not a probability. In a crowd the area beside one stone may contain another stone, so dark pixels there cannot safely be attributed to its shadow alone.

## Native 0.62 versus 0.63 comparison (November 4, 2026)

The neighbor-aware shaded-cross change was evaluated with `Tools/native_corpus_audit.py`, using separately compiled native 0.62 and 0.63 adapters on the same frozen pixels, calibrations, references and thresholds. All corpus checksums passed. The labels were not changed or used to tune this comparison; the algorithm had been developed against the separate live Q13 failure. These are published historical splits, not a new untouched validation set.

| Split | Scorable readings | 0.62 correct | 0.63 correct | New wrong calls | Correct calls regressed |
| --- | ---: | ---: | ---: | ---: | ---: |
| Development | 181 | 168 | 168 | 0 | 0 |
| Historical holdout | 196 | 164 | 166 | 0 | 0 |
| Neighbor challenge | 72 | 49 | 51 | 0 | 0 |
| Total | 449 | 381 | 385 | 0 | 0 |

Four uncertain empty readings became correctly empty, spanning three episodes in two games. Uncertain readings fell from 62 to 58 (6.5% fewer). Correct results rose from 84.9% to 85.7%; equal weighting of the 138 labeled episodes gives 82.4% to 83.3%. The six wrong calls remain: four missed White stones and two phantom Black stones, five with heuristic scores at least 0.90. The six occluded readings remain separate; both versions call stones in two of them. This is a small improvement in uncertainty resolution, with no measured regression, rather than a fix for the existing confidently wrong classifications.

The 250 earlier ConfidenceAudit labels are all contained in this frozen set. This result measures the historical difficult cases from one physical setup, not general game accuracy or move-send latency. Exact engine sources/binaries, paired rows, individual changes, mistakes and an independent count check are retained in the workspace's `work/shadow-audit-0.62-to-0.63` directory. The v1 labels, assets and original experiment results remain unchanged.
