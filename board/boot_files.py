"""Explicit boot/module installation or recovery; normal runtime install does not call this."""
import argparse,datetime,hashlib,json,os
from pathlib import Path
import shutil,subprocess

HERE=Path(__file__).resolve().parent
KERNEL='6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def replace(source,target):
    target.parent.mkdir(parents=True,exist_ok=True);temporary=target.with_name(target.name+'.zynq-new')
    assert not temporary.exists();shutil.copy2(source,temporary);assert sha(source)==sha(temporary);temporary.replace(target)
def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['install','restore']);p.add_argument('backup',type=Path,nargs='?');a=p.parse_args()
    if os.geteuid()!=0:raise SystemExit('Run with sudo on the board')
    units=['c04-r4-recognition.service','c04-r4-camera.service']
    if a.action=='restore':
        assert a.backup,'Supply the backup directory printed by install'
        backup=a.backup.resolve();record=json.loads((backup/'backup.json').read_text())
        for name,v in record['files'].items():
            if v['existed']:assert sha(backup/'files'/name.lstrip('/'))==v['sha256']
        for unit in units:subprocess.run(['systemctl','stop',unit],capture_output=True)
        for name,v in record['files'].items():
            target=Path(name)
            if v['existed']:replace(backup/'files'/name.lstrip('/'),target)
            else:target.unlink(missing_ok=True)
        subprocess.run(['depmod','-a',KERNEL],check=True);subprocess.run(['sync'],check=True)
        print('Boot/modules restored. Reboot manually; no camera was started.');return
    manifest=json.loads((HERE/'runtime/RUNTIME_MANIFEST.json').read_text())
    changes={Path('/boot')/n:HERE/'boot'/n for n in manifest['boot_sha256']}
    for n,h in manifest['boot_sha256'].items():assert sha(HERE/'boot'/n)==h
    for n in ['ax7021b_qr_capture.ko','ax7021b_qr_fitness.ko','ax7021b_camera_display.ko']:
        source=HERE/'runtime/kernel'/n;assert sha(source)==manifest['sha256']['kernel/'+n]
        changes[Path('/usr/lib/modules')/KERNEL/'updates'/n]=source
    changes[Path('/etc/modprobe.d/c04-r4-modules.conf')]=HERE/'control/c04-r4-modules.conf'
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup=Path('/var/backups/zynq-qr')/('boot-'+stamp);backup.mkdir(parents=True,mode=0o700)
    record=dict(files={},kernel=KERNEL,scope='Three /boot files, three release modules and one module-options config; no repartition or rootfs image replacement')
    for target in changes:
        v=dict(existed=target.exists());record['files'][str(target)]=v
        if target.exists():
            saved=backup/'files'/str(target).lstrip('/');saved.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(target,saved);v['sha256']=sha(saved)
    (backup/'backup.json').write_text(json.dumps(record,indent=2)+'\n');shutil.copy2(Path(__file__),backup/'boot_files.py')
    for unit in units:
        subprocess.run(['systemctl','stop',unit],capture_output=True)
        subprocess.run(['systemctl','disable',unit],capture_output=True)
    try:
        for target,source in changes.items():replace(source,target)
        subprocess.run(['depmod','-a',KERNEL],check=True);subprocess.run(['sync'],check=True)
    except BaseException:
        for name,v in record['files'].items():
            if v['existed']:replace(backup/'files'/name.lstrip('/'),Path(name))
            else:Path(name).unlink(missing_ok=True)
        subprocess.run(['sync'],check=True);raise
    print(json.dumps(dict(installed=True,backup=str(backup),reboot_required=True,camera_started=False)))
if __name__=='__main__':main()
