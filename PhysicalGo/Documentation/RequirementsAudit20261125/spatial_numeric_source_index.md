# Numeric-gate source index

Source-pinned candidate index for the audited files. Includes algorithm parameters and incidental numeric guards; the reviewed table distinguishes their meaning. This is not a claim that every number is an acceptance requirement.

## H/AimControl/AimControl.ino

```text
68: static bool poseFresh(){return poseValidated[0] && poseValidated[1] && uint32_t(millis()-poseValidatedAt[0])<=200u && uint32_t(millis()-poseValidatedAt[1])<=200u;}
73: if(gameSession && reportPending && reportPart>0)return;
80: if(strlen(text)>61){if(state!=OFF)fault("reply_too_long");return;}
103: if(uint32_t(millis()-gameStarted)>99999999u || reportSequence>=9999999u){reason="protocol_expired";disarm();return false;}
104: if(gameEngaging && uint32_t(millis()-armedAt)>12000u)return fault("engagement_timeout");
105: if(haveThermal && uint32_t(millis()-lastAckAt)>1500u)return fault("thermal_ACK_timeout");
107: if(busReady && haveThermal && (uint32_t(millis()-sampleAt[0])>750u || uint32_t(millis()-sampleAt[1])>750u))return fault("thermal_stale");
110: if(sweepActive && !markerActive && uint32_t(millis()-pulseAt)>=SWEEP_MS)return fault("sweep_timeout");
111: if (pulseOn && !markerActive && uint32_t(millis()-pulseAt)>=lightLimit) laserOff();
113: if (uint32_t(millis()-lastHB)>HEARTBEAT_MS) return fault("heartbeat_timeout");
114: if (!gameSession && !markerActive && uint32_t(millis()-armedAt)>(dualSession?SESSION_MS:ARM_MS)) return fault("arm_expired");
119: for (uint8_t n=0;n<64 && Serial.available();++n) {
145: if(!((c>='A' && c<='Z') || ((idleCollect || gameSession) && c>='0' && c<='9')) || used>=sizeof(line)-1) return fault("invalid_command");
150: if(!thermalBusy && !mutationBusy && !monitorBusy && busReady && (!haveThermal || (gameSession && reportWanted && !reportPending) || uint32_t(millis()-lastThermal)>=100u)) {
157: while(uint32_t(millis()-begin)<ms) {
170: for(uint8_t i=0;i<size;++i) bits|=uint32_t(data[i])<<(8*i);
173: static bool setReg(uint8_t id,uint16_t address,uint8_t size,int32_t value,uint8_t tolerance=0) {
178: for(uint8_t i=0;i<size;++i)data[i]=uint32_t(value)>>(8*i);
193: if(torque!=((dualSession?(torqueMask & (1u<<i)):(movingAxis==id || holdingAxis==id)) ? 1 : 0)) return fault("unexpected_torque");
195: if(voltage<37 || voltage>60) return fault("supply_voltage");
196: if(position<lowerBound(i)-3 || position>upperBound(i)+3)
201: const bool moving=movingAxis==id || (pairMoving && (pairMask & (1u<<i)));
204: low=(anchor[i]<target ? anchor[i] : target)-6;
205: high=(anchor[i]>target ? anchor[i] : target)+6;
207: if(position<low || position>high) return fault(moving ? (id==1?"base_during_move":"tilt_during_move") : (id==1?"base_drift":"tilt_drift"));
208: const bool held=!moving && (dualSession?(torqueMask & (1u<<i)):holdingAxis==id);
212: if(!moving && (velocity<-1 || velocity>1)) {
214: if(!held || velocity<-2 || velocity>2)
220: if(uint32_t(millis()-speedSince[i])>=120)return fault(id==1?"base_moving":"tilt_moving");
230: for(uint8_t id=1;id<=2;++id) {
244: for(uint8_t n=0;n<5;++n) {
246: for(uint8_t i=0;i<2;++i) {
247: if(positions[i]<previous[i]-1 || positions[i]>previous[i]+1) return fault("not_stationary");
266: for(uint8_t id=1;id<=2;++id) {
279: for(uint8_t id=1;id<=2;++id) {
304: for(uint8_t id=1;id<=2;++id) {
308: torqueMask|=1u<<i;
310: if(positions[i]<enablingPosition-3 || positions[i]>enablingPosition+3)return fault("enable_shift");
314: while(uint32_t(millis()-begin)<8000) {
317: for(uint8_t i=0;i<2;++i) {
318: if(velocities[i]<-1 || velocities[i]>1)quiet=false;
321: if(high[i]-low[i]>1)quiet=false;
323: if(!quiet || !quietAt){quietAt=quiet?millis():0;for(uint8_t i=0;i<2;++i)low[i]=high[i]=positions[i];}
324: if(quietAt && uint32_t(millis()-quietAt)>=(fastSession?300u:2000u)) {
332: if(!benchSession || !dualSession || state!=ARMED || pulseOn || level>3)return fault("invalid_bench_profile");
335: for(uint8_t id=1;id<=2;++id)
345: for(uint8_t id=1;id<=2;++id)
355: for(uint8_t i=0;i<2;++i) {
361: for(uint8_t i=0;i<2;++i){anchor[i]=start[i];pairTarget[i]=goals[i];if(goals[i]!=start[i])pairMask|=1u<<i;}
366: for(uint8_t i=0;i<2;++i)if(!setReg(i+1,116,4,goals[i]))return false;
368: while(uint32_t(millis()-begin)<8000) {
371: for(uint8_t i=0;i<2;++i) {
373: if(velocities[i]<-1 || velocities[i]>1)quiet=false;
376: if(high[i]-low[i]>1)quiet=false;
378: if(near && nearAt<0)nearAt=int32_t(millis()-begin);
379: if(!near || !quiet || !quietAt){quietAt=(near && quiet)?millis():0;for(uint8_t i=0;i<2;++i)low[i]=high[i]=positions[i];}
380: if(quietAt && uint32_t(millis()-quietAt)>=150) {
381: for(uint8_t i=0;i<2;++i) {
416: if(positions[i]<start-3 || positions[i]>start+3) return fault("enable_shift");
424: while(uint32_t(millis()-begin)<8000u) {
428: if(firstNear<0 && error>=-6 && error<=6)firstNear=int32_t(millis()-begin);
429: const int32_t speed=velocities[i]<0?-velocities[i]:velocities[i];if(speed>peakVelocity)peakVelocity=speed;
431: int32_t current=int16_t(rawCurrent);if(current<0)current=-current;if(current>peakCurrent)peakCurrent=current;
434: const int32_t tolerance=dualSession?6:3;
437: const bool fineDeadband=error>=-3 && error<=3 && uint32_t(millis()-begin)>=300;
438: const bool quiet=(!fastSession || progressStarted || fineDeadband) &&(dualSession || (error>=-tolerance && error<=tolerance)) && velocities[i]>=-1 && velocities[i]<=1 &&
439: positions[i]>=previousPosition-1 && positions[i]<=previousPosition+1;
446: if(stableHigh-stableLow>1) {stableSince=millis();stableLow=stableHigh=positions[i];}
449: if(uint32_t(millis()-lastTrace)>=(benchSession?50u:200u)) {
453: if(stableSince && uint32_t(millis()-stableSince)>=((benchSession || fastSession)?150u:cornerSession?300u:2000u)) {settled=true;break;}
457: if(dualSession && (target-start>=4 || target-start<=-4) && positions[i]==start)return fault("no_motion_progress");
477: if(strlen(message)>61)snprintf(message,sizeof(message),"RESULT %s reason=%s",ok?"OK":"ERROR",reason);
484: while(ok && uint32_t(millis()-start)<6000) {
486: if(ok && uint32_t(millis()-lastTrace)>=200) {
551: if(valid)for(uint8_t i=4;i<12;++i){if(cmd[i]<'0'||cmd[i]>'9'){valid=false;break;}q[(i-4)/4]=q[(i-4)/4]*10+cmd[i]-'0';}
560: if(strlen(cmd)!=6 || cmd[5]<'0' || cmd[5]>'3'){fault("invalid_bench_profile");result(false);return;}
590: if(valid)for(uint8_t i=3;i<7;++i){if(cmd[i]<'0'||cmd[i]>'9'){valid=false;break;}target=target*10+cmd[i]-'0';}
644: for(uint8_t n=0;n<32 && Serial.available();++n) {
653: if(!((c>='A' && c<='Z') || (c>='0' && c<='9')) || used>=sizeof(line)-1) {bad=true;fault("invalid_command");}
657: if(dualSession && state==ARMED && uint32_t(millis()-lastIdleMonitor)>=30) {
```

## H/board_commission.py

```text
16: optical_cap=40 if edge_distance<90 else 110
17: cap=CAP if np.linalg.norm(target-spot)>45 else np.array([18,10])
27: if cv2.pointPolygonTest(polygon,tuple(map(float,prediction)),True)<5:continue
29: inside=lambda axis:cv2.pointPolygonTest(polygon,tuple(map(float,spot+J[:,axis]*delta[axis])),True)>=5
50: if abs(goal-old[axis])>limit-6 or not LOW[axis]<=goal<=HIGH[axis]:raise RuntimeError('Host step envelope exceeded')
63: if abs(d)<=2:break
78: if abs(d)<=3:break
104: if np.min(np.linalg.svd(dq,compute_uv=False))<3:raise RuntimeError('Insufficient independent calibration motion')
106: if np.linalg.cond(J)>15 or np.min(np.linalg.svd(J,compute_uv=False))<.15:raise RuntimeError('Unreliable initial optical response')
115: if np.any(current_board<1.8) or np.any(current_board>16.2):stages.append(np.clip(current_board,2.,16.))
120: if np.linalg.norm(np.array(cur['spot_board'])-stage)<=.18:break
121: if time.monotonic()-start_target>240:raise RuntimeError('Target approach time limit')
122: if time.monotonic()-lit_since>35:light();cur=sample()
128: if np.linalg.norm(dp)>180:raise RuntimeError('Unexpected optical displacement')
129: if np.linalg.norm(target-cur['spot_reference_px'])>np.linalg.norm(target-previous['spot_reference_px'])+50:raise RuntimeError('Optical approach moved away from target')
130: if np.linalg.norm(dq)>=2:
132: if np.linalg.cond(candidate)<15 and np.linalg.norm(candidate-J)<2:J=.5*J+.5*candidate
```

## H/bridge_alignment.py

```text
27: if count<1:raise AlignmentChanged('Empty motion-check board mask')
72: if self.artifacts!=binding_key(binding) or not 0<=now-self.captured_at<=10:
93: support_policy='printed_board_interior_v1',flow_radius_half_px=radius)
96: if self.points is None or len(self.points)<40:raise AlignmentChanged('Insufficient motion-check texture')
120: good=(ok.ravel()>0)&(back_ok.ravel()>0)&np.isfinite(q).all(axis=1)&(np.linalg.norm(back.reshape(-1,2)-p,axis=1)<.5)
125: quadrants=[int(np.count_nonzero(good&(((p[:,0]>=center[0])==right)&((p[:,1]>=center[1])==lower))))
127: original_quadrants=[int(np.count_nonzero(((p[:,0]>=center[0])==right)&((p[:,1]>=center[1])==lower)))
131: if good.sum()<40 or good.mean()<.85:raise AlignmentChanged('Board view changed or obscured')
132: if min(quadrants)<6:raise AlignmentChanged('Uneven motion-check coverage')
137: if median>.5 or p95>1:
142: if median>.5:
155: if median>.5 or p95>1:
159: if np.max(np.linalg.norm((prepared[1]-self.prepared[1])*np.array(binding.binding['image_size']),axis=1))>2:
167: support_radius_full_px=EDGE_RADIUS,pyramid_max_level=0)
179: if good.sum()<40 or good.mean()<.85 or min(counts)<6:
184: if median>.5 or p95>1:
197: if self.entry is not None and time.time()-self.entry.captured_at<2:return None
```

## H/bridge_board_domain.py

```text
6: # Half-resolution radius: LK21 at pyramid2 (40), pyramid filtering(6),
10: # LK21 at level0: radius10 + derivatives1 + interpolation1 +2 margin.
14: EDGE_RADIUS = 10  # full-res window radius7 + derivative/interpolation +1 guard
18: return cv2.erode(mask,np.ones((2*radius+1,2*radius+1),np.uint8),borderType=cv2.BORDER_CONSTANT,borderValue=0)
24: inside=finite&(xy[:,0]>=0)&(xy[:,1]>=0)&(xy[:,0]<mask.shape[1])&(xy[:,1]<mask.shape[0])
25: result=np.zeros(len(p),bool);result[inside]=mask[xy[inside,1],xy[inside,0]]>0
60: if len(xs)>.01*np.count_nonzero(self.full_mask) or xs.max()-xs.min()>72 or ys.max()-ys.min()>72:
86: good=(ok.ravel()>0)&(bok.ravel()>0)&np.isfinite(q.reshape(-1,2)).all(axis=1)&np.isfinite(back.reshape(-1,2)).all(axis=1)
87: good &= np.linalg.norm(back.reshape(-1,2)-p.reshape(-1,2),axis=1)<1.
```

## H/bridge_correspondence.py

