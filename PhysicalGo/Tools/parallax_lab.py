#!/usr/bin/env python3
"""Offline geometry ablation. No app imports, temporal decisions, or clock authority.

For a camera C above a plane, intersecting the ray through a stone at height h
with the board plane gives apparent P'=P+k(P-C_xy), k=h/(H-h). Thus disparity
varies with distance from the camera's projected position; a uniform translation
is only a control. The constrained radial fit estimates k and the two intercepts,
not camera height or stone height separately. This is not calibrated probability.
"""
import math
import numpy as np


def point(s):
    return s['row']*19+s['col']


def center(s):
    return np.array([s['center']['x'], s['center']['y']], dtype=float)


def covers(s, p, padding=0):
    radii=np.array([s['radiusCol'],s['radiusRow']])+padding
    return bool(np.all(radii>0) and np.sum(((np.asarray(p)-center(s))/radii)**2)<=1)


def assignment_offsets(shapes, raw, before):
    """Port of BoardObservation.offsets(forAssignment:true); verified against native output."""
    result={}
    def occupied_neighbor(s,c,r):
        if not 0<=c<19 or not 0<=r<19:return False
        j=r*19+c
        if before[j] not in ('black','white') or raw[j][0]!=before[j] or raw[j][1]<.9:return False
        return any(o['col']==c and o['row']==r and o['quality']>=.78 and covers(o,[c,r]) and
                   np.linalg.norm((center(s)-center(o))/[s['radiusCol']+o['radiusCol'],s['radiusRow']+o['radiusRow']])>=.9 for o in shapes)
    for s in shapes:
        p=point(s);q=s['quality'];c,r=s['col'],s['row']
        if q<.86 or raw[p][0] not in ('black','white'):continue
        dx,dy=center(s)-[c,r];d=max(abs(dx),abs(dy))
        unique=q>=.94 and raw[p][1]>=.94 and .36<=s['radiusCol']<=.65 and .36<=s['radiusRow']<=.65 and covers(s,[c,r],-.08)
        if unique:
            unique=not any(covers(s,[x,y],.08) for y in range(max(0,r-1),min(18,r+1)+1) for x in range(max(0,c-1),min(18,c+1)+1) if (x,y)!=(c,r))
        if unique:d=0.
        elif q>=.90 and raw[p][1]>=.90 and d<=.46 and covers(s,[c,r]):
            outward_x=(c==0 and dx<0) or (c==18 and dx>0)
            outward_y=(r==0 and dy<0) or (r==18 and dy>0)
            blocked_x=abs(dx)>.24 and abs(dy)<=.24 and occupied_neighbor(s,c+(1 if dx>0 else -1),r)
            blocked_y=abs(dy)>.24 and abs(dx)<=.24 and occupied_neighbor(s,c,r+(1 if dy>0 else -1))
            d=max(0 if outward_x or blocked_x else abs(dx),0 if outward_y or blocked_y else abs(dy))
        result[p]=max(result.get(p,0),float(d))
    return result


def fit_field(shapes, raw, before, excluded=(), model='radial',geometry=None):
    """One observation only; established stones only; each intersection gets one vote."""
    excluded=set(excluded);selected={}
    for s in shapes:
        p=point(s)
        if p in excluded or before[p] not in ('black','white') or raw[p][0]!=before[p] or raw[p][1]<.94:continue
        if s['quality']<.9 or not .36<=s['radiusCol']<=.60 or not .36<=s['radiusRow']<=.65:continue
        d=center(s)-[s['col'],s['row']]
        if not np.isfinite(d).all() or max(abs(d))>.46:continue
        if p not in selected or s['quality']>selected[p]['quality']:selected[p]=s
    if len(selected)<6:return None
    coords=np.array([[s['col'],s['row']] for s in selected.values()],float)
    displacements=np.array([center(s)-p for s,p in zip(selected.values(),coords)])
    if np.any(np.ptp(coords,axis=0)<4) or np.linalg.svd(coords-coords.mean(axis=0),compute_uv=False)[-1]<2:return None
    n=len(coords)
    if model=='translation':design=np.tile(np.eye(2),(n,1))
    elif model=='raw-camera':
        if geometry is None:return None
        design=(coords-np.array(geometry['cameraGrid'])).reshape(-1,1)
    elif model=='radial':design=np.array([[1,0,x] if axis==0 else [0,1,y] for x,y in coords for axis in [0,1]],float)
    else:raise ValueError(model)
    weights=np.ones(n)
    for _ in range(8):
        w=np.sqrt(np.repeat(weights,2));coef=np.linalg.lstsq(design*w[:,None],displacements.ravel()*w,rcond=None)[0]
        if model=='raw-camera':coef=np.clip(coef,0,.04)
        if model=='radial' and not 0<=coef[2]<=.04:
            # Constrained optimum at the physical expansion bound, not a free affine warp.
            k=np.clip(coef[2],0,.04);intercept=np.average(displacements-k*coords,axis=0,weights=weights)
            coef=np.r_[intercept,k]
        residual=displacements-(design@coef).reshape(-1,2)
        weights=np.minimum(1,.10/np.maximum(np.linalg.norm(residual,axis=1),1e-8))
    error=float(np.median(np.linalg.norm(residual,axis=1)))
    if error>.18:return None
    return {'model':model,'coefficients':coef.tolist(),'support':sorted(selected),'medianResidual':error,'geometry':geometry,'clockAuthority':False}


