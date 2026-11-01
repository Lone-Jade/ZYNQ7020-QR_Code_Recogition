"""Persist failed-target diagnostics only; discard successful-frame/image data."""
from collections import Counter
import csv
import hashlib
import io
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent
ERRORS={0:'SUCCESS',1:'INVALID_GRID_SIZE',2:'INVALID_VERSION',3:'FORMAT_ECC',4:'DATA_ECC',5:'UNKNOWN_DATA_TYPE',6:'DATA_OVERFLOW',7:'DATA_UNDERFLOW'}


def save(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')


def retain(folder,report,events,truth_csv,browser_states=()):
    folder=Path(folder).resolve()
    assert folder.is_relative_to((ROOT/'board_runs').resolve())
    targets=list(csv.DictReader(io.StringIO(truth_csv.lstrip('\ufeff'))))
    missed=set(report['missed_payloads']);out=folder/'failure_data';out.mkdir(exist_ok=True)
    frames=[r for r in events if r.get('type')=='frame']
    failures=[]
    for t in targets:
        if t['payload'] not in missed:continue
        start=float(t.get('first_roi_intersect_epoch_ms') or t['generated_epoch_ms'])-600
        end=float(t.get('roi_exit_epoch_ms') or t.get('last_roi_full_epoch_ms') or start+20000)+600
        window=[r for r in frames if start<=r['host_epoch_ms']<=end]
        trace=[];hist=Counter();raw_success=[]
        for row in window:
            attempts=row.get('decode_attempts',[])
            errors=[{k:a.get(k) for k in ('error','mirrored','rejected','roi_otsu_threshold')} for a in attempts if a['error']!=0]
            hist.update(ERRORS.get(a['error'],str(a['error'])) for a in attempts if a['error']!=0)
            if any(a['error']==0 and a.get('payload')==t['payload'] for a in attempts):raw_success.append(row['pl_frame_sequence'])
            trace.append({k:row.get(k) for k in ['host_epoch_ms','pl_frame_sequence','pl_epoch','threshold','roi_count','roi_decode_calls','elapsed_us','soft_budget_exceeded','regions','pl_diagnostics','candidate_id','roi_trace_schema','roi_traces']} | {'decode_errors_not_target_specific':errors})
            if 'timing_ms' in row:trace[-1]['timing_ms']=row['timing_ms']
        suspects=[]
        if any(r.get('soft_budget_exceeded') for r in window):suspects.append('ROI_BUDGET_EXCEEDED_IN_WINDOW')
        if any(r.get('roi_decode_calls',0)>0 and not r.get('decode_attempts') for r in window):suspects.append('ROI_CALLS_WITHOUT_GRID_DECODE_ATTEMPTS')
        if hist.get('DATA_ECC'):suspects.append('DATA_ECC_ERRORS_IN_WINDOW')
        if any(r.get('pl_diagnostics',{}).get('counters',{}).get('flags',0)&8 for r in window):suspects.append('CLUSTER_CAPACITY_REACHED_IN_WINDOW')
        reason='RAW_SUCCESS_NOT_IN_RESULT' if raw_success else 'NO_PL_ROI_IN_WINDOW' if window and all(r.get('roi_count',0)==0 for r in window) else 'UNRESOLVED_WITHOUT_IMAGES'
        item=dict(payload=t['payload'],pitch=int(t['pitch']),angle_deg=float(t['angle_deg']),lane=int(t['lane']),
            time_window_host_epoch_ms=[start,end],reason=reason,
            confidence='confirmed raw/result discrepancy' if raw_success else 'window-level evidence; target-specific cause not established',
            suspected_stages=suspects,raw_success_pl_frames=raw_success,error_histogram_not_target_specific=dict(hist),
            diagnostics=trace,
            browser_positions=[dict(host_epoch_ms=b['host_epoch_ms'],targets=[x for x in b.get('targets',[]) if x['payload']==t['payload']])
                for b in browser_states if start<=b['host_epoch_ms']<=end and any(x['payload']==t['payload'] for x in b.get('targets',[]))],
            note='No images retained. Other QR codes can share this time window; error counts and capacity/budget flags are not a unique causal attribution.')
        failures.append(item)
    assert {f['payload'] for f in failures}==missed
    save(out/'failures.json',failures)
    with (out/'missed_targets.csv').open('w',encoding='utf-8-sig',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=['payload','pitch','angle_deg','lane','reason','confidence'])
        writer.writeheader();writer.writerows({k:f[k] for k in writer.fieldnames} for f in failures)
    compact={k:report[k] for k in ['simulated','complete','failure_reasons','remote_folder','metric','recall','counts','missed_payloads','unexpected_payloads','hdmi_display','overlay_revision'] if k in report}
    compact['counts'].pop('output_events',None)
    compact.update(storage_policy='failed-target metadata only; no images',images_retained=False,
                   diagnosis_path='failure_data/failures.json')
    if report.get('performance'):
        compact['performance']=report['performance']
        compact['display_mode']=report.get('display_mode')
        compact['pipeline_revision']=report.get('pipeline_revision')
    save(folder/'report.json',compact)
    for name in ['config_snapshot.json']:
        p=folder/name
        if p.exists():
            config=json.loads(p.read_text(encoding='utf-8'));seq=config.get('test',{}).pop('targetSequence',None)
            if seq:config['target_sequence_sha256']=hashlib.sha256(json.dumps(seq,sort_keys=True).encode()).hexdigest()
            save(p,config)
    for name in ['linux_events.jsonl','truth.csv','browser_targets.jsonl','display_at_start.json','session.json','worker_end.json','worker_stdout_other.log','worker_stderr.log']:
        p=folder/name
        if p.exists():p.unlink()
    for name in ['board_evidence','failure_analysis']:
        directory=folder/name
        if directory.exists():
            assert directory.resolve().parent==folder
            for p in directory.iterdir():
                assert p.is_file() and not p.is_symlink(),str(p)
                p.unlink()
            directory.rmdir()
    return compact


def convert_existing(suite):
    suite=Path(suite);manifest=json.loads((suite/'manifest.json').read_text(encoding='utf-8'))
    for group in manifest['rounds']:
        folder=Path(group['output_dir']);report=json.loads((folder/'report.json').read_text(encoding='utf-8'))
        if not (folder/'failure_data/failures.json').exists():
            events=[json.loads(x) for x in (folder/'linux_events.jsonl').read_text(encoding='utf-8').splitlines()]
            browser=[json.loads(x) for x in (folder/'browser_targets.jsonl').read_text(encoding='utf-8').splitlines()] if (folder/'browser_targets.jsonl').exists() else []
            retain(folder,report,events,(folder/'truth.csv').read_text(encoding='utf-8-sig'),browser)
        group['export_complete']=True;group['storage_policy']='failures-only';group.pop('processed_gray_frames',None)
        print('Retained failures only:',group['round'],group['run_id'],flush=True)
    manifest['storage_policy']='failures-only metadata; no images'
    save(suite/'manifest.json',manifest)


if __name__=='__main__':
    import sys
    convert_existing(sys.argv[1])
