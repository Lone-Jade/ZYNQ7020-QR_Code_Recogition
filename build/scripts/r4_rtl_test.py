from paths import PROJECT,tool
import sys
from pathlib import Path
"""Run real Vivado behavioral simulations in an isolated generated directory."""
from pathlib import Path
import subprocess,json,hashlib
R=PROJECT
V=tool('vivado').parent
def main():
 (R/'build/reports/generated').mkdir(parents=True,exist_ok=True)
 out=R/'build/work/unit-sim';out.mkdir(parents=True,exist_ok=True)
 inputs=[*sorted((R/'src/rtl').glob('r4_*.v')),R/'src/hardware/pynq_ax7021b/hardware/desktop/hdmi_desktop.v',R/'src/hardware/pynq_ax7021b/hardware/desktop/r4_hdmi_rgb.v',*[f for f in sorted((R/'sim/tests').glob('tb_*.sv')) if f.name!='tb_r4_vdma.sv']]
 commands=[[str(V/'xvlog'),'--sv','-i',str(R/'src/rtl'),*map(str,inputs)]]
 for name in ['tb_r4_fork','tb_r4_osd','tb_r4_memory','tb_r4_identity','tb_r4_hdmi']:
  commands += [[str(V/'xelab'),name,'-s',name],[str(V/'xsim'),name,'-runall']]
 logs=[]
 for i,cmd in enumerate(commands):
  p=subprocess.run(cmd,cwd=out,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  (out/f'{i}.txt').write_text(p.stdout);logs.append(p.stdout)
  if p.returncode or 'Fatal:' in p.stdout or 'ERROR:' in p.stdout:raise RuntimeError(p.stdout)
 for token in ['R4_FORK_PASS','R4_OSD_PASS','R4_MEMORY_PASS','R4_IDENTITY_PASS','R4_HDMI_PASS']:assert any(token in s for s in logs),token
 result=dict(passed=True,tool='Vivado XSim 2025.2',files={str(f.relative_to(R)):hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs},checks=['independent branch backpressure','QR branch overflow does not affect display','source tag pairing','transparent glyph-only overlay','RGB/DE/HS/VS alignment','AXI AW/W separation and response stalls','pending bank immutable','vblank atomic commit'],not_tested=['actual VDMA Genlock','DDR draining','board','full implementation'])
 (R/'build/reports/generated/rtl-unit.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result,indent=2))
if __name__=='__main__':main()