```text
19: MAX_REPAIRS = 32                  # Bound work; an unresolved frame remains rejected.
20: MIN_PEAK = .8                     # Repair confidence, never ordinary-frame admission.
21: MIN_PEAK_MARGIN = .1
22: MAX_REPAIR_SECONDS = .1
46: if x-r < 0 or y-r < 0 or x+r >= reference.shape[1] or y+r >= reference.shape[0]:
51: if float(template.std()) < 1:
57: if (competitors[:, 0].min() <= xmin+PEAK_RADIUS or competitors[:, 0].max() >= xmax-PEAK_RADIUS or
58: competitors[:, 1].min() <= ymin+PEAK_RADIUS or competitors[:, 1].max() >= ymax-PEAK_RADIUS):
92: diagnostics.update(maximum_seconds=MAX_REPAIR_SECONDS,patch_side_half_px=2*PATCH_RADIUS+1, search_radius_half_px=SEARCH_RADIUS,
95: suspects = np.flatnonzero(good & (np.linalg.norm(tracked-points, axis=1)*2 > 1))
113: if not _finite(found) or not _finite(reverse) or np.linalg.norm(reverse-points[i]) > .5:
123: np.linalg.norm(back-anchor) > .5 or np.linalg.norm(subpixel-found) > 1.5):
```

## H/bridge_feedback.py

```text
33: MAX_MOVES = 25
54: if abs(target-p[axis])>(18,10)[axis]:
70: np.linalg.cond(coefficients[:2]) > 15):
91: if np.any(abs(delta) > [8, 5]):
123: inward = (np.clip(origin, 3., 15.) if np.any((origin < 2.) | (origin > 16.))
124: and np.linalg.norm(origin-board) > 2. else None)
125: for count in range(MAX_MOVES+1):
134: if inward is not None and np.linalg.norm(np.asarray(current['spot_board'])-inward) <= .5:
140: fast = coarse_for_goal(current['pose'], goal, np.linalg.norm(target-spot) > 45)
196: if remaining <= 0:raise LaserOpticalFault('Visible correction exhausted geometry lifetime')
232: and np.any(abs(np.asarray(actual)-acquisition.pose)>3)):
282: if np.any(abs(actual-self.settled_pose) > 3):
304: now-bound <= .750 and p['generation'] == session.control_generation and
306: all(s['torque'] == 1 and abs(s['velocity']) <= 2 for s in p['samples'])):
328: if any(not np.isfinite(age) or age < 0 or age > .6 for age in ages):
353: if np.any(abs(actual-before) > 3):
363: expired=any(not np.isfinite(age) or age < 0 or age > .6 for age in ages)
394: if not 0 <= mono-pose_proof['acquisition_lower_bound_uptime'] <= .750:
398: if any(not np.isfinite(age) or age<0 or age>.6 for age in current_ages):
443: if remaining <= 0:raise LaserOpticalFault('Finite feedback approach allowance reached during acquisition')
447: if np.any(abs(actual-np.asarray(sample['pose'])) > 3):
464: if np.all(abs(goal-actual) <= 6):break
477: if np.any(abs(actual-waypoint)>6):
483: if np.any(abs(actual-recenter)>6):
510: if np.any(abs(actual-np.asarray(sample['pose'])) > 3):
513: if np.any(abs(goal-actual) > ([108, 58] if fast else [18, 10])):
542: if np.any(abs(fresh-actual)>3):
548: if np.any(abs(remaining-actual)>[18,10]):
```

## H/bridge_hardware.py

```text
39: if np.any(q<[1006,1906]) or np.any(q>[2894,2744]):raise LaserOpticalFault('Host pose bounds')
40: if np.any(abs(q-np.asarray(current))>([1800,350] if coarse else [24,12])):
114: if remaining<=0:raise LaserTransportFault('No reply for '+command)
176: if self.retain_frames and len(retained)<7:retained.append(frame)
255: if count==2 and target is not None and np.linalg.norm(np.asarray(target)-project(np.linalg.inv(H),[spot])[0])<=10:
306: if len(self.pending_optical_failures)>=2:return dict(retained=False,reason='bounded_queue_full')
376: if frame.metadata['frame']['timestampSource']!='cameraPresentation' or captured<max(off_since+.3,request['alignmentPreparation']['positionConfirmedAtUnix']):return
513: if not np.isfinite(J).all() or np.linalg.cond(J)>15:raise LaserSetupFault('Ill-conditioned optical model')
615: while continuous or time.monotonic()-light_start<55:
623: if missing>=3:raise LaserOpticalFault('Spot not found in three fresh samples') from error
633: emit('adequate' if distance<=10 and not provisional else 'refining',True,
636: if last is not None and distance>last+45:raise LaserOpticalFault('Correction diverged')
638: if distance<=3:after=stream.last.metadata['frame']['capturedAtUptime'];continue
643: if wiggle is not None and wiggle.index>=0 and np.linalg.norm(predicted-target)>8:
645: if cv2.pointPolygonTest(poly,tuple(map(float,predicted)),True)<2:
```

## H/bridge_lit_geometry.py

```text
17: MAX_RADIUS_PX=36
19: MAX_BOARD_FRACTION=.01
20: MAX_PROOF_SECONDS=.10
33: if len(set(members))<5 or n-1 not in members:
40: if np.linalg.norm(spot-center)>8:
42: radius=0.;used=[]
46: component=max((c for c in row['hits'] if np.linalg.norm(np.asarray(c['xy'])-chosen)<.001),
52: if min(x,y)<0 or min(w,h)<=0 or x+w>shape[1] or y+h>shape[0]:
55: radius=max(radius,float(np.linalg.norm(corners-spot,axis=1).max()))
59: if len(set(used))<5 or n-1 not in used:
62: radius=int(math.ceil(radius+HALO_PX))+1
63: if not 1<=radius<=MAX_RADIUS_PX:
66: if not cv2.isContourConvex(poly) or cv2.pointPolygonTest(poly,tuple(map(float,spot)),False)<0:
69: mask=np.zeros_like(board);cv2.circle(mask,tuple(np.rint(spot).astype(int)),radius,1,-1)
```

## H/bridge_reference.py

```text
55: if np.max(np.linalg.norm(np.array(candidate.setup['grid_corners'])-base.setup['grid_corners'],axis=1))>8:
65: if not np.isfinite(J).all() or np.linalg.cond(J)>15:raise SetupMismatch('Automatic reference optical model ill-conditioned')
72: captured<max(off_since+.3,request['alignmentPreparation']['positionConfirmedAtUnix'])):return None
77: if self.samples and (frame.identity[1]<=self.samples[-1][0] or captured<=self.samples[-1][1]):return None
81: if len(self.samples)<3 or captured-self.samples[0][1]<.4:return None
83: if agreement>1: self.samples=[];raise SetupMismatch('Automatic reference frames disagree')
```

## H/bridge_setup.py

```text
44: if len(row_col) != 2 or any(type(n) is not int or not 0 <= n < 19 for n in row_col):
71: if not np.isfinite(xy).all() or np.any(xy<0) or np.any(xy>18):
94: if corners.shape != (4,2) or not np.all(np.isfinite(corners)) or np.any(corners<0) or np.any(corners>1):
128: tolerance=min(8.,.2*spacing)
129: if not np.isfinite(spacing) or spacing<10 or geometry_error>tolerance:
```

## H/calibration_aim_quality.py

```text
31: if np.linalg.norm(project(grid, [board])[0]-pixels) >= .02:
34: if np.any(pose != np.rint(pose)) or np.any(pose < [1006,1906]) or np.any(pose > [2894,2744]):
43: ids != sorted(set(ids)) or not ids or ids[0] < 0 or ids[-1] != batch-1):
47: if len(selected) < 5 or selected[-1] != batch-1 or selected != detail['frames']:
52: if np.linalg.norm(project(transform, [pixels])[0]-center) >= 8:
61: if (any(type(v) is not int for v in (x,y,w,h)) or min(w,h) <= 0 or
62: not (x <= point[0] < x+w and y <= point[1] < y+h) or
63: not 3 <= component['area'] <= min(2000, w*h)):
66: margin = min(cv2.pointPolygonTest(polygon, tuple(map(float,p)), True) for p in corners)
68: unclipped = search is None or float(np.linalg.norm(np.asarray(corners)-pair(search), axis=1).max()) < 98
69: unique = bool(np.all(np.abs(project(to_board, corners)-target) < .5))
71: if unclipped and margin >= 2 and unique and distance_cells <= .25:
72: quality = 'desired' if distance_px < 3 else 'usable'
```

## H/calibration_fit_resume.py

```text
113: detection['frame_count']<5 or detection['search_center_px'] is not None):
135: if margin(setup,pixel) < 5:
143: np.any(pose < [1006,1906]) or np.any(pose > [2894,2744]) or
144: np.any(abs(pose-anchor['pose']) > [8,5])):
161: if np.linalg.norm(project(np.asarray(setup['board_to_image']),[board])[0]-pixels) >= .02:
165: # board. Admit only the ordinary <3 px aim envelope, not extra board cells.
167: if residual >= 3 or edge_error >= 3:
180: if np.any(goal < [1006,1906]) or np.any(goal > [2894,2744]):
183: if margin(setup,predicted) >= 5:
193: if np.any(abs(delta)>[8,5]):
199: if error >= 3 or actual@predicted <= 0:
224: if np.any(abs(delta)>[8,5]):
231: if min(np.linalg.svd(dq,compute_uv=False)) < 3:
235: if (goal[1]-current['pose'][1])*(probes[2]['pose'][1]-probes[1]['pose'][1]) <= 0:
240: if np.any(abs(delta)>[8,5]):
```

## H/calibration_observed_recenter.py

```text
59: not np.isfinite(off['off_since_unix']) or off['off_since_unix']<=0):
121: if len(samples)<3 or any(s.get('stage')!='fit' for s in samples):
124: if any(type(t) not in (int,float) or not np.isfinite(t) or t<=0 for t in times) or any(b<=a for a,b in zip(times,times[1:])):
127: if len(moves)<len(samples)-1:raise ValueError('Incomplete measured response move chain')
133: if move.get('profile')!='bounded fast pair' or np.any(abs(difference)>6):
137: np.any(abs(_pose(move['goal'])-_pose(move['start']))>[108,58])):
145: matching=[i for i,s in enumerate(samples) if s['pose']==last['pose'] and np.linalg.norm(np.asarray(s['spot_board'])-last['spot_board'])<.01]
149: if len(centers)!=1 or not np.isfinite(centers[0]['error_px']) or not 0<=centers[0]['error_px']<3:
152: if np.linalg.norm(np.asarray(center['spot_board'])-[9,9])>.15 or not any(s['pose']==center['pose'] and np.linalg.norm(np.asarray(s['spot_board'])-center['spot_board'])<.01 for s in samples):
155: if np.linalg.norm(project(run['setup']['board_to_image'],[sample['spot_board']])[0]-sample['spot_reference_px'])>.02:
158: if (np.any(np.asarray(latest['spot_board'])<0) or np.any(np.asarray(latest['spot_board'])>18) or
159: np.linalg.norm(project(spot['setup']['board_to_image'],[latest['spot_board']])[0]-latest['spot_reference_px'])>.02):
161: if latest['observed_at_uptime']<=times[-1] or spot['report']['finalOff']['off_since_unix']<=r['finalOff']['off_since_unix']:
183: if np.max(np.linalg.norm(project(expected,[[0,0],[18,0],[18,18],[0,18]])-np.asarray(setup['grid_corners']),axis=1))>.05:
187: if cv2.pointPolygonTest(polygon,tuple(prediction),True)<5:raise ValueError('Observed anchor lacks printed-board margin')
197: if np.any(abs(actual-admission['latest_pose'])>3):raise ValueError('Fresh recenter pose no longer matches observed anchor')
206: if error>3 or cv2.pointPolygonTest(admission['polygon'],tuple(pixel),True)<5:
208: if np.linalg.norm(project(admission['Gi'],[pixel])[0]-value['spot_board'])>.01:
219: if not np.isfinite(predicted).all() or cv2.pointPolygonTest(admission['polygon'],tuple(predicted),True)<5 or _distance(admission,predicted)>=_distance(admission,pixels):
```

## H/calibration_prelight.py

```text
66: self.pre_mask=np.rint(cv2.GaussianBlur((self.mask>0).astype(np.float32),(5,5),0)*(.5/.95)).astype(np.uint8)
88: valid=self.mask>0
90: changed=(np.abs(observed-(gain*predicted+offset))>.08).astype(np.uint8)
92: clear=self.mask.copy();clear[changed>0]=0
94: if coverage<.85:raise ValueError('Foreground coverage too large')
98: if ratio<.70:raise ValueError('Foreground coverage uneven')
107: if not np.isfinite(H).all() or movement>=3:raise ValueError(f'Board/camera moved: {movement:.6f}px')
110: if not np.isfinite(quality) or quality<.95:raise ValueError(f'Full-board fixed-transform ECC below .95: {quality:.9f}')
144: self.agrees_with_original = local['original']['delta_px'] < 3
203: if not np.isfinite(from_a) or from_a >= 3:
214: if not np.isfinite(from_b) or from_b >= 3:
222: conflicts = {key for key, distance in distances.items() if distance >= 3}
225: original_agrees = local['original']['delta_px'] < 3
234: local['B']['delta_px'] < 3)
257: if not np.isfinite(quality) or quality < .95:
```

## H/calibration_response_region.py

