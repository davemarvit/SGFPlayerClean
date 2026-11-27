"""Build offline, self-contained process maps. Does not import application code."""
from pathlib import Path
import html, json, re

OUT = Path(__file__).resolve().parent
SNAPSHOT = json.loads((OUT/'release-snapshot.json').read_text())
NATIVE = Path(SNAPSHOT['native_source'])
HOST = Path(SNAPSHOT['host_source'])
DOCS = Path('/Users/Dave/SGFPlayerClean/PhysicalGo/Documentation')
sources = {
 'S1': (DOCS/'IntegrationChecklist.md', 'Current authoritative issue register; live status outranks map snapshot'),
 'S2': (DOCS/'AgentGuide/Architecture.md', 'State ownership and architecture'),
 'S3': (DOCS/'CalibrationAndTiming.md', 'Calibration stages; historical overrides are calibration-only'),
 'S4': (NATIVE/'CameraCapture.swift', 'Camera serial queue and delivery'),
 'S5': (NATIVE/'CameraFrameTimestamp.swift', 'Presentation capture time versus callback arrival'),
 'S6': (NATIVE/'CameraAnalysisPipeline.swift', 'Serial analysis, early safety, immutable results'),
 'S7': (NATIVE/'LatestAnalysisInput.swift', 'One replaceable pending analysis input'),
 'S8': (NATIVE/'PhysicalLaserFrameBroker.swift', 'Independent safety and image publication queues'),
 'S9': (NATIVE/'LatestFileExchange.swift', 'Independent bounded request/status IO'),
 'S10': (NATIVE/'PhysicalAI.swift', 'Recognition, legal commit, pending physical placement and guidance'),
 'S11': (NATIVE/'PhysicalLaserGuidance.swift', 'Dark admission, leases, arming episodes, faults'),
 'S12': (HOST/'Tools/launch_reviewed_feedback.py', 'Attended READY, repeated preflight and child shutdown receipt'),
 'S13': (HOST/'bridge_runtime.py', 'Input/coordinator/supervision/worker threads and cancellation'),
 'S14': (HOST/'bridge_frames.py', 'Frame identity and independent capture/publication/arrival ages'),
 'S15': (HOST/'bridge_feedback.py', 'One active-work ledger, sole recovery owner, optical publication and held correction'),
 'S16': (HOST/'bridge_optical_geometry.py', 'Three-frame dark baseline; independent lit certificate; coherent dark requalification'),
 'S17': (HOST/'bridge_alignment.py', 'Fixed-anchor temporal tracking and independent correspondence proof'),
 'S18': (HOST/'dark_geometry_registration.py', 'ECC proposes; independent ORB/grid geometry admits'),
 'S19': (HOST/'bridge_setup.py', 'Setup hashes, camera/context/size and native grid agreement'),
 'S20': (HOST/'feedback_predicted_acquisition.py', 'Conditional model travel; fresh optical reacquisition still required'),
 'S21': (HOST/'AimControl/AimControl.ino', 'Firmware motor, heartbeat, temperature and finite light controls'),
 'S22': (DOCS/'AgentGuide/GameAIClocks.md', 'AI/local/online clock boundaries and persistence'),
 'S23': (DOCS/'AgentGuide/Markers.md', 'Placement/capture/centering evidence and priority'),
 'S24': (DOCS/'AgentGuide/RecordingReviewScoring.md', 'Local recording, chronology, explicit scoring approval'),
 'S25': (NATIVE/'PhysicalGuidanceRecovery.swift', 'Classified transient OFF barrier and fresh witness recovery'),
 'S26': (HOST/'bridge_lease.py', 'Generation cancellation and independently enforced lease'),
 'S27': (HOST/'bridge_thermal.py', 'Thermal supervision and causal telemetry freshness'),
 'S28': (HOST/'feedback_work_budget.py', '150s shared active ledger, 25 local plans, non-resetting recovery episode'),
 'S29': (HOST/'feedback_result_age.py', 'Typed finite optical-result expiry; original timestamps'),
 'S30': (HOST/'feedback_anchor_store.py', 'Ordered background persistence of historical measured hints'),
 'S31': (NATIVE/'PhysicalMotorAdmission.swift', 'Phase-aligned cold admission; authenticated monitor liveness'),
 'S32': (NATIVE/'WoodenBoardPerimeter.swift', 'Explicit physical-wood support; not a guessed grid/rim perimeter'),
 'S33': (HOST/'bridge_lit_geometry.py', 'Measured laser-only geometry exclusion and bounded optional work'),
 'S34': (HOST/'point_session.py', 'Actual write-lock and before-write boundary'),
 'S35': (HOST/'Feedback recovery contract.md', 'One-owner recovery contract and limits'),
 'S36': (HOST/'laser_bridge.py', 'Flag-only signal, startup cancellation and shutdown receipt ownership'),
 'S37': (DOCS/'ReturnedO17Failure20261127.md', 'Historical returned O17 evidence; installed repair does not validate that failed run'),
 'S38': (HOST/'Experiments/IPCLatencyIsolation/README.md', 'I/O isolation, newer-frame reread, shutdown fences and remaining filesystem limits'),
 'S39': (Path(SNAPSHOT['installation_receipt']), 'Root installation receipt; physical validation remains separate'),
 'S40': (NATIVE/'BoardVision.swift', 'Positive EMPTY receipt producer, original capture binding and invalidation'),
 'S41': (DOCS/'RequirementsRelease20261127.md', 'Current installed release and latest attended failure; acceptance remains open'),
 'S42': (NATIVE/'PhysicalLatencyTrace.swift', 'Opt-in bounded wall/thread-CPU stage records; no timing authority'),
 'S43': (NATIVE.parent/'Experiments/CameraStageTiming/README.md', 'Camera-stage attribution, original provenance and interpretation limits'),
 'S44': (HOST/'Experiments/SerialShutdownEvidence/README.md', 'Post-worker serial tail, raw OFF observation and separate gate verdict'),
 'S45': (HOST/'bridge_shutdown_receipt.py', 'Diagnostic receipt fields do not change full-OFF verification'),
 'S46': (NATIVE/'DiagnosticRecorder.swift', 'Image admission, gap journal and periodic/final atomic manifest publication'),
 'S47': (NATIVE/'DiagnosticManifest.swift', 'Compact immutable inline recording context cache; unchanged schema'),
 'S48': (NATIVE.parent/'Experiments/DiagnosticManifestCache/README.md', 'Retained manifest amplification, compatible cache repair and remaining queue limits'),
}

