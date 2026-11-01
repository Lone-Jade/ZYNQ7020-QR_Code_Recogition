"""Recreate R4 hardware from local source/IP; never depends on a saved Vivado project."""
from paths import PROJECT
import sys
import json
import ac_build_hw
from r4_hw_connections import verify

ac_build_hw.ROOT=PROJECT
original=ac_build_hw.render_standard_tcl
def render(work,source):
    verify(work)
    return original(work,source)
ac_build_hw.render_standard_tcl=render
if __name__=='__main__':
    if '--fitness-ip-dir' not in sys.argv:sys.argv+=['--fitness-ip-dir',str(PROJECT/'src/vendor/fitness_ip')]
    if '--fitness-receipt' not in sys.argv:sys.argv+=['--fitness-receipt',str(PROJECT/'build/reference/hls.json')]
    from pathlib import Path
    receipt=json.loads(Path(sys.argv[sys.argv.index('--fitness-receipt')+1]).read_text())
    assert receipt['hardware_abi']==2 and receipt['actual_ii']==2 and receipt['sample_pipeline_instances']==1
    sys.argv+=['--fitness','--fitness-vlnv','xiwei.org:qr:qr_fitness:2.0','--capture-layout','gray','--payload-bram','1']
    ac_build_hw.main()
