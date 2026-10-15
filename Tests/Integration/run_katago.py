#!/usr/bin/env python3
"""Opt-in offline smoke test of the installed engine and review model. No app or OGS access.
All logs, tuning data, and other engine files are directed to a temporary directory.
"""
import argparse
import json
import math
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--executable', default='/opt/homebrew/bin/katago')
parser.add_argument('--report', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
model = root / 'SGFPlayerClean/Resources/kata1-b18.bin.gz'
config = root / 'SGFPlayerClean/Resources/analysis.cfg'
queries = []

def query(name, **fields):
    result = dict(id=name, rules='japanese', komi=6.5, boardXSize=5, boardYSize=5,
                  moves=[], initialStones=[], initialPlayer='B', maxVisits=4,
                  includeOwnership=True, analyzeTurns=[0])
    result.update(fields)
    queries.append(result)

for rule in ['japanese', 'korean', 'chinese-ogs', 'aga', 'bga', 'new-zealand', 'tromp-taylor', 'stone-scoring']:
    query(rule, rules=rule, komi=0)
setup = [['B','B5'],['B','A4'],['B','B3'],['W','B4'],['W','C5'],['W','D4'],['W','C3']]
query('ko', initialStones=setup, moves=[['B','C4']], analyzeTurns=[1])
query('illegal-ko', initialStones=setup, moves=[['B','C4'],['W','B4']], analyzeTurns=[2])
query('ko-threat', initialStones=setup, moves=[['B','C4'],['W','E1'],['B','E2'],['W','B4']], analyzeTurns=[4])
suicide = [['B','A5'],['W','A4'],['W','B4'],['W','C5']]
query('nz-self-capture', rules='new-zealand', initialStones=suicide, moves=[['B','B5']], analyzeTurns=[1])
query('japanese-self-capture', initialStones=suicide, moves=[['B','B5']], analyzeTurns=[1])
query('handicap', rules='chinese-ogs', initialStones=[['B','B4'],['B','D2']], initialPlayer='W',
      komi=0.5, whiteHandicapBonus='N')
with tempfile.TemporaryDirectory(prefix='sgf-katago-smoke-') as directory:
    work = Path(directory)
    override = f'homeDataDir={work / "engine-data"},logDir={work / "logs"},nnCacheSizePowerOfTwo=12,numSearchThreads=1'
    run = subprocess.run([args.executable, 'analysis', '-config', str(config), '-model', str(model),
                          '-override-config', override], cwd=work,
                         input=''.join(json.dumps(q) + '\n' for q in queries),
                         text=True, capture_output=True, timeout=120)
    replies = []
    for line in run.stdout.splitlines():
        try:
            replies.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    if run.returncode:
        raise SystemExit(f'KataGo failed ({run.returncode}):\n{run.stderr[-6000:]}\n{run.stdout[-3000:]}')
    results = {r['id']:r for r in replies if 'id' in r and ('rootInfo' in r or 'error' in r)}
    # KataGo deliberately tolerates some illegal historical moves; it is not a legality validator.
    tolerated_history = {'illegal-ko', 'japanese-self-capture'}
    expected_errors = {name for name in tolerated_history if 'error' in results.get(name, {})}
    for q in queries:
        result = results.get(q['id'])
        assert result is not None, (q['id'], replies, run.stderr)
        if q['id'] in expected_errors:
            assert 'error' in result, result
        else:
            assert 'error' not in result, result
            info = result['rootInfo']
            assert 0 <= info['winrate'] <= 1 and math.isfinite(info['scoreLead']), result
    assert all(m['move'] != 'B4' for m in results['ko'].get('moveInfos', []))
    assert results['handicap']['rootInfo']['currentPlayer'] == 'W'
    report = dict(queries=len(queries), successful_analyses=len(queries)-len(expected_errors),
                  historical_move_rejections=sorted(expected_errors),
                  tolerated_illegal_histories=sorted(tolerated_history - expected_errors),
                  warnings=[r for r in replies if 'warning' in r],
                  version=subprocess.check_output([args.executable, 'version'], text=True).strip())
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
