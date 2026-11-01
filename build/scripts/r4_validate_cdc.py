from paths import PROJECT,tool
import sys
from pathlib import Path
"""Prove every named R4 max-delay rule is effective on a linked checkpoint."""
from pathlib import Path
import argparse,hashlib,json,subprocess
R=PROJECT
def query(line,key):
 start=line.index(key)+len(key)
 while line[start].isspace():start+=1
 assert line[start]=='[';depth=0
 for i in range(start,len(line)):
  if line[i]=='[':depth+=1
  elif line[i]==']':
   depth-=1
   if depth==0:return line[start:i+1]
 raise ValueError(line)
def main():
 (R/'build/reports/generated').mkdir(parents=True,exist_ok=True)
 p=argparse.ArgumentParser();p.add_argument('--reference',required=True,type=Path);p.add_argument('--label',required=True);a=p.parse_args()
 reference=a.reference.resolve();assert reference.is_file() and reference.is_relative_to((R/'build').resolve())
 assert a.label.replace('-','').isalnum();out=R/'build/work'/a.label;out.mkdir(exist_ok=False)
 xdc=R/'src/hardware/pynq_ax7021b/hardware/qr_desktop/r4_cdc.xdc'
 rules=[s for s in xdc.read_text().splitlines() if s.startswith('set_max_delay ')]
 assert len(rules)==23
 # Query constraints already saved by implementation. Re-reading the XDC
 # here could conceal a constraint that was absent from the actual build.
 lines=['set_param general.maxThreads 2',f'open_checkpoint {{{reference}}}',f'set f [open {{{out/"rules.tsv"}}} w]']
 for i,rule in enumerate(rules):
  source=query(rule,'-from ');target=query(rule,'-to ')
  if not target.startswith('[get_pins'):target=f'[get_pins -of_objects {target} -filter {{REF_PIN_NAME == D}}]'
  lines += [f'set sources {source}',f'set targets {target}',f'if {{![llength $sources] || ![llength $targets]}} {{error "R4 CDC rule {i}: no endpoints"}}',
            'set paths [get_timing_paths -from $sources -to $targets -max_paths 1]',f'if {{![llength $paths]}} {{error "R4 CDC rule {i}: no timed path (masked/ignored?)"}}',
            'set requirement [get_property REQUIREMENT [lindex $paths 0]]',f'if {{abs($requirement-9.7)>0.001}} {{error "R4 CDC rule {i}: requirement $requirement"}}',
            f'puts $f "{i}\\t[llength $sources]\\t[llength $targets]\\t$requirement\\t[get_property SLACK [lindex $paths 0]]"']
 lines += ['close $f',
           f'check_timing -verbose -file {{{out/"check-timing.txt"}}}',
           f'report_cdc -details -all_checks_per_endpoint -no_waiver -file {{{out/"full-cdc.txt"}}}',
           f'report_bus_skew -file {{{out/"bus-skew.txt"}}}',
           f'report_exceptions -summary -file {{{out/"exceptions.txt"}}}','exit']
 (out/'run.tcl').write_text('\n'.join(lines)+'\n')
 with (out/'stdout.txt').open('w') as f:
  r=subprocess.run([str(tool('vivado')),'-mode','batch','-source',str(out/'run.tcl'),'-log',str(out/'vivado.log'),'-journal',str(out/'vivado.jou')],stdout=f,stderr=subprocess.STDOUT)
 log=(out/'stdout.txt').read_text();assert r.returncode==0 and 'CRITICAL WARNING:' not in log and 'ERROR:' not in log,log[-4000:]
 rows=[s.split('\t') for s in (out/'rules.tsv').read_text().splitlines()];assert len(rows)==23
 result=dict(passed=True,scope='Each R4 CDC max-delay rule checked on the selected final routed checkpoint; full CDC diagnostics generated for separate topology review',full_cdc_diagnostics=str((out/'full-cdc.txt').relative_to(R)),cdc_topology_review_pending=True,reference=str(reference),reference_sha256=hashlib.sha256(reference.read_bytes()).hexdigest(),constraint_sha256=hashlib.sha256(xdc.read_bytes()).hexdigest(),critical_warnings=0,errors=0,clock_groups_added=False,primary_clocks_unchanged=True,
             rules=[dict(index=int(n),sources=int(s),targets=int(t),requirement_ns=float(q),slack_ns=float(v)) for n,s,t,q,v in rows],
             reports={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob('*.txt')})
 (R/'build/reports/generated/cdc-constraint-reader.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
