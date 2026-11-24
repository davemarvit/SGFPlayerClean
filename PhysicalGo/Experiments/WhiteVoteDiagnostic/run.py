#!/usr/bin/env python3
"""Build an isolated logging copy of the native fitter; no source/app mutation."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

p=argparse.ArgumentParser(description=__doc__);p.add_argument('recording',type=Path);p.add_argument('output',type=Path);args=p.parse_args()
root=Path(__file__).resolve().parents[2]
args.output.mkdir(parents=True,exist_ok=False)
build=args.output/'build';build.mkdir()
original=root/'Sources/StoneGeometry.swift';source=original.read_text()
anchor='''        let contextual = !occlusion.isEmpty'''
assert source.count(anchor)==1
source=source.replace(anchor,'''        let diagnosticTrace=StoneVoteTrace.wants(reading)
        var diagnosticCells=[[Double]]()
'''+anchor)
anchor='''            let offset=y*(side+1)+x
            prefix[offset+1]=prefix[offset]+vote'''
assert source.count(anchor)==1
source=source.replace(anchor,'''            if diagnosticTrace,let current=frame.patchMean(p),let base=reference.patchMean(q),
               let color=frame.patchColor(p),let referenceColor=reference.patchColor(q) {
                let expected=referenceColor+colorShift
                let minimumWhite=shadedWhite ? base*0.75:base-0.06
                let colorCriterion=color.supportsWhiteStone(comparedTo:expected) && current-correction>minimumWhite
                let brightnessCriterion=current-correction>base+0.12
                diagnosticCells.append([c,r,current,base,colorCriterion ? 1:0,brightnessCriterion ? 1:0,white ? 1:0,
                    color.magnitude,expected.magnitude,color.red,color.green,color.blue,expected.red,expected.green,expected.blue])
            }
'''+anchor)
anchor='''        guard let best,best.quality>=minimumQuality,best.radiusCol>0.32,best.radiusCol<maximumRadius else { return nil }'''
assert source.count(anchor)==1
source=source.replace(anchor,'''        if diagnosticTrace {
            try! StoneVoteTrace.save(reading:reading,cells:diagnosticCells,correction:correction,colorShift:colorShift,
                best:best,searchSteps:searchSteps,shadedWhite:shadedWhite,masking:masking.count,occlusion:occlusion.count)
        }
'''+anchor)
modified=build/'StoneGeometry.swift';modified.write_text(source)
sys.path.insert(0,str(root));from scripts.build_sources import resolve_sources
sources=[root.parent/'SGFPlayerClean/Models'/name for name in ['OGSModels.swift','OGSScoringState.swift']]
sources += [root/'Sources'/name for name in ['BoardVision.swift','StoneGeometry.swift','BoardAppearanceDetector.swift']]
sources=resolve_sources(root,sources)
sources=[modified if path==original else path for path in sources]
sources.append(Path(__file__).with_name('VoteReplay.swift'))
executable=build/'VoteReplay'
command=['xcrun','swiftc','-swift-version','5','-D','PHYSICAL_GO','-O',*map(str,sources),'-o',str(executable)]
manifest={'purpose':'Read-only native fitter trace; only a generated source copy is instrumented','originalStoneGeometrySHA256':sha(original),
          'instrumentedStoneGeometrySHA256':sha(modified),'sources':{str(path):sha(path) for path in sources},
          'recording':str(args.recording),'image_sha256':sha(args.recording/'frames/000697.png'),'events_sha256':sha(args.recording/'events.jsonl'),
          'buildCommand':command,'generator_sha256':sha(Path(__file__))}
(args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
subprocess.run(command,check=True)
subprocess.run([str(executable),str(args.recording),str(args.output)],check=True)
