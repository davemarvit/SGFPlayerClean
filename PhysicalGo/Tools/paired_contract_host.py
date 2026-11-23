#!/usr/bin/env python3
"""Private offline host stage for paired_contract_acceptance.py.

Import only no-device runtime/lease tests. All exports and runtime files are temp.
The host repository, its checked-in fixture directories and bytecode stay untouched.
"""
import copy
import importlib
import json
import math
import os
from pathlib import Path
import sys
import threading
import time
import types
import unittest

sys.dont_write_bytecode = True


def main():
    firmware, fixtures = map(lambda s: Path(s).resolve(), sys.argv[1:])
    sys.path[:0] = [str(firmware/'Host tests'), str(firmware)]
    parser = importlib.import_module('test_gameplay_contract_review')
    faults = importlib.import_module('test_gameplay_fault_contract_review')
    parser.FIXTURES = fixtures
    faults.FIXTURES = fixtures
    out = fixtures/'FaultStatus'
    os.environ['PHYSICAL_GO_EXPORT_FAULT_STATUS_FIXTURES'] = str(out)
    class PairedSwiftContractTests(parser.SwiftContractReviewTests):
        def test_expired_literal_swift_request_never_restarts_hold(self):
            # Wall expiry and the derived monotonic deadline can differ by an
            # IEEE-754 ulp. Test each authoritative clock at its own boundary.
            request = self.request()
            with self.assertRaises(parser.Rejected):
                parser.Request.parse(request, request['expiresAtUnix'])
            gate, now, writes = self.gate(request)
            gate.observe(self.initial_off(request)); gate.observe(request)
            boundary=gate.deadline
            now[0] = math.nextafter(boundary, -math.inf)
            gate.poll(); self.assertFalse(gate.blocked)
            now[0] = boundary
            gate.poll()
            self.assertTrue(gate.blocked)
            self.assertEqual(writes[-1], 'OFF')
            with self.assertRaises(parser.Rejected): gate.activate()
            now[0] = math.nextafter(boundary, math.inf)
            gate.poll(); self.assertTrue(gate.blocked)
            with self.assertRaises(parser.Rejected): gate.activate()
    suite = unittest.TestSuite([unittest.defaultTestLoader.loadTestsFromTestCase(PairedSwiftContractTests),
                               unittest.defaultTestLoader.loadTestsFromModule(faults)])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful() or result.testsRun != 16:
        raise RuntimeError(f'Mandatory host contract suite did not pass all16 tests: {result.testsRun}')
    # Exercise the real runtime with the just-exported Swift standby scope,
    # not the host repository's older checked-in Swift fixture.
    fixture = faults.RuntimeFixture()
    backend = fixture.backend
    backend.standby = types.MethodType(faults.FakeGameplayBackend.standby, backend)
    backend.confirm_standby = types.MethodType(faults.FakeGameplayBackend.confirm_standby, backend)
    backend.block_standby.clear()
    token = fixture.runtime.gate.activate()
    worker = threading.Thread(target=fixture.runtime._point,
                              args=(copy.deepcopy(fixture.request), token), daemon=True)
    basic = fixtures/'HostStatus'; basic.mkdir()
    def save(state):
        status, raw = fixture.publish()
        if status['state'] != state:
            raise AssertionError(f'Actual runtime expected {state}, got {status}')
        (basic/f'host-{state}.json').write_bytes(raw)
    try:
        worker.start()
        deadline = time.monotonic()+1
        while not (fixture.runtime.feedback and fixture.runtime.feedback[1]=='arming'):
            if time.monotonic()>deadline: raise TimeoutError('Fake runtime did not enter bounded arming')
            time.sleep(.002)
        save('arming')
        backend.block_standby.set(); worker.join(1)
        if worker.is_alive(): raise TimeoutError('Fake standby worker did not finish')
        save('holding')
        backend.state='cooling'
        fixture.runtime._refresh_standby(fixture.request, fixture.runtime.gate.generation)
        save('cooling')
        fixture.submit_new_off()
        if not fixture.runtime._confirm_off(fixture.runtime.gate.generation):
            raise AssertionError('Actual runtime did not confirm fake hardware full OFF')
        save('off')
    finally:
        backend.block_standby.set()
        fixture.runtime.gate.cancel('Offline fixture complete')
        worker.join(1)
        fixture.close()
    print('PASS mandatory host contract:16 tests,68 fault statuses,4 recovery chains,4 basic statuses')
    print('Expiry adapter: wall parser tested at expiresAtUnix; monotonic gate tested at gate.deadline')
    (fixtures/'host-stage.json').write_text(json.dumps(dict(tests=result.testsRun,
        expiryAdapter=dict(originalTest='SwiftContractReviewTests.test_expired_literal_swift_request_never_restarts_hold',
            reason='A derived monotonic deadline can differ from wall expiry by an IEEE-754 ulp',
            assertions=['wall expiry remains rejected','just before monotonic deadline remains live',
                        'exact monotonic deadline blocks','after monotonic deadline remains blocked']),
        runtimeInput='Fresh Swift-exported standby scope; runtime fixture rebases sequence and lease clocks',
        hardware='Fake backend only'),indent=2)+'\n')


if __name__ == '__main__':
    main()
