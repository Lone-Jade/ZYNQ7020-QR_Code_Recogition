"""Gray8-only single DMA owner and immutable private decoder snapshots."""
import ctypes as C,fcntl,threading,time,struct
from dataclasses import dataclass
from types import SimpleNamespace
from .capture import Capture,FrameSnapshot,Buffer,_ioc,_ioctl_struct
from .r4_timing import TimingStats
FREE,WRITING,PENDING,READING=0,1,2,3
class SourceTag(C.Structure):
 _fields_=[('version',C.c_uint32),('index',C.c_uint32),('sequence',C.c_uint64),
           ('source_epoch',C.c_uint32),('source_frame',C.c_uint32),('flags',C.c_uint32),('reserved',C.c_uint32)]
class GrayCapture(Capture):
 def __init__(self,device='/dev/ax7021b-qr0',prefetch=True):
  super().__init__(device,prefetch)
  if not self.info.reserved0&8 or (self.info.stride,self.info.frame_bytes)!=(1280,1280*722):
   self.close();raise RuntimeError('R4 requires Gray8-only source-tag capture')
 def source_tag(self,buffer):
  t=SourceTag(version=1,index=buffer.index,sequence=buffer.sequence)
  _ioctl_struct(self.fd,_ioc(3,13,C.sizeof(t)),t)
  if t.version!=1 or not t.flags&1 or t.index!=buffer.index or t.sequence!=buffer.sequence:
   raise RuntimeError('Stale source tag')
  return int(t.source_epoch),int(t.source_frame)
 def layout_diagnostics(self):
  from .capture import _ioctl_struct
  class D(C.Structure):_fields_=[('words',C.c_uint32*8)]
  d=D();_ioctl_struct(self.fd,_ioc(2,12,C.sizeof(d)),d)
  if d.words[0]!=1:raise RuntimeError('layout diagnostics ABI')
  return dict(version=1,format_errors=int(d.words[3]),input_stall_cycles=int(d.words[4]))
@dataclass(frozen=True)
class GrayLayout:
 width:int=1280
 height:int=720
 row_stride:int=1280
 storage_height:int=722
 canonical_bytes:int=1280*722

def validate_guards(storage, sequence, width=1280, height=720):
    """Pure protocol validation; never call or mutate the decoder context."""
    header = struct.unpack_from('<16I', storage, 0)
    footer = struct.unpack_from('<16I', storage, width*(height+1))
    if not (header[0] == 0x32485251 and footer[0] == 0x32465251 and
            header[1] == footer[1] == 0x00020003 and
            header[2] == footer[2] and header[3] == footer[3] == ((sequence+1)&0xffffffff) and
            header[4] == footer[4] == (~header[3]&0xffffffff) and
            header[5] == footer[5] and header[6] == footer[6] == 1 and
            header[7] == footer[7] == width | (height << 16) and
            header[8] == footer[8] and header[8] <= 255 and
            header[9] == footer[9] and header[10:12] == (0, 0) and
            footer[10:12] == (width*height, 1) and header[12:16] == footer[12:16]):
        raise RuntimeError('Gray8 frame guard, sequence or format mismatch')
    return header[2], header[3], header[5]
class FrozenGraySnapshot:
    def __init__(self, storage, buffer, frozen, timing_ms=None):
        self.storage = storage
        self.epoch, self.frame, self.config = validate_guards(storage, int(buffer.sequence))
        self.frozen = FrameSnapshot.from_buffer_copy(bytes(frozen))
        value = self.frozen
        header = struct.unpack_from('<16I', storage, 0)
        bank = tuple(int(word) for word in value.data[:16])
        if not (value.index == buffer.index and value.sequence == buffer.sequence and value.flags&1 and
                bank[0] and not bank[0]&1 and bank[1:4] == header[2:4]+(header[5],) and
                bank[4] <= 30 and bank[5]&1 and not bank[5]&34 and
                bank[6:8] == header[8:10] and bank[10:14] == header[12:16]):
            raise RuntimeError('Frozen ROI descriptor does not belong to the copied Gray8 frame')
        self.bank = bytes(value.data)
        self.roi_count = bank[4]
        self.regions = []
        for i in range(self.roi_count):
            lo, hi = value.data[16+i*16:18+i*16]
            self.regions.append([lo&65535, lo>>16, hi&65535, hi>>16])
        self.timing_ms = dict(timing_ms or {})

    def validate_result(self, row):
        if (not row['metadata_valid'] or row['pl_frame_sequence'] != self.frame or
                row['roi_count'] != self.roi_count or row['regions'] != self.regions):
            raise RuntimeError('Decoder result differs from its leased frame/ROI identity')
