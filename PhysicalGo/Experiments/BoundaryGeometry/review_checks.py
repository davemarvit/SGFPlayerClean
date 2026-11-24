"""Independent frozen-result checks and explicit shadow counterexamples, offline only."""
import collections,copy,hashlib,json,subprocess,sys,tempfile
from pathlib import Path
import cv2,numpy as np
from boundary import measure
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
ART=Path('/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((HERE/'cases.json').read_text());policy=manifest['policy'];old=json.loads(subprocess.check_output(['git','show','738f2d7:PhysicalGo/Experiments/BoundaryGeometry/cases.json'],cwd=ROOT,text=True))
assert policy==old['policy'] and len(manifest['cases'])==len(old['cases'])==29
for a,b in zip(old['cases'],manifest['cases']):
 a=copy.deepcopy(a);b=copy.deepcopy(b);a.pop('setup');b.pop('setup');assert a==b
for source in manifest['auxiliaryProvenance']+[c[k] for c in manifest['cases'] for k in ['image','metadata']]:assert sha(Path(source['path']))==source['sha256']
summary=json.loads((HERE/'results-summary.json').read_text());rp=Path(summary['resultPath']);assert sha(rp)==summary['resultSHA256'];current=json.loads(rp.read_text());assert current['manifestSHA256']==sha(HERE/'cases.json')
for name,h in current['sourceHashes'].items():assert sha(HERE/name if name!='estimate.py' else HERE.parent/'StoneSetCalibration'/name)==h
original=json.loads((ART/'boundary-geometry-01/results.json').read_text());second=json.loads((ART/'boundary-geometry-02/results.json').read_text())
def outcome(row):
 r=copy.deepcopy(row);e=r['evidence'];e['provenance'].pop('setup');e.pop('runtimeDisposition',None);e.pop('boundaryIdentity',None);return r
assert [outcome(r) for r in original['cases']]==[outcome(r) for r in second['cases']]==[outcome(r) for r in current['cases']]
counts=dict(collections.Counter(row['evidence']['status'] for row in current['cases']));assert counts=={'supported':17,'abstain':12}
for row in current['cases']:
 e=row['evidence'];assert e['runtimeDisposition']=='diagnosticOnly';assert e['boundaryIdentity']=='stoneVersusShadowUnverified';assert e['confidence']['classProbability'] is None;assert e['uncertainty']['calibratedProbability'] is None
 if e['status']=='abstain':assert e['supportedOutline'] is None and e['abstentionReasons']
 else:assert e['supportedOutline']==e['candidateOutline'] and not e['abstentionReasons']
with tempfile.TemporaryDirectory(prefix='boundary-independent-replay-') as td:
 out=Path(td)/'result';subprocess.run([sys.executable,str(HERE/'replay.py'),str(out)],check=True,capture_output=True,text=True)
 assert json.loads((out/'results.json').read_text())==current
# Color is provenance only, and external visibility must remain authoritative.
# These synthetic examples intentionally document failures; they are not new fit data.
image=np.full((384,384,3),150,np.uint8);cv2.ellipse(image,(192,205),(78,80),0,0,360,(60,60,60),-1);cv2.circle(image,(192,180),70,(80,80,80),-1)
seed=np.array([9.,9.]);before=image.copy();shadow_body=measure(image,seed,[],'clear',policy)
assert np.array_equal(image,before);assert shadow_body.status=='supported'
body_center=np.array([9.,8.925]);error=float(np.linalg.norm(np.array(shadow_body.supportedOutline.center)-body_center));assert error>.11
assert shadow_body.visibleArcCoverage==1.;assert max(shadow_body.uncertainty['centerRange'])<.02
for visibility in ['unknown','occluded']:
 e=measure(image,seed,[],visibility,policy);assert e.status=='abstain' and e.supportedOutline is None
pale=measure(image,seed,[],'clear',policy,provenance={'colorHypothesis':'white'});dark=measure(image,seed,[],'clear',policy,provenance={'colorHypothesis':'black'});assert pale.candidateOutline==dark.candidateOutline
# A circular dark patch on bare wood has no stone but is geometrically supported.
round_shadow=np.full((384,384,3),150,np.uint8);cv2.circle(round_shadow,(192,192),75,(80,80,80),-1)
round_result=measure(round_shadow,seed,[],'clear',policy);assert round_result.status=='supported'
report=dict(status='review only; failures deliberately retained',freezeCommit='738f2d7',reviewedCommit='b4184d5',all29FrozenSelectionAndPolicyUnchanged=True,all29OutcomesUnchangedAcross01_02_03=True,independentReplayExactlyEqual=True,sourceAndArtifactHashesVerified=True,counts=counts,
 syntheticShadowMergedWithBody=dict(status=shadow_body.status,center=shadow_body.supportedOutline.center,knownBodyCenter=body_center.tolist(),centerErrorCells=error,coverage=shadow_body.visibleArcCoverage,quadrantDeletionSpread=shadow_body.uncertainty['centerRange']),
 syntheticRoundDarkPatchWithoutStone=dict(status=round_result.status,coverage=round_result.visibleArcCoverage),imageUnchanged=True,visibilityNotOverridden=True,colorHypothesisDoesNotChangeGeometry=True)
(HERE/'independent-review-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
