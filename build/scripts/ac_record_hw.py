from paths import PROJECT,tool
"""Verify exported hardware and retain compact, independently readable evidence."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, zipfile
import xml.etree.ElementTree as ET
ROOT=PROJECT
RESOURCE_LIMITS={'Slice LUTs':85,'Block RAM Tile':85,'DSPs':85}
def sha(data): return hashlib.sha256(data).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('label');p.add_argument('--fitness',action='store_true');a=p.parse_args()
 work=ROOT/'build/work'/a.label;project=work/'ax7021b_linux_qr_desktop'
 xsa=work/'output/ax7021b_linux_qr_desktop.xsa';assert xsa.is_file()
 timing=(project/'timing_summary.txt').read_text()
 m=re.search(r'WNS\(ns\).*\n[^\n]*\n\s*([\d.-]+)\s+([\d.-]+)\s+(\d+)\s+\d+\s+([\d.-]+)',timing)
 assert m, 'Missing setup/hold summary'
 wns,tns,failed,whs=float(m[1]),float(m[2]),int(m[3]),float(m[4])
 assert wns>=0 and whs>=0 and tns==0 and failed==0
 assert 'checking unconstrained_internal_endpoints (0)' in timing
 warnings=[line.strip() for line in timing.splitlines() if re.match(r'TIMING-\d+\s+Critical Warning',line)]
 drc=(project/'drc.txt').read_text();assert not re.search(r'\|\s*(?:Error|Critical Warning)\s*\|',drc)
 bus=project/'bus_skew.txt'
 if not bus.exists():bus=project/'ax7021b_linux_qr_desktop.runs/impl_1/qr_desktop_top_bus_skew_routed.rpt'
 assert bus.exists() and 'VIOLATED' not in bus.read_text()
 with zipfile.ZipFile(xsa) as z:
  bits=[n for n in z.namelist() if n.endswith('.bit')];hw=[n for n in z.namelist() if n.endswith('.hwh')]
  assert len(bits)==len(hw)==1
  bit=z.read(bits[0]);tree=ET.fromstring(z.read(hw[0]))
  assert bit==(project/'ax7021b_linux_qr_desktop.runs/impl_1/qr_desktop_top.bit').read_bytes()
 modules={m.get('INSTANCE'):m for m in tree.iter('MODULE')}
 def params(name):return {x.get('NAME'):x.get('VALUE') for x in modules[name].iter('PARAMETER')}
 def port(name,pin):return next(x.attrib for x in modules[name].iter('PORT') if x.get('NAME')==pin)
 assert int(params('capture_timing')['C_BASEADDR'],16)==0x43c20000
 assert port('capture_timing','aclk')['SIGNAME']=='ps7_FCLK_CLK0'
 assert int(port('capture_timing','aclk')['CLKFREQUENCY'])==100000000
 assert int(params('qr_preprocess_0')['C_BASEADDR'],16)==0x43c00000
 if a.fitness:
  f=params('fitness');assert any(k.endswith('BASEADDR') and int(v,16)==0x43c10000 for k,v in f.items())
  assert port('fitness','ap_clk')['SIGNAME']=='ps7_FCLK_CLK0'
  assert port('interrupts','In5')['SIGNAME']==port('fitness','interrupt')['SIGNAME']
  assert params('ps7')['PCW_USE_S_AXI_HP2']=='1'
  if 'fitness_timing' in modules:
   assert int(params('fitness_timing')['C_BASEADDR'],16)==0x43c30000
   assert port('fitness_timing','aclk')['SIGNAME']=='ps7_FCLK_CLK0'
   for tap,field in [('awaddr','AWADDR'),('awvalid','AWVALID'),('awready','AWREADY'),('wdata','WDATA'),('wstrb','WSTRB'),('wvalid','WVALID'),('wready','WREADY')]:
    assert port('fitness_timing','tap_'+tap)['SIGNAME']==port('fitness','s_axi_control_'+field)['SIGNAME']

 target=ROOT/'build/reports/generated'/a.label;target.mkdir(parents=True,exist_ok=True)
 if a.fitness:
  rtl=work/'inputs/hardware_project/pynq_ax7021b/hardware/qr_desktop/roi_selection/rtl'
  for f in (ROOT/'src/rtl').glob('*.v'):assert sha(f.read_bytes())==sha((rtl/f.name).read_bytes()), 'Hardware input/source mismatch: '+f.name
 for name in ['timing_summary.txt','drc.txt','utilization.txt','clocks.txt','io.txt','validated_system.tcl']:
  shutil.copyfile(project/name,target/name)
 shutil.copyfile(bus,target/'bus_skew.txt')
 if (work/'input_sha256.json').exists():shutil.copyfile(work/'input_sha256.json',target/'input_sha256.json')
 else:
  variant=json.loads((ROOT/'hardware_variants/observation/VARIANT_MANIFEST.json').read_text())
  packaged=work/'ip/qr_preprocess_camera/src'
  actual={f.name:sha(f.read_bytes()) for f in sorted(packaged.iterdir()) if f.is_file()}
  assert actual==variant['packaged_ip_sha256']
  (target/'packaged_ip_sha256.json').write_text(json.dumps(actual,indent=2)+'\n')
 if (work/'fitness_input_sha256.json').exists():shutil.copyfile(work/'fitness_input_sha256.json',target/'fitness_input_sha256.json')
 for name in ['POSTROUTE-OPTIMIZATION.txt','qr_address_interrupt_audit.txt']:
  source=work/'output'/name
  if source.exists():shutil.copyfile(source,target/name)
  else:
   assert name=='POSTROUTE-OPTIMIZATION.txt'
   physical=work/'physical_implementation.json'
   if not physical.exists():physical=ROOT/'r2'/('physical-'+a.label+'.json')
   assert physical.exists()
   shutil.copyfile(physical,target/'physical_implementation.json')
 # Keep physical strategy/ECO bindings even when post-route optimization ran.
 physical=work/'physical_implementation.json'
 if physical.exists():shutil.copyfile(physical,target/'physical_implementation.json')
 utilization=(project/'utilization.txt').read_text()
 resources={}
 for resource in ['Slice LUTs','Block RAM Tile','DSPs']:
  row=re.search(r'^\| '+re.escape(resource)+r'\s+\|([^\n]+)',utilization,re.M);assert row,resource
  resources[resource]=float(row[1].split('|')[-2].strip())
  assert resources[resource]<=RESOURCE_LIMITS[resource], (resource,resources[resource],RESOURCE_LIMITS[resource])
 receipt=dict(label=a.label,fitness=a.fitness,xsa=str(xsa.relative_to(ROOT)),xsa_sha256=sha(xsa.read_bytes()),bit_sha256=sha(bit),setup_wns_ns=wns,hold_whs_ns=whs,drc_errors=0,bus_skew_violations=0,unconstrained_internal_endpoints=0,methodology_critical_warnings=warnings,hardware_addresses_checked=True,hardware_clocks_checked=True,deployed=False,reports={x.name:sha(x.read_bytes()) for x in target.iterdir() if x.is_file() and x.name!='receipt.json'})
 receipt['resource_percent']=resources
 receipt['resource_limits_percent']=RESOURCE_LIMITS
 receipt['capture_axis_bits']=int(params('qr_capture_vdma')['C_S_AXIS_S2MM_TDATA_WIDTH'])
 configuration=work/'build_config.json'
 if configuration.exists():
  receipt['configuration']=json.loads(configuration.read_text())
  if receipt['configuration'].get('fitness_vlnv')=='xiwei.org:qr:qr_fitness:2.0':
   assert modules['fitness'].get('VLNV')=='xiwei.org:qr:qr_fitness:2.0'
   assert params('qr_preprocess_0')['RGB_OUTPUT']==str(int(receipt['configuration']['capture_layout']=='color'))
   assert params('qr_preprocess_0')['PAYLOAD_BRAM']==str(receipt['configuration']['payload_bram'])
   assert int(params('qr_capture_vdma')['C_S_AXIS_S2MM_TDATA_WIDTH'])==32
   assert int(params('qr_capture_vdma')['C_S2MM_LINEBUFFER_DEPTH'])==1024
 (target/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()