diagrams=[]
def diagram(key,title,desc,height,nodes,edges,refs):
    diagrams.append(dict(key=key,title=title,desc=desc,height=height,nodes=nodes,edges=edges,refs=refs))
def n(id,x,y,title,body,kind='process',w=300,h=96):
    return dict(id=id,x=x,y=y,w=w,h=h,title=title,body=body,kind=kind)
def e(a,b,label='',route=None,kind='normal'):
    return dict(a=a,b=b,label=label,route=route,kind=kind)

diagram('overview','1 · The complete system','Separate observed stones, legal history, requested guidance and actual hardware state.',790,[
 n('setup',50,35,'A. Qualify the setup','Grid + motor map + wood profile\nIndependent checks + fresh READY','gate'),
 n('camera',50,225,'B. Observe the board','One app camera; fresh frames\nHand, grid, stones, uncertainty'),
 n('game',400,225,'C. Decide and preserve','Local recorder / AI / online\nLegal history + clocks + save'),
 n('guide',750,225,'D. Request guidance','AI placement → capture → hint\nExact target + bounded lease'),
 n('host',750,415,'E. Aim and monitor','Measure → hold → bounded recovery\nLost authority → full OFF'),
 n('human',400,415,'F. Human changes board','Place indicated stone; remove\ncaptures; center when needed'),
 n('confirm',50,415,'G. Verify physical change','Clear, dark, fresh evidence\nStable legal / cleanup result','gate'),
 n('save',400,625,'Review / end / restore','Preserve pending physical work\nExplicit scoring / resume'),
 n('fault',750,625,'Fault or pause → request OFF','Require beam / motor OFF receipt\nMissing receipt remains unknown','fault'),
],[e('setup','camera'),e('camera','game'),e('game','guide'),e('guide','host'),e('host','human','visible cue'),e('human','confirm'),e('confirm','camera','next evidence',[(30,463),(30,273)]),e('confirm','game','accepted',[(375,463),(375,205),(550,205)]),e('game','save','review / end',[(550,345),(720,345),(720,598),(550,598)]),e('host','fault','any hard fault'),e('save','fault','pause / stop')],['S1','S2','S22','S23','S24'])

