from paths import PROJECT,tool
"""Build the R3 single-score-pipeline whole-grid IP and retain evidence."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, xml.etree.ElementTree as ET

R = PROJECT
TOOL = tool('vitis-run')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def enrich_receipt(receipt):
    """Metadata also usable after a resumed long-running co-simulation."""
    source = R / 'src/hls'
    receipt.update(r3_kernel_source=str(source / 'qr_fitness.cpp'),
                   kernel_sha256=sha(source / 'qr_fitness.cpp'),
                   kernel_header_sha256=sha(source / 'qr_fitness.h'),
                   tree_header_sha256=sha(R / 'src/software/include/qr_fitness_tree.h'),
                   tool_executable=str(TOOL), tool_version='2025.2',
                   part='xc7z020clg484-2', clock_period_ns=10.0,
                   hls_csim_grid_versions=[1,20,40],
                   hls_csim_feature_counts=[161,638,1623])
    return receipt

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stage', choices=['csim', 'synth', 'cosim', 'all'], default='all')
    parser.add_argument('--work', type=Path, default=R / 'build/work/hls')
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    source = R / 'src/hls'
    reference = R / 'src/software/imported/quirc/identify.c'
    testbench = work / 'test_score.cpp'
    testbench.write_text((R / 'sim/hls_tests/test_score.cpp').read_text().replace(
        '"C04_IDENTIFY_REFERENCE"', '"' + str(reference) + '"'))
    native = work / 'native-score'
    subprocess.run(['g++', '-O2', '-std=c++14', '-ffp-contract=off', '-fno-fast-math',
                    '-I' + str(source), '-I' + str(R / 'src/software/include'),
                    '-I' + str(R / 'src/software/imported/quirc'),
                    '-I'+str(TOOL.parents[1]/'include'),
                    str(source / 'qr_fitness.cpp'), str(R / 'src/software/src/qr_fitness_tree.c'),
                    str(testbench), str(R / 'src/software/imported/quirc/version_db.c'),
                    '-o', str(native)], check=True)
    native_output = subprocess.check_output([str(native)], text=True)
    (work / 'native-score.log').write_text(native_output)
    assert 'WHOLE_GRID_REFERENCE_PASS grids=320 scores=25920' in native_output
    assert 'TREE_REFERENCE_PASS paths=5000 candidates=400000' in native_output
    legacy = work / 'native-legacy-score'
    subprocess.run(['g++', '-O2', '-std=c++14', '-ffp-contract=off', '-fno-fast-math',
                    '-I' + str(source), '-I' + str(R / 'src/software/include'),
                    '-I' + str(R / 'src/software/imported/quirc'),
                    '-I'+str(TOOL.parents[1]/'include'),
                    str(source / 'qr_fitness.cpp'), str(R / 'sim/hls_tests/test_score_legacy.cpp'),
                    str(R / 'src/software/imported/quirc/version_db.c'),
                    '-o', str(legacy)], check=True)
    legacy_output = subprocess.check_output([str(legacy)], text=True)
    (work / 'native-legacy-score.log').write_text(legacy_output)
    assert 'FITNESS_REFERENCE_PASS jobs=350' in legacy_output
    flags = ('-std=c++14 -O2 -ffp-contract=off -fno-fast-math '
             '-D_POSIX_C_SOURCE=200809L -I' + str(source) + ' -I' +
             str(R / 'src/software/include') + ' -I' + str(R / 'src/software/imported/quirc'))
    commands = []
    if args.stage in ('synth', 'all'):
        commands += ['csynth_design',
                     'export_design -format ip_catalog -vendor xiwei.org -library qr -version 2.0']
    commands += ['csim_design -argv reduced']
    if args.stage in ('all', 'cosim'):
        commands += ['cosim_design -rtl verilog -tool xsim -argv rtl_sparse']
    component = work / 'component'
    reset = '' if args.stage == 'cosim' else '-reset '
    if args.stage == 'cosim':
        assert (component / 'hls/syn/report/qr_fitness_csynth.xml').exists()
    command_text = '\n'.join(commands)
    tcl = f'''cd {{{work}}}
open_component {reset}{{{component}}} -flow_target vivado
set_top qr_fitness
set flags "{flags}"
add_files {{{source / 'qr_fitness.cpp'}}} -cflags $flags
add_files -tb {{{R / 'src/software/src/qr_fitness_tree.c'}}} -cflags "-O2 -ffp-contract=off -fno-fast-math -I{R / 'src/software/include'}"
add_files -tb {{{testbench}}} -cflags $flags
add_files -tb {{{R / 'src/software/imported/quirc/version_db.c'}}} -cflags "-I{R / 'src/software/imported/quirc'}"
set_part {{xc7z020clg484-2}}
create_clock -period 10 -name default
{command_text}
exit
'''
    (work / 'build.tcl').write_text(tcl)
    with (work / 'tool.log').open('w') as log:
        subprocess.run([str(TOOL), '--mode', 'hls', '--tcl', str(work / 'build.tcl')],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    output = component / 'hls'
    csim = output / 'csim/report/qr_fitness_csim.log'
    assert 'WHOLE_GRID_REFERENCE_PASS grids=3 scores=243' in csim.read_text()
    reports = [csim, work / 'native-score.log', work / 'native-legacy-score.log']
    receipt = dict(stage=args.stage, hardware_abi=2, requested_ii=2,
                   baseline_ii2_sha256='8ab0e9cefa51983f3eea724e4149565fc4b1e65e2c9ce1ebd54053e6a2417669',
                   r3_kernel_source=str(source / 'qr_fitness.cpp'),
                   kernel_sha256=sha(source / 'qr_fitness.cpp'),
                   tree_sha256=sha(R / 'src/software/src/qr_fitness_tree.c'),
                   testbench_sha256=sha(testbench), hls_csim_pass=True,
                   native_c_grids=320, native_c_scores=25920,
                   native_legacy_scores=350, native_explicit_rounding_clipping_cases=30,
                   hls_csim_grids=3, hls_csim_scores=243,
                   tree_paths=5000, tree_candidates=400000,
                   c_rtl_cosim_pass=False, board_tested=False)
    if args.stage != 'csim':
        report = output / 'syn/report/qr_fitness_csynth.xml'
        root = ET.parse(report).getroot()
        receipt['estimated_resources'] = {item.tag:int(item.text)
            for item in root.find('./AreaEstimates/Resources')}
        receipt['dsp_increment'] = receipt['estimated_resources']['DSP'] - 63
        receipt['lut_increment'] = receipt['estimated_resources']['LUT'] - 15607
        receipt['hls_estimate_within_lut_increment_budget'] = receipt['lut_increment'] <= 2000
        receipt['accepted'] = False
        receipt['acceptance_pending'] = 'Vivado actual joint resources, timing and board validation'
        assert receipt['dsp_increment'] <= 0, receipt
        pipelines = []
        for path in (output / 'syn/report').glob('*csynth.xml'):
            data = ET.parse(path).getroot()
            ii = data.find('.//PipelineII')
            if ii is not None and 'Pipeline' in path.name:
                depth = data.find('.//PipelineDepth')
                pipelines.append(dict(report=path.name, ii=int(ii.text),
                                      depth=int(depth.text) if depth is not None else 0))
                reports.append(path)
        samples = [item for item in pipelines if item['depth'] >= 80]
        assert len(samples) == 1, pipelines
        sample = samples[0]
        assert sample['ii'] == 2 and sample['depth'] >= 80, pipelines
        receipt['actual_ii'] = sample['ii']
        receipt['sample_pipeline_instances'] = 1
        receipt['pipelines'] = pipelines
        ip = output / 'impl/ip'
        receipt['ip'] = str(ip)
        receipt['ip_component_sha256'] = sha(ip / 'component.xml')
        headers = list((ip / 'drivers').glob('qr_fitness_v*/src/xqr_fitness_hw.h'))
        assert len(headers) == 1, headers
        header = headers[0]
        shutil.copyfile(header, work / 'qr_fitness_registers.h')
        receipt['registers_sha256'] = sha(header)
        reports += [report]
    if args.stage in ('all', 'cosim'):
        cosim = output / 'sim/report/qr_fitness_cosim.rpt'
        assert re.search(r'Verilog\s*\|\s*Pass', cosim.read_text())
        receipt['c_rtl_cosim_pass'] = True
        receipt['rtl_grid_versions'] = [1,20,40]
        receipt['rtl_feature_counts'] = [9,9,9]
        receipt['rtl_evaluations_per_grid'] = 81
        receipt['rtl_full_feature_lists_verified'] = False
        receipt['rtl_comparison'] = 'C04 fitness_cell weighted selected cells; every score, decision and final coefficient'
        reports += [cosim]
    retained = R / 'build/reports/generated/hls'
    retained.mkdir(parents=True, exist_ok=True)
    receipt['reports'] = {}
    for report in reports:
        name = report.name + '.txt' if report.suffix in ('.log', '.rpt') else report.name
        shutil.copyfile(report, retained / name)
        receipt['reports'][name] = sha(report)
    enrich_receipt(receipt)
    (retained / 'result.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))

if __name__ == '__main__':
    main()
