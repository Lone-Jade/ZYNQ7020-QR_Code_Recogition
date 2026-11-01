"""Re-run implementation/CDC gates; topology review must bind the new routed DCP."""
from paths import PROJECT
import argparse,hashlib,json,subprocess,sys
import ac_record_hw
from r4_record_hw import check
def main():
    p=argparse.ArgumentParser();p.add_argument('label');p.add_argument('--cdc-review');a=p.parse_args();label=a.label;assert label.replace('-','').isalnum()
    reports=PROJECT/'build/reports/generated';reports.mkdir(parents=True,exist_ok=True)
    ac_record_hw.ROOT=PROJECT;ac_record_hw.RESOURCE_LIMITS={'Slice LUTs':100,'Block RAM Tile':85,'DSPs':85}
    sys.argv=[sys.argv[0],label,'--fitness'];ac_record_hw.main()
    checkpoint=PROJECT/'build/work'/label/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.runs/impl_1/qr_desktop_top_routed.dcp'
    if not (PROJECT/'build/work'/(label+'-cdc')).exists():
        subprocess.run([sys.executable,'-B',str(PROJECT/'build/scripts/r4_validate_cdc.py'),'--reference',str(checkpoint),'--label',label+'-cdc'],check=True)
    else:
        reader=json.loads((reports/'cdc-constraint-reader.json').read_text())
        assert reader['passed'] and reader['reference_sha256']==hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    result=check(label)
    if not a.cdc_review:raise SystemExit('Bounds passed; inspect the full CDC diagnostics and provide --cdc-review JSON with passed=true and matching reference_sha256 before boot packaging')
    from pathlib import Path
    review=json.loads(Path(a.cdc_review).read_text());assert review['passed'] and review['reference_sha256']==hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    reader=reports/'cdc-constraint-reader.json';value=json.loads(reader.read_text());value['cdc_topology_review_pending']=False;reader.write_text(json.dumps(value,indent=2)+'\n')
    (reports/label/'cdc-reviewed.json').write_text(json.dumps(review,indent=2)+'\n');print('QUALIFICATION_PASS',result)
if __name__=='__main__':main()
