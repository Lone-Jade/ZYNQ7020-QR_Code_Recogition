from paths import PROJECT,tool
"""Isolated C04 hardware build; generated projects stay under development/build."""
from pathlib import Path
import argparse,os,subprocess,shutil,hashlib,json,re
ROOT=PROJECT
VIVADO=tool('vivado')

def snapshot_incremental_guide(work,guide):
 """Keep the guide outside impl_1, which reset_run removes before placement."""
 digest=hashlib.sha256(guide.read_bytes()).hexdigest()
 snapshot=work/'inputs'/('incremental_guide_'+digest+'.dcp')
 snapshot.parent.mkdir(parents=True,exist_ok=True)
 if not snapshot.exists():shutil.copyfile(guide,snapshot)
 assert hashlib.sha256(snapshot.read_bytes()).hexdigest()==digest,'Incremental guide snapshot hash mismatch'
 return snapshot,digest

def render_standard_tcl(work,source):
 """Disable retained incremental state; preserve other project run strategies."""
 return f'''open_project {{{work/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.xpr'}}}
# Reuse only Vivado-validated vendor IP cache entries. Custom RTL is rebuilt.
set cache_report [open {{{work/'vendor-cache-reuse.tsv'}}} w]
foreach ip [get_ips -all] {{
 if {{[string match "xilinx.com:ip:*" [get_property IPDEF $ip]]}} {{
  set match [config_ip_cache -cache_has_match $ip]
  if {{$match ne ""}} {{
   puts $cache_report "[get_property NAME $ip]\\t$match"
  }}
 }}
}}
close $cache_report
generate_target all -force [get_files *.bd]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs impl_1]
set_property INCREMENTAL_CHECKPOINT {{}} [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.TCL.PRE {{}} [get_runs impl_1]
close_project
source {{{source/'pynq_ax7021b/hardware/base/build_xsa.tcl'}}}
'''

def render_incremental_tcl(work,source,guide,directive):
 """Render only; callers decide when to write/run these isolated scripts.

 read_checkpoint -directive TimingClosure is documented by the installed
 2025.2 doc/eng/man/read_checkpoint. PLACE_DESIGN.TCL.PRE is documented in
 UG894 2025.2, Defining Tcl Hook Scripts. Clear automatic checkpoint reading
 before using that hook so RuntimeOptimized cannot replace the explicit mode.
 """
 assert directive in ('RuntimeOptimized','TimingClosure')
 hook_path=work/'timing_closure_place_pre.tcl';hook=None
 if directive=='TimingClosure':
  selection=f'''set_property INCREMENTAL_CHECKPOINT {{}} [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.TCL.PRE {{{hook_path}}} [get_runs impl_1]'''
  hook=f'''# Explicit incremental timing-closure target WNS=0; original clock constraints remain.
read_checkpoint -incremental -directive TimingClosure {{{guide}}}
report_incremental_reuse -file qr_desktop_top_incremental_reuse_timing_closure_pre_placed.rpt
'''
 else:
  selection=f'''set_property INCREMENTAL_CHECKPOINT {{{guide}}} [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.TCL.PRE {{}} [get_runs impl_1]'''
 wrapper=f'''open_project {{{work/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.xpr'}}}
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs impl_1]
{selection}
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
close_project
source {{{source/'pynq_ax7021b/hardware/base/build_xsa.tcl'}}}
'''
 return wrapper,hook

