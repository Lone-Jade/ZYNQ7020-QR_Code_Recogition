"""Decode per-buffer diagnostic snapshots without consulting advancing PL registers."""
from .frame_diagnostics import COUNTERS
def cached_diagnostics(value):
    if value.flags&2:
        d=value.diag
        return dict(extended_diagnostics=True,detail_scope='driver-per-frame-v1',
            generation=int(d[0]),frame=int(d[1]),epoch=int(d[2]),post_cycles=int(d[3]),bridge_comparisons=int(d[4]),
            counters={name:int(d[6+i]) for i,name in enumerate(COUNTERS)},union_diagnostics={name:int(d[38+i]) for i,name in enumerate(('mode','committed_merges','absorbed_old','rescans','max_members'))})
    return dict(extended_diagnostics=False,detail_scope='cached-bank-only',
        frame=int(value.data[2]),epoch=int(value.data[1]),
        bank_counters=dict(roi_count=int(value.data[4]),flags=int(value.data[5]),
                           raw_count=int(value.data[8]),cluster_count=int(value.data[9])))
