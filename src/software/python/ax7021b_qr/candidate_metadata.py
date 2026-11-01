"""Read fixed-size ROI metadata; retain frame IDs and preserve error ambiguity."""
from collections import Counter
import ctypes as C
import json
from pathlib import Path

REASONS=['pending','decoded','no_grid','decode_failed','invalid_geometry',
         'budget_not_executed','result_limit','decoded_but_filtered','same_frame_duplicate_crop']


class RoiTrace(C.Structure):
    _fields_=[(n,C.c_uint32) for n in ['index','epoch','frame','config','min_xy','max_xy',
      'module_angle','score_word','reason','decode_attempts','grids_found','decoded_instances',
      'copy_us','identify_us','sample_us','ecc_us','total_us','otsu_threshold']]+[
      ('errors',C.c_uint32*8)]+[(n,C.c_uint32) for n in ['flags','retry_count','retry_reason','retry_elapsed_us']]


class CandidateMetadata:
    def __init__(self,detector):
        self.detector=detector
        self.meta=json.loads((Path(__file__).resolve().parents[2]/'version.json').read_text())
        self.id=self.meta['id'];self.level=self.meta['level'];self.counts=Counter()
        lib=detector.lib
        lib.qr_candidate_level.argtypes=[];lib.qr_candidate_level.restype=C.c_uint32
        if lib.qr_candidate_level()!=self.level:raise RuntimeError('Candidate worker/library version mismatch')
        if self.level>=2:
            lib.qr_mainline_trace_count.argtypes=[C.c_void_p];lib.qr_mainline_trace_count.restype=C.c_uint32
            lib.qr_mainline_trace_size.argtypes=[];lib.qr_mainline_trace_size.restype=C.c_uint32
            lib.qr_mainline_get_roi_trace.argtypes=[C.c_void_p,C.c_uint32,C.POINTER(RoiTrace),C.c_size_t]
            assert lib.qr_mainline_trace_size()==C.sizeof(RoiTrace)==120
    def attach(self,row):
        row['candidate_id']=self.id
        if self.level<2:return row
        lib=self.detector.lib;records=[]
        count=lib.qr_mainline_trace_count(self.detector.context)
        if count>30:raise RuntimeError('ROI trace count exceeds PL capacity')
        for index in range(count):
            trace=RoiTrace()
            if lib.qr_mainline_get_roi_trace(self.detector.context,index,C.byref(trace),C.sizeof(trace)):
                raise RuntimeError('ROI trace getter failed')
            if trace.frame!=row['pl_frame_sequence']:raise RuntimeError('ROI trace belongs to another frame')
            item={name:getattr(trace,name) for name,_ in trace._fields_ if name!='errors'}
            item['errors']={str(i):int(n) for i,n in enumerate(trace.errors) if n}
            item['reason_name']=REASONS[trace.reason] if trace.reason<len(REASONS) else 'unknown'
            self.counts[item['reason_name']]+=1;records.append(item)
        row['roi_trace_schema']='roi-trace-v1-120bytes'
        row['roi_traces']=records
        return row