```text
16: if (np.any(low>high) or np.any(high-low>256) or J.shape!=(2,2) or not np.isfinite(J).all() or
17: type(max_boxes) is not int or not 1<=max_boxes<=32768):
31: queue=[(low,high,0)];visited=0;accepted=0;max_disagreement=0.;min_margin=math.inf
48: if gap<3 and margin>=5:
49: accepted+=1;max_disagreement=max(max_disagreement,float(gap));min_margin=min(min_margin,margin);continue
54: if np.linalg.norm(local_mid-relative_mid)>=3 or min(margin_lower(p) for p in (local_mid,absolute_mid,relative_mid))<5:
56: if depth>=18 or max(b-a)<1e-4:raise ValueError('Continuous response limits cannot be established')
61: disagreement_limit_px=3,margin_limit_px=5,visited_subboxes=visited,accepted_subboxes=accepted,
76: if abs(target-p[axis])>(8,5)[axis]:raise ValueError('Probe command exceeds8/5')
82: if np.any(low<[1006,1906]) or np.any(high>[2894,2744]):
```

## H/calibration_steering.py

```text
22: if np.any(q<[1006,1906]) or np.any(q>[2894,2744]):raise ValueError('Candidate pose outside motor domain')
29: if not np.isfinite(point).all() or abs(point[2])<1e-9:raise ValueError('Unbounded candidate ray intersection')
31: if np.linalg.norm(predict(p,[board])[0]-q)>1e-6:raise ValueError('Candidate ray inversion is not unique')
45: if not np.isfinite(J).all() or np.linalg.cond(J)>15 or min(np.linalg.svd(J,compute_uv=False))<.15:
64: margins=[float(cv2.pointPolygonTest(poly,tuple(map(float,p)),True)) for p in (local,candidate,absolute)]
65: if not np.isfinite(discrepancy) or not np.isfinite(margins).all() or discrepancy>=3 or min(margins)<5:
66: message=f'Steering endpoint rejected: disagreement={discrepancy:.6f}px, margins={margins}'
67: if np.isfinite(discrepancy) and np.isfinite(margins).all() and discrepancy>=3 and min(margins)>=5:
110: if min(np.linalg.svd(dq,compute_uv=False))<3:continue
129: if not np.isfinite([error,direction]).all() or error>=3 or direction<=0:raise ValueError('Observed independent probe disagrees with candidate steering')
140: if min(np.linalg.svd(dq,compute_uv=False))<3:
158: if min(np.linalg.svd(dq,compute_uv=False))<3:raise InsufficientProbeTravel('Bounded extension cannot establish independent travel')
170: return bool(preferred and np.any(abs(pair(goal)-pair(start))>[18,10]))
```

## H/dark_geometry_registration.py

```text
31: return distance[int(round(key.pt[1])),int(round(key.pt[0]))]>=np.ceil(28*1.2**key.octave+2)
38: if len(pair)==2 for m,n in [pair] if m.distance<.7*n.distance]
39: if len(good)<40:continue
43: if H is not None and int(ins.sum())>=35:
45: if kept.sum()>=35:
54: if not np.isfinite(shift).all() or shift.max()>25:raise RuntimeError('Board/camera moved; setup check needed')
59: if diagnostic['orb_median_px']>1.5 or diagnostic['orb_p90_px']>2.5:
72: mask=_support(a,polygon);mask[mapped_support<1.]=0
76: low,high=np.percentile(image[mask>0],[5,95])
80: # p/q/back with10/7px insets (window radius + derivative/interpolation guard),
88: inside=finite&(xy[:,0]>=0)&(xy[:,0]<a.shape[1])&(xy[:,1]>=0)&(xy[:,1]<a.shape[0])
89: result=np.zeros(len(xy),bool);result[inside]=support[xy[inside,1],xy[inside,0]]>0
108: good[indices]=(ok.ravel()>0)&(bok.ravel()>0)&supported(tracked,support)&supported(back,support)&(
109: np.linalg.norm(back.reshape(-1,2)-probes.reshape(-1,2),axis=1)<1.)
111: quadrants=[int(np.count_nonzero(good&((board[:,0]>=9)==right)&((board[:,1]>=9)==lower)))
116: if good.sum()<40 or min(quadrants)<6 or min(edges)<3:
120: if diagnostic['grid_median_px']>.5 or diagnostic['grid_p95_px']>1:
```

## H/fast_spot_feedback.py

```text
17: if not 20<=winner['area']<=500 or xy.shape!=(2,) or not np.isfinite(xy).all():
20: if np.linalg.norm(np.asarray(rival['xy'])-xy)>8 and rival['area']>=winner['area']/3:
24: if np.linalg.norm(xy[1]-xy[0])>2.5:
27: if max(areas)>2*min(areas):raise RuntimeError('Early spot appearance is changing')
38: if J.shape!=(2,2) or error.shape!=(2,) or not np.isfinite(J).all() or not np.isfinite(error).all() or np.linalg.cond(J)>15:
44: if np.linalg.norm(J@step)<=12:return position+step
```

## H/feedback_predicted_acquisition.py

```text
18: MAX_WAYPOINTS = 8
47: # local guard's 5px uncertainty + 5px retained margin, try points strictly
58: if np.any(np.rint(goal)<[1006,1906]) or np.any(np.rint(goal)>[2894,2744]):continue
67: if proof['minimum_model_margin_px'] < 2*MARGIN:
72: """Enclose absolute AND observed-origin-shifted model corridors >=5px.
82: if count > 511:raise AcquisitionDeclined('Predicted dark corridor proof budget exceeded')
86: margin = min(cv2.pointPolygonTest(self.polygon, tuple(map(float, p)), True)
95: if any(cv2.pointPolygonTest(self.polygon,tuple(map(float,pixel+shift)),True)<MARGIN
98: if depth >= 12 or max(hi-lo)<.01:
```

## H/feedback_response_prior.py

```text
61: if len(points) < 3:
67: while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:lower.pop()
70: while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:upper.pop()
73: if len(vertices) < 3:raise ValueError('Degenerate observed response support')
82: if np.any(pose != np.rint(pose)) or np.any(pose < [1006,1906]) or np.any(pose > [2894,2744]):
100: if type(value) not in (int,float) or not math.isfinite(value) or not 0 <= value < 3:
185: if vertices.ndim != 2 or vertices.shape[1] != 2 or len(vertices)<3 or not np.isfinite(vertices).all():
192: if np.any(p < [1006,1906]) or np.any(p > [2894,2744]):
197: if edge[0]*(p-a)[1]-edge[1]*(p-a)[0] < -1e-7:
213: if abs(board[2])<1e-9:raise ValueError('Unbounded response ray')
216: if abs(image[2])<1e-9:raise ValueError('Unbounded response projection')
226: if np.any(pose < [1006,1906]) or np.any(pose > [2894,2744]):raise ValueError('Pose outside motor domain')
228: if not np.isfinite(J).all() or np.linalg.cond(J)>15 or min(np.linalg.svd(J,compute_uv=False))<.15:
```

## H/feedback_step_policy.py

```text
15: MIN_MARGIN_PX = 5.
17: MAX_RESPONSE_GAIN = 2.
24: points lie in the convex hull of these four vertices. Requiring 10px margin
25: leaves the normal 5px margin even with an additional 5px position error.
32: or polygon.ndim != 2 or polygon.shape[1] != 2 or len(polygon) < 3
37: for gains in product((0., MAX_RESPONSE_GAIN), repeat=2):
39: if cv2.pointPolygonTest(polygon, tuple(map(float, pixel)), True) < MIN_MARGIN_PX + UNMODELLED_ERROR_PX:
63: optical_cap = EDGE_TRAVEL_PX if distance < EDGE_DISTANCE_PX else 110.
```

## H/point_vision.py

```text
33: if left<=0:raise RuntimeError('Camera timeout')
35: return [v for v in self.frames if v[0]>start][-n:]
37: with self.condition:return [v for v in self.frames if start<=v[1]<=end]
82: good=[m for m,n in cv2.BFMatcher(cv2.NORM_HAMMING).knnMatch(d1,d2,k=2) if m.distance<.7*n.distance]
83: if len(good)<40:
87: if H is not None and int(ins.sum())>=35:break
88: if H is None or int(ins.sum())<35:raise RuntimeError('Unreliable board registration')
106: if quality<.95:
113: valid=boardmask>0
117: changed=(np.abs(observed-(gain*predicted+offset))>.08).astype(np.uint8)
119: clear=boardmask.copy();clear[changed>0]=0
120: if np.count_nonzero(clear)<.85*np.count_nonzero(boardmask):
126: if np.count_nonzero(clear[region])<.70*np.count_nonzero(boardmask[region]):
143: if median_error>1.5 or p90_error>2.5:
145: if quality<.95:raise RuntimeError('Unreliable board registration texture match')
149: if np.max(np.linalg.norm(shift,axis=1))>25:raise RuntimeError('Board/camera moved; setup check needed')
217: mask=((im16[:,:,2]>120)&(d[:,:,2]>12)&(d[:,:,2]-d[:,:,1]>12)).astype(np.uint8)
223: if not 3<=area<=2000:continue
241: if w.sum()<=0:raise RuntimeError('No optical spot signal')
259: if len(frames)<5:raise RuntimeError('Too few on frames')
```

## H/spot_clusters.py

```text
12: nearby=[c for c in h['hits'] if np.linalg.norm(np.array(c['xy'])-seed)<8]
16: if sum(members)>=5:
22: if other>=.8*score and np.linalg.norm(where-center)>8:raise RuntimeError('Competing persistent bright clusters; inspect before moving')
25: chosen_areas=[max(c['area'] for c in h['hits'] if np.linalg.norm(np.array(c['xy'])-chosen)<.001)
27: if np.linalg.norm(xy[-1]-center)>=8 and keep[-1]:
31: if candidate['area']>=max(12,2*typical) and np.linalg.norm(np.array(candidate['xy'])-center)>8:
```

## N/AutoGridDetector.swift

