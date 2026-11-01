"""Coherent dynamic PL diagnostics; static configuration is read once at startup.

Retains every dynamic counter and union diagnostic used for missed-target
analysis. The 16-bin score histogram is explicitly omitted from frame events.
The producer generation brackets all reads, as in the full startup probe.
"""
REVISION = 'dynamic-counters-v1'
COUNTERS = ('quality_completed', 'score_rejected', 'finder_comparisons',
    'iou_comparisons', 'no_intersection', 'selection_cycles', 'finder_rejected',
    'iou_rejected', 'bridge_rejected', 'replaced', 'top30_evicted',
    'top30_rejected', 'roi_count', 'flags', 'raw_count', 'cluster_count')


def frame_probe(q, startup):
    if not startup['extended_diagnostics']:
        return dict(extended_diagnostics=False, detail_scope=REVISION)
    union = startup['algorithm_id'] == '0x524f4902'
    for _ in range(5):
        generation = q.read(0x128)
        if generation & 1:
            continue
        frame, epoch = q.read(0x12c), q.read(0x130)
        cycles, comparisons = q.read(0x134), q.read(0x138)
        counters = {name:q.read(0x140+4*i) for i,name in enumerate(COUNTERS)}
        union_diagnostics = ({name:q.read(0x1c0+4*i) for i,name in enumerate(
            ('mode','committed_merges','absorbed_old','rescans','max_members'))}
            if union else None)
        if q.read(0x128) == generation:
            return dict(extended_diagnostics=True, detail_scope=REVISION,
                generation=generation, frame=frame, epoch=epoch,
                post_cycles=cycles, bridge_comparisons=comparisons,
                counters=counters, union_diagnostics=union_diagnostics)
    raise RuntimeError('PL diagnostic generation changed during frame snapshot')
