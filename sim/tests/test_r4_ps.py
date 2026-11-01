import ctypes as C
import struct,time,unittest,tempfile
from pathlib import Path
from types import SimpleNamespace
from ax7021b_qr.r4_display import DisplayInfo,Text,Status,ascii_payload
from ax7021b_qr.r4_gray_capture import GrayCaptureProducer,SourceTag
from ax7021b_qr.capture import Buffer,FrameSnapshot
from ax7021b_qr.r4_startup import bound_framebuffers

class FakeDisplay:
 def __init__(self):self.requested=self.applied=0;self.pages=[]
 def status(self):return dict(requested=self.requested,applied=self.applied,flags=0,quarantined=0)
 def submit(self,seq,text):self.requested=seq;self.pages.append(text)

class FakeCapture:
 def __init__(self):self.maps=[bytearray(1280*722) for _ in range(3)];self.seq=0;self.running=False
 def start(self):self.running=True
 def stop(self):self.running=False
 def dequeue(self,timeout):
  n=self.seq;self.seq+=1;i=n%3;raw=self.maps[i]
  raw[:]=bytes([n&255])*len(raw)
  h=[0x32485251,0x20003,7,n+1,~(n+1)&0xffffffff,3,1,1280|(720<<16),100,0,0,0,0,0,0,0]
  f=h.copy();f[0]=0x32465251;f[10:12]=[1280*720,1]
  for offset,words in [(0,h),(1280*721,f)]:
   struct.pack_into('<16I',raw,offset,*words)
   struct.pack_into('<4I',raw,offset+64,0x34544701,9,n+8,~(n+8)&0xffffffff)
  return Buffer(index=i,bytes_used=len(raw),sequence=n,monotonic_ns=1),memoryview(raw)[1280:-1280]
 def queue(self,i):self.maps[i][:]=b'\xee'*len(self.maps[i])
 def frame_snapshot(self,b):
  h=struct.unpack_from('<16I',self.maps[b.index]);v=FrameSnapshot(index=b.index,sequence=b.sequence,flags=1)
  for i,w in enumerate([2,h[2],h[3],h[5],0,1,h[8],h[9],0,0,*h[12:16]]):v.data[i]=w
  return v
 def source_tag(self,b):return 9,int(b.sequence)+8
 def layout_diagnostics(self):return dict(version=1,format_errors=0)

class Tests(unittest.TestCase):
 def test_fbcon_is_not_framebuffer_but_fb_devices_are(self):
  with tempfile.TemporaryDirectory() as name:
   root=Path(name);(root/'fbcon').mkdir()
   self.assertEqual(bound_framebuffers(root),[])
   for n in ['fb0','fb12']:(root/n).mkdir()
   self.assertEqual(sorted(p.name for p in bound_framebuffers(root)),['fb0','fb12'])
 def test_abi(self):
  self.assertEqual([C.sizeof(t) for t in (DisplayInfo,Text,Status,SourceTag)],[64,144,128,32])
 def test_escape(self):self.assertEqual(ascii_payload('A\n中'),'A\\x0a\\u4e2d')
 def test_metadata_is_published_after_returning_dma(self):
  class Capture(FakeCapture):
   def queue(self,index):
    super().queue(index);self.last_queued=index
  c=Capture();events=[]
  class Display:
   def submit_candidates(self,epoch,frame,regions,captured_ns):
    self_checked=bytes(c.maps[c.last_queued][:4])==b'\xee'*4
    events.append((epoch,frame,self_checked))
  p=GrayCaptureProducer(c,display=Display()).start()
  with p.next() as lease:
   self.assertEqual(lease.snapshot.source_frame,8)
   self.assertNotEqual(bytes(lease.storage[:4]),b'\xee'*4)
  p.close();self.assertTrue(events);self.assertTrue(all(e[2] for e in events));self.assertEqual(events[0][:2],(9,8))
 def test_private_snapshot_and_backpressure(self):
  c=FakeCapture();p=GrayCaptureProducer(c).start()
  held=p.next();source=held.snapshot.source_frame
  before=bytes(held.storage)
  time.sleep(.12);captured=p.captured;time.sleep(.05)
  self.assertLessEqual(captured,3);self.assertEqual(p.captured,captured)
  self.assertEqual(bytes(held.storage),before);self.assertEqual(source,8)
  self.assertEqual(int(held.storage[1280]),0)
  held.release()
  for _ in range(10):
   with p.next() as lease:
    self.assertEqual(int(lease.storage[1280]),int(lease.buffer.sequence)&255)
    self.assertEqual(lease.snapshot.source_frame,int(lease.buffer.sequence)+8)
  summary=p.close();self.assertEqual(summary['skipped_decode_pending'],0)

if __name__=='__main__':unittest.main()
