"""Build the unchanged R4 ARM library/CLI, or a native functional-test library."""
from paths import PROJECT
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile
CORE=['src/qr_mainline_linux.c','src/qr_candidate_version.c','imported/common/qr_pipeline.c','imported/common/qr_decode_backend.c',
      *['imported/app/'+x+'.c' for x in ['qr_pl_roi_protocol','qr_quirc_fallback','qr_quirc_identify_replay','qr_tracker','qr_publication','qr_decode_scheduler']],
      *['imported/quirc/'+x+'.c' for x in ['quirc','decode','version_db']],
      'src/capture_hal.c','src/qr_candidate_schedule.c','src/qr_fitness_backend.c','src/qr_binary_pack.c','src/qr_fitness_tree.c']
INCLUDES=['include','compat','imported/common','imported/app','imported/quirc','imported/camera']
def main():
    p=argparse.ArgumentParser();mode=p.add_mutually_exclusive_group();mode.add_argument('--host',action='store_true');mode.add_argument('--native',action='store_true');p.add_argument('--cc');p.add_argument('--label',default='arm');a=p.parse_args()
    assert a.label.replace('-','').isalnum()
    source=PROJECT/'src/software';out=PROJECT/'build/work'/a.label;out.mkdir(parents=True,exist_ok=False)
    cc=a.cc or os.environ.get('CC_HOST' if a.host or a.native else 'CC_ARM') or shutil.which('gcc' if a.host or a.native else 'arm-linux-gnueabihf-gcc')
    assert cc,'Set CC_ARM or install arm-linux-gnueabihf-gcc'
    cc=Path(cc).resolve();meta=json.loads((source/'version.json').read_text())
    flags=['-std=c11','-O2','-g','-fPIC','-DQR_CAMERA_LIVE=0','-DQR_CANDIDATE_LEVEL='+str(meta['level']),'-DQR_DECODE_BUDGET_US=60000U','-D_POSIX_C_SOURCE=200809L','-ffp-contract=off','-fno-fast-math']
    flags+=['-DQR_HOST_TEST=1','-Dclock_gettime=qr_test_clock_gettime','-I'+str(source/'tests/host_compat')] if a.host else [] if a.native else ['-mcpu=cortex-a9','-mfpu=neon','-mfloat-abi=hard','-marm']
    flags+=['-I'+str(source/x) for x in INCLUDES];commands=[]
    def run(cmd):
        commands.append(cmd);v=subprocess.run(cmd,capture_output=True,text=True)
        if v.returncode:raise RuntimeError(v.stdout+v.stderr)
        return v.stdout
    with tempfile.TemporaryDirectory(dir=out) as temporary:
        objects=[];inputs=[x for x in CORE if not(a.host and x=='src/capture_hal.c')]
        if a.host:inputs+=['tests/host_hal.c']
        for i,name in enumerate(inputs):
            obj=str(Path(temporary)/f'{i}.o');run([str(cc),*flags,'-c',str(source/name),'-o',obj]);objects.append(obj)
        library=out/('qr_candidate.dll' if a.host else 'libqr_mainline.so.1')
        link=['-Wl,-Bsymbolic']+(['-pthread'] if a.host else ['-Wl,-soname,libqr_mainline.so.1','-Wl,--no-undefined'])
        run([str(cc),*flags,'-shared',*link,*objects,'-lm','-o',str(library)])
    artifacts=[library]
    if not a.host and not a.native:
        exe=out/'qr-mainline';run([str(cc),*flags,str(source/'src/qr_mainline_cli.c'),str(library),'-lm','-Wl,-rpath,$ORIGIN/../lib','-o',str(exe)]);artifacts.append(exe)
        readelf=shutil.which('arm-linux-gnueabihf-readelf') or str(cc.parent/'arm-linux-gnueabihf-readelf')
        for f in artifacts:
            audit=run([str(readelf),'-h','-A','-d','--version-info',str(f)])
            assert all(t in audit for t in ['ELF32','ARM','NEONv1','VFP registers'])
            (out/(f.name+'.elf.txt')).write_text(audit)
    sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
    result=dict(build_passed=True,kind='host-mock' if a.host else 'native-functional' if a.native else 'arm',candidate_id=meta['id'],compiler=run([str(cc),'--version']).splitlines()[0],commands=commands,artifacts={f.name:sha(f) for f in artifacts},source_sha256={f.relative_to(source).as_posix():sha(f) for f in source.rglob('*') if f.is_file() and f.suffix in ['.c','.h','.inc']},deployed=False)
    (out/'build_receipt.json').write_text(json.dumps(result,indent=2)+'\n');print('SOFTWARE_BUILD_PASS',out)
if __name__=='__main__':main()