diagram('calibration','2 · Two calibrations, then permission to play','A grid fit maps pixels to intersections. A motor fit maps encoder poses to the laser spot. Neither proves current clearance.',1120,[
 n('select',50,30,'Select actual app camera','Verify device, dimensions, epoch\nand advancing presentation times'),
 n('grid',50,205,'Fit camera → board grid','Find intersections / perspective\nValidate boundaries + interior'),
 n('ref',50,380,'Retain geometry/reference','Native grid + physical-wood profile\nUnknown perimeter stays unknown'),
 n('measure',400,205,'Measure pointer → board','Observe spot at measured poses\nAttended, guarded motor samples'),
 n('fit',400,380,'Fit candidate motor map','Predict target pose; quantify fit\nNot a physical test of 361 points'),
 n('check',400,555,'Independent optical checks','Separate targets + actual spot\nReject moved / invalid setup','gate'),
 n('bind',400,730,'Bind approved setup','Hashes: model/setup/reference/profile\nCamera/context/size/allowed targets'),
 n('verify',750,555,'Verify installed release','Pinned app + host + firmware\nRead-only camera preflight ×3','gate'),
 n('ready',750,730,'Attended READY gate','Recheck package + camera ×3\nExact controller identity + free port','gate'),
 n('launch',750,915,'Open one host / controller','Fresh OFF handshake + capabilities\nHistorical hint needs fresh proof'),
 n('moved',50,730,'If board/camera/pointer moves','Requalify affected relationships\nA matching file hash is insufficient','fault'),
],[e('select','grid'),e('grid','ref'),e('grid','measure'),e('measure','fit'),e('fit','check'),e('check','bind'),e('bind','ready'),e('verify','ready'),e('ready','launch'),e('ref','bind','identity + geometry',[(375,428),(375,778)]),e('moved','grid','fresh qualification',[(25,778),(25,253)])],['S3','S12','S19','S30','S32','S1'])

diagram('data','3 · Camera, processing and file boundaries','Native safety and pixels use separate lanes. Host request and status loops are independent. Optional stage traces measure cost. Recording caches immutable manifest context; gaps stay journaled and do not trigger full rewrites.',1220,[
 n('capture',50,30,'Camera serial queue','AVFoundation presentation time\nCapture + arrival + epoch/frame ID'),
 n('main',50,215,'Main actor: session snapshot','Camera/grid/reference/expected board\nRevision rejects stale completions'),
 n('vision',400,215,'Serial vision worker','Physical wood / grid / hand support\nThen stone/shape/assignment evidence'),
 n('latest',400,30,'Latest-only pending input','One replaceable waiting frame\nNo accumulated analysis backlog','store'),
 n('safety',750,215,'Early safety → main actor','Current revision + actual timestamps\nIndependent of geometry exclusions'),
 n('observe',400,430,'Final observation → game','Same immutable analysis context\nGame applies own dark/stable gates'),
 n('png',50,430,'Image preparation / broker','PNG work overlaps analysis\nCache key: epoch + frame ID'),
 n('manifest',50,630,'Image queue → latest.json','Publish exact checked PNG first\nOne pending; retain four PNGs','store'),
 n('safejson',750,430,'Safety queue → safety.json','Separate atomic publication\nNo matching pixels promised','store'),
 n('io',400,630,'Request / status IO queues','One read + one write in flight\nOne replaceable pending request','store'),
 n('reader',50,840,'Host optical worker','Read matching PNG + manifest\nCheck four ages ≤600 ms','gate'),
 n('supervisor',750,630,'Host safety supervision','Hand / camera / lease / thermal\nCan revoke busy optical worker'),
 n('status',400,840,'Host request reader','Dedicated bounded request read\nGate checks identity / lease / stop'),
 n('publisher',50,1050,'Host status writer: one owner','No queue; skip concurrent publish\nOld snapshot fenced at replacement'),
 n('reread',400,1050,'Raw expiry: one newer reread','Same scope; newer frame ID + capture\nOriginal 600 ms checks stay in force'),
 n('stopfence',750,1050,'Stop fences on background I/O','Before snapshot / lease poll / rename\nOnly close may publish final OFF','gate'),
],[e('capture','main'),e('capture','latest'),e('latest','vision'),e('main','vision'),e('vision','safety'),e('vision','observe'),e('main','png'),e('png','manifest'),e('safety','safejson'),e('safejson','supervisor'),e('observe','io'),e('manifest','reader'),e('reader','publisher'),e('io','status','request'),e('supervisor','status','revoke / monitor',[(900,790),(650,790)]),e('status','publisher',route=[(375,888),(375,1010),(200,1010)]),e('publisher','io','status',[(30,1098),(30,790),(550,790)]),e('reader','reread',route=[(375,888),(375,1010),(550,1010)])],['S4','S5','S6','S7','S8','S9','S13','S14','S34','S37','S38','S42','S43','S46','S47','S48'])

