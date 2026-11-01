#!/usr/bin/env python3
"""Run the copy inside /var/backups/zynq-qr/<id> to restore pre-install controls."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

if os.geteuid()!=0:raise SystemExit('Run with sudo')
root=Path(__file__).resolve().parent
record=json.loads((root/'recovery.json').read_text())
units=list(record['services'])
for target,meta in record['files'].items():
    if meta['existed'] and 'link_target' not in meta:
        saved=root/'files'/target.lstrip('/')
        assert hashlib.sha256(saved.read_bytes()).hexdigest()==meta['sha256']
subprocess.run(['systemctl','stop',*reversed(units)],capture_output=True,check=False)
subprocess.run(['systemctl','disable',*units],capture_output=True,check=False)
for target,meta in record['files'].items():
    path=Path(target)
    if meta['existed']:
        path.parent.mkdir(parents=True,exist_ok=True)
        temp=path.with_name(path.name+'.restore-new')
        assert not os.path.lexists(temp),'Restore temporary path already exists: '+str(temp)
        if 'link_target' in meta:temp.symlink_to(meta['link_target'])
        else:shutil.copy2(root/'files'/target.lstrip('/'),temp)
        temp.replace(path)
    else:path.unlink(missing_ok=True)
link=Path('/opt/zynq-qr/runtime')
if link.is_symlink():link.unlink()
if record['previous_runtime_link'] is not None:link.symlink_to(record['previous_runtime_link'])
subprocess.run(['systemctl','daemon-reload'],check=True)
for unit,state in record['services'].items():
    if state['enabled']=='enabled':subprocess.run(['systemctl','enable',unit],check=True,capture_output=True)
for unit,state in record['services'].items():
    if state['active']=='active':subprocess.run(['systemctl','start',unit],check=True,capture_output=True)
print(json.dumps(dict(restored=True,source=str(root))))
