import json,hashlib,math
from pathlib import Path
import numpy as np
ROOT=Path('/Users/dave/Documents/SGF PLayer/work/ai-laser-integration/stone-session-20261123/stone-set-calibration/offline-body-study-01')

def fit(p,d,c):
    p=np.asarray(p,float);d=np.asarray(d,float);c=np.asarray(c,float);n=len(p)
    X=np.zeros((2*n,3));X[::2,0]=p[:,0]-c[0];X[1::2,0]=p[:,1]-c[1];X[::2,1]=1;X[1::2,2]=1
    beta,_,rank,s=np.linalg.lstsq(X,d.ravel(),rcond=None)
    residual=d-(beta[0]*(p-c)+beta[1:]);sse=float(np.sum(residual**2));dof=2*n-3
    spread=float(np.sum((p-p.mean(axis=0))**2));sigma=math.sqrt(sse/dof);se=sigma/math.sqrt(spread)
    return dict(k=float(beta[0]),bias=beta[1:].tolist(),rank=int(rank),raw_design_condition=float(s[0]/s[-1]),spatial_leverage=spread,
        max_residual=float(max(np.linalg.norm(residual,axis=1))),median_residual=float(np.median(np.linalg.norm(residual,axis=1))),
        residual_vectors=residual.tolist(),residual_component_scale=sigma,conditional_k_standard_error=se,
        k_scale_plus_minus_2se=[float(beta[0]-2*se),float(beta[0]+2*se)],
        uncertainty_note='OLS residual-scale diagnostic only; not calibrated confidence. Assumes independent equal-variance component residuals, excluding shared grid/shape/placement uncertainty.')

rows=[]
for color in ('white','black'):
    path=ROOT/color/'results.json';raw=path.read_bytes();r=json.loads(raw)
    for mode,old in r['conditionalFits'].items():
        p=np.array(old['fitPoints']);c=np.array(old['geometry']['cameraGrid']);H=old['geometry']['heightRowPitches']
        d=np.array(old['residualVectors'])+old['k']*(p-c)
        f=fit(p,d,c);k=f['k'];b=np.array(f['bias']);held=[]
        for h in old['heldOut']:
            residual=np.array(h['observedOffset'])-k*(np.array(h['point'])-c)-b
            held.append(dict(point=h['point'],before=h['beforeNorm'],old_scalar=h['residualNorm'],with_bias=float(np.linalg.norm(residual)),residual=residual.tolist()))
        loo=[]
        for i in range(len(p)):
            keep=np.arange(len(p))!=i;g=fit(p[keep],d[keep],c)
            pred=g['k']*(p[i]-c)+g['bias']
            loo.append(dict(omitted=p[i].tolist(),k=g['k'],bias=g['bias'],omitted_error=float(np.linalg.norm(d[i]-pred))))
        rows.append(dict(color=color,mode=mode,report_sha256=hashlib.sha256(raw).hexdigest(),old_k=old['k'],old_height=old['effectiveHeightRowPitches'],old_max_residual=old['maxResidual'],
            fit=f,conditional_height=H*k/(1+k),positive_height_supported_by_residual_scale=f['k_scale_plus_minus_2se'][0]>0,
            heldout=held,leave_one_training_anchor_out=loo,loo_k_range=[min(x['k'] for x in loo),max(x['k'] for x in loo)]))
challenge=json.loads((ROOT/'white-development-results.json').read_bytes());neg=[]
for case in challenge['cases']:
    for mode,dec in case['decisions'].items():
        if 'conditionalInferredContact' not in dec:continue
        row=next(x for x in rows if x['color']=='white' and x['mode']==mode)
        old=json.loads((ROOT/'white/results.json').read_bytes())['conditionalFits'][mode];c=np.array(old['geometry']['cameraGrid'])
        apparent=(1+old['k'])*np.array(dec['conditionalInferredContact'])-old['k']*c
        f=row['fit'];contact=(apparent+f['k']*c-f['bias'])/(1+f['k'])
        neg.append(dict(case=case['caseID'],mode=mode,inferred_contact=contact.tolist(),distances=[dict(point=z['point'],distance=float(np.linalg.norm(contact-z['point']))) for z in dec['candidateComparisons']]))
controls={}
p=np.array([[3,3],[15,3],[3,9],[15,9],[3,15],[15,15]],float);c=np.array([14,23.]);k=.006;b=np.array([.02,-.05]);f=fit(p,k*(p-c)+b,c)
assert abs(f['k']-k)<1e-12;np.testing.assert_allclose(f['bias'],b,atol=1e-12);controls['known_k_and_constant_bias']='recovered exactly'
f=fit(p,np.tile(b,(6,1)),c);assert abs(f['k'])<1e-12;controls['zero_height_constant_bias']='k recovered zero'
# An isotropic board-grid scale error is algebraically identical to k plus bias.
grid_scale=.006;translation=np.array([.02,-.05]);f=fit(p,grid_scale*p+translation,c)
assert abs(f['k']-grid_scale)<1e-12;controls['grid_scale_confound']=dict(k=f['k'],bias=f['bias'],note='Zero physical height with this grid error has exactly the same fitted form.')
# With fixed c, changing its assumed value is fully absorbed by bias: k is unchanged.
f1=fit(p,k*(p-c)+b,c);f2=fit(p,k*(p-c)+b,c+[4,-7]);assert abs(f1['k']-f2['k'])<1e-12
controls['camera_projection_shift']='k invariant, bias absorbs camera projection change'
# Scalar expansion can be fit even on a line, but cannot expose missing 2D patterns.
line=np.array([[3,y] for y in range(6)],float);lf=fit(line,k*(line-c)+b,c)
controls['collinear_algebraic_rank']=lf['rank'];controls['collinear_warning']='Rank3 does not substitute for two-dimensional spatial support.'
output=dict(status='offline diagnostic extension only; no production changes, no profile replacement',training='Exactly original six centered anchors. Two fixed heldouts and White negative never fit.',
            model='apparent-contact = k*(contact-camera_projection) + constant_color_bias',rows=rows,white_development_control=neg,controls=controls,
            limitations=['Free bias removes camera-projection constraint: algebraically delta=k*P+b_prime. This is an isotropic affine field, not independent proof of parallax.',
              'Shared printed-grid scale error, spatially varying contour bias and placement offsets still confound k.',
              'Leave-one-out fits use five anchors only as diagnostics; they do not meet the six-anchor runtime support rule.',
              'Black midpoint and independent setup tests remain pending.'])
Path(__file__).with_name('bias-comparison.json').write_text(json.dumps(output,indent=2)+'\n')
for x in rows:print(x['color'],x['mode'],'k',round(x['fit']['k'],6),'bias',np.round(x['fit']['bias'],4),'height',round(x['conditional_height'],4),'k2se',np.round(x['fit']['k_scale_plus_minus_2se'],6),'held',[(round(h['old_scalar'],4),round(h['with_bias'],4)) for h in x['heldout']],'LOO',np.round(x['loo_k_range'],6))
print('negative',neg);print('controls',controls)