```text
41: request.minimumConfidence = 0.4
57: if let best = results.max(by: { $0.quality < $1.quality }) { return best }
72: var supported:Bool {matched>=4 && fraction>=0.6 && distributed}
82: for vertical in [false,true] {for rail in 0..<n {for segment in 0..<(n-1) {
104: let quadrant=(row<Double(n)/2 ? 0:2)+(col<Double(n)/2 ? 0:1)
106: guard contrasts.filter({$0>0.045}).count>=2 else {continue}
115: let bordersSupported=borders.allSatisfy({$0>=3}) ||
116: (allowSingleCoveredBorder && borders.filter({$0>=max(3,n/2)}).count>=3)
117: guard tested>=n*4,matched>=n*4,Double(matched)>=Double(tested)*0.65,
119: for quadrant in 0..<4 where quadrants[quadrant]<n/2 {
123: guard quadrantTests[quadrant]<n/2,quadrantTests[quadrant]>=3,
124: Double(quadrants[quadrant])>=Double(quadrantTests[quadrant])*0.85 else {return nil}
126: let q=(Double(i/n)<Double(n)/2 ? 0:2)+(Double(i%n)<Double(n)/2 ? 0:1)
137: guard stones.supported,stones.matched>=max(6,n/2),stones.fraction>=0.8 else {return nil}
148: for segment in 0..<(n-1) {
163: guard points.count>=6,let first=points.first,let last=points.last,last.0-first.0>=Double(n-1)*0.5 else {return nil}
168: guard points.allSatisfy({abs($0.1-intercept-slope*$0.0)<0.09}) else {return nil}
175: guard abs(denominator)>0.9 else {return nil}
179: guard hypot(x-expectedX,y-expectedY)<0.25 else {return nil}
199: let coherent=core.filter {expected[i] == .black ? outside-$0>0.06:$0-outside>0.06}.count
200: if contrast>0.09 && coherent>=3 {matched.append((c,r))}
207: distributed:xx>=1 && yy>=1 && xx*yy-xy*xy>=2)
217: guard whole.supported,whole.matched>=24,whole.fraction>=0.85 else {return nil}
218: for quadrant in 0..<4 {
220: let q=(Double(i/n)<Double(n)/2 ? 0:2)+(Double(i%n)<Double(n)/2 ? 0:1)
224: guard evidence.supported,evidence.matched>=6,evidence.fraction>=0.8 else {return nil}
233: guard whole.fraction-other.fraction>=0.025 else {return nil}
240: guard expected.count==size*size,expected.filter({$0.stone != nil}).count>=4,
252: if evidence.supported,evidence.fraction>=0.8,
256: let refinedSupport=knownGridSupport(frame:frame,calibration:refined,expected:expected),refinedSupport>=support*0.97 {
258: if landmarks.supported,landmarks.fraction>=0.8 {calibration=refined;quality=refinedSupport}
265: guard !candidates.contains(where:{zip($0.calibration.corners,candidate.calibration.corners).allSatisfy {hypot($0.x-$1.x,$0.y-$1.y)<0.004}}) else {return}
277: proposals.sort {$0.2.fraction>$1.2.fraction}
289: for turns in 0..<4 {
295: if !ranked.contains(where:{zip($0.0.calibration.corners,corners).allSatisfy {hypot($0.x-$1.x,$0.y-$1.y)<0.008}}) {ranked.append((rotated,evidence))}
298: ranked.sort {$0.1.fraction>$1.1.fraction}
303: if ranked.count>1,best.1.fraction-ranked[1].1.fraction<0.15 {
340: if landmarks.supported,landmarks.matched>=6,landmarks.fraction>=0.85,
351: refinedSupport>=support*0.97 {
359: if verified.supported,verified.matched>=6,verified.fraction>=0.85,pixels>=jitterTolerance {
376: let supported=error<0.04 && alignmentSupported(frame:frame,calibration:previous,anchor:anchor,
379: if !supported {details["rejectionReason"]=error>=0.04 ? "no grid fit; profile error too high":"no grid fit; insufficient distributed line support"}
398: guard maximum<0.4 else {
411: if after<before*0.8 && before-after>0.008 {details["outcome"]="tracking correction accepted";return aligned}
412: if before<0.04 {details["outcome"]="existing grid retained by profile error";return previous}
417: private static func alignmentSupported(frame:GrayFrame,calibration:BoardCalibration,anchor:TrackingAnchor,minimumFraction:Double=0.6,report:(([String:Any])->Void)?=nil)->Bool {
420: for vertical in [false,true] { for rail in 0..<n { for segment in 0..<(n-1) {
435: let shift=spacing.isFinite && spacing>0 ? min(0.04,1/spacing):0
446: let faint=high-low<=0.06
452: guard rail==0 || rail==n-1,high-low>max(0.018,high*0.035),
453: let trough=a.indices.min(by:{a[$0]<a[$1]}),(2...4).contains(trough),
454: min(a[0],a[6])-low>(high-low)*0.75 else {continue}
458: guard currentDepth>max(faint ? 0.012:0.035,depth*0.25),currentDepth<depth*3 else { continue }
463: guard error/7<min(0.10,0.03/depth) else { continue }
474: quadrants[(r<n/2 ? 0 : 2)+(c<n/2 ? 0 : 1)] += 1
479: if tested<n*4 {failed.append("too few reference line samples")}
480: if matched<n*8 {failed.append("too few matching line samples")}
482: if !borders.allSatisfy({$0>=3}) {failed.append("one or more outer rails lack support")}
483: if !quadrants.allSatisfy({$0>=n/2}) {failed.append("one or more quadrants lack support")}
492: for vertical in [false,true] { for rail in 0..<calibration.size {
493: for segment in 0..<(calibration.size-1) {
501: guard base.count==7,let bright=base.max(),let dark=base.min(),bright-dark>0.06,
508: return errors.count>=calibration.size*4 ? median(errors) : .infinity
527: for y in 0..<side { for x in 0..<side {
531: let margin = side/12
532: for i in 0..<side {
534: columns[i] /= Double(side-2*margin); rows[i] /= Double(side-2*margin)
541: return results.max { $0.quality < $1.quality }
551: guard abs(denominator)>0.5 else { return nil }
561: for vertical in [false,true] { for rail in 0..<proposal.size {
563: for index in 0..<(proposal.size-1) { for offset in [0.33,0.67] {
578: if best > -1 { contrasts.append(best) }
583: let supported = scores.filter { $0 > 0.035 }.count
584: guard [0,proposal.size-1,proposal.size,2*proposal.size-1].allSatisfy({ scores[$0] > 0.035 }) else { return nil }
585: guard supported >= Int(ceil(Double(scores.count)*0.9)), median(scores) > 0.07 else { return nil }
593: for i in 5..<(side-5) { ridge[i] = (profile[i-4]+profile[i+4])*0.5-profile[i] }
595: let peaks = (6..<(side-6)).filter { i in ridge[i]>=cutoff && ridge[i] == ridge[(i-3)...(i+3)].max()! }
599: for first in peaks where first < side/5 {
600: for last in peaks where last > side*4/5 {
602: guard pitch >= 12 else { continue }
603: let tolerance = min(6,pitch*0.22)
609: position > border+2 && position < Double(side-1)-border-2 &&
610: peaks.contains(where: { abs(Double($0)-position)<tolerance })
613: for i in 0..<count {
615: if let peak = peaks.filter({ abs(Double($0)-expected)<tolerance }).max(by:{ridge[$0]<ridge[$1]}) { matches.append(peak) }
619: let unused = peaks.filter { $0>=first && $0<=last && !matches.contains($0) }
623: guard knownPosition || unused.count <= max(1,count/8) else { continue }
625: guard errors.max() ?? 1 < 0.16 else { continue }
631: return fits.sorted { $0.1 > $1.1 }.prefix(4).map { $0.0 }
635: guard x>=0,y>=0,x<Double(side-1),y<Double(side-1) else { return nil }
642: for index in 0..<64 {
654: let radius = min(8,pitch*0.28)
656: for da in stride(from:-radius,through:radius,by:2) { for db in stride(from:-radius,through:radius,by:2) {
```

## N/BoardAppearanceDetector.swift

```text
19: guard (0..<n*n).contains(point),!occupied.contains(point) else {return nil}
21: for y in max(0,r-3)..<min(n-1,r+3) {for x in max(0,c-3)..<min(n-1,c+3) {
27: if y>=r-2,y<r+2,x>=c-2,x<c+2 {
35: guard candidate.state == .empty,candidate.confidence>=0.75,cross.crossVisible else {return nil}
41: for r in 0..<(n-1) { for c in 0..<(n-1) {
47: for r in 0..<n { for c in 0..<n {
50: for y in max(0,r-2)..<min(n-1,r+2) { for x in max(0,c-2)..<min(n-1,c+2) {
55: for y in max(0,r-3)..<min(n-1,r+3) { for x in max(0,c-3)..<min(n-1,c+3) {
59: let colors=wider.filter{abs($0.level-broadLevel)<0.06}.compactMap(\.color)
60: let broadColor:BoardChroma? = colors.count>=4 ? BoardChroma(red:median(colors.map(\.red)),green:median(colors.map(\.green))) : nil
61: let broad:Wood? = wider.count>=4 && broadLevel>0.15 && broadLevel<0.96 ? Wood(level:broadLevel,color:broadColor) : nil
65: var candidate=Candidate(state:.uncertain,confidence:0,delta:0)
86: if (0..<(n-1)).contains(r) && (0..<(n-1)).contains(c) { clean[r*(n-1)+c]=nil }
102: guard cross.horizontal>=0.75, cross.vertical>=0.75 else {continue}
106: for y in max(0,reading.row-1)..<min(n-1,reading.row+1) {
107: for x in max(0,reading.col-1)..<min(n-1,reading.col+1) {
115: nearby.contains(where:{($0-color).magnitude<0.055}) { matches+=1 }
117: let state:Occupancy = matches>=3 ? .empty : .uncertain
119: confidence:state == .empty ? min(cross.horizontal,cross.vertical) : 0,delta:reading.delta)
133: for r in 0..<3 { for c in 0..<3 { matrix[r][c] += w*a[r]*a[c] }; matrix[r][3] += w*a[r]*z }
136: guard used>=4 else { return nil }
137: for col in 0..<3 {
138: let pivot=(col..<3).max { abs(matrix[$0][col])<abs(matrix[$1][col]) }!
139: guard abs(matrix[pivot][col])>1e-8 else { return nil }
143: for row in 0..<3 where row != col {
153: let clean=zip(neighbors,residuals).filter{$0.1<cutoff}.map{$0.0}
154: guard let plane=fit(clean,value:{$0.level}),plane[0]>0.15,plane[0]<0.96,
155: abs(plane[1])<0.12,abs(plane[2])<0.12,median(residuals)<0.04 else { return nil }
164: for dy in [-0.26,-0.18,-0.10,0.10,0.18,0.26] { for dx in [-0.26,-0.18,-0.10,0.10,0.18,0.26] where dx*dx+dy*dy<0.13 {
171: if abs(dx)>=0.18 && abs(dy)>=0.18 {
176: if level-blackWoodLevel < -max(0.10,threshold) { black += 1 }
180: pale=base.magnitude-current.magnitude>0.035 && current.magnitude<base.magnitude*0.65 && delta > -0.01
182: if delta>max(0.045,min(threshold,(1-wood.level)*0.22)) || pale { white += 1 }
184: if let base=wood.color,let current=frame.patchColor(p) { colorClose=(base-current).magnitude<0.045 }
186: if abs(delta)<max(0.06,threshold*0.6) && colorClose { similar += 1 }
188: guard values.count>=24 && outerCount>=9 else { return Candidate(state:.uncertain,confidence:0,delta:0) }
193: if dark>=0.85 && ink<0.65 { return Candidate(state:.black,confidence:dark,delta:delta) }
196: if light>=0.85 && !grid.crossVisible && boundedWhite(frame:frame,calibration:calibration,col:col.rounded(),row:row.rounded()) {
200: if Double(similar)/count>=0.75 && ink>=0.65 {
203: return Candidate(state:.uncertain,confidence:0,delta:delta)
210: for sector in 0..<12 {
214: guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1),
219: guard radial.count>=5 else {continue}
225: if drop>max(0.025,min(0.065,median(Array(levels.prefix(3)))*0.18)) {supported+=1}
227: return tested>=3 && supported*2>tested
237: for sector in 0..<12 {
242: guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1),
247: let drops=(1..<4).map {levels[$0]-levels[$0+1]}
248: let peak=drops.indices.max {drops[$0]<drops[$1]}!
249: let threshold=max(0.035,min(0.06,median(Array(levels.prefix(2)))*0.065))
254: guard radii.count>=10,quadrants.allSatisfy({$0>=2}) else {continue}
256: guard radii.allSatisfy({abs($0-radius)<=0.12}) else {continue}
272: guard cross.horizontal>=0.75,cross.vertical>=0.75 else {return nil}
274: for r in max(0,row-1)..<min(calibration.size-1,row+1) {
275: for c in max(0,col-1)..<min(calibration.size-1,col+1) {
277: if let color=frame.patchColor(p),color.magnitude>=0.035 {wood.append(color)}
293: guard let level=frame.patchMean(p),level<median(levels)*0.65 else {return false}
306: for bodyCenter in centers {for radius in [0.12,0.18] {
310: if radius==0.18,neighborCovers(c,r) {maskedOuter=true;continue}
313: let minimumCount=radius==0.18 && maskedOuter ? 2:4
315: body.filter({$0>=minimumBody}).count>=min(3,body.count) else {return nil}
318: for radius in maskedOuter ? [0.12,0.18]:[0.18] {
321: if radius==0.18,neighborCovers(c,r) {continue}
324: color.magnitude>=0.035,wood.contains(where:{($0-color).magnitude<0.045 && color.magnitude >= $0.magnitude*0.65}) {matches+=1}
327: guard sampled>=4,Double(matches)/Double(sampled)>=0.75 else {return nil}
328: // Both axes independently passed >=75%; the usable inner/outer body
338: var crossVisible:Bool { horizontal>=0.5 && vertical>=0.5 }
347: guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1) else { continue }
356: let threshold=relativeContrast ? max(0.012,wood*0.07) : 0.045
363: func fraction(_ axis:Int)->Double { total[axis]>0 ? Double(visible[axis])/Double(total[axis]) : 0 }
365: return GridEvidence(horizontal:fraction(0),vertical:fraction(1),fraction:count>0 ? Double(visible.reduce(0,+))/Double(count) : 0)
```

## N/BoardHandDetector.swift

```text
18: for (name,point) in points where point.confidence>=0.25 {
24: return HandMotionPose(hands:hands,reliable:hands.allSatisfy{$0.count>=8})
```

## N/BoardVision.swift

