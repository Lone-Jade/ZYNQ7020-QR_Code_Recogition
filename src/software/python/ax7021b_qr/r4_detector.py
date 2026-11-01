"""Unchanged C04/R3 ctypes decoder bridge; no display or pixel conversion."""
import ctypes as C,fcntl,struct
from .capture import _ioc

class Symbol(C.Structure):
    _fields_ = [("track_id", C.c_uint32), ("publication_id", C.c_uint32),
                ("x", C.c_float), ("y", C.c_float), ("size", C.c_float),
                ("payload", C.c_char * 1024)]

class Result(C.Structure):
    _fields_ = [("capture_sequence", C.c_uint64)] + [
        (name, C.c_uint32) for name in ("pl_frame_sequence", "threshold", "roi_count",
        "decoded_count", "elapsed_us", "soft_budget_exceeded", "metadata_valid")
    ] + [("symbols", Symbol * 8)]

class Geometry(C.Structure):
    _fields_=[(n,C.c_uint32) for n in ('version','frame','epoch','valid')]+[('corners',C.c_float*8),('roi_min_xy',C.c_uint32),('roi_max_xy',C.c_uint32)]

class Detector:
    def __init__(self):
        self.lib = C.CDLL("libqr_mainline.so.1", use_errno=True)
        self.lib.qr_mainline_create.restype = C.c_void_p
        self.lib.qr_mainline_destroy.argtypes = [C.c_void_p]
        self.lib.qr_mainline_process.argtypes = [C.c_void_p, C.c_int, C.c_void_p,
                                               C.c_size_t, C.c_uint64, C.POINTER(Result)]
        self.context = self.lib.qr_mainline_create()
        if not self.context:
            raise MemoryError("cannot create detector")

    def process(self, capture, buffer, storage, snapshot=None):
        result = Result()
        if snapshot is not None and snapshot.frozen is not None:
            self.lib.qr_mainline_process_snapshot.argtypes=[C.c_void_p,C.c_void_p,C.c_size_t,C.c_uint64,C.c_void_p,C.POINTER(Result)]
            rc=self.lib.qr_mainline_process_snapshot(self.context,storage.ctypes.data,
                capture.info.frame_bytes,buffer.sequence,C.byref(snapshot.frozen),C.byref(result))
        else:
            rc=self.lib.qr_mainline_process(self.context, capture.fd, storage.ctypes.data,
                                       capture.info.frame_bytes, buffer.sequence, C.byref(result))
        if rc:
            error = C.get_errno()
            raise OSError(error, "frame guard/ROI bank validation failed")
        symbols = [{"track_id": s.track_id, "publication_id": s.publication_id,
                    "x": s.x, "y": s.y, "size": s.size,
                    "payload": s.payload.decode("utf-8", errors="replace")}
                   for s in result.symbols[:result.decoded_count]]
        get_geometry=self.lib.qr_mainline_get_symbol_geometry
        get_geometry.argtypes=[C.c_void_p,C.c_uint32,C.POINTER(Geometry),C.c_size_t]
        for index,symbol in enumerate(symbols):
            geometry=Geometry()
            if get_geometry(self.context,index,C.byref(geometry),C.sizeof(geometry)):
                raise RuntimeError('Successful symbol geometry accessor failed')
            if geometry.version!=1 or geometry.frame!=result.pl_frame_sequence:
                raise RuntimeError('Successful symbol geometry identity mismatch')
            symbol['corners']=list(geometry.corners) if geometry.valid else None
            symbol['geometry_epoch']=int(geometry.epoch)
            symbol['geometry_frame']=int(geometry.frame)
            symbol['roi']=[geometry.roi_min_xy&65535,geometry.roi_min_xy>>16,
                           geometry.roi_max_xy&65535,geometry.roi_max_xy>>16]
        regions = []
        epoch, frame = struct.unpack_from("<II", storage, 8)
        config = struct.unpack_from("<I", storage, 20)[0]
        for bank in range(0 if snapshot is not None else 3):
            raw = bytearray(1992)
            struct.pack_into("<I", raw, 0, bank)
            fcntl.ioctl(capture.fd, _ioc(3, 6, len(raw)), raw, True)
            words = struct.unpack_from("<6I", raw, 8)
            if words[1:4] != (epoch, frame, config) or not words[5] & 1:
                continue
            for i in range(min(words[4], 30)):
                lo, hi = struct.unpack_from("<II", raw, 72 + i * 64)
                regions.append([lo & 65535, lo >> 16, hi & 65535, hi >> 16])
            break
        if snapshot is not None: regions=snapshot.regions
        return {name: int(getattr(result, name)) for name in (
            "capture_sequence", "pl_frame_sequence", "threshold", "roi_count",
            "decoded_count", "elapsed_us", "soft_budget_exceeded", "metadata_valid")} | {"symbols": symbols, "regions": regions}

    def close(self):
        if self.context:
            self.lib.qr_mainline_destroy(self.context)
            self.context = None
