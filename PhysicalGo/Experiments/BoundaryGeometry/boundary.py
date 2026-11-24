"""Offline visible-outline evidence. Never estimates board contact or occupancy."""
from dataclasses import asdict,dataclass,field
from typing import Literal
import cv2
import numpy as np

@dataclass
class Outline:
    center: list[float]
    principalRadii: list[float]
    angleDegrees: float

@dataclass
class BoundaryEvidence:
    schemaVersion: int = 1
    runtimeDisposition: Literal['diagnosticOnly'] = 'diagnosticOnly'
    boundaryIdentity: Literal['stoneVersusShadowUnverified'] = 'stoneVersusShadowUnverified'
    status: Literal['supported','abstain'] = 'abstain'
    candidateOutline: Outline | None = None
    supportedOutline: Outline | None = None
    visibleArcCoverage: float = 0.
    maximumMissingArcDegrees: float = 360.
    neighborOwnership: dict = field(default_factory=dict)
    compactBodyDiscrepancy: dict | None = None
    uncertainty: dict = field(default_factory=lambda:dict(kind='unknown',physicalContact='notEstimated',calibratedProbability=None))
    confidence: dict = field(default_factory=lambda:dict(score=0.,meaning='fraction of sampled directions retained as boundary support',calibrationStatus='uncalibrated',classProbability=None))
    abstentionReasons: list[str] = field(default_factory=list)
    provenance: dict = field(default_factory=dict)
    diagnostics: dict = field(default_factory=dict)
    def json(self):return asdict(self)

def sample(patch,xy,scale,extent):
    pos=(np.asarray(xy)+extent)*scale
    return cv2.remap(patch,pos[...,0].astype('float32'),pos[...,1].astype('float32'),cv2.INTER_LINEAR,borderMode=cv2.BORDER_REFLECT101)

def missing_arc(keep):
    run=best=0
    for flag in np.r_[keep,keep]:
        run=0 if flag else run+1;best=max(best,run)
    return min(best,len(keep))*360/len(keep)

def fit(points):
    if len(points)<5:return None
    result=cv2.fitEllipse(np.asarray(points,'float32').reshape(-1,1,2))
    center=np.asarray(result[0]);radii=np.asarray(result[1])/2
    if not np.isfinite(np.r_[center,radii,result[2]]).all() or min(radii)<=0:return None
    return center,radii,result[2]

def residual(points,ellipse):
    center,radii,degrees=ellipse;theta=np.deg2rad(degrees)
    rotation=np.array([[np.cos(theta),np.sin(theta)],[-np.sin(theta),np.cos(theta)]])
    local=(points-center)@rotation.T
    return abs(np.linalg.norm(local/radii,axis=1)-1)*min(radii)