```text
20: for i in 0..<4 {
22: guard (b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x) > 0.0005 else { return nil }
25: guard area > 0.04 else { return nil }
28: for i in 0..<4 {
33: for col in 0..<8 {
34: let pivot = (col..<8).max { abs(a[$0][col]) < abs(a[$1][col]) }!
35: guard abs(a[pivot][col]) > 1e-9 else { return nil }
39: for row in 0..<8 where row != col {
62: guard abs(determinant)>1e-12 else { return nil }
77: let neutral = wood.magnitude-magnitude>0.035 && magnitude<wood.magnitude*0.65
78: let cool = magnitude<0.075 && magnitude<wood.magnitude*0.90
79: && wood.red-red>0.035 && blue-wood.blue>0.035
104: guard preparedPatches==nil,pixels.count<=4_194_304 else {return self}
105: func sums(_ sample:(Int)->UInt8)->[UInt16] {
107: for y in 0..<height {
109: var sum=Int(sample(row))+(width>1 ? Int(sample(row+1)):0)
110: for x in 0..<width {
112: if x>0 {sum-=Int(sample(row+x-1))}
113: if x+2<width {sum+=Int(sample(row+x+2))}
117: for y in 0..<height {for x in 0..<width {
119: result[i]=horizontal[i]+(y>0 ? horizontal[i-width]:0)+(y+1<height ? horizontal[i+width]:0)
134: return pixels.count*MemoryLayout<UInt16>.stride*(preparedPatches.red==nil ? 1:4)
138: precondition(width > 0 && height > 0 && pixels.count == width*height)
173: let lut=(0..<256).map { UInt8(min(255,(Double($0)*gain).rounded())) }
179: for row in 0..<height {
182: for col in 0..<width {
225: guard count>=4 else {return nil}
227: guard total>Double(count)*255*0.12 else {return nil}
238: guard total>Double(count)*255*0.12 else {return nil}
247: guard total > Double(count)*255*0.12 else { return nil } // Dark-pixel chroma is unreliable.
290: size>0,readings.count==size*size,confirmedBoard.count==readings.count else {return []}
294: guard shape.quality>=0.94,shape.center.x.isFinite,shape.center.y.isFinite,
295: (0.36...0.52).contains(shape.radiusCol),(0.33...0.56).contains(shape.radiusRow),
296: (0..<size).contains(shape.row),(0..<size).contains(shape.col),
300: confirmedBoard[p].stone != nil && hypot(shape.center.x-Double(p%size),shape.center.y-Double(p/size))<=0.75
304: hypot(shape.center.x-Double(point%size),shape.center.y-Double(point/size))<=0.65,
305: max(abs(shape.center.x-Double(point%size)),abs(shape.center.y-Double(point/size)))>=0.30 else {continue}
309: centers.allSatisfy {hypot($0.x-centers[0].x,$0.y-centers[0].y)<0.18} ? point:nil
326: guard col>=0, row>=0, col<size, row<size, confirmedBoard.count==readings.count else {return false}
329: readings[index].confidence>=0.9 else {return false}
331: other.col==col && other.row==row && other.quality>=0.78 &&
334: (shape.center.y-other.center.y)/(shape.radiusRow+other.radiusRow))>=0.90
338: // 0.08-cell margin inside the target and outside every adjacent point.
341: guard shape.quality>=0.94,readings[index].confidence>=0.94,
342: (0.36...0.65).contains(shape.radiusCol),(0.36...0.65).contains(shape.radiusRow),
358: guard shape.quality>=0.95,readings[index].confidence>=0.95,
359: (0.36...0.65).contains(shape.radiusCol),(0.36...0.65).contains(shape.radiusRow),
366: hypot(shape.center.x-other.x,shape.center.y-other.y)-distance>=0.10 else {return false}
373: guard shape.quality>=0.86,readings.indices.contains(index),readings[index].occupancy.stone != nil else {return nil}
380: guard forAssignment, shape.quality >= 0.90, readings[index].confidence >= 0.90,
381: displacement <= 0.46, shape.contains(.init(x:Double(shape.col), y:Double(shape.row))) else {
384: let outwardX = (shape.col == 0 && dx < 0) || (shape.col == size - 1 && dx > 0)
385: let outwardY = (shape.row == 0 && dy < 0) || (shape.row == size - 1 && dy > 0)
386: let blockedX = abs(dx)>0.24 && abs(dy)<=0.24 && occupiedNeighbor(shape,col:shape.col+(dx>0 ? 1 : -1),row:shape.row)
387: let blockedY = abs(dy)>0.24 && abs(dx)<=0.24 && occupiedNeighbor(shape,col:shape.col,row:shape.row+(dy>0 ? 1 : -1))
391: var ambiguousPlacements:Set<Int> {Set(assignmentOffsets.filter{$0.value>=0.30}.map(\.key))}
426: guard quantile(values.map { ($0-median).magnitude },0.8) < 0.025 else { return nil }
434: guard colors.count >= 48 else { return nil }
436: guard center.magnitude < 0.025 else { return nil }
439: guard let color, (color-center).magnitude < 0.015 else { continue }
440: let quadrant = (index / side < side / 2 ? 0 : 2) + (index % side < side / 2 ? 0 : 1)
443: guard matches.min()! >= 4, matches.reduce(0,+)*5 >= colors.count*3 else { return nil }
456: if let base = reference.patchMean(referencePoint), ink == nil || base < ink!.1 { ink = (point,base) }
458: guard let (point,base) = ink, woodLevel-base > 0.08,
461: if current-correction-base > 0.08 && current-correction > woodLevel-0.05 { covered += 1 }
463: guard found >= 3 else { return nil } // No reliable printed-line evidence here.
464: return Double(covered)/Double(found) >= 0.6
480: for axis in 0..<2 { for along in [-0.24,-0.12,0.12,0.24] {
482: guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1) else {continue}
491: let probes=[-0.08,-0.06,-0.04,-0.02,0,0.02,0.04,0.06,0.08].compactMap { offset -> (Double,Double)? in
494: guard let best=probes.max(by:{$0.1<$1.1}),best.1>0.07 else {continue}
497: if live>0.07 && live>=best.1*0.55 && live<=best.1*1.8 {matched[axis] += 1}
498: if live<0.035 && live<best.1*0.35 {missing[axis] += 1}
502: // ink loss (not coverage). Only the >=0.94 white-disk recovery below
504: let enough=found.allSatisfy{$0>=2}
505: return (enough && (0..<2).allSatisfy{Double(matched[$0])/Double(found[$0])>=0.75},
506: enough && (0..<2).allSatisfy{Double(missing[$0])/Double(found[$0])>=0.75},
507: (0..<2).allSatisfy{found[$0]>=3 && missing[$0]>=2 && matched[$0]==0},
508: matched.allSatisfy{$0==0} && missing.reduce(0,+)>=2)
517: for dy in -4...4 { for dx in -4...4 where dx != 0 && dy != 0 && dx*dx+dy*dy <= 16 {
526: let wood=samples.filter{$0.reference>=woodLevel-0.08}
527: guard wood.count>=16,let colorShift else { return nil }
530: guard abs(lighting)<0.16 else { return nil }
533: return abs(delta-lighting)<0.035 && (current-base-colorShift).magnitude<0.025
551: let coloredShadow = level<=sample.reference-0.03 && expected.magnitude>=0.04
552: && current.magnitude>=expected.magnitude*0.90 && current.magnitude<=expected.magnitude*1.80
553: && dot>=current.magnitude*expected.magnitude*0.95
554: return level>=sample.reference*0.55 && level<=sample.reference+0.07
555: && ((current-expected).magnitude<0.030 || coloredShadow)
558: guard woodAgreement>=0.75 || (!shadowNeighbors.isEmpty && shadowAgreement>=0.90) else {return nil}
560: for axis in 0..<2 { for along in [-0.24,-0.12,0.12,0.24] {
562: guard c>=0,r>=0,c<=Double(calibration.size-1),r<=Double(calibration.size-1) else { continue }
573: let relativeProbes=(shadowNeighbors.isEmpty ? [] : [-0.08,-0.06,-0.04,-0.02,0,0.02,0.04,0.06,0.08]).compactMap { offset -> (Double,Double)? in
576: if let best=relativeProbes.max(by:{$0.1<$1.1}),best.1>0.07 {
579: if live>0.07 && live>=best.1*0.55 && live<=best.1*1.8 {shadowMatched[axis] += 1}
581: let probes=[-0.08,-0.04,0,0.04,0.08].compactMap { offset -> (Double,Double)? in
584: guard let best=probes.max(by:{$0.1<$1.1}),best.1>0.035 else { continue }
587: if live>0.035 && live>=best.1*0.55 && live<=best.1*1.8 { matched[axis] += 1 }
589: if found.allSatisfy({$0>=2}),woodAgreement>=0.75 {
590: let railAgreement=(0..<2).map{Double(matched[$0])/Double(found[$0])}
591: if railAgreement.allSatisfy({$0>=0.75}) {
595: guard !shadowNeighbors.isEmpty,shadowAgreement>=0.90,shadowFound.allSatisfy({$0>=3}) else {return nil}
596: let shadowRails=(0..<2).map{Double(shadowMatched[$0])/Double(shadowFound[$0])}
597: guard shadowRails.allSatisfy({$0>=0.75}) else {return nil}
605: let threshold = max(0.04, min(0.5, threshold))
613: for row in 0..<gapSide { for col in 0..<gapSide {
620: if current>0.06, base>0.06, current<0.95, base<0.95 { woodGains.append(base/current) }
628: let uniformExposure = gapDeltas.count >= 20 && exposureSpread < 0.04
634: let region = (i/gapSide < gapSide/2 ? 0 : 2) + (i%gapSide < gapSide/2 ? 0 : 1)
636: if exposureDelta < 0 ? delta < -0.12 : delta > 0.12 { shifted[region] += 1 }
638: let widespreadShift = abs(exposureDelta) > 0.14 && totals.indices.allSatisfy {
639: totals[$0] >= 4 && shifted[$0]*4 >= totals[$0]*3
641: let regionalShift=gapDeltas.filter {abs($0)>0.10}.count*2>gapDeltas.count
642: if widespreadShift || (uniformExposure && abs(exposureDelta) > 0.08) || regionalShift {
648: current.lightingBlocked = empty*4 < current.readings.count || uncertain*4 > current.readings.count
664: if contradictions<=max(1,calibration.size/6),matched.readings.filter({$0.occupancy == .uncertain}).count<=uncertain {
673: if adaptLighting && !current.lightingBlocked && woodGains.count >= gapSide*gapSide/2 {
675: if (0.45...2.8).contains(gain), quantile(woodGains.map { abs($0/gain-1) },0.8)<0.12,
682: if contradictions <= max(1,calibration.size/6),
683: matched.readings.filter({$0.occupancy == .uncertain}).count <= uncertain {
700: for row in 0..<calibration.size { for col in 0..<calibration.size {
702: for r in max(0,row-2)..<min(gapSide,row+2) { for c in max(0,col-2)..<min(gapSide,col+2) {
717: for row in 0..<calibration.size { for col in 0..<calibration.size {
722: for r in max(0,row-2)..<min(gapSide,row+2) { for c in max(0,col-2)..<min(gapSide,col+2) {
728: let localReliable = nearby.count >= 4 && localSpread < 0.04
734: let verifiedReliable=verifiedLighting.count>=4 && quantile(verifiedLighting.map{abs($0-verifiedMedian)},0.8)<0.04
735: let excessiveChange = localReliable && abs(localChange)>0.08 && !verifiedReliable
744: if excessiveChange,candidate.occupancy == .black,candidate.confidence>=0.95,candidate.delta < -0.30 {
748: independentlyDark=live.occupancy == .black && live.confidence>=0.95 && cross.horizontal<0.25 && cross.vertical<0.25
750: if excessiveChange && !independentlyDark { candidate.occupancy = .uncertain; candidate.confidence = 0; geometryBlocked.insert(row*calibration.size+col) }
761: let score = shifted.confidence-0.15*hypot(dc,dr)
783: if candidate.occupancy.stone != nil,candidate.confidence>=0.9 {
789: candidate.occupancy = .uncertain; candidate.confidence = 0
808: guard hypot(centers[i].x-centers[j].x,centers[i].y-centers[j].y)<0.6 else { continue }
811: if a.confidence > b.confidence+0.1 && offsetA+0.12 < offsetB { disputed.insert(j) }
812: else if b.confidence > a.confidence+0.1 && offsetB+0.12 < offsetA { disputed.insert(i) }
819: readings[index] = .init(row:reading.row,col:reading.col,occupancy:.uncertain,confidence:0,delta:reading.delta)
836: let trustedShape=shape.quality>=0.85 || (shape.quality>=0.80 && stone.confidence>=0.90)
837: return trustedShape && abs(shape.row-reading.row)<=1 && abs(shape.col-reading.col)<=1
846: return shape.quality>=0.78 && stone.occupancy == .black && stone.confidence>=0.95
847: && abs(shape.row-reading.row)<=1 && abs(shape.col-reading.col)<=1
859: for r in max(0,reading.row-2)..<min(gapSide,reading.row+2) {
860: for c in max(0,reading.col-2)..<min(gapSide,reading.col+2) {
895: cross.covered || (color == .white && shape.quality>=0.90) ? (color,shape):nil
898: occupancy:accepted?.0 ?? .uncertain,confidence:accepted?.1.quality ?? 0,delta:reading.delta)
914: // still needs >=0.94 quality, white body color and separate ownership.
918: occupancy:.uncertain,confidence:0,delta:reading.delta),frame:frame,reference:reference,
941: guard liveCross.horizontal<=0.25,liveCross.vertical<=0.25 else {continue}
946: guard live.occupancy == .white,live.confidence>=0.95,
949: hypot((shape.center.x-$0.center.x)/(shape.radiusCol+$0.radiusCol),
950: (shape.center.y-$0.center.y)/(shape.radiusRow+$0.radiusRow))<0.90
956: let outlined=Set((geometry.footprints+geometry.placementFits+recoveredShapes).filter{$0.quality>=0.80}.map{$0.row*calibration.size+$0.col})
961: resolved[index] = .init(row:reading.row,col:reading.col,occupancy:.uncertain,confidence:0,delta:reading.delta)
983: let validShape:(StoneFootprint)->Bool = {liveWood[$0.row*calibration.size+$0.col] == nil}
996: for dy in -4...4 {for dx in -4...4 where dx != 0 && dy != 0 && dx*dx+dy*dy<=16 {
1003: if current.magnitude>=0.045,expected.magnitude>=0.035,
1004: current.magnitude>=expected.magnitude*0.65,
1005: dot>=current.magnitude*expected.magnitude*0.94 {wood+=1}
1007: return sampled>=20 && Double(wood)/Double(sampled)>=0.75
1020: for dy in -4...4 { for dx in -4...4 where dx != 0 && dy != 0 && dx*dx+dy*dy <= 16 {
1028: let wood = samples.filter { $0.reference >= woodLevel-0.08 }
1031: guard samples.count >= 20, wood.count >= 16 else {
1032: return Candidate(occupancy:.uncertain,confidence:0,delta:delta,stoneHint:nil)
1035: let whiteThreshold = max(0.045,min(threshold,(1-referenceLevel)*0.20))
1036: let dark = Double(deltas.filter { $0 < -threshold }.count)/Double(deltas.count)
1050: whiteColor = change > -0.06 && current.supportsWhiteStone(comparedTo:expectedWood)
1058: whiteColor = gridCoverage == true || (change > 0.015 && gridCoverage != false)
1061: if change > whiteThreshold || whiteColor { lightVotes += 1 }
1064: let unchanged = Double(deltas.filter { abs($0) < min(threshold*0.55,whiteThreshold*0.8) }.count)/Double(deltas.count)
1071: let whiteHint = light >= 0.35 || Double(colorHintVotes)/Double(deltas.count) >= 0.25
1075: let hint: Occupancy? = dark >= 0.35 && light < 0.15 ? .black : (whiteHint && (dark < 0.15 || light > dark) ? .white : nil)
1076: if dark >= 0.8 { return Candidate(occupancy:.black,confidence:dark,delta:delta,stoneHint:hint) }
1077: if light >= 0.8 { return Candidate(occupancy:.white,confidence:light,delta:delta,stoneHint:hint) }
1078: if unchanged >= 0.8 { return Candidate(occupancy:.empty,confidence:unchanged,delta:delta,stoneHint:hint) }
1092: return matchingFrames >= 5
```

