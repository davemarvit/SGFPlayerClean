import importlib.util
import unittest
from pathlib import Path
import uuid
import tempfile
import subprocess
import sys
import json
import time

spec=importlib.util.spec_from_file_location('bridge',Path(__file__).parents[1]/'Tools/laser_bridge_simulator.py')
bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)

class ContractTests(unittest.TestCase):
    def setUp(self):
        self.driver=bridge.Simulator()
        self.request=dict(schemaVersion=1,producer=str(uuid.uuid4()),sequence=1,sentAtUnix=100.,expiresAtUnix=100.6,action='off',reason='test',cameraContext='camera/grid',target=None)
        self.driver.consume(self.request,100.1)
    def point(self):
        self.request.update(sequence=2,action='point',target=dict(source='ai',session=str(uuid.uuid4()),moveNumber=2,size=19,row=18,col=0,black=False,decisionReceivedAtUnix=99.))
        return self.driver.consume(self.request,100.1)
    def test_off_handshake_required(self):
        self.request['producer']=str(uuid.uuid4())
        self.assertEqual(self.point()['state'],'off')
    def test_point_and_duplicates(self):
        result=self.point();self.assertEqual(result['state'],'adequate');self.assertFalse(result['laserOn'])
        self.assertEqual(self.driver.consume(self.request,100.2)['state'],'adequate')
    def test_changed_same_revision(self):
        self.point();self.request['target']['col']=4
        self.assertEqual(self.driver.consume(self.request,100.2)['state'],'off')
    def test_expired_and_future(self):
        self.point()
        self.assertEqual(self.driver.consume(self.request,100.7)['state'],'off')
        self.assertEqual(self.driver.consume(self.request,99.9)['state'],'off')
    def test_off_and_stale_revision(self):
        self.point();self.request.update(sequence=3,action='off')
        self.assertEqual(self.driver.consume(self.request,100.2)['state'],'off')
        self.request.update(sequence=2,action='point')
        self.assertEqual(self.driver.consume(self.request,100.3)['state'],'off')
    def test_invalid_coordinate(self):
        self.point();self.request['sequence']=3;self.request['target']['row']=19
        self.assertEqual(self.driver.consume(self.request,100.2)['state'],'off')
    def test_expired_revision_cannot_resurrect(self):
        self.point();self.driver.consume(self.request,101.)
        self.request.update(sentAtUnix=101.,expiresAtUnix=101.6)
        self.assertEqual(self.driver.consume(self.request,101.1)['state'],'off')
        self.request['sequence']+=1
        self.assertEqual(self.driver.consume(self.request,101.2)['state'],'adequate')
    def test_monotonic_lease_survives_wall_clock_rollback(self):
        self.point();deadline=self.driver.lease_deadline
        self.assertEqual(self.driver.consume(self.request,100.2,monotonic=deadline+.1)['state'],'off')
        self.request.update(sentAtUnix=100.3,expiresAtUnix=100.9)
        self.assertEqual(self.driver.consume(self.request,100.4,monotonic=deadline+.2)['state'],'off')
    def test_rereading_file_does_not_extend_lease(self):
        self.point();deadline=self.driver.lease_deadline
        self.driver.consume(self.request,100.2)
        self.assertEqual(self.driver.lease_deadline,deadline)
    def test_stream_revision_fingerprint(self):
        self.point();self.request['streamEpoch']=str(uuid.uuid4())
        self.assertEqual(self.driver.consume(self.request,100.2)['state'],'off')
    def test_bad_lease(self):
        self.request['expiresAtUnix']=float('nan')
        self.assertEqual(self.driver.consume(self.request,100.2)['state'],'off')
    def test_live_file_handshake_and_watchdog(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            process=subprocess.Popen([sys.executable,spec.origin,'--directory',directory],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
            def write(action,sequence):
                self.request.update(action=action,sequence=sequence,sentAtUnix=time.time(),expiresAtUnix=time.time()+.6)
                tmp=root/'request.tmp';tmp.write_text(json.dumps(self.request));tmp.replace(root/'request.json')
            def wait_for(state,sequence):
                deadline=time.monotonic()+2
                while time.monotonic()<deadline:
                    try:
                        status=json.loads((root/'status.json').read_text())
                        if status['state']==state and status['sequence']==sequence:return status
                    except (OSError,ValueError):pass
                    time.sleep(.02)
                self.fail('No matching status: '+state)
            try:
                write('off',1);wait_for('off',1)
                self.point();write('point',2)
                result=wait_for('adequate',2)
                self.assertEqual(result['mode'],'simulation');self.assertFalse(result['laserOn'])
                time.sleep(.7)
                wait_for('off',2)  # Expiry works with the consumer still running.
                write('off',3);wait_for('off',3)
            finally:
                process.terminate();process.wait(timeout=3);process.stderr.close()

    def test_supported_sizes(self):
        self.point()
        for size in [9,13,19]:
            self.request['sequence']+=1;self.request['target'].update(size=size,row=size-1,col=size-1)
            self.assertEqual(self.driver.consume(self.request,100.2)['state'],'adequate')

if __name__=='__main__':unittest.main()
