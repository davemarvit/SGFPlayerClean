"""Follow-up to hard outline rejection: causal bounded persistence, offline only.

This is a decision filter over the frozen control's evidence, not clock logic.
The .8s threshold is fixed from the existing pre-hand lookback, not fitted.
"""
from copy import deepcopy

from prehand_lab import edge

WAIT_SECONDS = .8


def probation(result, outlined):
    result = deepcopy(result)
    if (result['state'] == 'placement' and result['color'] == 'black'
            and edge(result['selected']) and result['selected'] not in outlined
            and result['witnesses'][-1]['capturedAt']-result['witnesses'][0]['capturedAt'] < WAIT_SECONDS-1e-9):
        result.update(state='unknown', selected=None, color=None, confirmedAt=None,
                      firstSeen=None, firstSupported=None, witnesses=[])
        result['reasons'] = sorted(set(result['reasons']) | {'outline unavailable at edge; awaiting sustained evidence'})
    return result
