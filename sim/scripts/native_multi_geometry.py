"""Check payload/corner indexing with two actual QR codes, including duplicates."""
from pathlib import Path
import ctypes as C
import hashlib
import json
import os
import struct
import sys

R = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(R/'src/software/python'))
os.environ['QR_FITNESS_BACKEND'] = 'software'

def main():
    (R/'sim/results/generated').mkdir(parents=True,exist_ok=True)
    import numpy as np
    from PIL import Image
    from ax7021b_qr.r4_detector import Result, Geometry
    from ax7021b_qr.capture import FrameSnapshot
    libraries = []
    for path in [R/'build/work/native/libqr_mainline.so.1']:
        lib = C.CDLL(str(path), use_errno=True)
        lib.qr_mainline_create.restype = C.c_void_p
        lib.qr_mainline_destroy.argtypes = [C.c_void_p]
        lib.qr_mainline_process_snapshot.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t,
                                                   C.c_uint64, C.POINTER(FrameSnapshot), C.POINTER(Result)]
        libraries.append(lib)
    final = libraries[0]
    final.qr_mainline_get_symbol_geometry.argtypes = [C.c_void_p, C.c_uint32,
                                                    C.POINTER(Geometry), C.c_size_t]
    cases = []
    for label, ids in [('distinct-payloads', (1, 2)), ('identical-payloads', (1, 1))]:
        canvas = Image.new('L', (1280, 720), 255)
        expected = []
        for index, case_id in enumerate(ids):
            fixture = R/'sim/fixtures'/('case_%04d' % case_id)
            meta = json.loads((fixture/'manifest.json').read_text())
            n = meta['module_count']
            modules = np.frombuffer((fixture/'expected_modules.bin').read_bytes(), dtype=np.uint8).reshape(n, n)
            pixels = np.pad(255-modules*255, 4, constant_values=255).repeat(7, axis=0).repeat(7, axis=1)
            tile = Image.fromarray(pixels).rotate(90*index, expand=True, fillcolor=255)
            x, y = 120+640*index, 200
            canvas.paste(tile, (x, y))
            expected.append((meta['payload'].encode(), (x, y, x+tile.width, y+tile.height)))
        # Exercise the production explicit-ROI entry point. The legacy file
        # entry point intentionally deduplicates identical payloads globally.
        storage = np.full((722, 1280), 255, dtype=np.uint8)
        storage[1:721] = np.array(canvas, dtype=np.uint8)
        header = [0x32485251, 0x00020003, 7, 1, 0xfffffffe, 1, 1,
                  1280 | (720 << 16), 128, 1, 0, 0, 0, 0, 0, 0]
        footer = header.copy()
        footer[0], footer[10], footer[11] = 0x32465251, 1280*720, 1
        raw = storage.reshape(-1)
        raw[:64] = np.frombuffer(struct.pack('<16I', *header), dtype=np.uint8)
        raw[721*1280:721*1280+64] = np.frombuffer(struct.pack('<16I', *footer), dtype=np.uint8)
        frozen = FrameSnapshot(flags=1, sequence=0)
        bank = [2, 7, 1, 1, 2, 1, 128, 1, 6, 2, 0, 0, 0, 0, 0, 0]
        frozen.data[:16] = bank
        pack_xy = lambda x, y: int(x) | (int(y) << 16)
        for i, (_, b) in enumerate(expected):
            x0, y0, x1, y1 = b
            roi = [pack_xy(x0,y0),pack_xy(x1,y1),pack_xy(x0+50,y0+50),
                   pack_xy(x1-50,y0+50),pack_xy(x0+50,y1-50),7,1,0]+[0]*8
            frozen.data[16+i*16:32+i*16] = roi
        outputs = []
        matched = set()
        for lib in libraries:
            context = lib.qr_mainline_create()
            try:
                result = Result()
                assert lib.qr_mainline_process_snapshot(context, storage.ctypes.data, storage.nbytes,
                                                       0, C.byref(frozen), C.byref(result)) == 0
                symbols = [(int(s.track_id), int(s.publication_id), s.x, s.y, s.size,
                            bytes(s.payload)) for s in result.symbols[:result.decoded_count]]
                outputs.append(symbols)
                assert len(symbols) == 2, (label, symbols)
                if lib is final:
                    for i, symbol in enumerate(symbols):
                        g = Geometry()
                        assert final.qr_mainline_get_symbol_geometry(context, i, C.byref(g), C.sizeof(g)) == 0
                        assert g.version == 1 and g.valid and g.epoch == 7 and g.frame == 1
                        assert (g.roi_min_xy, g.roi_max_xy) in [(frozen.data[16+j*16], frozen.data[17+j*16]) for j in range(2)]
                        xs, ys = list(g.corners)[::2], list(g.corners)[1::2]
                        hits = [j for j, (payload, b) in enumerate(expected)
                                if payload == symbol[-1] and b[0] <= min(xs) < max(xs) <= b[2]
                                and b[1] <= min(ys) < max(ys) <= b[3]]
                        assert len(hits) == 1 and hits[0] not in matched, (label, hits)
                        j = hits[0]
                        assert (g.roi_min_xy, g.roi_max_xy) == (frozen.data[16+j*16], frozen.data[17+j*16])
                        matched.add(hits[0])
            finally:
                lib.qr_mainline_destroy(context)
        assert matched == {0, 1}
        assert len({s[1] for s in outputs[0]}) == 2, (label, 'publication identity collapse')
        cases.append(dict(name=label, decoded=2, geometry_payload_pairs=2,
                          spatial_publication_ids_distinct=True))
    value = dict(passed=True, software_backend=True, actual_quirc_decoding=True,
                 entry_point='production explicit ROI snapshot', synthetic_metadata=True,
                 cases=cases, libraries={str((R/'build/work/native/libqr_mainline.so.1').relative_to(R)):hashlib.sha256((R/'build/work/native/libqr_mainline.so.1').read_bytes()).hexdigest()}, images_saved=False)
    (R/'sim/results/generated/native-multi-rebuilt.json').write_text(json.dumps(value, indent=2)+'\n')
    print(json.dumps(value, indent=2))

if __name__ == '__main__':
    main()
