#!/usr/bin/env python3
"""Prepare a signed candidate and optionally replace the installed bundle.

Never launches/quits the app or changes recordings. Installation requires a green
validation artifact and keeps a verified copy of the previous installed bundle.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import uuid


def verify(app):
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)


def copy_app(source,destination):
    subprocess.run(['ditto',str(source),str(destination)],check=True)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-app',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--validation',type=Path,required=True)
    p.add_argument('--install',type=Path)
    p.add_argument('--version',default='0.194')
    p.add_argument('--build-number',default='195')
    a=p.parse_args()
    validation=json.loads(a.validation.read_text())
    if validation.get('readyForInstallation') is not True:
        raise SystemExit('Validation does not authorize installation of this candidate.')
    verify(a.source_app)
    executable=a.source_app/'Contents/MacOS/PhysicalGo'
    if hashlib.sha256(executable.read_bytes()).hexdigest()!=validation['appExecutableSHA256']:
        raise SystemExit('The built executable does not match the validated build.')
    a.output.mkdir(parents=True,exist_ok=False)
    candidate=a.output/'Physical Go candidate.app'
    copy_app(a.source_app,candidate)
    info=candidate/'Contents/Info.plist'
    data=plistlib.loads(info.read_bytes())
    data['PhysicalGoDeferredLocations']=True
    data['PhysicalGoReleaseCommit']=validation['commit']
    data['CFBundleShortVersionString']=a.version
    data['CFBundleVersion']=a.build_number
    info.write_bytes(plistlib.dumps(data))
    signature=subprocess.run(['codesign','-d','--verbose=4',str(a.source_app)],capture_output=True,text=True,check=True)
    authority=re.search(r'^Authority=(.+)$',signature.stderr,re.MULTILINE)
    identity=os.environ.get('PHYSICAL_GO_SIGN_IDENTITY') or (authority.group(1) if authority else None)
    if not identity or identity=='-':raise SystemExit('A stable signing identity is required for this release.')
    subprocess.run(['codesign','--force','--sign',identity,'--timestamp=none','--identifier','com.davemarvit.PhysicalGo',str(candidate)],check=True)
    verify(candidate)
    result=dict(candidate=str(candidate),version=data['CFBundleShortVersionString'],commit=validation['commit'],
                deferredLocationsEnabled=True,appRelaunched=False,recordingsModified=False)
    if a.install:
        if not a.install.is_dir():raise SystemExit('Expected an existing installed app to preserve for rollback.')
        backup=a.output/'Physical Go previous.app'
        copy_app(a.install,backup);verify(backup)
        staging=a.install.parent/f'.PhysicalGo-staging-{uuid.uuid4()}.app'
        previous=a.install.parent/f'.PhysicalGo-previous-{uuid.uuid4()}.app'
        copy_app(candidate,staging);verify(staging)
        # Both renames remain on the destination volume. Running processes are
        # not terminated; the updated executable takes effect on next launch.
        a.install.rename(previous)
        try:
            staging.rename(a.install)
            verify(a.install)
        except BaseException:
            if a.install.exists():a.install.rename(staging)
            previous.rename(a.install)
            raise
        shutil.rmtree(previous)
        result.update(installed=str(a.install),rollbackBundle=str(backup),takesEffect='next launch')
    (a.output/'release.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
