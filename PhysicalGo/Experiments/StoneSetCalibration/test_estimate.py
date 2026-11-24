"""Small analytic controls for the confirmed-anchor adapter, no camera reads."""
import unittest
import numpy as np
from estimate import fit_confirmed,POINTS,HELD_OUT


class HeightControls(unittest.TestCase):
    def setUp(self):
        self.geometry=dict(cameraGrid=[14.,23.],heightRowPitches=26.)
        self.training=np.array([p for p in POINTS if p not in HELD_OUT],float)

    def test_known_height_and_position_field(self):
        k=.01
        apparent=self.training+k*(self.training-self.geometry['cameraGrid'])
        fit=fit_confirmed(self.training.tolist(),apparent,self.geometry)
        self.assertAlmostEqual(fit['k'],k,places=12)
        self.assertAlmostEqual(fit['effectiveHeightRowPitches'],26*k/(1+k),places=12)
        self.assertLess(fit['maxResidual'],1e-12)

    def test_held_out_midpoint_is_not_corrected_to_intersection(self):
        k=.01
        apparent=self.training+k*(self.training-self.geometry['cameraGrid'])
        fit=fit_confirmed(self.training.tolist(),apparent,self.geometry)
        midpoint=np.array([9.,14.5])
        observed=midpoint+k*(midpoint-self.geometry['cameraGrid'])
        inferred=(observed+fit['k']*np.array(self.geometry['cameraGrid']))/(1+fit['k'])
        np.testing.assert_allclose(inferred,midpoint,atol=1e-12)
        for point in [[9.,14.],[9.,15.]]:
            self.assertGreater(np.linalg.norm(inferred-point),.49)
        self.assertEqual(len(fit['fitPoints']),6)
        self.assertNotIn([9,15],fit['fitPoints'])

    def test_sparse_and_collinear_anchors_abstain(self):
        self.assertIsNone(fit_confirmed(self.training[:5].tolist(),self.training[:5],self.geometry))
        points=np.array([[3,float(i)] for i in range(6)])
        self.assertIsNone(fit_confirmed(points.tolist(),points,self.geometry))

    def test_negative_height_is_marked_at_constraint_boundary(self):
        apparent=self.training-.01*(self.training-self.geometry['cameraGrid'])
        fit=fit_confirmed(self.training.tolist(),apparent,self.geometry)
        self.assertLess(fit['unconstrainedK'],0)
        self.assertEqual(fit['k'],0)
        self.assertTrue(fit['atConstraintBoundary'])


if __name__=='__main__':unittest.main()