diagram('gameplay','4 · AI game and physical placement','The AI move enters legal history before its stone is physically placed. pendingPlacement preserves that difference.',1170,[
 n('resume',50,30,'Start / explicit Resume','Restore accepted save + clocks\nVerify physical board matches'),
 n('observe',50,210,'Admit observation','Current context; clear and aligned\nConfirmed dark + post-dark frame','gate'),
 n('ambiguity',50,390,'Resolve assignment','Unique new-stone assignment\nPG23: current qualified EMPTY only','gate'),
 n('stable',50,570,'Collect stable witnesses','≥3 distinct frames spanning 450 ms\nGaps >600 ms reset continuity','gate'),
 n('legal',50,750,'Accept legal human move','Rules + captures → history/save\nClock ownership changes here'),
 n('ai',400,750,'Ask KataGo','Normal or fast-test settings\nRetained idle worker in fast mode'),
 n('commit',750,750,'Commit AI answer','Validate move; save decision time\nSet pendingPlacement; switch turn'),
 n('request',750,570,'Select physical guidance','Placement → capture → centering\nKeep pre-placement referenceCells'),
 n('aim',750,390,'Host aims / holds dot','Aim / hold / recover same target\nCue needs original fresh optical proof'),
 n('human',750,210,'Human places / removes','Hand or stone suspicion darkens\nLit evidence cannot confirm a move'),
 n('match',400,570,'Expected board now matches?','Pending placement / cleanup ends\nOnly after admitted stable evidence','gate'),
 n('wait',400,390,'Unclear / halfway / illegal','Wait or show correction markers\nNever silently alter legal history'),
 n('end',400,965,'Pass / finish / pause / save','Hard guidance fault pauses clocks\nExplicit Resume keeps pending work'),
],[e('resume','observe'),e('observe','ambiguity'),e('ambiguity','stable','unique'),e('ambiguity','wait','unclear'),e('wait','observe','new evidence',[(550,350),(200,350)]),e('stable','legal','new human move'),e('stable','match','saved position'),e('legal','ai'),e('ai','commit'),e('commit','request'),e('request','aim'),e('aim','human'),e('human','observe','new dark evidence',[(900,180),(200,180)]),e('match','observe','next human turn',[(375,618),(375,258)]),e('ai','end','pass / end'),e('match','end','pause / fault',[(710,618),(710,1013)])],['S10','S11','S22','S23','S25','S40'])

diagram('laser','5 · Aim, publish and hold one target','Measured optical anchors and target-adequate evidence are different results. The same operation owns initial aiming and every recovery.',1390,[
 n('admit',50,30,'Admit current request','Binding + fresh frame + identity\nHistorical anchor is only a hint','gate'),
 n('arm',400,30,'Cold GA / warm RS','Dark engagement; phase evidence\nNo admission-clock reset on retry'),
 n('prepare',400,210,'Prepare while dark','Three new dark frames + grid fit\nFresh actual pose + first-light proof'),
 n('initial',400,395,'Measure actual spot','SWEEP + fresh stationary batch\nPost-image causal motor evidence'),
 n('coarse',50,585,'Initial predicted travel once','Dark contained coarse waypoints\nSame active time; separate step cap'),
 n('observe',50,790,'Observe actual landing','Coarse / recovery: full-board batch\nOrdinary fine: measured near estimate'),
 n('fine',400,790,'Contained local correction','Charge shared correction-plan ledger\nFresh settled frame fence; remeasure'),
 n('accept',750,585,'Within 0.20 cell','Fresh optical target acceptance\nKeep accepted beam if eligible','gate'),
 n('hold',750,790,'Independent held verification','Recheck exact evidence + scope\nPublish adequate; then native cue','gate'),
 n('monitor',750,1000,'Monitor current held target','Outside band → withdraw adequate\nFresh confirmation → bounded repair'),
 n('renew',400,1190,'Renew geometry certificate','Fresh fixed-anchor lit proof if valid\nDefer optional work / DARK fallback'),
 n('anchor',50,1000,'Persist historical measured hint','After gated optical publication\nValid even if requested target missed','store'),
 n('placement',750,1190,'Hand / placement / new intent','Revoke old operation → dark/OFF\nNative independently confirms stone'),
 n('budget',50,1190,'One work ledger','150s active / 25 local plans\nStable adequate waiting excluded','gate'),
],[e('admit','arm'),e('arm','prepare'),e('prepare','initial'),e('initial','coarse','outside band',[(200,443)]),e('initial','accept','accepted beam',[(900,443)]),e('coarse','observe'),e('observe','fine','outside band'),e('fine','observe','remeasure',[(550,940),(200,940)]),e('observe','accept','measured pass',[(375,838),(375,720),(735,720),(735,633)]),e('accept','hold'),e('hold','monitor'),e('monitor','placement'),e('monitor','renew','renewal due',[(725,1048),(725,1238)]),e('renew','prepare','DARK when needed',[(720,1238),(720,175),(550,175)]),e('observe','anchor','published sample')],['S15','S16','S20','S28','S29','S30','S33','S34','S35'])