class DecodeLease:
    def __init__(self, owner, slot):
        self.owner, self.slot, self.active = owner, slot, True
        self.snapshot = owner.snapshots[slot]
        self.storage = owner.storage[slot]
        self.buffer = owner.buffers[slot]
        self.capture = owner.canonical_capture

    def release(self):
        if self.active:
            with self.owner.condition:
                if self.owner.states[self.slot] != READING:
                    raise RuntimeError('Decode lease lost its frame ownership')
                self.owner.states[self.slot] = FREE
                self.owner.condition.notify_all()
            self.active = False

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.release()
class GrayCaptureProducer:
    """Only this thread may dequeue, snapshot and requeue physical DMA slots.

    Default backpressure never replaces pending/reading decode frames. The
    display may supersede its own pending copy. Its independent timer can
    refresh the latest color picture without claiming extra captured frames.
    """
    def __init__(self, capture, display=None, layout=None, slots=3, decode_policy='backpressure'):
        import numpy as np
        if decode_policy not in ('backpressure', 'latest') or slots < 2:
            raise ValueError('Invalid private decode queue policy')
        self.capture, self.display = capture, display
        self.layout = GrayLayout()
        self.decode_policy = decode_policy
        self.storage = np.empty((slots, self.layout.canonical_bytes), dtype=np.uint8)
        self.states, self.versions = [FREE]*slots, [0]*slots
        self.buffers, self.snapshots = [None]*slots, [None]*slots
        self.condition = threading.Condition()
        self.closing, self.ready = threading.Event(), threading.Event()
        self.error = None
        self.layout_diagnostics = None
        self.layout_diagnostics_error = None
        self.captured = self.skipped_decode = self.version = 0
        self.timers = TimingStats()
        self.canonical_capture = SimpleNamespace(fd=-1, prefetch=True, info=SimpleNamespace(
            width=self.layout.width, visible_height=self.layout.height,
            stride=self.layout.width, storage_height=self.layout.storage_height,
            frame_bytes=self.layout.canonical_bytes))
        self.thread = threading.Thread(target=self._run, name='r4-gray-owner', daemon=True)
        self.started = None

    def start(self):
        self.thread.start()
        if not self.ready.wait(10):
            raise TimeoutError('Gray8 capture producer did not start')
        self._raise_error()
        return self

    def _raise_error(self):
        if self.error is not None:
            raise RuntimeError('Gray8 capture producer failed: '+self.error) from None

    def _record_error(self, error):
        # Keeping an exception object keeps its traceback and the mmap-backed
        # RGB/Gray arguments in any failing callee alive. Store only text so
        # STOP can be followed by unmap/close and a clean capture restart.
        if self.error is None:
            self.error = type(error).__name__+': '+str(error)

    def _reserve(self):
        with self.condition:
            while not self.closing.is_set():
                free = [i for i, state in enumerate(self.states) if state == FREE]
                if free:
                    self.states[free[0]] = WRITING
                    return free[0]
                if self.decode_policy == 'latest':
                    pending = [i for i, state in enumerate(self.states) if state == PENDING]
                    if pending:
                        slot = min(pending, key=lambda i:self.versions[i])
                        self.states[slot] = WRITING
                        self.skipped_decode += 1
                        return slot
                self.condition.wait(.05)
        return None

    def _run(self):
        import numpy as np
        self.started = time.monotonic()
        try:
            self.capture.start()
            self.ready.set()
            while not self.closing.is_set():
                slot = self._reserve()
                if slot is None:
                    break
                buffer = pixels = rgb = gray_rows = None
                try:
                    stamp = time.perf_counter_ns()
                    buffer, pixels = self.capture.dequeue(timeout=2)
                    pixels.release()
                    pixels = None
                    self.timers.elapsed('wait_capture', stamp)
                    physical = self.capture.maps[buffer.index]
                    stamp = time.perf_counter_ns()
                    np.copyto(self.storage[slot], np.frombuffer(self.capture.maps[buffer.index],dtype=np.uint8,count=self.layout.canonical_bytes))
                    self.timers.elapsed('copy_gray_snapshot',stamp)
                    frozen=self.capture.frame_snapshot(buffer)
                    source=self.capture.source_tag(buffer)
                    snapshot=FrozenGraySnapshot(self.storage[slot],buffer,frozen)
                    ext=struct.unpack_from('<4I',self.storage[slot],64)
                    if ext!=(0x34544701,source[0],source[1],(~source[1]&0xffffffff)) or ext!=struct.unpack_from('<4I',self.storage[slot],1280*721+64):
                        raise RuntimeError('source identity differs from copied pixels')
                    snapshot.source_epoch,snapshot.source_frame=source
                    self.buffers[slot]=Buffer.from_buffer_copy(bytes(buffer))
                    self.snapshots[slot]=snapshot
                finally:
                    rgb = gray_rows = None
                    if pixels is not None:
                        pixels.release()
                    if buffer is not None:
                        stamp = time.perf_counter_ns()
                        self.capture.queue(int(buffer.index))
                        self.timers.elapsed('queue_dma', stamp)
                # Metadata only, after physical DMA ownership was returned.
                # This does not replace/drop a decode snapshot or call the C decoder.
                if self.display is not None:
                    self.display.submit_candidates(snapshot.source_epoch,snapshot.source_frame,
                                                   snapshot.regions,int(buffer.monotonic_ns))
                with self.condition:
                    self.version += 1
                    self.versions[slot] = self.version
                    self.states[slot] = PENDING
                    self.captured += 1
                    self.condition.notify_all()
        except BaseException as exc:
            self._record_error(exc)
            self.closing.set()
        finally:
            # STOP can assert processing_resetn and clear the PL formatter's
            # counters. Only the capture owner samples them before STOP.
            try:
                self.layout_diagnostics = self.capture.layout_diagnostics()
                self.layout_diagnostics['sampled_before_stop'] = True
                if self.layout_diagnostics['format_errors']:
                    raise RuntimeError('Capture row formatter reported %d errors' %
                                       self.layout_diagnostics['format_errors'])
            except BaseException as exc:
                self.layout_diagnostics_error = type(exc).__name__+': '+str(exc)
                self._record_error(exc)
                self.closing.set()
            try:
                self.capture.stop()
            except BaseException as exc:
                self._record_error(exc)
                self.closing.set()
            finally:
                self.ready.set()
                with self.condition:
                    self.condition.notify_all()

    def next(self, timeout=5):
        deadline = time.monotonic()+timeout
        with self.condition:
            while True:
                self._raise_error()
                pending = [i for i, state in enumerate(self.states) if state == PENDING]
                if pending:
                    slot = min(pending, key=lambda i:self.versions[i])
                    self.states[slot] = READING
                    return DecodeLease(self, slot)
                if self.closing.is_set():
                    raise EOFError('Gray8 capture producer stopped')
                remaining = deadline-time.monotonic()
                if remaining <= 0:
                    raise TimeoutError('No immutable Gray8 decode snapshot available')
                self.condition.wait(min(.05, remaining))

    def close(self):
        self.closing.set()
        with self.condition:
            self.condition.notify_all()
        self.thread.join(3)
        if self.thread.is_alive():
            raise TimeoutError('Gray8 capture owner did not stop')
        self._raise_error()
        seconds = max(.001, time.monotonic()-self.started)
        return dict(captured_frames=self.captured, capture_fps=self.captured/seconds,
                    skipped_decode_pending=self.skipped_decode,
                    unprocessed_pending_at_stop=sum(state == PENDING for state in self.states),
                    leased_at_stop=sum(state == READING for state in self.states),
                    decode_policy=self.decode_policy,
                    formal_comparison=self.decode_policy == 'backpressure',
                    layout_diagnostics=self.layout_diagnostics,
                    layout_diagnostics_error=self.layout_diagnostics_error,
                    timers=self.timers.summary(), images_saved=False)