## N/EstablishedStoneTracker.swift

```text
41: guard observation.readings.indices.contains(p),shape.quality>=0.90,
45: (0.30...0.65).contains(shape.radiusCol),(0.30...0.65).contains(shape.radiusRow),
46: observation.readings[p].confidence>=0.90,
50: if let i=result.firstIndex(where:{$0.color==reading.occupancy && distance($0.shape.center,shape.center)<0.18 &&
51: abs($0.shape.radiusCol-shape.radiusCol)<0.12 && abs($0.shape.radiusRow-shape.radiusRow)<0.12}) {
70: guard distance(logical,disk.shape.center)<=0.65 else {continue}
71: if let track=tracks[p],now-track.lastSeen<=2 {
72: guard distance(track.shape.center,disk.shape.center)<=0.40 else {continue}
90: raw.readings.count==expected.count,raw.size>0,
96: if now-lastFrame>1 {tracks=[:];proposals=[:];shiftStarted=nil;lastScan = -Double.infinity}
105: if let track=tracks[p],now-track.lastSeen<=2 {
111: if displacements.count>=4 {
114: coherentShift=hypot(dx,dy)>0.18 &&
115: Double(displacements.filter{hypot($0.x-dx,$0.y-dy)<0.09}.count)/Double(displacements.count)>=0.7
119: report.possibleBoardShift=now-shiftStarted!>=0.5
133: if var proposal=proposals[p],now-proposal.last<=1.1,distance(proposal.shape.center,shape.center)<=0.12 {
136: if let proposal=proposals[p],proposal.count>=3,now-proposal.first>=1 {
148: guard let track=tracks[p],now-track.lastSeen<=2,
151: distance(track.shape.center,visible[d].shape.center)<=0.40,
163: readings[alias] = .init(row:alias/raw.size,col:alias%raw.size,occupancy:.uncertain,confidence:0,delta:raw.readings[alias].delta)
```

## N/HandBoardBoundary.swift

```text
16: for i in 0..<4 {
18: guard hypot(b.x-a.x,b.y-a.y)>1,
19: (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x)>0 else {return nil}
22: guard vertices[0].x<center,vertices[0].y<center,
23: vertices[1].x>center,vertices[1].y<center,
24: vertices[2].x>center,vertices[2].y>center,
25: vertices[3].x<center,vertices[3].y>center else {return nil}
27: edges=(0..<4).map {i in
36: guard (0..<4).contains(edge),x.isFinite,y.isFinite else {return -.infinity}
46: func contains(x:Double,y:Double)->Bool {minimumDepth(x:x,y:y)>=0}
47: func closestEdge(x:Double,y:Double)->Int {(0..<4).min{depth(x:x,y:y,edge:$0)<depth(x:x,y:y,edge:$1)}!}
```

## N/HandMotionTiming.swift

```text
18: time.isFinite && (estimatedError.map{$0.isFinite && $0>=0} ?? true) &&
19: (observedLower.map{$0.isFinite && $0<=time} ?? true) &&
20: (observedUpper.map{$0.isFinite && $0>=time} ?? true) && earliestPlausibleTime.isFinite && latestPlausibleTime.isFinite
42: guard $0.confidence>=0.25 else {return false}
65: guard time.isFinite,lastTime.map({time>$0}) ?? true else {return nil}
66: if let lastTime,time-lastTime>0.65 {reset()}
72: let points=pose.hands[0].filter{$0.confidence>=0.5 && $0.x.isFinite && $0.y.isFinite}
73: guard points.count>=8 else {views=[];fallback="Too few reliable joints";return nil}
81: guard views.count>=2,time-lower<=0.6,views.allSatisfy({$0.source==source}),let last=views.last else {return estimate}
83: guard common.count>=8,common.count>=last.points.count-2 else {estimate.fallbackReason="Joint identities changed";return estimate}
85: guard span>=0.025,span<=1.0 else {return estimate}
99: guard max(x.2,y.2)<0.35 else {estimate.fallbackReason="Nonlinear or noisy hand motion";return estimate}
103: for (axis,fitResult) in [x,y].enumerated() where abs(fitResult.1)>0.5 {
105: let dt=((velocity>0 ? high:low)-position)/velocity
106: if dt>=0 {
120: guard let crossing=crossings.min(by:{$0.0<$1.0}) else {estimate.fallbackReason="Hand is not withdrawing consistently";return estimate}
123: guard let crossing=exits.max(by:{$0.time<$1.time}),crossing.time>=lower,crossing.time<=time,
124: crossing.time-last.time<=0.4 else {estimate.fallbackReason="Predicted crossing is outside the observed interval";return estimate}
126: guard error<(time-lower)/2 else {estimate.fallbackReason="Motion fit does not improve the observed bracket";return estimate}
```

## N/HandOutlineSampling.swift

```text
5: let n=Int((Double(calibration.size-1)+2*HandOutlineFrame.margin)*HandOutlineFrame.scale)+1
17: let visible=boundary.size==calibration.size && denominators.allSatisfy{$0.isFinite && $0>1e-8} &&
21: let edges=polygon.map {points in (0..<4).map {i -> (Double,Double,Double) in
33: for i in 0..<4 {
35: if (b.0-a.0)*(Double(y)-a.1)-(b.1-a.1)*(Double(x)-a.0)<0 {return false}
39: for row in 0..<n {for col in 0..<n {
55: let wholePatch=(interior && depth>1.414213563) || (!interior && depth < -1.414213563)
73: let centered=hypot(shape.center.x-Double(shape.col),shape.center.y-Double(shape.row))<=0.2
74: let edgeFit=outer && centered && shape.quality>=0.90 && observation?.readings.contains(where:{
75: $0.row==shape.row && $0.col==shape.col && $0.occupancy == .white && $0.confidence>=0.99
77: return (shape.quality>=0.95 || edgeFit) && observation?.readings.contains(where:{
78: $0.row==shape.row && $0.col==shape.col && $0.occupancy == .white && $0.confidence>=0.95
80: }.map {HandOutlineFrame.WhiteStone(x:$0.center.x,y:$0.center.y,radiusX:$0.radiusCol,radiusY:$0.radiusRow)}
```

## N/HandOutlineTracker.swift

```text
9: pow((x-self.x)/radiusX,2)+pow((y-self.y)/radiusY,2)<=1
15: var valid:Bool {light>=0}
22: static let scale=10.0,margin=2.0
28: guard col>=0,row>=0,col<width,row<width else {return nil};return row*width+col
32: guard (0.32...0.60).contains(stone.radiusX),(0.32...0.65).contains(stone.radiusY) else {return false}
39: return p.valid && p.light>=0.65 && sqrt(red*red+green*green+(red+green)*(red+green))<=0.12
140: guard time.isFinite,previousTime.map({time>$0}) ?? true else {return result}
148: if elapsed>=5,clearPoseSamples>=10 {
161: if let lastTime,time-lastTime>0.65 || self.source != source {reset()}
167: guard !relevant.isEmpty,relevant.filter({frame.pixels[$0].valid}).count>relevant.count*3/5 else {
177: if hand==false {initialization+=1;if initialization>=3 {baseline=frame}}
183: let confident=points.filter{$0.confidence>=0.25 && $0.x.isFinite && $0.y.isFinite}
194: let confident=points.filter{$0.confidence>=0.25}
211: let entries=(0..<4).filter {side in component.indices.contains {i in
212: let p=frame.grid(i);return boundary.depth(x:p.0,y:p.1,edge:side)<0
215: active=true;edge=entries.min{boundary.depth(x:component.x,y:component.y,edge:$0)<boundary.depth(x:component.x,y:component.y,edge:$1)}!
226: if let safe=references.last(where:{time-$0.time>=0.5}) {baseline=safe.frame}
227: references.removeAll{time-$0.time>0.8}
228: if references.count>90 {references.removeFirst(references.count-90)}
233: let points=boardHands.flatMap{$0}.filter{$0.confidence>=0.5}
238: [wrist.y,n-wrist.x,n-wrist.y,wrist.x].enumerated().min{$0.element<$1.element}!.offset
242: guard boardHands.count<=1 else {
245: let points=boardHands.first?.filter{$0.confidence>=0.5} ?? []
246: if points.count>=8,points.contains(where:{depth(x:$0.x,y:$0.y,frame:frame)>1}) {
248: for p in points where p.x>=0 && p.y>=0 && p.x<Double(frame.cells) && p.y<Double(frame.cells) {
250: frame.pixels[i].light>0.12,background.pixels[i].light>0.12 else {continue}
255: if changes.count>=5 {
256: func median(_ values:[Double])->Double {values.sorted()[values.count/2]}
258: if norm>=0.02 {
270: guard c.minimum<0 else {return false}
278: if depth>=1/HandOutlineFrame.scale-(frame.boundary == nil ? 0:1e-9) {return true}
279: if depth>0 {inside+=1;if inside>=9 {return true}}
287: guard lateral<3.5 && (c.minimum<0 || points.contains{p in hypot(p.x-c.x,p.y-c.y)<2}) else {return false}
290: if hand==false,c.maximum>0,!c.indices.contains(where:{crossingCore.contains($0)}) {return false}
295: if hand==false,c.maximum>0,c.maximum<=0.1,
303: let component=candidates.min{hypot($0.x-center.x,$0.y-center.y)<hypot($1.x-center.x,$1.y-center.y)}
307: if hand==false,component == nil || component!.maximum<=0 {
318: return p.0>0.65 && p.1>0.65 && p.0<last-0.65 && p.1<last-0.65
320: guard interior>=9 else {continue}
321: let entries=(0..<4).filter {side in
324: return (frame.boundary?.depth(x:p.0,y:p.1,edge:side) ?? [p.1+0.75,high-p.0,high-p.1,p.0+0.75][side])<0
341: if depth>0 || hand==true {
353: guard clearTimes.count>=2,let firstClear=clearTimes.first else {
368: guard let side=(0..<4).first(where:{edge in points.allSatisfy{boundary.depth(x:$0.0,y:$0.1,edge:edge)<0}}) else {return false}
374: guard boundary.contains(x:x,y:y),boundary.depth(x:x,y:y,edge:side)<=1.5,
377: guard p.valid,b.valid,abs(p.light-b.light)<=0.06 else {return false}
379: guard r*r+g*g+(r+g)*(r+g)<=0.035*0.035 else {return false}
382: return count>=50
389: let side=maxY<0 ? 0:minX>high ? 1:minY>high ? 2:maxX<0 ? 3:nil
396: guard x>=(-0.65),y>=(-0.65),x<=high+0.65,y<=high+0.65 else {continue}
399: case 0:near=y<=0.75 && x>=minX-1 && x<=maxX+1
400: case 1:near=x>=high-0.75 && y>=minY-1 && y<=maxY+1
401: case 2:near=y>=high-0.75 && x>=minX-1 && x<=maxX+1
402: default:near=x<=0.75 && y>=minY-1 && y<=maxY+1
406: guard p.valid,b.valid,abs(p.light-b.light)<=0.06 else {return false}
408: guard r*r+g*g+(r+g)*(r+g)<=0.035*0.035 else {return false}
411: return count>=50
422: guard component.indices.count>=100 else {return false}
433: if vx/n>0.0016,vy/n>0.0016,cov/sqrt(vx*vy)>0.98 {
439: guard component.maximum<=0.5 else {return false}
446: guard col>=0,col<width,row>=0,row<width else {continue}
452: if count>=15 {pairs.append((x/Double(count),y/Double(count)))}
454: guard pairs.count>=100 else {return false}
458: guard xx/count>0.0001,yy/count>0.0001,xy/sqrt(xx*yy)>0.985 else {return false}
473: return tiles.values.allSatisfy{$0.count<12 || $0.squared/Double($0.count)<=tileLimit}
484: guard indices.count>=12 else {return false}
490: guard vx/n>0.0001,vy>0,covariance/sqrt(vx*vy)>0.99 else {return false}
496: return original.valid && current.valid && abs(y[i]-slope*x[i]-offset)<=0.025 &&
497: r*r+g*g+(r+g)*(r+g)<=0.025*0.025
506: guard entryEdge != nil || component.minimum<0 && component.maximum>0.5 else {return false}
517: if inside,(-0.4...0.5).contains(d),side>=lo-0.3,side<=hi+0.3 {
530: let neutral=sqrt(p.red*p.red+p.green*p.green+(p.red+p.green)*(p.red+p.green))<=0.12
531: if p.light>=0.65,neutral,whiteStones.contains(where:{$0.contains(x:point.0,y:point.1)}) {return false}
534: if p.light<=0.08 || b.light<=0.08 {return abs(p.light-b.light)>0.10}
539: guard sqrt(a*a+b*b+(a+b)*(a+b))<0.065 else {return false}
541: return r*d.0+g*d.1+(-r-g)*d.2>0.018
544: return abs(p.light-b.light)>0.10 || sqrt(r*r+g*g+(r+g)*(r+g))>0.035
550: for y in 1..<n-1 {for x in 1..<n-1 {
555: for y in 1..<n-1 {for x in 1..<n-1 {
573: if core[i],boardDepth>0 {coreInside=true}
577: if xx>=0,xx<n,yy>=0,yy<n {
585: if indices.count>=10,indices.filter({core[$0]}).count>=9 {result.append(.init(indices:indices,x:sx/Double(indices.count),y:sy/Double(indices.count),minimum:lo,maximum:hi,coreInside:coreInside))}
```

