"""Verify the small source submission without requiring generated firmware."""
from paths import PROJECT
import argparse,ast,hashlib,json,os,subprocess,xml.etree.ElementTree as ET

def sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda:handle.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()

def files():
    for directory,dirs,names in os.walk(PROJECT):
        from pathlib import Path
        path=Path(directory);relative=path.relative_to(PROJECT)
        dirs[:]=[n for n in dirs if n not in ['.git','.venv','.agents','.codex','.aws','__pycache__'] and not (relative.as_posix()=='build' and n in ['work','outputs','deps']) and not (relative.as_posix()=='board' and n in ['boot','runtime']) and not (relative.as_posix() in ['build/reports','sim/results'] and n=='generated')]
        for name in names:
            p=path/name
            if p==PROJECT/'build/MANIFEST.json':continue
            assert not p.is_symlink(),p
            yield p

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dependencies',action='store_true',help='Also check downloaded kernel/platform dependencies')
    args=parser.parse_args()
    manifest=json.loads((PROJECT/'build/MANIFEST.json').read_text());actual={p.relative_to(PROJECT).as_posix():p for p in files()}
    assert set(actual)==set(manifest['sha256']),'Source inventory differs'
    for name,path in actual.items():assert sha(path)==manifest['sha256'][name],name
    total=sum(p.stat().st_size for p in actual.values())+(PROJECT/'build/MANIFEST.json').stat().st_size
    assert total<200_000_000,'Source content exceeds 200 MB'
    assert not any(p.suffix.lower() in ['.dcp','.bit','.xsa','.elf','.ko','.ub'] for p in actual.values()),'Generated firmware in source inventory'
    assert not any('kernel-sdk.tar.gz' in n for n in actual),'SDK archive in source inventory'
    from fetch_dependencies import lock,acquire
    dependencies=lock();sdk=json.loads((PROJECT/'src/vendor/kernel-sdk.json').read_text())
    assert dependencies['groups']['kernel-sdk']==sdk['chunks']
    assert dependencies['kernel_release']==sdk['kernel_release']
    assert sha(PROJECT/'src/platform/kernel/kernel.config')==sdk['config_sha256']
    assert sha(PROJECT/'src/platform/kernel/Module.symvers')==sdk['module_symvers_sha256']
    checked=[acquire(g,check=True) for g in dependencies['groups']] if args.dependencies else []
    paired=0
    for rtl in (PROJECT/'src/rtl').glob('*.v'):
        hardware=PROJECT/'src/hardware/pynq_ax7021b/hardware/qr_desktop/roi_selection/rtl'/rtl.name
        assert hardware.is_file() and sha(hardware)==sha(rtl),rtl.name
        paired+=1
    ip=PROJECT/'src/vendor/fitness_ip';component=ET.parse(ip/'component.xml').getroot();namespace={'s':'http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009'}
    ip_files=component.findall('.//s:file/s:name',namespace)
    for entry in ip_files:
        path=(ip/entry.text).resolve();assert path.is_relative_to(ip.resolve()) and path.is_file(),entry.text
    for name in ['c04-r4-camera.service','c04-r4-recognition.service']:
        text=(PROJECT/'board/control/systemd'/name).read_text();assert '[Install]' not in text and 'WantedBy=' not in text and '/opt/zynq-qr/runtime/' in text
    camera_unit=(PROJECT/'board/control/systemd/c04-r4-camera.service').read_text()
    assert 'ExecStart=/usr/local/share/pynq-venv/bin/python -B /usr/local/lib/zynq-qr-camera/camera_control.py start-preview' in camera_unit
    for name in ['camera_control.py','capture_gray.py','ov5640_720p.json']:
        assert sha(PROJECT/'src/software/camera'/name)==sha(PROJECT/'board/control/camera'/name),name
    assert sha(PROJECT/'src/software/tools/zynq-qr-data.py')==sha(PROJECT/'board/control/zynq-qr-data')
    camera=ast.parse((PROJECT/'src/software/camera/camera_control.py').read_text())
    table_sha=next(ast.literal_eval(node.value) for node in camera.body if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='TABLE_SHA' for t in node.targets))
    assert sha(PROJECT/'src/software/camera/ov5640_720p.json')==table_sha
    for folder in ['build/scripts','sim/scripts','sim/tests','board/control','src/software/python','src/software/camera','src/software/tools']:
        for path in (PROJECT/folder).rglob('*.py'):ast.parse(path.read_text(),filename=str(path))
    for path in [PROJECT/'board/install.sh',PROJECT/'board/ssh_control.sh',PROJECT/'board/control/zynq-qr',PROJECT/'board/control/zynq-qr-camera']:subprocess.run(['sh','-n',str(path)],check=True)
    print(json.dumps(dict(passed=True,source_files=len(actual)+1,source_bytes=total,source_limit_bytes=200_000_000,paired_rtl=paired,local_hls_ip_files=len(ip_files),manual_only_units=True,default_aec_agc=True,dependency_groups_checked=checked,full_hardware_rebuilt=False),indent=2))
if __name__=='__main__':main()
