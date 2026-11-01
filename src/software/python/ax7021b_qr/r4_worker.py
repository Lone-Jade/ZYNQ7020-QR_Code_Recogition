"""R4 Gray8 decoder / independent PL camera display entry point.

No images or successful-frame logs are saved. Optional result events are
streamed to stdout for a host controller which retains summaries/misses only.
"""
import argparse
import ctypes as C
import json
import os
import signal
import subprocess
import time

from .candidate_capture import cached_diagnostics
from .candidate_metadata import CandidateMetadata
from .r4_timing import TimingStats
from .r4_detector import Detector
from .r4_gray_capture import GrayCapture, GrayCaptureProducer
from .r4_display import ResultDisplay
PIPELINE_REVISION="c04-r4-final-scene-v2"

PROFILE_STAGES = ('otsu', 'binarize', 'finder', 'grid_total', 'grid_size',
                  'alignment_search', 'perspective_total', 'perspective_jiggle')


class FitnessMetrics(C.Structure):
    _fields_ = [(name, C.c_uint64) for name in (
        'grids', 'software_grids', 'prepared', 'hardware_calls', 'compared',
        'mismatches', 'faults', 'fallback_grids', 'prepare_us', 'score_us',
        'software_us', 'release_us', 'bytes')]


class R3FitnessMetrics(C.Structure):
    _fields_ = [(name, C.c_uint64) for name in (
        'version', 'binary_generations', 'packed_rois', 'pack_reuses',
        'roi_loads', 'grid_jobs', 'tree_us', 'tree_bytes', 'logical_scores',
        'trace_differences', 'roi_releases')]


class PrepareMetrics(C.Structure):
    _fields_ = [(name, C.c_uint64) for name in ('pack_us', 'features_us', 'prepare_ioctl_us')]


def backend_counts(detector):
    result = {}
    for key, name, structure, sized in (
            ('legacy', 'qr_fitness_get_metrics', FitnessMetrics, False),
            ('r3', 'qr_fitness_get_r3_metrics', R3FitnessMetrics, True),
            ('prepare', 'qr_fitness_get_prepare_metrics', PrepareMetrics, False)):
        method = getattr(detector.lib, name, None)
        if method is None:
            continue
        value = structure()
        method.argtypes = [C.c_void_p, C.c_uint32] if sized else [C.POINTER(structure)]
        if sized:
            method.restype = C.c_int
            if method(C.byref(value), C.sizeof(value)) or value.version != 1:
                raise RuntimeError('R3 fitness metric size or version mismatch')
        else:
            method(C.byref(value))
        result[key] = {name:int(getattr(value, name)) for name, _ in structure._fields_}
    if 'r3' in result and 'legacy' in result:
        result['actual_grid_jobs'] = result['r3']['grid_jobs']
        result['logical_scores'] = result['r3']['logical_scores']
        result['hardware_grid_ratio'] = result['r3']['grid_jobs']/max(1, result['legacy']['grids'])
    return result


def emit(value):
    print(json.dumps(value, ensure_ascii=True, separators=(',', ':')), flush=True)


