"""Version 2 scene client: live HUD and successful QR annotations, no pixels copied."""
import ctypes as C
from dataclasses import dataclass,field
from collections import deque
import errno,fcntl,math,os,threading,time

# Candidate rectangles are presence evidence, never QR coordinates or velocity.
MAX_GEOMETRY_AGE=.5
MAX_DECODE_AGE=1.
MAX_SCAN_LAG=15

class DisplayInfo(C.Structure):
 _fields_=[(n,C.c_uint32) for n in ('version','capabilities','width','height','stride','slots','columns','rows','cell_width','cell_height','color565','text_bytes','reserved0','reserved1','reserved2','reserved3')]
class Text(C.Structure):
 _fields_=[('version',C.c_uint32),('sequence',C.c_uint32),('flags',C.c_uint32),('reserved',C.c_uint32),('text',C.c_ubyte*128)]
class Annotation(C.Structure):
 _fields_=[(n,C.c_uint32) for n in ('x0','y0','x1','y1','label_x','label_y','source_epoch','source_frame')]+[('label',C.c_ubyte*64)]
class Scene(C.Structure):
 _fields_=[(n,C.c_uint32) for n in ('version','sequence','count','reserved')]+[('hud',C.c_ubyte*128),('annotation',Annotation*8)]
class Status(C.Structure):
 _fields_=[(n,C.c_uint32) for n in ('version','running','requested','applied','flags','source_epoch','source_frames','branch_frames','display_drops','qr_drops','unique_frames','committed_frames','monitor_errors','valid_slots','scan_epoch','scan_frame','read_dma_status','write_dma_status')]+[(n,C.c_uint64) for n in ('read_irqs','write_irqs','dma_errors','recoveries','quarantined','submissions')]+[('reserved',C.c_uint32*2)]
def command(direction,number,size=0):return direction<<30|size<<16|ord('D')<<8|number
def ioctl(fd,cmd,value):
 raw=bytearray(bytes(value));fcntl.ioctl(fd,cmd,raw,True);C.memmove(C.addressof(value),bytes(raw),len(raw));return value
class DisplayDevice:
 def __init__(self,path='/dev/ax7021b-display0'):
  self.fd=os.open(path,os.O_RDWR|os.O_CLOEXEC)
  try:
   self.info=ioctl(self.fd,command(2,0,C.sizeof(DisplayInfo)),DisplayInfo())
   if tuple(getattr(self.info,n) for n in ('version','capabilities','width','height','stride','slots','columns','rows','cell_width','cell_height','color565','text_bytes'))!=(2,11,1280,720,2560,3,32,4,12,16,0x07e0,128):
    raise RuntimeError('Final R4 scene ABI/geometry mismatch')
  except BaseException:self.close();raise
 def start(self):fcntl.ioctl(self.fd,command(0,1))
 def stop(self):fcntl.ioctl(self.fd,command(0,2))
 def status(self):
  s=ioctl(self.fd,command(2,4,C.sizeof(Status)),Status())
  if s.version!=2:raise RuntimeError('Final display status ABI mismatch')
  return {n:int(getattr(s,n)) for n,_ in s._fields_ if n!='reserved'}
 def submit_scene(self,scene):ioctl(self.fd,command(1,5,C.sizeof(Scene)),scene)
 def close(self):
  if getattr(self,'fd',-1)>=0:os.close(self.fd);self.fd=-1

def ascii_payload(value):
 return ''.join(ch if 32<=ord(ch)<127 else ('\\x%02x'%ord(ch) if ord(ch)<256 else '\\u%04x'%ord(ch) if ord(ch)<65536 else '\\U%08x'%ord(ch)) for ch in str(value))
def label_bytes(payload,column=0,row=0):
 text=ascii_payload(payload)[:9]
 if not 0<=column<=32-len(text) or row not in (0,1):raise ValueError('Label offset outside hardware character area')
 data=bytearray(b' '*64);offset=row*32+column;data[offset:offset+len(text)]=text.encode('ascii')
 return bytes(data)
def overlap(a,b):return max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
def match_score(a,b):
 aw,ah=a[2]-a[0],a[3]-a[1];bw,bh=b[2]-b[0],b[3]-b[1]
 if min(aw,ah,bw,bh)<=0 or not .5<=bw/aw<=2 or not .5<=bh/ah<=2:return None
 distance=math.hypot((a[0]+a[2]-b[0]-b[2])/2,(a[1]+a[3]-b[1]-b[3])/2)
 gate=.75*max(aw,ah,bw,bh);area=overlap(a,b);iou=area/(aw*ah+bw*bh-area)
 if iou<.2 or distance>gate:return None
 return .65*iou+.35*(1-distance/gate)