## N/LightingCompensation.swift

```text
17: let usable=samples.filter {$0.current>0.08 && $0.current<0.94 && $0.reference>0.08 && $0.reference<0.94}
18: guard usable.count>=max(24,samples.count*3/4) else {return nil}
23: for r in 0..<3 {for c in 0..<3 {matrix[r][c] += a[r]*a[c]};matrix[r][3] += a[r]*gain}
25: for c in 0..<3 {
26: let pivot=(c..<3).max {abs(matrix[$0][c])<abs(matrix[$1][c])}!
27: guard abs(matrix[pivot][c])>1e-8 else {return nil}
31: for r in 0..<3 where r != c {
39: for _ in 0..<3 {
42: let inliers=zip(usable,residuals).filter {$0.1<=cutoff}.map {$0.0}
43: guard inliers.count>=usable.count*3/4,let refined=solve(inliers) else {return nil}
47: guard residual<0.035,calibration.corners.allSatisfy({(0.45...2.8).contains(field.gain(at:$0))}) else {return nil}
52: let q=(p.x<Double(calibration.size-1)/2 ? 0:1)+(p.y<Double(calibration.size-1)/2 ? 0:2)
54: if abs(field.gain(at:s.point)*s.current-s.reference)<0.04 {good[q] += 1}
56: guard total.indices.allSatisfy({total[$0]>=4 && good[$0]*4>=total[$0]*3}) else {return nil}
63: for r in 0..<(calibration.size-1) {for c in 0..<(calibration.size-1) {
66: guard values.count>=24 else {return false}
67: return values.filter {$0<0.08}.count*5>values.count*4 || values.filter {$0>0.97}.count*5>values.count*4
84: guard fresh,lastFrame.map({now>$0}) ?? true else {return nil}
85: if let lastFrame,now-lastFrame>1 {clearSince=nil;clearFrames=0}
93: if clearFrames>=3,now-clearSince!>=0.6 {active=false;needsHelp=false;began=nil;spoken=false}
95: if active,let began,now-began>=8 {needsHelp=true}
96: guard active,needsHelp,speech,!spoken,lastSpoken.map({now-$0>=30}) ?? true else {return nil}
```

## N/OccupiedReference.swift

```text
21: let usable=(0..<12).filter{!excluding.contains($0)}
22: guard usable.count>=4 else {return 0}
25: return abs(a[i*3]-b[i*3])<=0.045 && sqrt(r*r+g*g+(r+g)*(r+g))<=0.025
28: func unchangedOutside(_ other:Self)->Bool {outsideAgreement(other)>=10.0/12}
32: let color=(0..<16).map {i -> Double in
36: return light[14]<=0.045 && color[14]<=0.025 && abs(center-other.center)<=0.05
50: guard let (l,r,g)=sample(Double(p%cal.size)+x,Double(p/cal.size)+y),l>0.08,l<0.94 else {return nil}
55: for sector in 0..<12 {
113: guard size>0 else {return result}
114: for p in points where (0..<size*size).contains(p) {
125: points.formUnion(observation.assignmentOffsets(confirmedBoard:expected).filter{$0.value>=0.30}.map(\.key))
127: for shape in observation.footprints+observation.placementFits where shape.quality>=0.86 &&
128: max(abs(shape.center.x-Double(shape.col)),abs(shape.center.y-Double(shape.row)))>=0.30 {
159: valid:Bool,allowRefresh:Bool,stoneThreshold:Double=0.13)->BoardObservation {
164: raw.readings.enumerated().allSatisfy({$0.element.row==$0.offset/cal.size && $0.element.col==$0.offset%cal.size && $0.element.confidence.isFinite}),
172: return hypot(x.x-y.x,x.y-y.y)<=0.10
176: if now-lastFrame>0.6 {suspend()}
181: for p in position.indices where changed.contains(where:{abs($0/cal.size-p/cal.size)<=1 && abs($0%cal.size-p%cal.size)<=1}) {
196: (raw.readings[$0].occupancy.stone != nil && raw.readings[$0].confidence>=0.8)})
207: var independentMatch=r.occupancy==expected[p] && r.confidence>=0.9
211: if r.occupancy == .white,r.confidence>=0.9 {
214: if expected[p] == .white,whiteAnchors?[p]==nil,let c=observedWhite[p],c.count>=3,now-c.first>=0.4 {
217: } else if let c=observedWhite[p],c.patch.matches(patch),now-(c.lastStrong ?? c.first)<=0.6,
219: let contradiction=r.occupancy != .uncertain && r.occupancy != expected[p] && r.confidence>=0.8
236: if held.matches>=3,now-held.first!>=0.4 {
246: threshold:stoneThreshold,occupied:occupied),confidence>=0.75,
248: return grid.horizontal>=0.75 && grid.vertical>=0.75}() {
254: if let c=observedEmpty[p],c.count>=3,now-c.first>=0.4 {
255: if result.readings[p].occupancy == .uncertain || result.readings[p].confidence<0.8 {
256: result.readings[p] = .init(row:r.row,col:r.col,occupancy:.empty,confidence:0.9,delta:r.delta)
259: if c.count>=8,now-c.first>=1.4 {independentMatch=true;challenged.remove(p)}
265: if entry.matches>=3,now-entry.first!>=0.4,
266: result.readings[p].occupancy == .uncertain || result.readings[p].confidence<0.8 {
267: result.readings[p] = .init(row:r.row,col:r.col,occupancy:expected[p],confidence:0.9,delta:r.delta)
285: if r.occupancy == .uncertain || (r.occupancy == .white && r.confidence<0.8),
289: let fits=examples.filter{abs(patch.body.light-$0.body.light)<=0.12}
302: (raw.readings[$0].confidence>=0.8 && [.black,.white].contains(raw.readings[$0].occupancy)))
304: let excludedSectors=Set((0..<12).filter {sector in
307: return neighbors.contains{hypot(x-Double($0%cal.size),y-Double($0/cal.size))<0.60}
310: if fits.count>=2,fits[1]<=0.02,locality>=(knownWhite ? 0.5:0.75),
320: let inkChange = !knownWhite && coveredGrid && shape.quality>=0.98 &&
321: fits[1]<=0.005 && grid>=0.95 && locality>=0.9
325: if referenceSupport>=0.5,score>=0.92 {
336: if let c=whiteWitness[p],c.patch.matches(patch),now-(c.lastStrong ?? c.first)<=0.6 {} else {whiteWitness[p]=nil}
338: if let c=whiteWitness[p],c.count>=3,now-c.first>=0.4,let shape=c.shape,
339: r.occupancy == .uncertain || (r.occupancy == .white && r.confidence<0.8) {
340: result.readings[p] = .init(row:r.row,col:r.col,occupancy:.white,confidence:0.95,delta:r.delta)
344: if whiteObserved,expected[p] == .white,c.count>=8,now-c.first>=1.4 {independentMatch=true;challenged.remove(p)}
357: result.readings[$0].occupancy == .uncertain || result.readings[$0].confidence<0.8
362: result.readings[p].occupancy != expected[p] || result.readings[p].confidence<0.9 {pending[p]=nil}
367: report.stable=stableFrames>=8 && now-stableSince!>=2
369: if report.stable,now-lastRefresh!>=10 {
370: for (p,c) in pending where c.count>=8 && now-c.first>=1.4 {
```

## N/PhysicalAI.swift

```text
147: lastCapturePoints.count>=2 &&
156: func canPass(at now: Double)->Bool {phase == .human && lastMatch.map {(0..<1.5).contains(now-$0)} == true}
161: wallTime: @escaping ()->Double = {Date().timeIntervalSince1970}) {
182: if let p=move.point, !(0..<saved.settings.size*saved.settings.size).contains(p) {throw Failure(message:"Invalid saved AI move.")}
237: saved.acceptedAtUnix.isFinite,saved.acceptedAtUnix>0 {
362: if s.moves.count>=2,s.moves.suffix(2).allSatisfy({$0.point == nil}) {s.ended=true}
363: if s.pendingCaptureCleanup == true,lastCapturePoints.count<2 {s.pendingCaptureCleanup=false}
439: var candidates=observation.centeringEvidence.filter{$0.shape.quality>=0.94}
443: observation.readings[p].occupancy.stone != nil,observation.readings[p].confidence>=0.9,
444: shape.quality>=0.9 else {return nil}
450: (0.36...0.65).contains(shape.radiusCol) && (0.33...0.65).contains(shape.radiusRow) &&
451: max(abs(c.x-c.x.rounded()),abs(c.y-c.y.rounded()))>=0.30
455: if (da<0.25) != (db<0.25) {return da<0.25}
457: if abs(a.shape.center.y-b.shape.center.y)>0.18 {return a.shape.center.y<b.shape.center.y}
458: if abs(a.shape.center.x-b.shape.center.x)>0.18 {return a.shape.center.x<b.shape.center.x}
463: if let old=centeringWitness,hypot(old.center.x-center.x,old.center.y-center.y)<0.12,
464: stamp>old.last,stamp-old.last<=0.6 {
467: guard let witness=centeringWitness,witness.count>=3,stamp-witness.first>=0.45 else {return}
468: if centeringStone.map({hypot($0.x-center.x,$0.y-center.y)>0.18}) ?? true {
495: observation.readings.allSatisfy({$0.occupancy != .uncertain && $0.confidence>=0.8}) else {
501: var raw=Array<String?>(repeating:nil,count:cells.count),confidence=Array(repeating:0.0,count:cells.count)
543: if laser.target?.purpose==nil,let point=pendingPoint, now>=stamp,now-stamp<1.5,
545: observation.readings.contains(where:{(0..<size).contains($0.row) && (0..<size).contains($0.col) && $0.row*size+$0.col==point && ($0.occupancy == .black || $0.occupancy == .white) && $0.confidence>=0.8}) {
548: if let target=laser.target,target.purpose=="capture",now>=stamp,now-stamp<1.5,
551: ($0.occupancy == .empty || ($0.occupancy.stone != nil && $0.occupancy.rawValue != (target.black ? "black":"white"))) && $0.confidence>=0.8}) {
558: guard stamp.isFinite,now-stamp>=0,now-stamp<1.5,
565: if let lastFrame,stamp-lastFrame>0.6 {detail["frameGapSeconds"]=stamp-lastFrame;interruptObservation(reason:"frame_gap")}
567: var values=Array(repeating:"",count:size*size),seen=Set<Int>(),unknown=0
570: var ambiguous=Set(assignmentOffsets.filter {$0.value>=0.30}.map(\.key))
572: guard (0..<size).contains(r.row),(0..<size).contains(r.col),r.confidence.isFinite,
582: for r in observation.readings where r.occupancy.stone != nil && r.confidence>=0.8 {
590: if reading.occupancy == .uncertain || reading.confidence<0.8 {neighbors.append(other)}
600: $0.occupancy.rawValue != cells[$0.row*size+$0.col] || $0.confidence<0.8 || $0.row*size+$0.col==pendingPoint
601: }.prefix(40).map { ["point":$0.row*size+$0.col,"occupancy":$0.occupancy.rawValue,"confidence":$0.confidence] as [String:Any] }
629: if ambiguous.contains(index),r.occupancy.stone != nil,r.confidence>=0.8,
655: if r.occupancy == .uncertain || r.confidence<0.8 || ambiguous.contains(index) {
659: guard let verifiedCells,verifiedCells[index]==cells[index],unknown<=max(12,size*size/5) else {
663: guard reading.occupancy == .uncertain || reading.confidence<0.8 || ambiguous.contains(p) else {return nil}
664: return self.verifiedCells?[p] != cells[p] || unknown>max(12,size*size/5) ? p:nil
675: guard witnesses>=3,stamp-witnessStart>=0.45 else {outcome="waiting_for_stable_position";return}
697: // same 0.8 threshold as standalone placement confirmation above; an
701: $0.row*size+$0.col==point && $0.occupancy.rawValue==cells[point] && $0.confidence>=0.8
728: if let point,!(0..<size*size).contains(point) {fail("AI returned an off-board move.");return}
738: s.pendingCaptureCleanup=capturedCount>=2
739: s.captureIndication=capturedCount>0 ? .init(moveNumber:s.moves.count,acceptedAtUnix:receivedAt ?? wallTime()):nil
740: if s.ended || capturedCount>=2 {timing.pause(at:now)}
783: if !ambiguous.contains(p),reading.confidence>=0.8,reading.occupancy != .uncertain {
825: guard let first=chars.first,let col=letters.firstIndex(of:first),col<size,let row=Int(String(chars.dropFirst())),(1...size).contains(row) else {return nil}
837: guard policy.count==n*n+1,policy.allSatisfy({$0.isFinite && (-1...1).contains($0)}),(0..<1).contains(unit) else {return nil}
838: let options=policy.indices.filter {i in policy[i]>0 && player.moveRejection(color:player.turn,x:i==n*n ? -1:i%n,y:i==n*n ? -1:i/n)==nil}
839: let total=options.reduce(0.0) {$0+policy[$1]};guard total>0 else {return nil}
843: if threshold<0 {return i==n*n ? "pass":"\(Array("ABCDEFGHJKLMNOPQRST")[i%n])\(n-i/n)"}
920: guard let sampled=Self.sampledHumanMove(policy,player:p,unit:Double.random(in:0..<1)) else {throw Failure(message:"KataGo returned no legal human-style move.")}
```

