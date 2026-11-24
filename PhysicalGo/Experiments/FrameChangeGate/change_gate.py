"""Offline region-change experiment; deliberately not imported by the app.

Outputs scheduling hints, never current occupancy or hand/safety evidence.
Keep the anchor fixed until a full, independently admitted analysis replaces it.
"""
from dataclasses import dataclass
import cv2
import numpy as np


@dataclass(frozen=True)
class Descriptor:
    features: np.ndarray
    valid: np.ndarray
    size: int
    scope: str


def maps(calibration, width, height, samples=20):
    size=calibration['size']
    axis=(np.arange(size*samples,dtype=np.float32)+.5)/samples-.5
    c,r=np.meshgrid(axis/(size-1),axis/(size-1))
    h=calibration['h'];den=h[6]*c+h[7]*r+1
    return (((h[0]*c+h[1]*r+h[2])/den*(width-1)).astype(np.float32),
            ((h[3]*c+h[4]*r+h[5])/den*(height-1)).astype(np.float32))


def describe(image, calibration, scope, samples=20):
    """Small board ROI; no full-resolution temporal image copy is retained."""
    x,y=maps(calibration,image.shape[1],image.shape[0],samples)
    valid=(x>=1)&(y>=1)&(x<image.shape[1]-2)&(y<image.shape[0]-2)
    rect=cv2.remap(image,x,y,cv2.INTER_LINEAR,borderMode=cv2.BORDER_REFLECT101)
    return describe_rectified(rect,valid,calibration['size'],scope)


def describe_rectified(rect, valid, size, scope):
    # Blur sensor/compression noise, then remove slowly varying illumination.
    # Strong/structured shadows can still request work; they are not discarded
    # merely because a background model labels them as shadows.
    rgb=cv2.GaussianBlur(rect.astype(np.float32)/255,(3,3),0)
    light=np.mean(rgb,axis=2)
    detail=light-cv2.GaussianBlur(light,(0,0),5)
    total=np.maximum(np.sum(rgb,axis=2),.06)
    features=np.stack((detail,rgb[:,:,2]/total,rgb[:,:,1]/total,light),axis=2)
    return Descriptor(features,valid,size,scope)


def changes(anchor, current, samples=20, halo=1):
    """A region list is diagnostic only; unchanged does NOT mean freshly clear.

    Scope must include stream, calibration/reference revision, image dimensions,
    target/game phase, and dark-evidence boundary. Any change requests all cells.
    """
    n=current.size
    if anchor is None or anchor.scope!=current.scope or anchor.size!=n or anchor.features.shape!=current.features.shape:
        return dict(raw=list(range(n*n)),expanded=list(range(n*n)),reason='new_scope')
    d=np.abs(current.features-anchor.features)
    chroma_valid=np.minimum(anchor.features[:,:,3],current.features[:,:,3])>.15
    mask=(d[:,:,0]>6/255)|(chroma_valid&((d[:,:,1]>.018)|(d[:,:,2]>.018)))
    # Four changed samples within one intersection cell. At 20 samples/pitch,
    # even a small shifted edge requests analysis. These are prototype constants.
    counts=mask.reshape(n,samples,n,samples).sum(axis=(1,3))
    invalid=(~(anchor.valid&current.valid)).reshape(n,samples,n,samples).any(axis=(1,3))
    selected=(counts>=4)|invalid
    raw=np.flatnonzero(selected).tolist()
    if halo:
        selected=cv2.dilate(selected.astype(np.uint8),np.ones((2*halo+1,2*halo+1),np.uint8))>0
    return dict(raw=raw,expanded=np.flatnonzero(selected).tolist(),reason='pixel_change',
                maxChangedSamples=int(counts.max()),invalidCells=int(invalid.sum()))