def run(args):
    os.environ['QR_FITNESS_BACKEND'] = args.backend
    os.environ['QR_FITNESS_PROFILE'] = '0'
    stop = False
    def on_stop(*_):
        nonlocal stop
        stop = True
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, on_stop)
    if args.init_camera:
        raise RuntimeError('R4 camera initialization belongs to the independent preview service')
    display = capture = detector = producer = None
    timers = TimingStats()
    processed = decoded_frames = decoded_symbols = pairing_errors = 0
    started = time.monotonic()
    capture_summary = display_summary = counters = fitness = layout_diagnostics = None
    failure = None
    try:
        if args.hdmi:
            display = ResultDisplay()
        detector = Detector()
        metadata = CandidateMetadata(detector)
        detector.lib.qr_mainline_set_decode_budget_us.argtypes = [C.c_void_p, C.c_uint32]
        if detector.lib.qr_mainline_set_decode_budget_us(detector.context, args.decode_budget_us):
            raise RuntimeError('R3 decode budget was rejected')
        for name in ('qr_profile_get', 'qr_profile_calls'):
            getattr(detector.lib, name).argtypes = [C.c_uint32]
            getattr(detector.lib, name).restype = C.c_uint64
        # R4 keeps only private Gray8 recognition snapshots; PL owns RGB display.
        capture = GrayCapture(prefetch=True)
        producer = GrayCaptureProducer(capture,display=display)
        producer.start()
        started = time.monotonic()
        emit(dict(type='ready', pipeline_revision=PIPELINE_REVISION,
                  candidate_id=metadata.id, color=bool(display), color_fps_limit=None,
                  decode_budget_us=args.decode_budget_us, decode_policy='backpressure',
                  backend=args.backend,
                  layout=vars(producer.layout), images_saved=False,
                  successful_frame_logs_saved=False, board_monotonic_ns=time.monotonic_ns()))
        while not stop and time.monotonic()-started < args.seconds:
            if display and display.error:
                raise RuntimeError('Display scene failed: '+display.error)
            if display and display.user_stop.is_set():
                break
            stamp = time.perf_counter_ns()
            with producer.next(timeout=5) as lease:
                timers.elapsed('wait_private_decode_lease', stamp)
                stamp = time.perf_counter_ns()
                row = detector.process(lease.capture, lease.buffer, lease.storage, lease.snapshot)
                lease.snapshot.validate_result(row)
                timers.elapsed('decode', stamp)
                metadata.attach(row)
                identity = lease.snapshot
                row.update(pl_epoch=identity.epoch, pl_config=identity.config,
                           source_epoch=identity.source_epoch,source_frame=identity.source_frame,
                           capture_completed_ns=int(lease.buffer.monotonic_ns),
                           board_monotonic_ns=time.monotonic_ns())
                diagnostics = cached_diagnostics(identity.frozen)
                paired = diagnostics['frame'] == identity.frame and diagnostics['epoch'] == identity.epoch
                pairing_errors += not paired
                if not paired:
                    raise RuntimeError('Cached diagnostics identity differs from decoder lease')
                row['profile_us'] = {name:int(detector.lib.qr_profile_get(i))
                                     for i, name in enumerate(PROFILE_STAGES)}
                for name, value in row['profile_us'].items():
                    timers.add('decode_'+name, value/1000.)
                processed += 1
                decoded_frames += bool(row['decoded_count'])
                decoded_symbols += row['decoded_count']
                recognition_fps = processed/max(.001, time.monotonic()-started)
                if display:
                    display.submit_results(row, recognition_fps)
                if args.stream_events and row['decoded_count']:
                    emit(dict(type='decode', board_monotonic_ns=row['board_monotonic_ns'],
                              pl_epoch=identity.epoch, pl_config=identity.config,
                              source_epoch=identity.source_epoch,source_frame=identity.source_frame,
                              pl_frame_sequence=identity.frame,
                              capture_sequence=int(lease.buffer.sequence), symbols=row['symbols']))
                if args.status_every and processed % args.status_every == 0:
                    emit(dict(type='progress', frames=processed, decoded_frames=decoded_frames,
                              decoded_symbols=decoded_symbols, processing_fps=recognition_fps,
                              capture_frames=producer.captured, skipped_decode=producer.skipped_decode,
                              annotations=display.metrics() if display else None,
                              frame_pairing_errors=pairing_errors, images_saved=False,
                              fitness_metrics=backend_counts(detector)))
            if args.frames and processed >= args.frames:
                break
    except BaseException as exc:
        failure = type(exc).__name__+': '+str(exc)
        raise
    finally:
        elapsed = max(.001, time.monotonic()-started)
        cleanup_errors = []
        if producer:
            try:
                capture_summary = producer.close()
            except BaseException as exc:
                cleanup_errors.append(type(exc).__name__+': '+str(exc))
            layout_diagnostics = producer.layout_diagnostics
        producer_still_running = bool(producer and producer.thread.is_alive())
        if capture and not producer_still_running:
            try:
                counters = capture.counters()
            except BaseException as exc:
                cleanup_errors.append(type(exc).__name__+': '+str(exc))
            try:
                capture.close()
            except BaseException as exc:
                cleanup_errors.append(type(exc).__name__+': '+str(exc))
        elif capture:
            cleanup_errors.append('Capture mappings quarantined: producer thread is still running')
        if display:
            try:
                display_summary = display.close(drain=args.drain_osd)
            except BaseException as exc:
                cleanup_errors.append(type(exc).__name__+': '+str(exc))
        if detector:
            try:
                fitness = backend_counts(detector)
            except BaseException as exc:
                cleanup_errors.append(type(exc).__name__+': '+str(exc))
            try:
                detector.close()
            except BaseException as exc:
                cleanup_errors.append(type(exc).__name__+': '+str(exc))
        emit(dict(type='summary', pipeline_revision=PIPELINE_REVISION,
                  processed_frames=processed, decoded_frames=decoded_frames,
                  decoded_symbols=decoded_symbols, frame_pairing_errors=pairing_errors,
                  seconds=elapsed, processing_fps=processed/elapsed,
                  capture=capture_summary, display=display_summary,
                  capture_counters=counters, timers=timers.summary(),
                  capture_layout_diagnostics=layout_diagnostics,
                  capture_layout_diagnostics_error=(producer.layout_diagnostics_error if producer else None),
                  capture_format_valid=bool(layout_diagnostics is not None and
                                            not layout_diagnostics['format_errors']),
                  backend=args.backend, fitness_metrics=fitness,
                  failure=failure, cleanup_errors=cleanup_errors,
                  decode_budget_us=args.decode_budget_us,
                  images_saved=False, successful_frame_logs_saved=False,
                  stability_30_minutes_tested=False))
        if cleanup_errors and failure is None:
            raise RuntimeError('R3 cleanup failed: '+'; '.join(cleanup_errors))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--init-camera', action='store_true')
    parser.add_argument('--hdmi', action='store_true',help='Submit status HUD and successful QR annotations to PL display')
    parser.add_argument('--drain-osd', action='store_true',help='Drain after recognition window; excluded from processing FPS')
    parser.add_argument('--backend', choices=('software', 'pl', 'compare', 'pl-reuse',
                                               'pl-grid', 'compare-grid'), default='pl-grid')
    parser.set_defaults(color_fps=30)
    parser.add_argument('--frames', type=int, default=450)
    parser.add_argument('--seconds', type=float, default=900)
    parser.add_argument('--decode-budget-us', type=int, choices=(60000,), default=60000)
    parser.add_argument('--status-every', type=int, default=30)
    parser.add_argument('--stream-events', action='store_true')
    args = parser.parse_args()
    if args.frames < 0 or args.seconds <= 0 or args.status_every < 0:
        parser.error('Invalid frame, time or status limit')
    run(args)


if __name__ == '__main__':
    main()