## N/StoneAspectEstimator.swift

```text
23: readings.filter{$0.occupancy.stone != nil && $0.confidence>=0.75}
27: guard measurements.count>=3 else { return nil }
31: guard abs(middle)>0.035, abs(abs(middle)-expected)<0.045,
32: median(ratios.map{abs($0-middle)})<0.035 else { return nil }
33: let supporting=measurements.filter{log($0.ratio)*middle>0 && abs(log($0.ratio)-middle)<0.065}
34: guard supporting.count>=3,Double(supporting.count)/Double(measurements.count)>=0.75,
35: Set(supporting.map(\.row)).count>=2,Set(supporting.map(\.col)).count>=2 else { return nil }
39: if group.count>=2 && median(group)*middle<0 { return nil }
41: return Estimate(longAxisRows:middle>0,measurements:measurements,medianRatio:exp(middle))
45: guard row>=1,col>=1,row<n,col<n else { return nil }
48: guard col+dx>=0,col+dx<=n,row+dy>=0,row+dy<=n else { continue }
52: guard levels.count>=9 else { return nil }
54: guard wood>0.25,wood<0.94 else { return nil }
55: let woodColor=colors.count>=8 ? BoardChroma(red:median(colors.map(\.red)),green:median(colors.map(\.green))) : nil
58: for y in 0..<side { for x in 0..<side {
62: mask[y*side+x]=value<wood*0.50 && value<wood-0.20
66: pale=b.magnitude-a.magnitude>0.025 && a.magnitude<b.magnitude*0.7 && value>wood-0.08
68: mask[y*side+x]=pale || value>wood+0.10
73: for y in 1..<side-1 { for x in 1..<side-1 {
76: for y in 1..<side-1 { for x in 1..<side-1 {
86: for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && ny>=0 && nx<side && ny<side {
94: if distance<0.55 && component.count>500 && distance<bestDistance { best=component;bestDistance=distance }
99: guard minX>1,minY>1,maxX<side-2,maxY<side-2,
107: for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && ny>=0 && nx<side && ny<side {
118: guard xx>0,yy>0,abs(xy)/sqrt(xx*yy)<0.12 else { return nil }
122: guard (0.75...1.33).contains(ratio),abs(area/(Double.pi*rx*ry)-1)<0.12,
123: abs(Double(maxX-minX)*step/(2*rx)-1)<0.12,
124: abs(Double(maxY-minY)*step/(2*ry)-1)<0.12 else { return nil }
```

## N/StoneGeometry.swift

```text
8: func contains(_ p:ImagePoint, padding:Double = 0)->Bool {
9: pow((p.x-center.x)/(radiusCol+padding),2)+pow((p.y-center.y)/(radiusRow+padding),2)<=1
72: occlusion:[ColoredNeighbor]=[],searchSteps:Int=11,shadedWhite:Bool=false,diagnostic:((StoneFitAttempt)->Void)?=nil,diagnosticStage:String="outline")->StoneFootprint? {
79: let radii=occlusion.map{$0.shape.radiusCol}.sorted()
80: let expectedRadius=contextual ? radii[radii.count/2] : 0
83: for y in 0..<side { for x in 0..<side {
88: black=current-correction<base-0.20 && current-correction<base*0.65
93: || current-correction>base+0.12
124: let maximumRadius = masking.isEmpty ? 0.54 : 0.60
126: if contextual && (abs(shape.rx-expectedRadius)>0.041 || abs(dx)>5 || abs(dy)>5) {continue}
142: guard hidden>=shape.disk.count*0.02,body>=shape.disk.count*0.65 else {continue}
144: guard inside>=0.92,inside>bestScore else {continue}
146: guard visible>=area*0.50 else {continue}
150: guard inside>=0.92,!masking.contains(where:{hypot((center.x-$0.center.x)/(shape.rx+$0.radiusCol),(center.y-$0.center.y)/(shape.ry+$0.radiusRow))<0.90}) else {continue}
152: guard visible>=area*0.50 else {continue}
165: let reason=best.map {$0.quality<minimumQuality ? "below_minimum_quality":
166: $0.radiusCol<=0.32 || $0.radiusCol>=maximumRadius ? "radius_at_search_boundary":"fit_passed"} ?? "no_candidate"
170: guard let best,best.quality>=minimumQuality,best.radiusCol>0.32,best.radiusCol<maximumRadius else { return nil }
178: guard reading.occupancy.stone != nil,reading.confidence>=0.9,let colorShift,
182: (0.36...0.52).contains(shape.radiusCol),
183: max(abs(shape.center.x-Double(reading.col)),abs(shape.center.y-Double(reading.row)))>=0.30 else {return nil}
193: let nearby=neighbors.filter{abs($0.row-reading.row)<=1 && abs($0.col-reading.col)<=1}
197: guard shape.quality>=0.86,shape.radiusCol>=0.38,shape.radiusCol<=0.52,
200: stone.occupancy.stone != nil,stone.confidence>=0.90 else {return nil}
205: let hypothesis=IntersectionReading(row:reading.row,col:reading.col,occupancy:color,confidence:0,delta:reading.delta)
213: nearby.contains(where:{hypot((shape.center.x-$0.center.x)/(shape.radiusCol+$0.radiusCol),
214: (shape.center.y-$0.center.y)/(shape.radiusRow+$0.radiusRow))<0.90}) ? nil : shape
229: max(abs(shape.center.x-Double(reading.col)),abs(shape.center.y-Double(reading.row)))<=0.28+1e-9 else {continue}
242: let hypothesis=IntersectionReading(row:reading.row,col:reading.col,occupancy:.white,confidence:0,delta:reading.delta)
247: // the candidate's body. The masked fit still requires >=92% body votes,
249: let masks=neighbors.filter{$0.quality>=0.90 && abs($0.row-reading.row)<=1 && abs($0.col-reading.col)<=1}
254: (0.38...0.52).contains(shape.radiusCol),
255: max(abs(shape.center.x-Double(reading.col)),abs(shape.center.y-Double(reading.row)))<=0.28+1e-9,
256: !neighbors.contains(where:{hypot((shape.center.x-$0.center.x)/(shape.radiusCol+$0.radiusCol),
257: (shape.center.y-$0.center.y)/(shape.radiusRow+$0.radiusRow))<0.90}) else {return nil}
273: let workers=candidates.count>=8 ? min(4,ProcessInfo.processInfo.activeProcessorCount):1
293: (a.center.y-b.center.y)/(a.radiusRow+b.radiusRow))<0.85
313: abs(neighbor.row-reading.row)<=1,abs(neighbor.col-reading.col)<=1 else {return false}
314: let centeredStrong=neighbor.confidence>=0.9 &&
315: hypot(centers[j].x-Double(neighbor.col),centers[j].y-Double(neighbor.row))<0.05
316: if centeredStrong && hypot(center.x-Double(reading.col),center.y-Double(reading.row))>0.05 {return true}
320: return centeredStrong && hypot(center.x-centers[j].x,center.y-centers[j].y)<0.75
324: if secondaryClaim,reading.confidence>=0.9,!blocked.contains(index) {
325: let nearby=footprints.filter { abs($0.row-reading.row)<=1 && abs($0.col-reading.col)<=1 }
331: for neighbor in readings where neighbor.occupancy == .black && neighbor.confidence>=0.9 &&
333: abs(neighbor.row-reading.row)<=1 && abs(neighbor.col-reading.col)<=1 {
336: hypot(centers[neighborIndex].x-Double(neighbor.col),centers[neighborIndex].y-Double(neighbor.row))<0.05,
345: if secondaryClaim {result[index]=IntersectionReading(row:reading.row,col:reading.col,occupancy:.uncertain,confidence:0,delta:reading.delta)}
349: let neighbors=footprints.filter{abs($0.row-reading.row)<=1 && abs($0.col-reading.col)<=1}
354: result[index]=IntersectionReading(row:reading.row,col:reading.col,occupancy:.empty,confidence:0.8,delta:reading.delta)
361: // still needs >=92% body coverage, >=50% visible ring, nonoverlap and
364: for reading in result where reading.occupancy.stone != nil && reading.confidence>=0.9 {
366: if let original, original.quality>=0.86 {continue}
369: abs(shape.row-reading.row)<=1 && abs(shape.col-reading.col)<=1 &&
370: result[shape.row*calibration.size+shape.col].occupancy == reading.occupancy && shape.quality>=0.78
373: for neighbor in result where neighbor.occupancy == .white && neighbor.confidence>=0.9 &&
375: abs(neighbor.row-reading.row)<=1 && abs(neighbor.col-reading.col)<=1 &&
391: if neighbors.count >= (reading.occupancy == .white ? 1 : 2), refined.quality >= 0.90 {
393: } else if reading.occupancy == .black, reading.confidence >= 0.95,
394: let original, refined.quality >= 0.86 {
400: max(abs(fit.center.x-point.x),abs(fit.center.y-point.y)) <= 0.20
403: hypot(original.center.x-refined.center.x, original.center.y-refined.center.y) <= 0.08 {
421: let rx=max(0.30,(neighbors.map(\.radiusCol).min() ?? 0.42)-0.03)
422: let ry=max(0.30,(neighbors.map(\.radiusRow).min() ?? 0.42)-0.03)
423: func masked(_ p:ImagePoint)->Bool { neighbors.contains{$0.contains(p,padding:0.04)} }
429: guard woodLevels.count>=200 else { return false }
436: guard let a=frame.patchMean(q),let b=reference.patchMean(basePoint),b>=woodLevel-0.08,
439: let matches=change > -0.12 && change<0.07 && colorDifference<0.025
441: if abs(p.x-Double(col))<=0.48 && abs(p.y-Double(row))<=0.48,
442: change < -0.18 || (colorDifference>0.04 && change > -0.06) { unexplained += 1 }
444: guard unexplained<5 else { return false }
446: for axis in 0..<2 { for k in -11...11 {
458: let candidates=[-0.08,-0.04,0,0.04,0.08].compactMap { shift -> (Double,Double)? in
461: guard let best=candidates.max(by:{$0.1<$1.1}),best.1>0.04 else { continue }
470: if live-correction-base>0.08 && live-correction>woodLevel-0.08 { unexplainedCoveredInk += 1 }
472: ink.append(InkEvidence(point:p,axis:axis,survives:current>0.04 && current>=best.1*0.55 && current<=best.1*1.8))
474: guard unexplainedCoveredInk<2 else { return false }
481: guard pow((center.x-Double(col))/rx,2)+pow((center.y-Double(row))/ry,2)<=0.81 else { continue }
482: if neighbors.contains(where:{hypot((center.x-$0.center.x)/(rx+$0.radiusCol),(center.y-$0.center.y)/(ry+$0.radiusRow))<0.90}) { continue }
484: func inside(_ p:ImagePoint,_ scale:Double)->Bool { pow((p.x-center.x)/(rx*scale),2)+pow((p.y-center.y)/(ry*scale),2)<=1 }
486: guard body.count>=15,Double(body.filter(\.matches).count)/Double(body.count)>=0.85 else {
489: for axis in 0..<2 {
495: guard rails.filter(\.survives).count >= ((edgeColumn || edgeRow) ? 3 : 2) else {
501: return feasible>=3
```

## N/StoneSetProfile.swift

```text
16: name.count<=80,createdAt.timeIntervalSince1970.isFinite,updatedAt.timeIntervalSince1970.isFinite,
27: guard opticalHeightCandidates.count<=100,
40: guard value.isFinite,value>0,source == "userMeasurement",measuredAt.timeIntervalSince1970.isFinite,
41: uncertaintyMm.map({$0.isFinite && $0>=0 && $0<=value}) ?? true else {
104: func present(_ s:String?)->Bool {s.map{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty} ?? false}
105: func hash(_ s:String)->Bool {s.count == 64 && s.allSatisfy{"0123456789abcdefABCDEF".contains($0)}}
106: guard status == "offlineCandidate",value.isFinite,value>0,
109: confidence.calibrationStatus == "uncalibrated",present(confidence.description),confidence.sampleCount>=0,
122: guard units == .rowPitch,conversion.rowPitchMm.isFinite,conversion.rowPitchMm>0,present(conversion.source),
123: conversion.uncertaintyMm.map({$0.isFinite && $0>=0 && $0<conversion.rowPitchMm}) ?? true,
132: low>=0,low<=value,value<=high else {throw StoneSetProfileError.invalid("Invalid optical-estimate uncertainty interval.")}
144: guard schemaVersion == 1,profiles.count<=1000,Set(profiles.map(\.stoneSetID)).count == profiles.count,
```
