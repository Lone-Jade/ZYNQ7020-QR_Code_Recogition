from paths import PROJECT,tool
import sys
from pathlib import Path
"""Record R4 actual implementation and bind DMA/OSD topology to the XSA."""
from pathlib import Path
import json,sys,zipfile,hashlib,xml.etree.ElementTree as E
import ac_record_hw
from r4_hw_connections import verify
R=PROJECT
# The user explicitly accepted the ~85% LUT footprint on 2026-10-25.
# Keep physical device fit, setup/hold, DRC and CDC gates; LUT headroom alone
# must not trigger implementation/export again for this finalization.
RESOURCE_LIMITS={'Slice LUTs':100,'Block RAM Tile':85,'DSPs':85}

def check(label):
 w=R/'build/work'/label;verify(w)
 log=(w/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.runs/impl_1/runme.log').read_text()
 assert not any(('CRITICAL WARNING:' in line or 'ERROR:' in line) and 'r4_cdc.xdc' in line for line in log.splitlines()),'R4 CDC constraints were rejected'
 manifest=json.loads((w/'input_sha256.json').read_text())
 for name,digest in manifest.items():
  current=R/'src/hardware'/name;snapshot=w/'inputs/hardware_project'/name
  assert current.is_file() and hashlib.sha256(current.read_bytes()).hexdigest()==digest,'Current hardware differs: '+name
  assert hashlib.sha256(snapshot.read_bytes()).hexdigest()==digest,'Build snapshot changed: '+name
 p=R/'build/reports/generated'/label/'receipt.json';receipt=json.loads(p.read_text());xsa=R/receipt['xsa']
 assert hashlib.sha256(xsa.read_bytes()).hexdigest()==receipt['xsa_sha256']
 with zipfile.ZipFile(xsa) as z:t=E.fromstring(z.read(next(n for n in z.namelist() if n.endswith('.hwh'))))
 modules={m.get('INSTANCE'):m for m in t.iter('MODULE')}
 def params(n):return {v.get('NAME'):v.get('VALUE') for v in modules[n].iter('PARAMETER')}
 def port(n,p):return next(v.attrib for v in modules[n].iter('PORT') if v.get('NAME')==p)
 v=params('display_vdma')
 expected={'C_INCLUDE_MM2S':1,'C_INCLUDE_S2MM':1,'C_NUM_FSTORES':3,'C_MM2S_GENLOCK_MODE':3,'C_S2MM_GENLOCK_MODE':2,'C_INCLUDE_INTERNAL_GENLOCK':1,'C_S_AXIS_S2MM_TDATA_WIDTH':16,'C_M_AXIS_MM2S_TDATA_WIDTH':16}
 for k,wanted in expected.items():assert int(v[k])==wanted,(k,v[k],wanted)
 assert int(params('display_osd')['C_BASEADDR'],16)==0x43c40000
 assert port('interrupts','In6')['SIGNAME']==port('display_vdma','s2mm_introut')['SIGNAME']
 assert params('qr_preprocess_0')['RGB_OUTPUT']=='0'
 assert int(port('qr_preprocess_0','s_axis_video_tuser')['LEFT'])+1==65
 assert port('display_guard','clk')['SIGNAME']=='ps7_FCLK_CLK0'
 assert modules['fitness'].get('VLNV')=='xiwei.org:qr:qr_fitness:2.0'
 import re
 util=(p.parent/'utilization.txt').read_text()
 def used(name):return float(re.search(r'^\| '+re.escape(name)+r'\s+\|([^\n]+)',util,re.M)[1].split('|')[0])
 assert used('DSPs')==99,'R4 may not add a DSP'
 baseline=R/'build/reference/clock_constraints'
 for relative in ['qr_desktop/camera.xdc','desktop/hdmi.xdc']:
  assert (R/'src/hardware/pynq_ax7021b/hardware'/relative).read_bytes()==(baseline/relative).read_bytes(),'Primary clock constraints changed'
 cdc=R/'src/hardware/pynq_ax7021b/hardware/qr_desktop/r4_cdc.xdc';policy=cdc.read_text()
 assert 'set_max_delay 9.700 -datapath_only' in policy and not any(x in policy for x in ['set_clock_groups','set_false_path','create_clock','set_multicycle_path'])
 reader=json.loads((R/'build/reports/generated/cdc-constraint-reader.json').read_text());assert reader['passed'] and reader['constraint_sha256']==hashlib.sha256(cdc.read_bytes()).hexdigest()
 selected=w/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.runs/impl_1/qr_desktop_top_routed.dcp'
 assert reader['reference_sha256']==hashlib.sha256(selected.read_bytes()).hexdigest(),'CDC qualification must use the selected final routed checkpoint'
 assert len(reader.get('rules',[]))==23 and all(abs(x['requirement_ns']-9.7)<.001 and x['slack_ns']>=0 for x in reader['rules']),'Every CDC bound must be effective and met'
 skew=(p.parent/'bus_skew.txt').read_text();assert 'display_identity/inst/cg0_reg' in skew and 'display_osd/inst/stat_cache_reg' in skew and '9.700' in skew
 assert receipt['setup_wns_ns']>=0 and receipt['hold_whs_ns']>=0
 assert receipt['drc_errors']==receipt['bus_skew_violations']==0
 assert all(v<=RESOURCE_LIMITS[k] for k,v in receipt['resource_percent'].items())
 result=dict(passed=True,generation='R4',label=label,xsa_sha256=receipt['xsa_sha256'],bit_sha256=receipt['bit_sha256'],vdma_parameters={k:v[k] for k in expected},exclusive_ddr_observer_connections=True,source_tag_axis_bits=65,gray_only=True,osd_address='0x43c40000',display_irq='In0/SPI29;In6/SPI35',dsp_count=99,resource_percent=receipt['resource_percent'],setup_wns_ns=receipt['setup_wns_ns'],hold_whs_ns=receipt['hold_whs_ns'],clocks_relaxed=False,original_primary_clock_files_unchanged=True,new_cdc_constraints_sha256=hashlib.sha256(cdc.read_bytes()).hexdigest(),cdc_data_bound_ns=9.7,cdc_clock_group_exceptions=False,registered_gray_count=True,board_tested=False)
 (p.parent/'r4-qualification.json').write_text(json.dumps(result,indent=2)+'\n');return result
if __name__=='__main__':
 label=sys.argv[1];ac_record_hw.ROOT=R;ac_record_hw.RESOURCE_LIMITS=RESOURCE_LIMITS;sys.argv=[sys.argv[0],label,'--fitness'];ac_record_hw.main();print(json.dumps(check(label),indent=2))
