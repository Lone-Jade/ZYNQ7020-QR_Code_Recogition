from paths import PROJECT,tool
import sys
from pathlib import Path
"""Create a standalone final R4 scene runtime; never installs or starts it."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,ast
R=PROJECT
LAUNCH='''import argparse,os,sys,json
from pathlib import Path
root=Path(__file__).resolve().parent
sys.path.insert(0,str(root/'python'))
from ax7021b_qr.r4_startup import verify_runtime,verify_board
p=argparse.ArgumentParser();p.add_argument('--run',action='store_true');p.add_argument('--start-preview',action='store_true');p.add_argument('--stop-preview',action='store_true');p.add_argument('--guard',action='store_true');a,rest=p.parse_known_args()
m=verify_runtime(root)
if a.stop_preview:
 from ax7021b_qr.r4_display import DisplayDevice
 d=DisplayDevice();d.stop();d.close()
elif a.start_preview:
 verify_board(root)
 from ax7021b_qr.r4_display import DisplayDevice
 import subprocess
 d=DisplayDevice()
 if not d.status()['running']:
  subprocess.run([str(root/'bin/qr-mainline'),'--init-camera'],check=True)
  d.start()
 d.close()
elif a.guard:print(json.dumps(verify_board(root)))
elif a.run:
 state=verify_board(root)
 if not state['display_status']['running']:raise RuntimeError('Start the independent camera preview service first')
 env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1',PYTHONPATH=str(root/'python'),LD_LIBRARY_PATH=str(root/'lib'),PATH=str(root/'bin')+os.pathsep+os.environ.get('PATH',''))
 os.execvpe(sys.executable,[sys.executable,'-u','-B','-m','ax7021b_qr.r4_worker',*rest],env)
else:print(json.dumps(dict(revision='R4-FINAL',integrity=True,installed=False,board_tested=False)))
'''
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--arm-label',default='arm-v1');p.add_argument('--kernel-label',default='r4-v2');p.add_argument('--output',type=Path,default=R/'build/outputs/runtime');p.add_argument('--firmware',type=Path);a=p.parse_args()
 out=a.output.resolve();assert out.is_relative_to(R.resolve()) and not out.exists()
 source=R/'src/software';arm=R/'build/work'/a.arm_label;k=R/'build/work/kernel'/a.kernel_label
 receipt=json.loads((arm/'build_receipt.json').read_text());kr=json.loads((k/'build_receipt.json').read_text())
 assert receipt['build_passed'] and kr['loadable_module_built'] and not kr['fault_test_build']
 for n,h in receipt['source_sha256'].items():assert sha(source/n)==h,n
 for n,h in kr['production_source_sha256'].items():assert sha(source/'kernel'/n)==h,n
 for n,h in kr['include_sha256'].items():assert sha(source/'include'/n)==h,n
 out.mkdir(parents=True);files={}
 def copy(src,name):
  dst=out/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 for n in ['libqr_mainline.so.1','qr-mainline']:
  assert sha(arm/n)==receipt['artifacts'][n]
  copy(arm/n,('bin/' if n=='qr-mainline' else 'lib/')+n)
 (out/'bin/qr-mainline').chmod(0o755)
 for n,h in kr['modules'].items():
  assert sha(k/'module'/n)==h;copy(k/'module'/n,'kernel/'+n)
 for n in ['__init__.py','capture.py','candidate_capture.py','candidate_metadata.py','frame_diagnostics.py','r4_detector.py','r4_timing.py','r4_gray_capture.py','r4_display.py','r4_worker.py','r4_startup.py']:
  f=source/'python/ax7021b_qr'/n;ast.parse(f.read_text());copy(f,'python/ax7021b_qr/'+n)
 copy(source/'version.json','version.json')
 (out/'launch_r4.py').write_text(LAUNCH)
 copy(arm/'build_receipt.json','build-receipts/arm.json');copy(k/'build_receipt.json','build-receipts/kernel.json')
 files={p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file()}
 # No PS color/raster/X11 runtime can enter this package by accident.
 assert not any(any(word in n for word in ['xshm','r3_color','hdmi_pipeline']) for n in files)
 release=json.loads((R/'build/RELEASE.json').read_text())
 result=dict(revision='R4-FINAL',source_origin_commit=release['source_origin_commit'],source_inventory_sha256=sha(R/'build/MANIFEST.json'),sha256=files,source_version_sha256=sha(source/'version.json'),layout='Gray8',display='camera RGB565 via PL/VDMA/OSD',display_abi=2,source_tag_abi=1,fitness_abi=2,ps_rgb_copies=0,ps_raster=False,installed=False,board_tested=False,deployment_ready=False)
 if a.firmware:
  f=json.loads((a.firmware/'build_receipt.json').read_text())
  result['boot_sha256']={n:f['sha256'][n] for n in ['BOOT.BIN','image.ub','boot.scr']}
  for n,h in result['boot_sha256'].items():assert sha(a.firmware/n)==h
 (out/'RUNTIME_MANIFEST.json').write_text(json.dumps(result,indent=2)+'\n')
 print('R4_RUNTIME_PACKAGED',len(files),sha(out/'RUNTIME_MANIFEST.json'))
if __name__=='__main__':main()
