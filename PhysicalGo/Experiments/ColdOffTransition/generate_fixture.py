#!/usr/bin/env python3
"""Produce real host wire statuses with a fake command sink; never start IO threads."""
import argparse,hashlib,json,sys,tempfile
from pathlib import Path
sys.dont_write_bytecode=True
p=argparse.ArgumentParser();p.add_argument('--host-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();firmware=a.host_root/'Firmware';sys.path.insert(0,str(firmware))
from bridge_runtime import BridgeRuntime
from bridge_lease import Rejected

class FakeBackend:
    mode='hardware' # real-wire semantics, no device import/constructor
    capabilities=('darkMotorStandbyV1','capturedStoneIndication')
    current_setup_id='8d98ed7584c4265a'
    def __init__(self):self.commands=[]
    def send_now(self,command,**kwargs):self.commands.append(command);return 100.0
    def attach_runtime(self,runtime):pass
    def standby_command(self,generation):return None
    def forbidden(self,*args,**kwargs):raise AssertionError('No worker, camera, telemetry or hardware operation allowed')
    confirm_standby=standby=should_reengage=standby_receipt_current=supervise_once=forbidden
    def publication_snapshot(self,powered):
        return 100.0,1000.0,dict(policy='warm_hold',unavailableReason='bootstrap' if powered else 'power_off')

backend=FakeBackend()
request=dict(schemaVersion=1,producer='11111111-1111-4111-8111-111111111111',sequence=1,sentAtUnix=1000.0,expiresAtUnix=1000.6,action='off',reason='fixture',cameraContext='fixture-camera',streamEpoch='22222222-2222-4222-8222-222222222222')
a.output.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='pg37-host-fixture-') as folder:
    runtime=BridgeRuntime(folder,backend);runtime._configure_backend()
    runtime.gate.monotonic=lambda:100.0;runtime.gate.wall=lambda:1000.0
    runtime.latest_request=request.copy();runtime.gate.observe(request)
    assert runtime.gate.confirm_off(runtime.gate.generation,999.5)
    request.update(schemaVersion=2,sequence=2,playSession=dict(source='ai',session='33333333-3333-4333-8333-333333333333',size=9))
    runtime.latest_request=request.copy();runtime.gate.observe(request)
    runtime._publish()
    transition=json.loads((Path(folder)/'status.json').read_text())
    assert transition['state']=='transitioning' and transition['laserOn'] and not transition['illuminationConfirmed']
    assert transition['offSinceUnix'] is None and transition['motorsHeld'] is None
    assert not runtime.gate.workers and runtime.worker is None
    try:runtime.gate.activate()
    except Rejected:pass
    else:raise AssertionError("OFF request cannot activate a worker")
    (a.output/'request.json').write_text(json.dumps(request,indent=2)+'\n')
    (a.output/'transition.json').write_text(json.dumps(transition,indent=2)+'\n')
    assert runtime.gate.confirm_off(runtime.gate.generation,999.5)
    runtime.evidence=(runtime.gate.generation,dict(streamEpoch=request['streamEpoch'],frameID=1,timestampSource='cameraPresentation'))
    runtime._publish();off=json.loads((Path(folder)/'status.json').read_text())
    assert off['state']=='off' and off['motorsHeld'] is False and off['motorBusPowered'] is False
    (a.output/'full-off.json').write_text(json.dumps(off,indent=2)+'\n')
assert backend.commands==['OFF','OFF'],backend.commands
sources={name:hashlib.sha256((firmware/name).read_bytes()).hexdigest() for name in ('bridge_runtime.py','bridge_lease.py','bridge_thermal.py','bridge_errors.py')}
(a.output/'provenance.json').write_text(json.dumps(dict(host_root=str(a.host_root),source_hashes=sources,commands=backend.commands,claim='Production parser/gate/publisher with fake command sink; not a retained live bad status.'),indent=2)+'\n')
print('PASS: actual host cold OFF replacement publishes transitioning then full OFF; only two fake OFF writes, no worker')
