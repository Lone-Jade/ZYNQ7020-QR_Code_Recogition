#!/usr/bin/env python3
"""Install a hash-bound runtime and manual-only systemd commands on the board."""
import argparse
import datetime
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
UNITS=['c04-r4-camera.service','c04-r4-recognition.service']
FILES={Path('/etc/systemd/system')/n:HERE/'systemd'/n for n in UNITS}
FILES.update({Path('/usr/local/sbin/zynq-qr'):HERE/'zynq-qr',
              Path('/usr/local/libexec/zynq-qr-status.py'):HERE/'zynq-qr-status.py',
              Path('/etc/modprobe.d/c04-r4-modules.conf'):HERE/'c04-r4-modules.conf',
              Path('/usr/local/bin/zynq-qr-camera'):HERE/'zynq-qr-camera',
              Path('/usr/local/bin/zynq-qr-data'):HERE/'zynq-qr-data'})
FILES.update({Path('/usr/local/lib/zynq-qr-camera')/name:HERE/'camera'/name
              for name in ['camera_control.py','capture_gray.py','ov5640_720p.json']})


def run(*args):return subprocess.run(args,check=True,capture_output=True,text=True)
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def bind_camera_runtime(text, digest):
    """Bind the installed camera controller to this verified rebuild."""
    if not re.fullmatch(r'[0-9a-f]{64}', digest):
        raise ValueError('Invalid runtime SHA-256')
    text, count = re.subn(r"(?m)^RUNTIME_SHA = '[0-9a-f]{64}'$",
                          "RUNTIME_SHA = '" + digest + "'", text)
    if count != 1:
        raise ValueError('Expected one camera runtime binding')
    return text


def main():
    p=argparse.ArgumentParser();p.add_argument('runtime',type=Path);a=p.parse_args()
    if os.geteuid()!=0:raise SystemExit('Run with sudo')
    rt=a.runtime.resolve();m=json.loads((rt/'RUNTIME_MANIFEST.json').read_text())
    digest=sha(rt/'RUNTIME_MANIFEST.json')
    actual={p.relative_to(rt).as_posix() for p in rt.rglob('*') if p.is_file() and p.name!='RUNTIME_MANIFEST.json'}
    assert actual==set(m['sha256'])
    for name,wanted in m['sha256'].items():assert sha(rt/name)==wanted,name
    for name,wanted in m['boot_sha256'].items():assert sha(Path('/boot')/name)==wanted,name
    assert os.uname().release=='6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68'
    for name in ['ax7021b_qr_capture.ko','ax7021b_qr_fitness.ko','ax7021b_camera_display.ko']:
        assert sha(Path('/usr/lib/modules')/os.uname().release/'updates'/name)==m['sha256']['kernel/'+name]
    for path in FILES.values():assert path.is_file(),path
    run('systemd-analyze','verify',*[str(HERE/'systemd'/n) for n in UNITS])
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup=Path('/var/backups/zynq-qr')/stamp;backup.mkdir(parents=True,mode=0o700)
    link=Path('/opt/zynq-qr/runtime')
    record=dict(runtime_manifest_sha256=digest,files={},services={},
                previous_runtime_link=os.readlink(link) if link.is_symlink() else None)
    assert not link.exists() or link.is_symlink(),'Existing runtime must be a managed symlink'
    for target in FILES:
        exists=os.path.lexists(target)
        meta=record['files'][str(target)]=dict(existed=exists)
        if target.is_symlink():
            meta['link_target']=os.readlink(target)
        elif exists:
            assert target.is_file(),'Existing control target must be a file or symlink: '+str(target)
            saved=backup/'files'/str(target).lstrip('/');saved.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(target,saved);meta['sha256']=sha(saved)
    for name in UNITS:
        record['services'][name]=dict(enabled=subprocess.getoutput('systemctl is-enabled '+name),
                                      active=subprocess.getoutput('systemctl is-active '+name))
    (backup/'recovery.json').write_text(json.dumps(record,indent=2)+'\n')
    # This small self-contained recovery entry works even if the new CLI is damaged.
    shutil.copyfile(HERE/'restore_manual.py',backup/'restore.py')
    try:
        run('systemctl','stop',*reversed(UNITS))
        run('systemctl','disable',*UNITS)
        destination=Path('/opt/zynq-qr/releases')/digest
        if not destination.exists():
            destination.parent.mkdir(parents=True,exist_ok=True)
            shutil.copytree(rt,destination)
        assert sha(destination/'RUNTIME_MANIFEST.json')==digest
        for name,wanted in m['sha256'].items():assert sha(destination/name)==wanted,name
        temporary=link.with_name('runtime.new');assert not os.path.lexists(temporary)
        temporary.symlink_to(Path('releases')/digest);temporary.replace(link)
        for target,source in FILES.items():
            target.parent.mkdir(parents=True,exist_ok=True)
            temp=target.with_name(target.name+'.manual-new');assert not os.path.lexists(temp)
            if source==HERE/'camera/camera_control.py':temp.write_text(bind_camera_runtime(source.read_text(),digest))
            else:shutil.copyfile(source,temp)
            temp.chmod(0o644 if target.suffix in ['.service','.conf','.json'] else 0o755);temp.replace(target)
        run('systemctl','daemon-reload')
        # No WantedBy section: even accidental enable cannot wire these units into boot.
        for name in UNITS:
            assert subprocess.getoutput('systemctl is-enabled '+name)=='static'
            assert subprocess.getoutput('systemctl is-active '+name)=='inactive'
        status=json.loads(run('/usr/local/sbin/zynq-qr','stop').stdout)
        assert status['state']=='stopped'
        run('sync')
        reboot_required=False
        for module,parameter,wanted in [('ax7021b_qr_capture','early_rearm','Y'),('ax7021b_qr_fitness','optimize_writes','Y'),('ax7021b_qr_fitness','profile','N')]:
            path=Path('/sys/module')/module/'parameters'/parameter
            if path.exists() and path.read_text().strip()!=wanted:reboot_required=True
        result=dict(passed=True,manual_start_only=True,reboot_required=reboot_required,runtime=str(destination),runtime_manifest_sha256=digest,
                    recovery=str(backup/'restore.py'),backup=str(backup),status=status)
        (backup/'installed.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result))
    except BaseException:
        subprocess.run([sys.executable,'-B',str(backup/'restore.py')],check=True)
        raise


if __name__=='__main__':main()