def main():
 p=argparse.ArgumentParser();p.add_argument('label');p.add_argument('--fitness',action='store_true');p.add_argument('--fitness-ip-dir',type=Path);p.add_argument('--fitness-receipt',type=Path);p.add_argument('--incremental-checkpoint',type=Path);p.add_argument('--incremental-directive',choices=['RuntimeOptimized','TimingClosure'],default='RuntimeOptimized');p.add_argument('--observation-snapshot',action='store_true');p.add_argument('--create-only',action='store_true');p.add_argument('--resume',action='store_true');p.add_argument('--capture-layout',choices=['gray','color'],default=os.environ.get('AX7021B_CAPTURE_LAYOUT','gray'));p.add_argument('--payload-bram',choices=['0','1'],default=os.environ.get('AX7021B_PAYLOAD_BRAM','0'));p.add_argument('--fitness-vlnv',default=os.environ.get('AX7021B_FITNESS_VLNV','xiwei.org:qr:qr_fitness:1.0'));a=p.parse_args()
 if a.incremental_directive!='RuntimeOptimized' and not a.incremental_checkpoint:p.error('--incremental-directive TimingClosure requires --incremental-checkpoint')
 assert not (a.fitness and a.observation_snapshot)
 assert a.label.replace('-','').isalnum()
 work=ROOT/'build/work'/a.label;source=work/'inputs/hardware_project'
 if not a.resume:
  assert not work.exists(), 'Use a fresh label or --resume'
  shutil.copytree(ROOT/'src/hardware',source,ignore=shutil.ignore_patterns('work'))
  if a.observation_snapshot:
   variant=ROOT/'hardware_variants/observation';manifest=json.loads((variant/'VARIANT_MANIFEST.json').read_text())
   for name,h in manifest['overrides'].items():
    assert hashlib.sha256((variant/name).read_bytes()).hexdigest()==h
    for rtl in ['pynq_ax7021b/hardware/qr_desktop/roi_selection/rtl','qr_diag45_20261018/qr_video_replay/rtl']:shutil.copyfile(variant/name,source/rtl/name)
  (work/'input_sha256.json').write_text(json.dumps({str(x.relative_to(source)):hashlib.sha256(x.read_bytes()).hexdigest() for x in source.rglob('*') if x.is_file()},indent=2)+'\n')
 env={**os.environ,'AX7021B_NO_PWM':'1','AX7021B_QR':'1','AX7021B_DESKTOP':'1','AX7021B_ROI_PROFILE':'b3a-145-union','AX7021B_QR_WORK_ROOT':str(work),'AX7021B_QR_OUTPUT':str(work/'output'),'AX7021B_JOBS':'1','AX7021B_IP_CACHE':str(ROOT/'build/work/ip-cache')}
 env.update(AX7021B_CAPTURE_LAYOUT=a.capture_layout,AX7021B_PAYLOAD_BRAM=a.payload_bram,AX7021B_FITNESS_VLNV=a.fitness_vlnv)
 configuration=dict(capture_layout=a.capture_layout,payload_bram=int(a.payload_bram),fitness_vlnv=a.fitness_vlnv if a.fitness else None,clock_constraints_changed=False)
 if not a.resume:(work/'build_config.json').write_text(json.dumps(configuration,indent=2)+'\n')
 else:assert json.loads((work/'build_config.json').read_text())==configuration,'Resume configuration mismatch'
 if a.fitness:
  ip=a.fitness_ip_dir or ROOT/'build/work/fitness_hls/hls/impl/ip';assert (ip/'component.xml').exists()
  receipt=json.loads((a.fitness_receipt or ROOT/'build/reports/hls_build.json').read_text())
  assert receipt['c_rtl_cosim_pass'] and receipt['hls_csim_pass']
  kernel=ROOT/'src/hls/qr_fitness.cpp'
  assert receipt['kernel_sha256']==hashlib.sha256(kernel.read_bytes()).hexdigest()
  assert receipt['ip_component_sha256']==hashlib.sha256((ip/'component.xml').read_bytes()).hexdigest()
  if a.fitness_ip_dir:
   snap=work/'inputs/fitness_ip'
   if not a.resume:shutil.copytree(ip,snap)
   assert hashlib.sha256((snap/'component.xml').read_bytes()).hexdigest()==receipt['ip_component_sha256']
   manifest={str(f.relative_to(snap)):hashlib.sha256(f.read_bytes()).hexdigest() for f in snap.rglob('*') if f.is_file()}
   if not a.resume:(work/'fitness_input_sha256.json').write_text(json.dumps(dict(hls=receipt,files=manifest),indent=2)+'\n')
   else:assert manifest==json.loads((work/'fitness_input_sha256.json').read_text())['files']
   ip=snap
  env['AX7021B_FITNESS_IP']=str(ip)
 def run(name,script):
  command=[str(VIVADO),'-mode','batch','-source',str(source/'pynq_ax7021b/hardware'/script),'-log',str(work/(name+'.log')),'-journal',str(work/(name+'.jou'))]
  with (work/(name+'.stdout')).open('w') as log:subprocess.run(command,cwd=work,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
 if not a.resume:run('package','qr_desktop/package_qr_ip.tcl');run('create','base/create_project.tcl')
 if a.fitness and (source/'pynq_ax7021b/hardware/qr_desktop/fitness_bd.tcl').read_text().find('fitness_timing')>=0:
  hdl=(work/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.gen/sources_1/bd/system/synth/system.v').read_text()
  core=re.search(r'\bfitness\s*\n?\s*\((.*?)\);',hdl,re.S).group(1)
  monitor=re.search(r'\bfitness_timing\s*\n?\s*\((.*?)\);',hdl,re.S).group(1)
  def connection(block,pin):
   m=re.search(r'\.'+pin+r'\(([^)]+)\)',block);assert m,('Missing monitor connection',pin)
   name=re.sub(r'\[[^]]+\]','',m[1]);assert not "'" in name,('Constant monitor connection',pin)
   return name
  for tap,field in [('awaddr','AWADDR'),('awvalid','AWVALID'),('awready','AWREADY'),('wdata','WDATA'),('wstrb','WSTRB'),('wvalid','WVALID'),('wready','WREADY')]:
   net=connection(monitor,'tap_'+tap);assert net==connection(core,'s_axi_control_'+field)
   assert re.search(r'\.M\d+_AXI_'+field.lower()+r'\('+re.escape(net)+r'(?:\[[^]]+\])?\)',hdl),('AXI master disconnected',field,net)
 if not a.create_only:
  script='base/build_xsa.tcl'
  if not a.incremental_checkpoint:
   wrapper=work/'standard_build.tcl';wrapper.write_text(render_standard_tcl(work,source));script=wrapper
   (work/'physical_implementation.json').write_text(json.dumps(dict(strategy='non-incremental implementation; prior incremental guide and PLACE PRE hook cleared; optional existing post-route closure',clock_constraints_changed=False,reference_checkpoint_sha256=None,reference_checkpoint_original_path=None,reference_checkpoint_original_sha256=None,reference_checkpoint_snapshot_path=None,reference_checkpoint_snapshot_sha256=None,incremental_directive=None,target_wns_source='standard clock constraints',target_wns_ns=None,automatic_checkpoint_read_disabled=True,place_pre_hook_sha256=None,phys_route_strategy_reset=False,phys_route_strategy='retain existing project settings',script_sha256=hashlib.sha256(wrapper.read_bytes()).hexdigest()),indent=2)+'\n')
  if a.incremental_checkpoint:
   guide=a.incremental_checkpoint.resolve();assert guide.is_file() and guide.is_relative_to(ROOT/'build/work')
   snapshot,guide_sha256=snapshot_incremental_guide(work,guide)
   wrapper=work/'incremental_build.tcl';wrapper_text,hook_text=render_incremental_tcl(work,source,snapshot,a.incremental_directive);wrapper.write_text(wrapper_text);script=wrapper
   hook_path=work/'timing_closure_place_pre.tcl'
   if hook_text is not None:hook_path.write_text(hook_text)
   (work/'physical_implementation.json').write_text(json.dumps(dict(reference_checkpoint_sha256=guide_sha256,reference_checkpoint_original_path=str(guide),reference_checkpoint_original_sha256=guide_sha256,reference_checkpoint_snapshot_path=str(snapshot),reference_checkpoint_snapshot_sha256=hashlib.sha256(snapshot.read_bytes()).hexdigest(),strategy='incremental placement/routing guide; tool may override phys/route directives',incremental_directive=a.incremental_directive,target_wns_source='explicit zero slack' if a.incremental_directive=='TimingClosure' else 'reference checkpoint WNS',target_wns_ns=0.0 if a.incremental_directive=='TimingClosure' else None,automatic_checkpoint_read_disabled=a.incremental_directive=='TimingClosure',place_pre_hook_sha256=hashlib.sha256(hook_text.encode()).hexdigest() if hook_text is not None else None,clock_constraints_changed=False,script_sha256=hashlib.sha256(wrapper.read_bytes()).hexdigest()),indent=2)+'\n')
  run('build',script)
 (work/'input_sha256.json').write_text(json.dumps({str(x.relative_to(source)):hashlib.sha256(x.read_bytes()).hexdigest() for x in source.rglob('*') if x.is_file()},indent=2)+'\n')
 print('HARDWARE_PROJECT_CREATED' if a.create_only else 'HARDWARE_BUILD_PASS',a.label,flush=True)
if __name__=='__main__':main()