def rectangle_distance(a,b):
 return math.hypot(max(0,a[0]-b[2],b[0]-a[2]),max(0,a[1]-b[3],b[1]-a[3]))
def label_candidates(box,width):
 x0,y0,x1,y1=box
 candidates=[(x1-width,y0-22,False),(x0,y0-22,False),(x1+6,y0,False),
             (x1-width,y1+6,False),(x0,y1+6,False),(x0-width-6,y0,False)]
 if x1-x0>=width+12 and y1-y0>=28:candidates.append((x1-width-6,y0+6,True))
 seen=set()
 for x,y,inside in candidates:
  x=max(0,min(1280-width,int(x)));y=max(0,min(704,int(y)))
  if (x,y) in seen:continue
  seen.add((x,y));glyph=(x,y,x+width,y+16)
  if overlap(glyph,box) and not inside:continue
  if rectangle_distance(glyph,box)>6:continue
  # Shift the nine visible characters inside the unchanged 32x2 character
  # bank, so right/bottom-edge glyphs need no driver/RTL ABI change.
  column=(max(0,x-896)+11)//12;row=int(y>688)
  origin=(x-12*column,y-16*row)
  yield dict(glyph=glyph,origin=origin,column=column,row=row,
             area=(origin[0],origin[1],origin[0]+384,origin[1]+32))
def label_order(placements):
 # PL slot0 has highest text priority, including the padded blank cells.
 # Order slots so no higher-priority blank area erases another label's glyphs.
 edges={i:set() for i,p in enumerate(placements) if p is not None}
 for i in edges:
  for j in edges:
   if i!=j and overlap(placements[i]['glyph'],placements[j]['area']):edges[i].add(j)
 order=[]
 while edges:
  ready=sorted(i for i in edges if not any(i in targets for targets in edges.values()))
  if not ready:return None
  for i in ready:order.append(i);del edges[i]
  for targets in edges.values():targets.difference_update(ready)
 return order+[i for i,p in enumerate(placements) if p is None]
def place_labels(boxes,payloads):
 placements=[];hud=(880,16,1264,80)
 for index,(box,payload) in enumerate(zip(boxes,payloads)):
  width=max(1,len(ascii_payload(payload)[:9]))*12;chosen=None
  for candidate in label_candidates(box,width):
   glyph=candidate['glyph'];distance=rectangle_distance(glyph,box)
   if overlap(glyph,hud):continue
   if any(rectangle_distance(glyph,p['glyph'])<6 for p in placements if p is not None):continue
   if any(j!=index and rectangle_distance(glyph,other)<distance+16 for j,other in enumerate(boxes)):continue
   if label_order(placements+[candidate]) is None:continue
   chosen=candidate;break
  placements.append(chosen)
 return placements,label_order(placements)
@dataclass
class Track:
 key:tuple
 payload:str
 box:tuple
 roi:tuple
 epoch:int
 frame:int
 last_seen:float
 first_ack:float=None
 positions:list=field(default_factory=list)
 visibility:list=field(default_factory=list)

