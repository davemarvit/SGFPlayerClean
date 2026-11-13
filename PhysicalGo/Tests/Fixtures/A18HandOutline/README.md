# White A18 mistaken for a remaining hand

Recorded in Physical Go0.170/build171,2026-11-13, during the19-move paused
acceptance game. Source diagnostic: `Diagnostic 2026-11-13 00-01-31 5EA26833`.
Frames230–280, in original analysis order and capture times. Frames246–252
show placement/withdrawal; frame254 visibly has no hand. The original outline
tracker remained obstructed until270 because it included the newly placed White
A18 in its foreground component. A separate preceding capture documented the
same false outline persisting for minutes with reliable no-hand pose output.

Pixels are the production221×221 grid-space samples, quantized as in the other
HandOutline fixtures. `disks` are this frame's original raw detector white-stone
fits with quality/confidence≥0.95, before any history or lighting adaptation.
The tracker independently checks the sampled bright neutral core. No manual
labels feed tracking. `lower`/`upper` bracket the independently inspected hand
exit; `clearBy` allows two subsequent clear views. Source photos are preserved
in the pinned diagnostic capture.

`before.png`, `hand.png`, `after.png` and `reference.png` are unchanged original
photos for the separate full pipeline regression. Repeating the static after
photo also catches the residual low-contrast rim-lighting component. This
constructed pipeline stimulus is not claimed as an original temporal sequence.
The sequence lacks a qualified chromatic motion estimate; `noEstimate` requires
that none be fabricated. Clearance still needs the observed clear frames.
