"""Package a newly qualified XSA using the bundled matched Linux/U-Boot inputs."""
from paths import PROJECT,tool
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,zipfile
from r4_device_tree import make_device_tree
from fetch_dependencies import acquire, lock, destination
def main():
    p=argparse.ArgumentParser();p.add_argument('label');a=p.parse_args();assert a.label.replace('-','').isalnum()
    acquire('platform', check=True)
    receipt=json.loads((PROJECT/'build/reports/generated'/a.label/'receipt.json').read_text())
    review=json.loads((PROJECT/'build/reports/generated'/a.label/'cdc-reviewed.json').read_text());assert review['passed']
    checkpoint=PROJECT/'build/work'/a.label/'ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.runs/impl_1/qr_desktop_top_routed.dcp'
    assert review['reference_sha256']==hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    xsa=PROJECT/receipt['xsa'];assert hashlib.sha256(xsa.read_bytes()).hexdigest()==receipt['xsa_sha256']
    out=PROJECT/'build/outputs'/('boot-'+a.label);out.mkdir(parents=True,exist_ok=False);base=PROJECT/'src/platform/base_boot'
    shutil.copy2(base/'image.its',out/'image.its')
    for asset in lock()['groups']['platform']:shutil.copy2(destination('platform',asset),out/asset['file'])
    with zipfile.ZipFile(xsa) as z:
        bits=[n for n in z.namelist() if n.endswith('.bit')];assert len(bits)==1;(out/'system.bit').write_bytes(z.read(bits[0]))
    assert hashlib.sha256((out/'system.bit').read_bytes()).hexdigest()==receipt['bit_sha256']
    subprocess.run([str(tool('xsct')),str(PROJECT/'src/hardware/build_fsbl.tcl'),str(xsa),str(out/'fsbl.elf')],check=True)
    readelf=shutil.which('arm-none-eabi-readelf') or shutil.which('readelf');assert readelf,'Install GNU binutils/readelf'
    header=subprocess.check_output([readelf,'-h',str(out/'fsbl.elf')],text=True);assert 'ELF32' in header and re.search(r'Machine:\s+ARM\b',header);(out/'fsbl_elf_header.txt').write_text(header)
    (out/'system.dts').write_text(make_device_tree((base/'system.dts').read_text()))
    subprocess.run([str(tool('dtc')),'-I','dts','-O','dtb','-o',str(out/'system.dtb'),str(out/'system.dts')],check=True)
    subprocess.run(['mkimage','-f','image.its','image.ub'],cwd=out,check=True)
    (out/'static-boot.bif').write_text('the_ROM_image:\n{\n [bootloader] fsbl.elf\n system.bit\n u-boot.elf\n [load=0x100000] system.dtb\n}\n')
    subprocess.run([str(tool('bootgen')),'-image','static-boot.bif','-arch','zynq','-o','BOOT.BIN','-w'],cwd=out,check=True)
    result=dict(xsa_sha256=receipt['xsa_sha256'],sha256={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in out.iterdir() if f.is_file()},deployed=False)
    (out/'build_receipt.json').write_text(json.dumps(result,indent=2)+'\n');print('BOOT_PACKAGED',out)
if __name__=='__main__':main()