def measure(patch,seed,neighbors,visibility,policy,compact=None,provenance=None,scale=160,extent=1.2):
    e=BoundaryEvidence(provenance=provenance or {})
    e.provenance.update(estimator='radial-rgb-edge-v1',correlationFamily='same-image-outline-geometry',colorUsedForGeometry=False)
    if (patch is None or patch.ndim!=3 or patch.shape[2]!=3 or not np.isfinite(patch).all()
        or np.asarray(seed).shape!=(2,) or not np.isfinite(seed).all()):
        e.abstentionReasons=['invalidInput'];return e
    if visibility not in ['clear','occluded','unknown']:raise ValueError('Invalid visibility state')
    if visibility!='clear':e.abstentionReasons.append('occluded' if visibility=='occluded' else 'visibilityUnverified')
    image=cv2.GaussianBlur(patch.astype('float32'),(5,5),1.)
    angles=np.arange(policy['samplingAngles'])*2*np.pi/policy['samplingAngles']
    unit=np.c_[np.cos(angles),np.sin(angles)];tangent=np.c_[-unit[:,1],unit[:,0]]
    radius=np.arange(*policy['radiusSearch'],.005);xy=unit[:,None,:]*radius[None,:,None];half=policy['edgeHalfWidth']
    dr=sample(image,xy+half*unit[:,None,:],scale,extent)-sample(image,xy-half*unit[:,None,:],scale,extent)
    dt=sample(image,xy+half*tangent[:,None,:],scale,extent)-sample(image,xy-half*tangent[:,None,:],scale,extent)
    strength=np.linalg.norm(dr,axis=2)/np.sqrt(3);tstrength=np.linalg.norm(dt,axis=2)/np.sqrt(3)
    radiality=strength/np.maximum(np.hypot(strength,tstrength),1e-6)
    score=np.where(radiality>=policy['minimumRadiality'],strength,0)
    index=np.argmax(score,axis=1);a=np.arange(len(angles));points=xy[a,index]
    valid=(score[a,index]>=policy['minimumRGBStep'])
    # Ownership is a conservative candidate-point comparison, never legal-move truth.
    contested=np.zeros(len(angles),bool)
    for neighbor in neighbors:
        d=np.array(neighbor)-seed
        contested|=np.linalg.norm(points-d,axis=1)<np.linalg.norm(points,axis=1)+policy['neighborOwnershipMargin']
    contested_fraction=float(np.mean(contested&valid))
    e.neighborOwnership=dict(source='supplied visual candidate centers; may be incomplete',candidateCount=len(neighbors),contestedArcFraction=contested_fraction,excludedDirections=np.flatnonzero(contested&valid).tolist())
    keep=valid&~contested
    ellipse=fit(points[keep])
    if ellipse is not None:
        # Fixed three robust pruning steps; no image-dependent threshold fitting.
        for _ in range(3):
            keep=valid&~contested&(residual(points,ellipse)<=2*policy['maximumEllipseResidual'])
            updated=fit(points[keep])
            if updated is None:break
            ellipse=updated
        keep=valid&~contested&(residual(points,ellipse)<=policy['maximumEllipseResidual'])
        center,radii,degrees=ellipse
        e.candidateOutline=Outline((center+seed).tolist(),radii.tolist(),float(degrees))
        low,high=policy['ellipseRadiusBounds']
        if min(radii)<low or max(radii)>high:e.abstentionReasons.append('radiusOutsideAssumedStoneRange')
        if np.linalg.norm(center)>policy['maximumCenterShift']:e.abstentionReasons.append('centerOutsideLocalSearchTrustRegion')
        # Deleting whole angular quadrants tests sensitivity, not independent noise.
        jack=[]
        for quadrant in range(4):
            chosen=keep&((np.arange(len(angles))*4//len(angles))!=quadrant);trial=fit(points[chosen])
            if trial is not None:jack.append(trial[0])
        e.uncertainty.update(kind='angularDeletionSensitivity',centerRange=(np.ptp(jack,axis=0).tolist() if jack else None),description='leave-one-quadrant-out spread; excludes seed/grid/lighting/model bias, not a confidence interval')
        e.diagnostics['medianResidual']=float(np.median(residual(points[keep],ellipse))) if keep.any() else None
        if compact:
            c=np.array([compact['center']['x'],compact['center']['y']]);c_radius=np.array([compact['radiusCol'],compact['radiusRow']])
            e.compactBodyDiscrepancy=dict(compactMinusOutline=(c-center-seed).tolist(),compactRadii=c_radius.tolist(),outlinePrincipalRadii=radii.tolist(),meaning='same-image estimator disagreement, not contact error; radii coordinate axes differ')
    else:e.abstentionReasons.append('insufficientBoundaryPoints')
    e.visibleArcCoverage=float(keep.mean());e.maximumMissingArcDegrees=missing_arc(keep)
    e.confidence['score']=e.visibleArcCoverage
    if e.visibleArcCoverage<policy['minimumArcFraction']:e.abstentionReasons.append('insufficientVisibleArcCoverage')
    if e.maximumMissingArcDegrees>policy['maximumMissingArcDegrees']:e.abstentionReasons.append('longUnobservedArc')
    if contested_fraction>policy['maximumContestedFraction']:e.abstentionReasons.append('neighborOwnershipUnresolved')
    e.diagnostics.update(edgePoints=(points+seed).tolist(),retainedDirections=np.flatnonzero(keep).tolist(),rawEdgeCoverage=float(valid.mean()),radialStepRGB=strength[a,index].tolist())
    if not e.abstentionReasons and ellipse is not None:e.status='supported';e.supportedOutline=e.candidateOutline
    return e