def prediction(field,p):
    c=np.asarray(field['coefficients']);xy=np.asarray(p,float)
    if field['model']=='raw-camera':return c[0]*(xy-np.array(field['geometry']['cameraGrid']))
    return c[:2]+(c[2]*xy if field['model']=='radial' else 0)


def evaluate(shapes,raw,before,targets,model='radial',exclude=(),minimum_confidence=.90,geometry=None):
    original=assignment_offsets(shapes,raw,before)
    field=fit_field(shapes,raw,before,set(targets)|set(exclude),model,geometry)
    rows=[]
    for p in targets:
        c,r=p%19,p//19;old=original.get(p);new=old;reason='unchanged';estimate=None
        if old is not None and old>=.30:
            if field is None:reason='insufficient field support'
            else:
                estimate=prediction(field,[c,r]);residuals=[]
                if max(abs(estimate))>.40:reason='field exceeds bound'
                else:
                    for s in shapes:
                        if point(s)!=p or s['quality']<.90 or raw[p][1]<minimum_confidence:continue
                        residual=center(s)-[c,r]-estimate
                        if max(abs(center(s)-[c,r]))>.46:continue
                        # Candidate must cover its predicted point and uniquely own it.
                        if not covers(s,np.array([c,r])+estimate,-.08):continue
                        if any(covers(s,np.array([x,y])+prediction(field,[x,y]),.08)
                               for y in range(max(0,r-1),min(18,r+1)+1)
                               for x in range(max(0,c-1),min(18,c+1)+1) if (x,y)!=(c,r)):continue
                        residuals.append(float(max(abs(residual))))
                    if residuals and max(residuals)<.30:new=max(residuals);reason='geometry proposal'
                    else:reason='ownership or confidence remains unresolved'
        rows.append({'point':p,'occupancy':raw[p][0],'originalOffset':old,'proposedOffset':new,
                     'proposedRelief':old is not None and old>=.3 and new is not None and new<.3,
                     'reason':reason,'predictedOffset':None if estimate is None else estimate.tolist()})
    return {'field':field,'targets':rows,'clockAuthority':False,'changesOccupancy':False,'changesCaptureHandling':False}


def camera_geometry(calibration,width,height,principal_fraction=(.5,.5)):
    """Pinhole hypothesis from raw-image homography and orthogonal grid axes.

    Assumes square pixels, zero skew/distortion and a specified principal point.
    A single plane does not verify those assumptions. Grid pitch may differ by
    axis; camera height is reported in row-spacing units, not millimeters.
    """
    h=calibration['h'];H=np.array([[h[0],h[1],h[2]],[h[3],h[4],h[5]],[h[6],h[7],1.]])
    H=np.diag([width-1,height-1,1])@H
    cx,cy=(width-1)*principal_fraction[0],(height-1)*principal_fraction[1]
    a=H[:2,0]-[cx*H[2,0],cy*H[2,0]];b=H[:2,1]-[cx*H[2,1],cy*H[2,1]]
    denominator=H[2,0]*H[2,1]
    if abs(denominator)<1e-10:return None
    f2=-float(a@b)/denominator
    if not math.isfinite(f2) or f2<=0:return None
    focal=math.sqrt(f2)
    if not .2*width<focal<4*width:return None
    K=np.array([[focal,0,cx],[0,focal,cy],[0,0,1.]])
    B=np.linalg.solve(K,H)@np.diag([1/(calibration['size']-1),1/(calibration['size']-1),1])
    nx=np.linalg.norm(B[:,0]);ny=np.linalg.norm(B[:,1]);r1=B[:,0]/nx;r2=B[:,1]/ny
    r3=np.cross(r1,r2);t=B[:,2]
    return {'cameraGrid':[-float(r1@t)/nx,-float(r2@t)/ny],'heightRowPitches':abs(float(r3@t))/ny,
            'focalPixels':focal,'columnToRowPitch':float(nx/ny),'principalFraction':list(principal_fraction),
            'assumptionsVerified':False}
