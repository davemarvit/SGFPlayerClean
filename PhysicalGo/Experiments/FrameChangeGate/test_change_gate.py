import unittest
import cv2
import numpy as np
from benchmark import run
from change_gate import changes,describe_rectified

class RegionChangeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result=run()
        cls.cases={x['name']:x for x in cls.result['cases']}

    def test_real_insertions_and_removals(self):
        for name,c in self.cases.items():
            if name.startswith('recorded/') and c['required'] is not None:
                with self.subTest(name=name):self.assertTrue(c['requiredFound'])

    def test_small_black_white_motion_and_edge_cells(self):
        for name,c in self.cases.items():
            if name.startswith('synthetic/') and c['required'] is not None:
                with self.subTest(name=name):self.assertTrue(c['requiredFound'])

    def test_noise_and_modest_illumination_do_not_select_whole_board(self):
        for name in ['same_pixels','sensor_noise_sigma2','uniform_5percent_dimmer']:
            self.assertEqual(self.cases['synthetic/'+name]['expandedCount'],0)
        self.assertLess(self.cases['synthetic/smooth_8percent_shadow']['expandedCount'],36)

    def test_camera_translation_and_scope_reset_request_every_region(self):
        for name in ['scope_reset','synthetic/camera_translation_2px']:
            self.assertEqual(self.cases[name]['expandedCount'],361)

    def test_no_claim_of_current_occupancy_or_safety(self):
        self.assertTrue(self.result['diagnosticOnly'])
        self.assertFalse(self.result['runtimeIntegrated'])
        for c in self.cases.values():
            self.assertFalse({'occupancy','handClear','alignmentValid','accepted'}.intersection(c))

    def test_boundary_and_fixed_anchor(self):
        wood=np.zeros((380,380,3),np.uint8);wood[:]=[140,170,190]
        def frame(col):
            x=cv2.resize(wood,(1520,1520),interpolation=cv2.INTER_NEAREST)
            cv2.circle(x,(round((col+.5)*80),760),32,(193,199,203),-1,lineType=cv2.LINE_AA)
            x=cv2.resize(x,(380,380),interpolation=cv2.INTER_AREA)
            return describe_rectified(x,np.ones((380,380),bool),19,'same')
        a,b=frame(9.35),frame(9.65)
        self.assertTrue({180,181}.issubset(changes(a,b)['expanded']))
        original=a.features.copy()
        for col in np.linspace(9.35,9.65,31):changes(a,frame(col))
        np.testing.assert_array_equal(a.features,original)
        self.assertTrue({180,181}.issubset(changes(a,b)['expanded']))

    def test_unknown_image_boundary_is_not_reused(self):
        image=np.full((380,380,3),160,np.uint8)
        valid=np.ones((380,380),bool);valid[0,0]=False
        a=describe_rectified(image,valid,19,'same')
        self.assertIn(0,changes(a,a)['expanded'])

if __name__=='__main__':unittest.main(verbosity=2)
