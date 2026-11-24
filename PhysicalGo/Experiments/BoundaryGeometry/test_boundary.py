import json,unittest
from pathlib import Path
import cv2
import numpy as np
from boundary import measure,missing_arc
P=json.loads(Path(__file__).with_name('cases.json').read_text())['policy']
def image(kind='stone'):
 im=np.full((384,384,3),150,np.uint8)
 if kind=='stone':cv2.ellipse(im,(200,184),(75,71),0,0,360,(220,220,220),-1)
 if kind=='cross':cv2.line(im,(0,192),(383,192),(20,20,20),4);cv2.line(im,(192,0),(192,383),(20,20,20),4)
 if kind=='shadow':im[:190]=70
 return im
class BoundaryTests(unittest.TestCase):
 def test_circle_geometry(self):
  e=measure(image(),np.array([9.,9.]),[],'clear',P)
  self.assertEqual(e.runtimeDisposition,'diagnosticOnly');self.assertEqual(e.boundaryIdentity,'stoneVersusShadowUnverified')
  self.assertEqual(e.status,'supported');self.assertLess(np.linalg.norm(np.array(e.supportedOutline.center)-[9.05,8.95]),.02)
  self.assertIsNone(e.confidence['classProbability']);self.assertIsNone(e.uncertainty['calibratedProbability'])
 def test_uniform_and_cross_abstain(self):
  for kind in ['empty','cross','shadow']:self.assertEqual(measure(image(kind),np.array([9.,9.]),[],'clear',P).status,'abstain')
 def test_hand_gate_not_overridden(self):
  e=measure(image(),np.array([9.,9.]),[],'occluded',P);self.assertEqual(e.status,'abstain');self.assertIsNone(e.supportedOutline);self.assertIn('occluded',e.abstentionReasons)
 def test_unknown_visibility(self):self.assertIn('visibilityUnverified',measure(image(),np.array([9.,9.]),[],'unknown',P).abstentionReasons)
 def test_neighbor_ownership(self):
  e=measure(image(),np.array([9.,9.]),[[9.4,9]],'clear',P);self.assertEqual(e.status,'abstain');self.assertIn('neighborOwnershipUnresolved',e.abstentionReasons)
 def test_invalid(self):
  self.assertEqual(measure(None,np.array([9.,9.]),[],'clear',P).abstentionReasons,['invalidInput'])
  self.assertEqual(measure(image(),np.array([np.nan,9]),[],'clear',P).status,'abstain')
 def test_arc_wrap(self):self.assertEqual(missing_arc(np.array([False,False,True,True,True,True,False,False])),180)
if __name__=='__main__':unittest.main()