diagram('recovery','6 · One recovery owner; full OFF remains the fallback','One scope/deadline governs recovery. Flag-only signals and stopped-background fences protect shutdown; success still requires an actual OFF receipt.',1730,[
 n('input',400,25,'Held crossing / typed failure','Withdraw adequate immediately\nEnter existing shared work ledger'),
 n('cross',50,220,'Measured error >0.20 cell','Newer full-board confirmation\nNo wider adequate band','gate'),
 n('expiry',400,220,'Finite optical-result expiry','Discard old result; check live safety\nReacquire pose + newer full-board data'),
 n('geometry',750,220,'Coherent geometry candidate','DARK first, including PREPARE\nAssess exact rejected pixels only'),
 n('confirm',50,420,'Confirmation still outside?','Use contained local correction\nThen independent held observation'),
 n('fresh',400,420,'Same operation / current proof','Original target, token and session\nOnly acknowledged own RS may advance','gate'),
 n('fit',750,420,'Qualify replacement geometry','Three newer dark frames; validate\nInstall only after replacement passes','gate'),
 n('hint',750,620,'Historical containment only','Old sample/H grants no movement\nFresh pose + full-board spot required'),
 n('adequate',400,820,'Current adequate publication','Same-sample age / pose / hand checks\nRecheck original cue age at native','gate'),
 n('lease',50,620,'Shared finite recovery episode','≤30s provisional wall cap\nNested retries never restart it','gate'),
 n('failure',50,1020,'Any unqualified failure','Unknown hand/spot, lost lease,\ntransport, identity or exhausted work','fault'),
 n('cancel',400,1020,'Revoke → quiesce → full OFF','Coordinator owns stop + receipt\nNo transport writes inside validators'),
 n('off',750,1020,'Require full OFF receipt','Beam off + motor power released\nNot merely DARK with motors held','gate'),
 n('dark',750,1220,'Post-dark physical evidence','Same stream + watermark + flush\nNo stone acceptance from a receipt'),
 n('resume',400,1400,'Native recovery / explicit Resume','Preserve pending move and clocks\nHardware recovery cannot resume game'),
 n('nooff',50,1220,'Missing receipt: state unknown','Raw OFF ≠ gate-accepted receipt\nDiagnostics grant no OFF authority','fault'),
 n('signal',50,1575,'Signal: assign plain stop flag','Handler takes no Event/runtime locks\nNormal control flow performs cleanup'),
 n('startupstop',750,1575,'Startup and late-I/O cancellation','Stop predicate checked before launch\nStopped readers cannot admit or poll'),
],[e('input','cross',route=[(200,155)]),e('input','expiry'),e('input','geometry',route=[(900,155)]),e('cross','confirm'),e('confirm','adequate','independent recheck',[(375,468),(375,780),(550,780)]),e('expiry','fresh'),e('fresh','adequate'),e('geometry','fit'),e('fit','hint'),e('hint','adequate','new optical proof',[(900,780),(550,780)]),e('failure','cancel'),e('cancel','off'),e('cancel','nooff','no receipt',[(350,1068),(350,1160),(200,1160)]),e('off','dark'),e('dark','resume','fresh evidence',[(900,1448)])],['S11','S13','S15','S16','S25','S26','S28','S29','S34','S35','S36','S37','S38','S44','S45'])

