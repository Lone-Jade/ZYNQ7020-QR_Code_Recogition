"""Fail closed before sensor/DMA startup; all PL access uses versioned drivers."""
import ctypes as C,fcntl,json,hashlib,os,subprocess
from pathlib import Path
from .capture import Capture
from .r4_display import DisplayDevice
KERNEL='6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68'
class Caps(C.Structure):_fields_=[('words',C.c_uint32*8)]
def bound_framebuffers(root=Path('/sys/class/graphics')):
 # fbcon is the console subsystem, not a bound fbdev framebuffer.
 return [p for p in Path(root).glob('fb*') if p.name[2:].isdigit()]
def verify_runtime(root):
 root=Path(root);m=json.loads((root/'RUNTIME_MANIFEST.json').read_text())
 actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.name!='RUNTIME_MANIFEST.json'}
 if actual!=set(m['sha256']):raise RuntimeError('R4 runtime inventory differs')
 for n,h in m['sha256'].items():
  p=root/n
  if p.is_symlink() or hashlib.sha256(p.read_bytes()).hexdigest()!=h:raise RuntimeError('R4 runtime integrity: '+n)
 return m

def verify_board(root):
 m=verify_runtime(root)
 boot=m.get('boot_sha256',{})
 if set(boot)!={'BOOT.BIN','image.ub','boot.scr'}:raise RuntimeError('R4 boot/runtime binding missing')
 for name,h in boot.items():
  if hashlib.sha256((Path('/boot')/name).read_bytes()).hexdigest()!=h:raise RuntimeError('R4 boot file mismatch: '+name)
 if os.uname().release!=KERNEL:raise RuntimeError('R4 kernel mismatch')
 for module,param,wanted in [('ax7021b_qr_capture','early_rearm','Y'),('ax7021b_qr_fitness','optimize_writes','Y'),('ax7021b_qr_fitness','profile','N')]:
  if (Path('/sys/module')/module/'parameters'/param).read_text().strip()!=wanted:raise RuntimeError('R4 module parameter mismatch')
 for name in ['ax7021b_qr_capture.ko','ax7021b_qr_fitness.ko','ax7021b_camera_display.ko']:
  path=Path('/usr/lib/modules')/KERNEL/'updates'/name
  if hashlib.sha256(path.read_bytes()).hexdigest()!=m['sha256']['kernel/'+name]:raise RuntimeError('R4 installed module mismatch: '+name)
 if bound_framebuffers():raise RuntimeError('Framebuffer still bound')
 owner=Path('/sys/bus/platform/devices/43000000.dma/driver')
 if not owner.is_symlink() or owner.resolve().name!='ax7021b-camera-display':raise RuntimeError('Display VDMA owner mismatch')
 # Open only for ABI queries; do not initialize the camera or allocate jobs here.
 with Capture(prefetch=True) as c:
  if not c.info.reserved0&8 or c.info.stride!=1280:raise RuntimeError('R4 Gray8/source tag capability missing')
 fd=os.open('/dev/ax7021b-fitness0',os.O_RDWR|os.O_CLOEXEC)
 try:
  raw=bytearray(32);raw[0:4]=(2).to_bytes(4,'little');fcntl.ioctl(fd,0xc0204605,raw,True)
  caps=Caps.from_buffer_copy(raw)
  if tuple(caps.words[6:])!=(0xac04f003,2) or caps.words[1]&48!=48:raise RuntimeError('R3 scoring core mismatch')
 finally:os.close(fd)
 d=DisplayDevice();s=d.status();d.close()
 if s['flags']&6 or s['quarantined'] or s['monitor_errors'] or s['dma_errors'] or s['recoveries']:raise RuntimeError('R4 display hardware error')
 return dict(passed=True,kernel=KERNEL,display_owner='ax7021b-camera-display',gray_only=True,fitness_abi=2,display_abi=2,display_status=s)
