"""Build the three production drivers from the bundled, relocatable Linux SDK."""
from paths import PROJECT
from kernel_sdk_bundle import restore
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tarfile
def main():
    p=argparse.ArgumentParser();p.add_argument('--label',default='modules');a=p.parse_args();assert a.label.replace('-','').isalnum()
    work=PROJECT/'build/work';work.mkdir(parents=True,exist_ok=True)
    sdk=work/'kernel-sdk';meta=json.loads((PROJECT/'src/vendor/kernel-sdk.json').read_text());bundle=work/'kernel-sdk.tar.gz'
    restore(PROJECT/'src/vendor',bundle if not sdk.exists() else None)
    if not sdk.exists():
        sdk.mkdir()
        with tarfile.open(bundle) as tar:
            for member in tar.getmembers():
                assert (sdk/member.name).resolve().is_relative_to(sdk.resolve())
                if member.issym():assert ((sdk/member.name).parent/member.linkname).resolve().is_relative_to(sdk.resolve())
                if member.islnk():assert (sdk/member.linkname).resolve().is_relative_to(sdk.resolve())
            tar.extractall(sdk)
    source=sdk/'kernel-source';artifact=sdk/'kernel-build'
    assert (artifact/'include/config/kernel.release').read_text().strip()==meta['kernel_release']
    assert hashlib.sha256((artifact/'.config').read_bytes()).hexdigest()==meta['config_sha256']
    cc=Path(os.environ.get('CC_ARM') or shutil.which('arm-linux-gnueabihf-gcc') or '');assert cc.is_file()
    out=work/'kernel'/a.label;module=out/'module';module.mkdir(parents=True,exist_ok=False);include=out/'include';include.mkdir()
    for f in (PROJECT/'src/software/kernel').iterdir():
        if f.is_file():shutil.copy2(f,module/f.name)
    for f in (PROJECT/'src/software/include').glob('*.h'):shutil.copy2(f,include/f.name)
    sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
    production={f.name:sha(f) for f in module.iterdir() if f.suffix in ['.c','.h']}
    cmd=['make','-j2','-C',str(source),'O='+str(artifact),'M='+str(module),'ARCH=arm','CROSS_COMPILE='+str(cc.with_name('arm-linux-gnueabihf-')),'modules']
    result=subprocess.run(cmd,capture_output=True,text=True);(out/'compile.txt').write_text(result.stdout+result.stderr)
    assert result.returncode==0,result.stdout+result.stderr
    modules={f.name:sha(f) for f in module.glob('*.ko')};assert set(modules)=={'ax7021b_qr_capture.ko','ax7021b_qr_fitness.ko','ax7021b_camera_display.ko'}
    for f in module.glob('*.ko'):assert ('vermagic='+meta['kernel_release']+' ').encode() in f.read_bytes()
    receipt=dict(loadable_module_built=True,fault_test_build=False,kernel_release=meta['kernel_release'],production_source_sha256=production,include_sha256={f.name:sha(f) for f in include.glob('*.h')},modules=modules,command=cmd,deployed=False)
    (out/'build_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print('KERNEL_BUILD_PASS',out)
if __name__=='__main__':main()