diagram('modes','7 · Local recording, online play and review','The camera pipeline is shared. Move acceptance, clocks and persistence have different owners in each mode.',910,[
 n('observation',400,25,'Admitted board observations','Same camera / wood / hand pipeline\nMode owns evidence + move acceptance'),
 n('local',50,220,'Local: GameRecorder','Legal transition + chronology\nDeferred / uncertain history retained'),
 n('ai',400,220,'AI: PhysicalAI','Human + KataGo legal history\nPhysical pending placement tracked'),
 n('online',750,220,'Online: SGF Player bridge','Ephemeral physical-board bridge\nServer state / clocks authoritative'),
 n('clock',50,415,'Local clocks + recording','SGF + clock/review sidecars\nOrdered writes; failure stops saves'),
 n('aisave',400,415,'AI snapshot + elapsed clocks','current.json authoritative\nSGF export derived; no time forfeits'),
 n('gap',750,415,'Online laser integration gap','Wire source=online is not proof\nof an end-to-end target producer','fault'),
 n('review',50,615,'Review / corrections / undo','Resolve uncertainty explicitly\nDo not retime accepted moves'),
 n('analysis',400,615,'KataGo review / forecast','Cancellable historical analysis\nCoverage gaps stay visible'),
 n('score',50,790,'Explicit scoring agreement','Pause; analyze; approve corrections\nAgree result only after review'),
],[e('observation','local',route=[(200,140)]),e('observation','ai'),e('observation','online',route=[(900,140)]),e('local','clock'),e('ai','aisave'),e('online','gap'),e('clock','review'),e('clock','analysis','analysis',[(375,463),(375,580),(550,580)]),e('review','score'),e('analysis','score','proposal only',[(550,760),(200,760)])],['S2','S22','S24'])

