"""Build offline, self-contained process maps. Does not import application code."""
from pathlib import Path
import html, json, re

OUT = Path(__file__).resolve().parent
NATIVE = Path('/Users/Dave/SGFPlayerClean-worktrees/arming-episode-release-20261124/PhysicalGo/Sources')
HOST = Path('/Users/Dave/DYNAMIXEL-Go-Pointer-worktrees/geometry-visible-release-20261124/Firmware')
DOCS = Path('/Users/Dave/SGFPlayerClean/PhysicalGo/Documentation')
sources = {
 'S1': (DOCS/'IntegrationChecklist.md', 'Current implementation and physical results; snapshot Nov 25'),
 'S2': (DOCS/'AgentGuide/Architecture.md', 'State ownership and architecture'),
 'S3': (DOCS/'CalibrationAndTiming.md', 'Calibration stages; historical overrides are calibration-only'),
 'S4': (NATIVE/'CameraCapture.swift', 'Camera serial queue and delivery'),
 'S5': (NATIVE/'CameraFrameTimestamp.swift', 'Presentation capture time versus callback arrival'),
 'S6': (NATIVE/'CameraAnalysisPipeline.swift', 'Serial analysis, early safety, immutable results'),
 'S7': (NATIVE/'LatestAnalysisInput.swift', 'One replaceable pending analysis input'),
 'S8': (NATIVE/'PhysicalLaserFrameBroker.swift', 'Independent safety and image publication queues'),
 'S9': (NATIVE/'LatestFileExchange.swift', 'Independent bounded request/status IO'),
 'S10': (NATIVE/'PhysicalAI.swift', 'Recognition 491–665; commit/advance 667–715; guidance 742 onward'),
 'S11': (NATIVE/'PhysicalLaserGuidance.swift', 'Dark admission, leases, arming episodes, faults'),
 'S12': (HOST/'Tools/launch_reviewed_feedback.py', 'READY and preflight 98–180; shutdown receipt 132 onward'),
 'S13': (HOST/'bridge_runtime.py', 'Input/coordinator/supervision/worker threads and cancellation'),
 'S14': (HOST/'bridge_frames.py', 'Frame identity and independent capture/publication/arrival ages'),
 'S15': (HOST/'bridge_feedback.py', 'Approach 106; preparation 254; observation 306; hold 505; admission 543'),
 'S16': (HOST/'bridge_optical_geometry.py', 'Three-frame dark median; age 10s, refresh reserve 4s; per-frame verification'),
 'S17': (HOST/'bridge_alignment.py', 'Fixed-anchor temporal tracking; installed maxLevel=2'),
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
}

diagrams=[]
def diagram(key,title,desc,height,nodes,edges,refs):
    diagrams.append(dict(key=key,title=title,desc=desc,height=height,nodes=nodes,edges=edges,refs=refs))
def n(id,x,y,title,body,kind='process',w=300,h=96):
    return dict(id=id,x=x,y=y,w=w,h=h,title=title,body=body,kind=kind)
def e(a,b,label='',route=None,kind='normal'):
    return dict(a=a,b=b,label=label,route=route,kind=kind)

diagram('overview','1 · The complete system','Separate observed stones, legal history, requested guidance and actual hardware state.',790,[
 n('setup',50,35,'A. Qualify the setup','Camera grid + pointer map\nIndependent checks + READY','gate'),
 n('camera',50,225,'B. Observe the board','One app camera; fresh frames\nHand, grid, stones, uncertainty'),
 n('game',400,225,'C. Decide and preserve','Local recorder / AI / online\nLegal history + clocks + save'),
 n('guide',750,225,'D. Request guidance','AI placement → capture → hint\nExact target + bounded lease'),
 n('host',750,415,'E. Aim and monitor','Dark admission → optical aim\nHold or stop; report real state'),
 n('human',400,415,'F. Human changes board','Place indicated stone; remove\ncaptures; center when needed'),
 n('confirm',50,415,'G. Verify physical change','Clear, dark, fresh evidence\nStable legal / cleanup result','gate'),
 n('save',400,625,'Review / end / restore','Preserve pending physical work\nExplicit scoring / resume'),
 n('fault',750,625,'Fault or pause → full OFF','Beam off + motor bus released\nRetain game and pending move','fault'),
],[e('setup','camera'),e('camera','game'),e('game','guide'),e('guide','host'),e('host','human','visible cue'),e('human','confirm'),e('confirm','camera','next evidence',[(30,463),(30,273)]),e('confirm','game','accepted',[(375,463),(375,205),(550,205)]),e('game','save','review / end',[(550,345),(720,345),(720,598),(550,598)]),e('host','fault','any hard fault'),e('save','fault','pause / stop')],['S1','S2','S22','S23','S24'])

