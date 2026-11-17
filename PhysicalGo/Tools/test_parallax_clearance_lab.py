import copy,unittest
import numpy as np
from parallax_lab import fit_field,prediction,evaluate,assignment_offsets,camera_geometry
from hand_clearance_lab import RimClearance

class GeometryTests(unittest.TestCase):
    def scene(self):
        raw=[['empty',1.0] for _ in range(361)];before=['empty']*361;shapes=[]
        for x,y in [(2,2),(16,2),(2,16),(16,16),(9,3),(9,15),(4,9),(14,9)]:
            before[y*19+x]='black';raw[y*19+x]=['black',.99]
            d=.018*(np.array([x,y])-[24,9])
            shapes.append(dict(col=x,row=y,center=dict(x=x+d[0],y=y+d[1]),radiusCol=.46,radiusRow=.48,quality=.99))
        return raw,before,shapes
    def test_spatial_camera_distance(self):
        raw,before,shapes=self.scene();field=fit_field(shapes,raw,before)
        self.assertIsNotNone(field)
        np.testing.assert_allclose(field['coefficients'],[-.432,-.162,.018],atol=1e-8)
        self.assertGreater(abs(prediction(field,[2,9])[0]),abs(prediction(field,[16,9])[0]))
    def test_raw_perspective_recovers_known_camera(self):
        def rotation(axis,a):
            c,s=np.cos(a),np.sin(a)
            if axis==0:return np.array([[1,0,0],[0,c,-s],[0,s,c]])
            return np.array([[c,0,s],[0,1,0],[-s,0,c]])
        R=rotation(0,.5)@rotation(1,.2);t=np.array([-9.,-10.,30.])
        K=np.array([[1000,0,959.5],[0,1000,539.5],[0,0,1.]])
        H=K@np.column_stack([R[:,0]*1.1*18,R[:,1]*18,t]);H=H/H[2,2]
        H=np.diag([1/1919,1/1079,1])@H
        model=camera_geometry({'size':19,'h':H.ravel()[:8].tolist()},1920,1080)
        self.assertAlmostEqual(model['focalPixels'],1000,places=7)
        np.testing.assert_allclose(model['cameraGrid'],[-R[:,0]@t/1.1,-R[:,1]@t],atol=1e-8)
        self.assertAlmostEqual(model['heightRowPitches'],abs(R[:,2]@t))
        self.assertFalse(model['assumptionsVerified'])
    def test_frontal_or_degenerate_camera_abstains(self):
        self.assertIsNone(camera_geometry({'size':19,'h':[.8,0,.1,0,.8,.1,0,0]},1920,1080))
    def test_holdout_cannot_train_itself(self):
        raw,before,shapes=self.scene();p=4*19+4;before[p]='white';raw[p]=['white',.91]
        base=fit_field(shapes,raw,before,excluded=[p])
        shapes.append(dict(col=4,row=4,center=dict(x=4.4,y=4.4),radiusCol=.46,radiusRow=.48,quality=1))
        self.assertEqual(base,fit_field(shapes,raw,before,excluded=[p]))
    def test_geometry_relief_without_changing_color_or_input(self):
        raw,before,shapes=self.scene();p=4*19+4;raw[p]=['white',.91]
        d=.018*(np.array([4,4])-[24,9])
        shapes.append(dict(col=4,row=4,center=dict(x=4+d[0],y=4+d[1]),radiusCol=.46,radiusRow=.48,quality=.96))
        frozen=copy.deepcopy((raw,before,shapes));result=evaluate(shapes,raw,before,[p])
        self.assertTrue(result['targets'][0]['proposedRelief']);self.assertFalse(result['clockAuthority'])
        self.assertFalse(result['changesCaptureHandling']);self.assertEqual(frozen,(raw,before,shapes))
    def test_halfway_placement_stays_unresolved(self):
        raw,before,shapes=self.scene();p=4*19+4;raw[p]=['white',.91]
        d=.018*(np.array([4,4])-[24,9])+[-.5,0]
        shapes.append(dict(col=4,row=4,center=dict(x=4+d[0],y=4+d[1]),radiusCol=.46,radiusRow=.48,quality=.96))
        result=evaluate(shapes,raw,before,[p]);self.assertFalse(result['targets'][0]['proposedRelief'])
        self.assertGreaterEqual(result['targets'][0]['proposedOffset'],.3)
    def test_sparse_and_collinear_support_abstain(self):
        raw,before,shapes=self.scene();self.assertIsNone(fit_field(shapes[:5],raw,before))
        for s in shapes:s['row']=2;s['center']['y']=2
        self.assertIsNone(fit_field(shapes,raw,before))
    def test_empty_uncertain_and_wrong_color_never_seed_field(self):
        raw,before,shapes=self.scene()
        for i,s in enumerate(shapes):raw[s['row']*19+s['col']]=[['empty',1],['uncertain',1],['white',1]][i%3]
        self.assertIsNone(fit_field(shapes,raw,before))
    def test_no_shape_no_geometry_promotion(self):
        raw,before,shapes=self.scene();p=180;raw[p]=['black',.99]
        self.assertFalse(evaluate(shapes,raw,before,[p])['targets'][0]['proposedRelief'])
    def test_physical_scale_sign_and_bound(self):
        raw,before,shapes=self.scene()
        for s in shapes:
            s['center']['x']=s['col']-.01*(s['col']-9)
            s['center']['y']=s['row']-.01*(s['row']-9)
        self.assertGreaterEqual(fit_field(shapes,raw,before)['coefficients'][2],0)

class ClearanceTests(unittest.TestCase):
    def row(self,t,**changes):
        v=dict(time=t,poseClear=True,gap=False,result=dict(obstructed=True,depth=.15,edge=0,estimate={'time':2.3}))
        v.update(changes);return v
    def test_camera_gap_restarts_wait(self):
        p=RimClearance(seconds=.8)
        for t in [0,.2,.4,.6]:self.assertFalse(p.step(self.row(t))['proposedClear'])
        self.assertFalse(p.step(self.row(3,gap=True))['proposedClear'])
    def test_missing_pose_is_not_clear(self):
        p=RimClearance(seconds=.4)
        for t in [0,.2,.4,.6,1]:self.assertFalse(p.step(self.row(t,poseClear=False))['proposedClear'])
    def test_original_timing_not_replaced_by_timeout(self):
        p=RimClearance(seconds=.4)
        for t in [0,.2,.4,.6]:result=p.step(self.row(t))
        self.assertTrue(result['proposedClear']);self.assertIsNone(result['pressEstimate'])
        self.assertEqual(result['sourceTimingUnchanged'],{'time':2.3});self.assertFalse(result['clockAuthority'])
    def test_fingertip_counterexample_exposes_unsafe_rule(self):
        p=RimClearance(seconds=3)
        result=None
        for t in np.arange(0,5,.2):result=p.step(self.row(float(t)))
        # Same observed shallow component could be a stationary real fingertip.
        # This assertion documents why this rule must NOT be promoted.
        self.assertTrue(result['proposedClear'])

if __name__=='__main__':unittest.main()