COLORS={'process':('#eaf2ff','#23538a'),'gate':('#fff4d9','#805d16'),'store':('#edf5ef','#386347'),'fault':('#fff0ef','#99433b')}
def esc(s):return html.escape(str(s),quote=True)
def svg(d):
    width=1120; nodes={v['id']:v for v in d['nodes']}
    occupied=[]
    for v in d['nodes']:occupied.append((v['x']-5,v['y']-5,v['x']+v['w']+5,v['y']+v['h']+5))
    parts=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {d["height"]}" width="{width}" height="{d["height"]}" role="img" aria-labelledby="{d["key"]}-title {d["key"]}-desc">',f'<title id="{d["key"]}-title">{esc(d["title"])}</title><desc id="{d["key"]}-desc">{esc(d["desc"])}</desc>', '<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto-start-reverse"><path d="M 1 1 L 9 5 L 1 9" fill="none" stroke="#5e6c7d" stroke-width="1.5"/></marker></defs>', '<style>text{font-family:Arial,Helvetica,sans-serif;fill:#182b40}.edge-label{font-size:14px;paint-order:stroke;stroke:#fff;stroke-width:7px;stroke-linejoin:round}.node-title{font-size:18px;font-weight:600}.node-body{font-size:15px}</style>','<rect width="100%" height="100%" fill="#fff"/>']
    for edge in d['edges']:
        a,b=nodes[edge['a']],nodes[edge['b']]
        ac=(a['x']+a['w']/2,a['y']+a['h']/2);bc=(b['x']+b['w']/2,b['y']+b['h']/2)
        route=edge['route']
        def boundary(node,t):
            cx=node['x']+node['w']/2;cy=node['y']+node['h']/2
            dx=t[0]-cx;dy=t[1]-cy
            if abs(dx)/(node['w']/2)>abs(dy)/(node['h']/2):return (cx+(node['w']/2 if dx>0 else -node['w']/2),cy)
            return (cx,cy+(node['h']/2 if dy>0 else -node['h']/2))
        start=boundary(a,route[0] if route else bc);end=boundary(b,route[-1] if route else ac)
        points=[start]+(route or [])+[end]
        # Route with explicit right angles, preserving designer waypoints.
        orth=[points[0]]
        for p in points[1:]:
            old=orth[-1]
            if old[0]!=p[0] and old[1]!=p[1]:orth.append((p[0],old[1]))
            orth.append(p)
        parts.append('<polyline points="'+' '.join(f'{x},{y}' for x,y in orth)+'" fill="none" stroke="#5e6c7d" stroke-width="1.6" marker-end="url(#arrow)"/>')
        if edge['label']:
            # Reserve actual whitespace for labels, including tight cross-lane edges.
            # Conservative text-width estimate is verified with browser getBBox.
            tw=len(edge['label'])*7.7+12
            candidates=[]
            segments=sorted(zip(orth,orth[1:]),key=lambda z:-(abs(z[1][0]-z[0][0])+abs(z[1][1]-z[0][1])))
            for offset in [-8,-28,28,-58,58,-78,78]:
                for seg in segments:
                    for f in [.5,.3,.7]:
                        x=seg[0][0]+f*(seg[1][0]-seg[0][0]);y=seg[0][1]+f*(seg[1][1]-seg[0][1])+offset
                        box=(x-tw/2,y-15,x+tw/2,y+5)
                        if box[0]<12 or box[2]>width-12 or box[1]<0 or box[3]>d['height']:continue
                        if any(box[0]<b[2] and box[2]>b[0] and box[1]<b[3] and box[3]>b[1] for b in occupied):continue
                        candidates.append((x,y,box))
                if candidates:break
            if not candidates:
                # Obvious flow labels are optional; never put text over a node.
                continue
            x,y,box=candidates[0];occupied.append(box)
            parts.append(f'<text class="edge-label" x="{x}" y="{y}" text-anchor="middle">{esc(edge["label"])}</text>')
    for v in d['nodes']:
        fill,stroke=COLORS[v['kind']]
        dash=' stroke-dasharray="5 3"' if v['kind']=='fault' else ''
        parts.append(f'<g data-node="{v["id"]}"><rect x="{v["x"]}" y="{v["y"]}" width="{v["w"]}" height="{v["h"]}" rx="8" fill="{fill}" stroke="{stroke}"{dash}/>')
        parts.append(f'<text class="node-title" x="{v["x"]+14}" y="{v["y"]+27}">{esc(v["title"])}</text>')
        for j,line in enumerate(v['body'].split('\n')):
            parts.append(f'<text class="node-body" x="{v["x"]+14}" y="{v["y"]+54+j*21}">{esc(line)}</text>')
        parts.append('</g>')
    parts.append(f'<text x="30" y="{d["height"]-10}" style="font-size:12px;fill:#5e6c7d">{esc(SNAPSHOT["svg_scope"])}</text>')
    parts.append('</svg>');return '\n'.join(parts)

def main():
    for d in diagrams:(OUT/(d['key']+'.svg')).write_text(svg(d))
    (OUT/'diagram-data.json').write_text(json.dumps(diagrams,indent=2)+'\n')
    fragments=[]
    for d in diagrams:
        refs=' · '.join(f'<a href="#source-{r}">{r}</a>' for r in d['refs'])
        fragments.append(f'<section id="{d["key"]}"><h2>{esc(d["title"])}</h2><p>{esc(d["desc"])}</p><p class="refs">Sources: {refs} · <a href="{d["key"]}.svg">Open full-size SVG</a></p><div class="diagram" tabindex="0" aria-label="Scrollable {esc(d["title"])}">{svg(d)}</div></section>')
    source_html=''.join(f'<li id="source-{key}"><strong>{key}</strong> · {esc(desc)}<br><a href="{path.as_uri()}">{esc(str(path))}</a></li>' for key,(path,desc) in sources.items())
    source_md='\n'.join(f'- **{key}** — {desc}. [{path.name}](<{path}>)' for key,(path,desc) in sources.items())
    source_intro=f"# Source index\n\n{SNAPSHOT['state']}. Source snapshot {SNAPSHOT['date']}: native `{SNAPSHOT['native_commit']}`, host `{SNAPSHOT['host_commit']}`. Installed baseline is separately recorded in release-snapshot.json. The issue register and final root installation receipt own current status.\n\n"
    (OUT/'sources.md').write_text(source_intro+source_md+'\n')
    findings=(OUT/'findings.html').read_text()
    page='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Physical Go — complete process map</title><style>
    *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f5f7fa;color:#182b40;font:16px/1.55 system-ui,-apple-system,sans-serif}main{max-width:1200px;margin:auto;padding:32px 24px 70px}h1{font-size:32px;margin:0 0 8px}h2{font-size:24px;margin:0 0 8px}h3{font-size:19px;margin:24px 0 8px}p{margin:8px 0 14px}a{color:#175a91}nav{display:flex;flex-wrap:wrap;gap:8px 20px;margin:22px 0}.snapshot{border-left:4px solid #805d16;padding:6px 18px;background:#fff4d9}section{margin-top:42px;padding-top:12px;border-top:1px solid #d4dde5}.diagram{overflow:auto;background:white;margin:16px 0;max-width:100%;border:1px solid #d4dde5}.diagram svg{display:block;min-width:1120px}li{margin:10px 0}.refs{font-size:14px}code{font-size:0.94em;overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;font-size:15px}td,th{text-align:left;vertical-align:top;border-bottom:1px solid #d4dde5;padding:10px}th{background:#edf2f8}.table-wrap{overflow:auto}#sources a{overflow-wrap:anywhere}summary{cursor:pointer;font-weight:600}.legend{display:flex;flex-wrap:wrap;gap:10px 20px}.legend span{padding:3px 10px;border-radius:4px}.process{background:#eaf2ff}.gate{background:#fff4d9}.store{background:#edf5ef}.fault{background:#fff0ef}button{font:inherit;padding:5px 12px;background:#fff;border:1px solid #889aae;border-radius:5px;color:#182b40;cursor:pointer}button:focus-visible,a:focus-visible{outline:3px solid #23538a;outline-offset:3px}#validation{display:none}@media(max-width:600px){main{padding:20px 14px}h1{font-size:27px}h2{font-size:22px}}@media print{body{background:white}main{max-width:none;padding:0}.diagram{overflow:visible;border:0}.diagram svg{min-width:0;width:100%;height:auto}section{break-before:page}nav,button{display:none}}
    </style></head><body><main><h1>Physical Go · complete process map</h1><p>Read the overview first; follow each detailed map to the decisions and evidence that matter.</p><div class="snapshot">__STATUS_BANNER__</div><nav>'''
    page+=''.join(f'<a href="#{d["key"]}">{esc(d["title"].split(" · ")[1])}</a>' for d in diagrams)
    page+='<a href="#findings">Architectural findings</a><a href="#timing">Timing boundaries</a><a href="#sources">Sources</a></nav><div class="legend"><span class="process">Process</span><span class="gate">Evidence / admission gate</span><span class="store">Queue / stored exchange</span><span class="fault">Fault / limitation</span></div><p class="refs">Arrows show control or evidence flow, not measured duration. Diagrams remain readable at full size; horizontally scroll on narrow windows or open the SVG. Browser zoom and print are supported.</p>'
    status_banner='<strong>'+esc(SNAPSHOT['state'])+'</strong><br>Source '+esc(SNAPSHOT['date'])+' · native <code>'+esc(SNAPSHOT['native_commit'][:7])+'</code> · host <code>'+esc(SNAPSHOT['host_commit'][:7])+'</code><br>Installed baseline: '+esc(SNAPSHOT['installed_native'])+' / '+esc(SNAPSHOT['installed_host'])+'<br>'+esc(SNAPSHOT['physical_state'])+'<br>'+esc(SNAPSHOT['release_note'])
    page=page.replace('__STATUS_BANNER__',status_banner)
    page+=''.join(fragments)+findings+'<section id="sources"><h2>Source index and limits</h2><p>Diagrams are a source-grounded architecture review, not a complete executable state-machine specification. Native and host source are pinned above. Older guide status paragraphs are superseded by the current checklist; the installed source snapshot and remaining physical-validation limits are stated in the banner. This work performed no camera, serial, app UI, installation or hardware actions.</p><ol>'+source_html+'</ol></section><output id="validation"></output></main><script>window.addEventListener("load",()=>{const issues=[];document.querySelectorAll("svg [data-node]").forEach(n=>{const r=n.querySelector("rect");const x=+r.getAttribute("x"),y=+r.getAttribute("y"),w=+r.getAttribute("width"),h=+r.getAttribute("height");n.querySelectorAll("text").forEach(t=>{const b=t.getBBox();if(b.x<x||b.y<y||b.x+b.width>x+w||b.y+b.height>y+h)issues.push(n.dataset.node+": text outside box")})});document.querySelectorAll("a[href^=\\"#\\"]").forEach(a=>{if(!document.getElementById(a.hash.slice(1)))issues.push("missing anchor "+a.hash)});const out=document.getElementById("validation");out.textContent=JSON.stringify({diagrams:document.querySelectorAll(".diagram").length,nodes:document.querySelectorAll("[data-node]").length,issues});out.dataset.result=issues.length?"fail":"pass"});</script></body></html>'
    label_check='''document.querySelectorAll(".diagram svg").forEach(svg=>{const labels=[];const vb=svg.viewBox.baseVal;svg.querySelectorAll(".edge-label").forEach(t=>{const b=t.getBBox();if(b.x<0||b.y<0||b.x+b.width>vb.width||b.y+b.height>vb.height)issues.push("edge label outside canvas: "+t.textContent);svg.querySelectorAll("[data-node] rect").forEach(r=>{const a=r.getBBox();if(b.x<a.x+a.width&&b.x+b.width>a.x&&b.y<a.y+a.height&&b.y+b.height>a.y)issues.push("edge label overlaps node: "+t.textContent)});labels.forEach(a=>{if(b.x<a.x+a.width&&b.x+b.width>a.x&&b.y<a.y+a.height&&b.y+b.height>a.y)issues.push("edge labels overlap: "+t.textContent)});labels.push(b)})});'''
    page=page.replace('const out=document.getElementById("validation");',label_check+'const out=document.getElementById("validation");')
    (OUT/'index.html').write_text(page)
    print(f'Built {len(diagrams)} SVGs and self-contained index.html')
if __name__=='__main__':main()