class SceneState:
 def __init__(self):
  self.tracks={};self.seen=set();self.epoch=None;self.frame=None
  self.accepted=self.stale=self.ambiguous=0;self.processed=0
  self.motion_updates=self.expired=self.peak_annotations=0
  self.preview_fps=self.recognition_fps=0.;self.sample=None
  self.candidate_history=deque(maxlen=16);self.candidate_frame=None;self.candidate_rejects=0;self.predicted=0
  self.label_layout_key=None;self.label_layout=([],[])
 def update(self,row,now):
  epoch,frame=int(row['source_epoch']),int(row['source_frame'])
  if self.epoch is None:self.epoch=epoch
  elif self.epoch!=epoch:self.stale+=1;return
  if self.frame is not None and ((frame-self.frame)&0xffffffff)>=0x80000000:
   self.stale+=1;return
  if self.frame==frame:self.stale+=1;return
  self.frame=frame;self.processed+=1
  for s in row.get('symbols',()):
   publication=int(s.get('publication_id') or 0)
   if not publication:continue
   key=(epoch,publication)
   if key not in self.seen:self.seen.add(key);self.accepted+=1
  age=max(0,(int(row.get('board_monotonic_ns',now*1e9))-int(row.get('capture_completed_ns',now*1e9)))/1e9)
  if age>=MAX_DECODE_AGE:self.stale+=1;return
  self._prune(now)
  updated=set()
  for s in row.get('symbols',()):
   key=(epoch,int(s.get('publication_id') or s['track_id']))
   corners=s.get('corners');roi=tuple(s.get('roi',()))
   if not corners or len(corners)!=8 or not all(math.isfinite(v) for v in corners) or len(roi)!=4:
    self.tracks.pop(key,None);continue
   if s.get('geometry_epoch')!=row.get('pl_epoch') or s.get('geometry_frame')!=row.get('pl_frame_sequence'):
    self.tracks.pop(key,None);continue
   box=(max(0,min(corners[::2])),max(0,min(corners[1::2])),min(1280,max(corners[::2])),min(720,max(corners[1::2])))
   if min(box[2]-box[0],box[3]-box[1],roi[2]-roi[0],roi[3]-roi[1])<=0:continue
   old=self.tracks.get(key)
   if old and (old.payload!=str(s['payload']) or match_score(old.box,box) is None):
    self.tracks.pop(key,None)
    old=None
   # A republished identity must not leave a duplicate of the same physical QR.
   shadows=[k for k,t in self.tracks.items() if k!=key and t.payload==str(s['payload']) and
            overlap(t.box,box)>.8*max((t.box[2]-t.box[0])*(t.box[3]-t.box[1]),(box[2]-box[0])*(box[3]-box[1]))]
   for k in shadows:del self.tracks[k]
   if old is None and len(self.tracks)>=8:continue
   observed=float(row.get('capture_completed_ns',now*1e9))/1e9
   positions=(old.positions if old else [])+[(frame,box,observed)]
   if old and old.box!=box:self.motion_updates+=1
   self.tracks[key]=Track(key,str(s['payload']),box,roi,epoch,frame,observed,old.first_ack if old else None,positions=positions[-4:],visibility=[(frame,True,observed)])
   updated.add(key);self.peak_annotations=max(self.peak_annotations,len(self.tracks))
  # Replay only presence/ambiguity evidence. Never transform decoded corners
  # using the enclosing proposal, which may jitter, merge or change size.
  for candidate_frame,regions,observed in self.candidate_history:
   self._follow(regions,candidate_frame,observed,only=updated)
  self._follow(row.get('regions',()),frame,float(row.get('capture_completed_ns',now*1e9))/1e9,exclude=updated)
 def candidates(self,epoch,frame,regions,observed):
  if self.epoch is None:self.epoch=epoch
  if epoch!=self.epoch or (self.candidate_frame is not None and not 0<((frame-self.candidate_frame)&0xffffffff)<0x80000000):
   self.candidate_rejects+=1;return
  clean=tuple(tuple(b) for b in regions if len(b)==4 and 0<=b[0]<b[2]<=1280 and 0<=b[1]<b[3]<=720)
  self.candidate_frame=frame;self.candidate_history.append((frame,clean,observed));self._follow(clean,frame,observed)
 def _follow(self,regions,frame,observed,only=None,exclude=()):
  candidates=[tuple(b) for b in regions if len(b)==4 and b[0]<b[2] and b[1]<b[3]]
  proposals={};eligible=set()
  for key,track in self.tracks.items():
   if key in exclude or (only is not None and key not in only):continue
   latest=track.visibility[-1][0]
   if not 0<((frame-latest)&0xffffffff)<0x80000000 or observed-track.last_seen>MAX_DECODE_AGE:continue
   eligible.add(key)
   scores=sorted(((score,i) for i,b in enumerate(candidates) if
      b[0]<=track.box[0]+4 and b[1]<=track.box[1]+4 and b[2]>=track.box[2]-4 and b[3]>=track.box[3]-4 and
      (score:=match_score(track.roi,b)) is not None),reverse=True)
   if not scores:continue
   if len(scores)>1 and scores[0][0]-scores[1][0]<.15:self.ambiguous+=1;continue
   proposals[key]=scores[0][1]
  moved=set()
  for key,index in proposals.items():
   # Do not share a crop with another matched or already-current identity.
   occupied=[t for k,t in self.tracks.items() if k!=key and k not in proposals]
   if sum(i==index for i in proposals.values())>1 or any(overlap(candidates[index],t.roi)>.5*((t.roi[2]-t.roi[0])*(t.roi[3]-t.roi[1])) for t in occupied):
    self.ambiguous+=1;continue
   t=self.tracks[key];t.visibility=(t.visibility+[(frame,True,observed)])[-16:];moved.add(key)
  for key in eligible-moved:
   t=self.tracks[key];t.visibility=(t.visibility+[(frame,False,observed)])[-16:]
 def _prune(self,now):
  for key,t in list(self.tracks.items()):
   if now-t.last_seen>=MAX_DECODE_AGE:
    del self.tracks[key];self.expired+=1
 def scan_box(self,track,status,now):
  if now-track.last_seen>=MAX_DECODE_AGE:return None
  if 'scan_epoch' not in status:
   if not track.visibility[-1][1] or now-track.visibility[-1][2]>MAX_GEOMETRY_AGE:return None
   return track.box,track.frame
  if status['scan_epoch']!=track.epoch:return None
  frame=status['scan_frame'];past=[(((frame-f)&0xffffffff),b,observed,f) for f,b,observed in track.positions if ((frame-f)&0xffffffff)<0x80000000]
  if not past:return None
  observations=[(((frame-f)&0xffffffff),valid,observed) for f,valid,observed in track.visibility if ((frame-f)&0xffffffff)<0x80000000]
  if not observations:return None
  lag,valid,seen=min(observations,key=lambda item:item[0])
  if not valid or lag>MAX_SCAN_LAG or now-seen>MAX_GEOMETRY_AGE:return None
  delta,box,observed,geometry_frame=min(past,key=lambda item:item[0])
  if delta<=2 and now-observed<=.1:return box,geometry_frame
  # Only repeated decoded geometry can establish a stationary target across
  # capture backlog. Moving/rotating targets need a genuinely recent result.
  recent=sorted(past,key=lambda item:item[0])[:3]
  if len(recent)<3 or recent[-1][0]-recent[0][0]>15:return None
  if any(max(abs(a-b) for a,b in zip(box,p[1]))>3 for p in recent):return None
  return box,geometry_frame
 def acknowledge(self,keys,now):
  for key in keys:
   if key in self.tracks and self.tracks[key].first_ack is None:self.tracks[key].first_ack=now
 def scene(self,status,now,sequence,stopped=False):
  if status['source_epoch']!=self.epoch:
   self.tracks.clear();self.epoch=status['source_epoch'];self.frame=None
   self.candidate_history.clear();self.candidate_frame=None
   self.sample=None;self.preview_fps=self.recognition_fps=0.
  self._prune(now)
  if self.sample is None:self.sample=(now,status['unique_frames'],self.processed)
  elif now-self.sample[0]>=1:
   seconds=now-self.sample[0];self.preview_fps=((status['unique_frames']-self.sample[1])&0xffffffff)/seconds
   self.recognition_fps=(self.processed-self.sample[2])/seconds;self.sample=(now,status['unique_frames'],self.processed)
  scene=Scene(version=2,sequence=sequence)
  lines=['R4 / '+('STOP' if stopped else 'RUN')+'  1280x720',f'PREVIEW {self.preview_fps:5.1f} FPS',f'DECODE  {self.recognition_fps:5.1f} FPS',f'SUCCESS {self.accepted}']
  scene.hud[:]=''.join(line[:32].ljust(32) for line in lines).encode('ascii')
  rendered=[];keys=[]
  for t in (() if stopped else self.tracks.values()):
   visible=self.scan_box(t,status,now)
   if visible is None:continue
   visible,display_frame=visible
   box=(max(0,int(visible[0])-4),max(0,int(visible[1])-4),min(1280,math.ceil(visible[2])+4),min(720,math.ceil(visible[3])+4))
   rendered.append((t,box,display_frame))
  layout_key=(tuple(r[1] for r in rendered),tuple(ascii_payload(r[0].payload)[:9] for r in rendered))
  if layout_key!=self.label_layout_key:
   self.label_layout=place_labels(*layout_key);self.label_layout_key=layout_key
  placements,order=self.label_layout
  self.visible_labels=sum(p is not None for p in placements)
  for index in order:
   t,box,display_frame=rendered[index];p=placements[index]
   a=scene.annotation[scene.count];a.x0,a.y0,a.x1,a.y1=box
   a.label_x,a.label_y=p['origin'] if p else (0,0)
   a.source_epoch=t.epoch;a.source_frame=display_frame;a.label[:]=label_bytes(t.payload,p['column'],p['row']) if p else b' '*64
   scene.count+=1;keys.append(t.key)
  return scene,keys