diagram('calibration','2 · Two calibrations, then permission to play','A grid fit maps pixels to intersections. A motor fit maps encoder poses to the laser spot. Neither proves current clearance.',1120,[
 n('select',50,30,'Select actual app camera','Verify device, dimensions, epoch\nand advancing presentation times'),
 n('grid',50,205,'Fit camera → board grid','Find intersections / perspective\nValidate boundaries + interior'),
 n('ref',50,380,'Retain geometry/reference','Native board coordinate system\nLighting / occupancy references'),
 n('measure',400,205,'Measure pointer → board','Observe spot at measured poses\nAttended, guarded motor samples'),
 n('fit',400,380,'Fit candidate motor map','Predict target pose; quantify fit\nNot a physical test of 361 points'),
 n('check',400,555,'Independent optical checks','Separate targets + actual spot\nReject moved / invalid setup','gate'),
 n('bind',400,730,'Bind approved setup','Hashes: model/setup/reference\nCamera/context/size/allowed targets'),
 n('verify',750,555,'Verify installed release','Pinned app + host + firmware\nRead-only camera preflight ×3','gate'),
 n('ready',750,730,'Attended READY gate','Recheck package + camera ×3\nExact controller identity + free port','gate'),
 n('launch',750,915,'Open one host / controller','OFF handshake → capability check\nThen current session admission'),
 n('moved',50,730,'If board/camera/pointer moves','Requalify affected relationships\nA matching file hash is insufficient','fault'),
],[e('select','grid'),e('grid','ref'),e('grid','measure'),e('measure','fit'),e('fit','check'),e('check','bind'),e('bind','ready'),e('verify','ready'),e('ready','launch'),e('ref','bind','identity + geometry',[(375,428),(375,778)]),e('moved','grid','fresh qualification',[(25,778),(25,253)])],['S3','S12','S19','S1'])

diagram('data','3 · Camera, processing and file boundaries','Parallel lanes prevent slow image writing from blocking safety delivery. Original timestamps survive every queue.',1110,[
 n('capture',50,30,'Camera serial queue','AVFoundation presentation time\nCapture + arrival + epoch/frame ID'),
 n('main',50,215,'Main actor: session snapshot','Camera/grid/reference/expected board\nRevision rejects stale completions'),
 n('vision',400,215,'Serial vision worker','Alignment + exposure + hand\nThen stone/shape/assignment evidence'),
 n('latest',400,30,'Latest-only pending input','One replaceable waiting frame\nNo accumulated analysis backlog','store'),
 n('safety',750,215,'Early safety → main actor','Current revision checked\nClearance is not stone acceptance'),
 n('observe',400,430,'Final observation → game','Same immutable analysis context\nGame applies own dark/stable gates'),
 n('png',50,430,'Image preparation / broker','PNG work overlaps analysis\nCache key: epoch + frame ID'),
 n('manifest',50,630,'Image queue → latest.json','Publish exact checked PNG first\nOne pending; retain four PNGs','store'),
 n('safejson',750,430,'Safety queue → safety.json','Separate atomic publication\nNo matching pixels promised','store'),
 n('io',400,630,'Request / status IO queues','One read + one write in flight\nOne replaceable pending request','store'),
 n('reader',50,840,'Host optical worker','Read matching PNG + manifest\nCheck four ages ≤600 ms','gate'),
 n('supervisor',750,630,'Host safety supervision','Hand / camera / lease / thermal\nCan revoke busy optical worker'),
 n('status',400,840,'Host coordinator + worker','Single hardware generation\nReceipt/status returns to native'),
],[e('capture','main'),e('capture','latest'),e('latest','vision'),e('main','vision'),e('vision','safety'),e('vision','observe'),e('main','png'),e('png','manifest'),e('safety','safejson'),e('safejson','supervisor'),e('observe','io'),e('manifest','reader'),e('reader','status'),e('io','status','lease / receipt'),e('supervisor','status','revoke / monitor',[(900,790),(650,790)]),e('status','io','fresh ack',[(725,888),(725,678)])],['S4','S5','S6','S7','S8','S9','S13','S14'])

