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



    def test_invalid_measurements_and_camera_geometry_abstain(self):
        good=self.training+.01*(self.training-self.geometry['cameraGrid'])
        for value in [float('nan'),float('inf'),-float('inf')]:
            broken=good.copy();broken[0,0]=value
            self.assertIsNone(fit_confirmed(self.training.tolist(),broken,self.geometry))
        for centers in [good[:-1],good.ravel(),np.zeros((6,3))]:
            self.assertIsNone(fit_confirmed(self.training.tolist(),centers,self.geometry))
        for height in [0,-1,float('nan'),float('inf')]:
            self.assertIsNone(fit_confirmed(self.training.tolist(),good,dict(self.geometry,heightRowPitches=height)))
        for camera in [[1], [1,2,3], [float('nan'),23]]:
            self.assertIsNone(fit_confirmed(self.training.tolist(),good,dict(self.geometry,cameraGrid=camera)))

    def test_contour_bias_can_mimic_height(self):
        # Deliberately no physical height: a constant optical-center bias alone
        # creates a plausible positive scalar fit. A low residual is not proof
        # that the estimated height is identifiable physical thickness.
        apparent=self.training+np.array([0.,-.05])
        fit=fit_confirmed(self.training.tolist(),apparent,self.geometry)
        self.assertGreater(fit['effectiveHeightRowPitches'],.05)
        self.assertLess(fit['maxResidual'],.05)


if __name__=='__main__':unittest.main()
