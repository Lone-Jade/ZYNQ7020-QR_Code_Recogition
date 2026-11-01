#!/usr/local/share/pynq-venv/bin/python
"""Check artifacts and driver status without reopening the exclusive capture device."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode=True
runtime=Path('/opt/zynq-qr/runtime').resolve()
KERNEL='6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68'


def verify_runtime(root):
    manifest=json.loads((root/'RUNTIME_MANIFEST.json').read_text())
    actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and p.name!='RUNTIME_MANIFEST.json'}
    assert actual==set(manifest['sha256']),'Runtime file inventory mismatch'
    for name,wanted in manifest['sha256'].items():
        p=root/name
        assert not p.is_symlink() and hashlib.sha256(p.read_bytes()).hexdigest()==wanted,name
    return manifest


def display_status():
    # Avoid package __init__, which imports the Gray8 NumPy capture stack.
    # The unchanged display module itself uses only the Python standard library.
    spec=importlib.util.spec_from_file_location('_zynq_status_display',runtime/'python/ax7021b_qr/r4_display.py')
    module=importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
    d=module.DisplayDevice()
    try:return d.status()
    finally:d.close()


def inspect():
    manifest=verify_runtime(runtime)
    assert os.uname().release==KERNEL,'Kernel release mismatch'
    for name,wanted in manifest['boot_sha256'].items():
        assert hashlib.sha256((Path('/boot')/name).read_bytes()).hexdigest()==wanted,'Boot mismatch: '+name
    for name in ['ax7021b_qr_capture.ko','ax7021b_qr_fitness.ko','ax7021b_camera_display.ko']:
        path=Path('/usr/lib/modules')/KERNEL/'updates'/name
        assert hashlib.sha256(path.read_bytes()).hexdigest()==manifest['sha256']['kernel/'+name],name
    units={}
    for name in ['c04-r4-camera.service','c04-r4-recognition.service']:
        text=subprocess.check_output(['systemctl','show',name,'-p','ActiveState,SubState,MainPID,UnitFileState,ExecMainStatus'],text=True)
        units[name]=dict(line.split('=',1) for line in text.splitlines())
    running=all(s['ActiveState']=='active' for s in units.values())
    stopped=all(s['ActiveState']=='inactive' for s in units.values())
    display=None
    if Path('/dev/ax7021b-display0').exists():
        display=display_status()
        assert not display['flags']&6
        assert not any(display[k] for k in ['monitor_errors','dma_errors','recoveries','quarantined'])
    ready=False
    if running:
        pid=units['c04-r4-recognition.service']['MainPID'];proc=Path('/proc')/pid
        try:
            targets=[]
            for fd in (proc/'fd').iterdir():
                try:targets.append(os.readlink(fd))
                except FileNotFoundError:pass
            ready=str(runtime/'lib/libqr_mainline.so.1') in (proc/'maps').read_text() and '/dev/ax7021b-qr0' in targets
        except FileNotFoundError:pass
    return dict(state='running' if running and ready else 'starting' if running else 'stopped' if stopped else 'transition',
                runtime=str(runtime),runtime_manifest_sha256=hashlib.sha256((runtime/'RUNTIME_MANIFEST.json').read_bytes()).hexdigest(),
                boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),kernel=KERNEL,
                units=units,display=display,artifact_integrity=True,manual_start_only=True)


def main():
    p=argparse.ArgumentParser();p.add_argument('--wait',type=float,default=0)
    state=p.add_mutually_exclusive_group();state.add_argument('--require-running',action='store_true');state.add_argument('--require-stopped',action='store_true');a=p.parse_args()
    deadline=time.monotonic()+a.wait
    while True:
        value=inspect()
        good=(not a.require_running or value['state']=='running' and value['display'] and value['display']['running']) and (not a.require_stopped or value['state']=='stopped' and (not value['display'] or not value['display']['running']))
        if good or time.monotonic()>=deadline:break
        time.sleep(.5)
    print(json.dumps(value,indent=2))
    if not good:raise SystemExit('Requested state was not reached')


if __name__=='__main__':main()