diagram('gameplay','4 · AI game and physical placement','The AI move enters legal history before its stone is physically placed. pendingPlacement preserves that difference.',1170,[
 n('resume',50,30,'Start / explicit Resume','Restore accepted save + clocks\nVerify physical board matches'),
 n('observe',50,210,'Admit observation','Current context; clear and aligned\nConfirmed dark + post-dark frame','gate'),
 n('ambiguity',50,390,'Resolve assignment','New stone location must be unique\nWeak empty neighbor can block','gate'),
 n('stable',50,570,'Collect stable witnesses','≥3 distinct frames spanning 450 ms\nGaps >600 ms reset continuity','gate'),
 n('legal',50,750,'Accept legal human move','Rules + captures → history/save\nClock ownership changes here'),
 n('ai',400,750,'Ask KataGo','Normal or fast-test settings\nRetained idle worker in fast mode'),
 n('commit',750,750,'Commit AI answer','Validate move; save decision time\nSet pendingPlacement; switch turn'),
 n('request',750,570,'Select physical guidance','Placement → capture → centering\nKeep pre-placement referenceCells'),
 n('aim',750,390,'Host aims / holds dot','Fresh target admission + optical aim\nNative click: first light ack only'),
 n('human',750,210,'Human places / removes','Hand or stone suspicion darkens\nLit evidence cannot confirm a move'),
 n('match',400,570,'Expected board now matches?','Pending placement / cleanup ends\nOnly after admitted stable evidence','gate'),
 n('wait',400,390,'Unclear / halfway / illegal','Wait or show correction markers\nNever silently alter legal history'),
 n('end',400,965,'Pass / finish / pause / save','Hard guidance fault pauses clocks\nExplicit Resume keeps pending work'),
],[e('resume','observe'),e('observe','ambiguity'),e('ambiguity','stable','unique'),e('ambiguity','wait','unclear'),e('wait','observe','new evidence',[(550,350),(200,350)]),e('stable','legal','new human move'),e('stable','match','saved position'),e('legal','ai'),e('ai','commit'),e('commit','request'),e('request','aim'),e('aim','human'),e('human','observe','new dark evidence',[(900,180),(200,180)]),e('match','observe','next human turn',[(375,618),(375,258)]),e('ai','end','pass / end'),e('match','end','pause / fault',[(710,618),(710,1013)])],['S10','S11','S22','S23','S25'])

diagram('laser','5 · Host aiming and holding','Every observation has its own fresh pixels and actual-pose checks. Geometry can be reused only while its fixed anchor still agrees.',1480,[
 n('admit',50,30,'Admit current request','Binding + fresh frame + identity\nWarm receipt or cold admission','gate'),
 n('arm',400,30,'Cold GA / warm RS','Dark motor engagement / resume\nNative unfinished episode ≤12 s'),
 n('prepare',400,205,'Prepare while dark','PREPARE → three dark frames\nFit median geometry + fresh check'),
 n('initial',400,390,'Initial optical observation','SWEEP light; flush ≥300 ms\nFresh batch + pose before/after'),
 n('dark',400,575,'Initial observe darkens','DARK + state/pose recheck\nEven if target already accepted'),
 n('coarse',50,750,'Try predicted dark travel','Bounded model / support corridor\nGOTO + recenter actual settlement'),
 n('reacquire',50,925,'Observe actual landing','Coarse: search across the board\nFine: measure near predicted spot'),
 n('fine',400,925,'If outside 0.20 cell: correct','Local response at actual pose\nFine light allowed only if guarded'),
 n('accept',750,750,'Within 0.20 cell','Measured target acceptance\nDoes not confirm physical stone','gate'),
 n('hold',750,925,'Verify and hold indication','If dark: new PREPARE + SWEEP\nIf already lit: promote same beam'),
 n('monitor',750,1110,'Read fresh spot repeatedly','Must stay within 0.20 cell\nEmit adequate; await placement'),
 n('refresh',400,1110,'Renew dark geometry','At age ≥6 s (10 s max, 4 s reserve)\nOr light interval near 55 s'),
 n('placement',750,1300,'Hand / stone / new request','Revoke old operation → dark/OFF\nNative confirms physical outcome'),
 n('guards',50,1300,'Independent guards throughout','Lease / hand / thermal / actual pose\nAny fault → cancellation / full OFF','fault'),
],[e('admit','arm'),e('arm','prepare'),e('prepare','initial'),e('initial','dark'),e('dark','coarse','outside tolerance',[(200,623)]),e('coarse','reacquire'),e('reacquire','fine','miss'),e('fine','reacquire','remeasure',[(550,1068),(200,1068)]),e('dark','accept','already close',[(900,623)]),e('reacquire','accept','measured pass',[(375,973),(375,867),(735,867),(735,798)]),e('accept','hold'),e('hold','monitor'),e('monitor','refresh','refresh due'),e('refresh','prepare','new dark anchor',[(720,1158),(720,170),(550,170)]),e('monitor','placement')],['S15','S16','S17','S18','S20','S21','S11'])