class ResultDisplay:
 def __init__(self,device=None):
  self.device=device or DisplayDevice();self.state=SceneState();self.lock=threading.Lock()
  self.user_stop=threading.Event();self.closing=threading.Event();self.error=None
  self.started=time.monotonic();self.before=self.device.status();self.sequence=self.before['requested'];self.state.epoch=self.before['source_epoch']
  self.pending=None;self.last_content=None;self.last_submit=0;self.acks=0;self.visible_count=0;self.scan_frame=None
  self.thread=threading.Thread(target=self._run,name='r4-scene',daemon=True);self.thread.start()
 def submit_results(self,row,recognition_fps=0.):
  with self.lock:self.state.update(row,time.monotonic())
 def submit_candidates(self,epoch,frame,regions,captured_ns):
  with self.lock:self.state.candidates(int(epoch),int(frame),regions,int(captured_ns)/1e9)
 def tick(self,now=None,stopped=False):
  now=time.monotonic() if now is None else now;s=self.device.status()
  if s['flags']&6 or s['quarantined']:raise RuntimeError('Final R4 video monitor fault')
  with self.lock:
   if self.pending:
    seq,keys,since=self.pending
    if s['applied']==seq:self.state.acknowledge(keys,now);self.pending=None;self.acks+=1
    elif now-since>2:raise TimeoutError('Scene commit not acknowledged')
    else:return
   if s['flags']&1 or now-self.last_submit<1/30:return
   seq=(self.sequence+1)&0xffffffff or 1
   scene,keys=self.state.scene(s,now,seq,stopped);self.scan_frame=s.get('scan_frame')
   content=bytes(scene)[8:]
   if content==self.last_content and now-self.last_submit<1 and not stopped:return
   try:self.device.submit_scene(scene)
   except OSError as e:
    if e.errno in (errno.EBUSY,errno.EAGAIN):return
    raise
   self.sequence=seq;self.pending=(seq,keys,now);self.last_content=content;self.last_submit=now;self.visible_count=scene.count
 def metrics(self):
  with self.lock:
   ages=[max(0,time.monotonic()-t.last_seen)*1000 for t in self.state.tracks.values()]
   lags=[(self.scan_frame-t.frame)&0xffffffff for t in self.state.tracks.values()] if self.scan_frame is not None else []
   return dict(successful_entities=self.state.accepted,active_annotations=len(self.state.tracks),visible_annotations=self.visible_count,visible_labels=getattr(self.state,'visible_labels',0),min_geometry_age_ms=min(ages,default=None),max_geometry_age_ms=max(ages,default=None),min_scan_lag_frames=min(lags,default=None),max_scan_lag_frames=max(lags,default=None),motion_updates=self.state.motion_updates,expired_annotations=self.state.expired,peak_annotations=self.state.peak_annotations,osd_failure=self.error)
 def _run(self):
  try:
   while not self.closing.wait(.025):self.tick()
  except BaseException as e:self.error=type(e).__name__+': '+str(e)
 def close(self,drain=False):
  self.closing.set();self.thread.join(2)
  # Clear target overlays before returning; the independent PL camera continues.
  deadline=time.monotonic()+2.2
  try:
   while time.monotonic()<deadline:
    self.tick(stopped=True)
    if self.pending and not self.pending[1] and self.device.status()['applied']==self.pending[0]:break
    time.sleep(.025)
  except BaseException as e:self.error=self.error or type(e).__name__+': '+str(e)
  after=self.device.status();self.device.close();seconds=max(.001,time.monotonic()-self.started)
  delta=lambda k:(after[k]-self.before[k])&0xffffffff
  return dict(revision='r4-final-scene-v2',scan_compensations=self.state.predicted,candidate_rejects=self.state.candidate_rejects,motion_updates=self.state.motion_updates,expired_annotations=self.state.expired,peak_annotations=self.state.peak_annotations,successful_entities=self.state.accepted,ambiguous_associations=self.state.ambiguous,stale_rows=self.state.stale,acknowledged_scenes=self.acks,osd_failure=self.error,
   displayed_frames=delta('unique_frames'),display_fps=delta('unique_frames')/seconds,source_frames=delta('source_frames'),source_fps=delta('source_frames')/seconds,
   preview_source_ratio=delta('unique_frames')/max(1,delta('source_frames')),hardware_status=after,ps_pixel_copies=0,ps_rasterizations=0,images_saved=False)