diagram('recovery','6 · Cancellation, darkness and full OFF','Dark motors-held state is useful during play. It is not a full power-off receipt, and a command submission is not an acknowledgement.',1130,[
 n('event',50,30,'Interruption / state change','Hand, target replacement, pause\nCamera/lease, optical or hard fault'),
 n('revoke',400,30,'Invalidate generation first','No late worker command/result\nmay authorize the next request'),
 n('quiet',750,30,'Quiesce worker / controller','Coordinator owns stop and receipt\nWorker cleanup cannot send old IO'),
 n('branch',750,220,'Choose permitted stop path','Healthy eligible handoff only\nOtherwise request full OFF','gate'),
 n('darkhold',400,405,'DARK / holding receipt','Beam off, motors held, bus powered\nCooling can instead release motors'),
 n('off',750,405,'Full OFF receipt','Beam off + motor bus released\nExact identity + fresh acknowledgement','gate'),
 n('frame',400,600,'Post-dark camera evidence','Same stream + frame watermark\n≥300 ms presentation flush','gate'),
 n('transient',50,795,'Classified transient recovery','Camera/lease barrier + fresh streak\nCurrent target must be reverified'),
 n('explicit',750,795,'Hard / unexplained failure','Pause game + clock; retain target\nExplicit recheck / Resume required','fault'),
 n('retry',400,980,'Re-admit under current proof','New scope, clear board, fresh status\nHardware recovery alone ≠ Resume'),
],[e('event','revoke'),e('revoke','quiet'),e('quiet','branch'),e('branch','off','fault / pause'),e('branch','darkhold','eligible warm handoff',[(550,268)]),e('darkhold','frame'),e('off','frame','after full OFF',[(900,555),(550,555)]),e('frame','transient','classified recovery',[(200,648)]),e('off','explicit','hard fault',[(1080,453),(1080,843)]),e('explicit','retry','explicit action',[(900,1028)]),e('transient','retry','fresh witnesses',[(200,1028)])],['S11','S13','S25','S26','S27','S1'])

diagram('modes','7 · Local recording, online play and review','The camera pipeline is shared. Move acceptance, clocks and persistence have different owners in each mode.',910,[
 n('observation',400,25,'Admitted board observations','Same camera / grid / hand pipeline\nMode chooses the decision owner'),
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
    (OUT/'sources.md').write_text('# Source index\n\nNative source pinned to `0f9ac752414b12b85dae5e10b161bd7e6de69950`; host source pinned to `fc8cb7d2648c198c319e4f046098d8fabc8b8f89`. Latest installed/frozen host is `968ba538d457c03fc34ed0b17b0d59e853817838-app0264`; final attended retry failed temporal reuse at frame57014, followed by separate full OFF1795596934.1468098. No sustained-play pass is claimed. The source index retains the earlier fc8cb7d flow snapshot; later tracking/validation repairs leave that high-level flow unchanged. Documentation is a Nov 25 snapshot; current checklist and release pointer outrank stale guide version paragraphs.\n\n'+source_md+'\n')
    findings=(OUT/'findings.html').read_text()
    page='''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Physical Go — complete process map</title><style>
    *{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f5f7fa;color:#182b40;font:16px/1.55 system-ui,-apple-system,sans-serif}main{max-width:1200px;margin:auto;padding:32px 24px 70px}h1{font-size:32px;margin:0 0 8px}h2{font-size:24px;margin:0 0 8px}h3{font-size:19px;margin:24px 0 8px}p{margin:8px 0 14px}a{color:#175a91}nav{display:flex;flex-wrap:wrap;gap:8px 20px;margin:22px 0}.snapshot{border-left:4px solid #805d16;padding:6px 18px;background:#fff4d9}section{margin-top:42px;padding-top:12px;border-top:1px solid #d4dde5}.diagram{overflow:auto;background:white;margin:16px 0;max-width:100%;border:1px solid #d4dde5}.diagram svg{display:block;min-width:1120px}li{margin:10px 0}.refs{font-size:14px}code{font-size:0.94em;overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;font-size:15px}td,th{text-align:left;vertical-align:top;border-bottom:1px solid #d4dde5;padding:10px}th{background:#edf2f8}.table-wrap{overflow:auto}#sources a{overflow-wrap:anywhere}summary{cursor:pointer;font-weight:600}.legend{display:flex;flex-wrap:wrap;gap:10px 20px}.legend span{padding:3px 10px;border-radius:4px}.process{background:#eaf2ff}.gate{background:#fff4d9}.store{background:#edf5ef}.fault{background:#fff0ef}button{font:inherit;padding:5px 12px;background:#fff;border:1px solid #889aae;border-radius:5px;color:#182b40;cursor:pointer}button:focus-visible,a:focus-visible{outline:3px solid #23538a;outline-offset:3px}#validation{display:none}@media(max-width:600px){main{padding:20px 14px}h1{font-size:27px}h2{font-size:22px}}@media print{body{background:white}main{max-width:none;padding:0}.diagram{overflow:visible;border:0}.diagram svg{min-width:0;width:100%;height:auto}section{break-before:page}nav,button{display:none}}
    </style></head><body><main><h1>Physical Go · complete process map</h1><p>Read the overview first; follow each detailed map to the decisions and evidence that matter.</p><div class="snapshot"><strong>Architecture snapshot · November 25, 2026</strong><br>Native 0.264/build265 · <code>0f9ac75</code> · host <code>fc8cb7d</code> · firmware v44. Original flow snapshot: game paused, Q17 pending, separate full OFF verified. Latest installed/frozen host: <code>968ba538-app0264</code>. Final attended retry again failed temporal reuse at frame57014; separate full OFF <code>1795596934.1468098</code>. Q17 remains pending; no sustained-play pass. The diagrams/source index retain the <code>fc8cb7d</code> process-flow snapshot; later tracking/validation repairs leave this high-level flow unchanged. The attended baseline window and authorized retry have ended; subsequent work is offline. This document cannot establish current hardware state.</div><nav>'''
    page+=''.join(f'<a href="#{d["key"]}">{esc(d["title"].split(" · ")[1])}</a>' for d in diagrams)
    page+='<a href="#findings">Architectural findings</a><a href="#timing">Timing boundaries</a><a href="#sources">Sources</a></nav><div class="legend"><span class="process">Process</span><span class="gate">Evidence / admission gate</span><span class="store">Queue / stored exchange</span><span class="fault">Fault / limitation</span></div><p class="refs">Arrows show control or evidence flow, not measured duration. Diagrams remain readable at full size; horizontally scroll on narrow windows or open the SVG. Browser zoom and print are supported.</p>'
    page+=''.join(fragments)+findings+'<section id="sources"><h2>Source index and limits</h2><p>Diagrams are a source-grounded architecture review, not a complete executable state-machine specification. Native and host source are pinned above. Older guide version/status paragraphs were superseded by the current checklist. This work performed no camera, serial, app UI, installation or hardware actions.</p><ol>'+source_html+'</ol></section><output id="validation"></output></main><script>window.addEventListener("load",()=>{const issues=[];document.querySelectorAll("svg [data-node]").forEach(n=>{const r=n.querySelector("rect");const x=+r.getAttribute("x"),y=+r.getAttribute("y"),w=+r.getAttribute("width"),h=+r.getAttribute("height");n.querySelectorAll("text").forEach(t=>{const b=t.getBBox();if(b.x<x||b.y<y||b.x+b.width>x+w||b.y+b.height>y+h)issues.push(n.dataset.node+": text outside box")})});document.querySelectorAll("a[href^=\\"#\\"]").forEach(a=>{if(!document.getElementById(a.hash.slice(1)))issues.push("missing anchor "+a.hash)});const out=document.getElementById("validation");out.textContent=JSON.stringify({diagrams:document.querySelectorAll(".diagram").length,nodes:document.querySelectorAll("[data-node]").length,issues});out.dataset.result=issues.length?"fail":"pass"});</script></body></html>'
    label_check='''document.querySelectorAll(".diagram svg").forEach(svg=>{const labels=[];const vb=svg.viewBox.baseVal;svg.querySelectorAll(".edge-label").forEach(t=>{const b=t.getBBox();if(b.x<0||b.y<0||b.x+b.width>vb.width||b.y+b.height>vb.height)issues.push("edge label outside canvas: "+t.textContent);svg.querySelectorAll("[data-node] rect").forEach(r=>{const a=r.getBBox();if(b.x<a.x+a.width&&b.x+b.width>a.x&&b.y<a.y+a.height&&b.y+b.height>a.y)issues.push("edge label overlaps node: "+t.textContent)});labels.forEach(a=>{if(b.x<a.x+a.width&&b.x+b.width>a.x&&b.y<a.y+a.height&&b.y+b.height>a.y)issues.push("edge labels overlap: "+t.textContent)});labels.push(b)})});'''
    page=page.replace('const out=document.getElementById("validation");',label_check+'const out=document.getElementById("validation");')
    (OUT/'index.html').write_text(page)
    print(f'Built {len(diagrams)} SVGs and self-contained index.html')
if __name__=='__main__':main()
