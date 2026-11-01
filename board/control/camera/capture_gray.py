#!/usr/bin/env python3
"""Capture guarded R4 Gray8 samples while the independent PL preview continues.

Run with the board's existing NumPy environment, for example:
  sudo /usr/local/share/pynq-venv/bin/python -B capture_gray.py --output /tmp/qr-samples

This diagnostic briefly stops recognition, then restores its previous active
state. It never initializes the sensor, changes exposure, or starts the camera.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

sys.dont_write_bytecode = True


CAMERA = 'c04-r4-camera.service'
RECOGNITION = 'c04-r4-recognition.service'
WIDTH, HEIGHT, STORAGE_HEIGHT = 1280, 720, 722
DISCARD_FRAMES = 6


def systemctl(*arguments, timeout=25):
    result = subprocess.run(['systemctl', *arguments], capture_output=True,
                            text=True, timeout=timeout)
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError('systemctl ' + ' '.join(arguments) + ': ' + detail)
    return result.stdout.strip()


def service_state(unit):
    return systemctl('show', unit, '-p', 'ActiveState', '--value')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_preview(display_type):
    display = display_type()
    try:
        return display.status()
    finally:
        display.close()


def require_preview(display_type):
    if service_state(CAMERA) != 'active':
        raise RuntimeError('Camera service must already be active; this sampler does not start it.')
    preview = read_preview(display_type)
    if not preview['running'] or preview['flags'] & 6:
        raise RuntimeError('Independent PL preview is stopped or reports invalid/error flags.')
    return preview


def frames_argument(value):
    number = int(value)
    if not 1 <= number <= 20:
        raise argparse.ArgumentTypeError('--frames must be between 1 and 20')
    return number


def write_new_file(folder, name, data):
    with (folder / name).open('xb') as stream:
        stream.write(data)
    return dict(path=name, bytes=len(data), sha256=sha256(data))


def camera_startup_metadata(profile, profile_bytes, profile_source, applied,
                            boot_id, source_epoch, runtime_manifest_sha256):
    """Associate startup readback with the effective profile and source lifetime."""
    source_matches = bool(isinstance(applied, dict) and
                          applied.get('profile_source', profile_source) == profile_source)
    if profile_source == 'installed_default':
        # An orphaned override receipt cannot establish the installed default.
        source_matches = bool(isinstance(applied, dict) and
                              applied.get('profile_source') == 'installed_default')
    matching = bool(source_matches and applied.get('boot_id') == boot_id and
                    applied.get('source_epoch') == source_epoch and
                    applied.get('profile_sha256') == sha256(profile_bytes) and
                    applied.get('profile') == profile and
                    profile.get('runtime_manifest_sha256') == runtime_manifest_sha256)
    return dict(camera_control_profile=profile,
                camera_control_profile_source=profile_source,
                camera_startup_readback_matches_lifetime=matching,
                camera_startup_readback=applied if matching else None)


def collect(args):
    if sys.platform != 'linux' or os.geteuid() != 0:
        raise RuntimeError('Run on the Linux board with sudo and the pynq-venv Python interpreter.')
    runtime = args.runtime.resolve(strict=True)
    sys.path.insert(0, str(runtime / 'python'))
    # Imports remain below argument parsing so --help works on a Windows host.
    from ax7021b_qr.r4_gray_capture import GrayCapture, GrayCaptureProducer
    from ax7021b_qr.r4_display import DisplayDevice
    from ax7021b_qr.r4_startup import verify_runtime
    verify_runtime(runtime)

    original_state = service_state(RECOGNITION)
    if original_state not in ('active', 'inactive'):
        raise RuntimeError('Recognition is ' + original_state + '; wait for a stable active/inactive state.')
    preview_before = require_preview(DisplayDevice)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    record = dict(
        schema_version=1,
        purpose='Guarded diagnostic Gray8 samples; not an accuracy or worker-performance measurement',
        runtime=str(runtime),
        runtime_manifest_sha256=sha256((runtime / 'RUNTIME_MANIFEST.json').read_bytes()),
        sampler_sha256=sha256(Path(__file__).read_bytes()),
        boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        kernel=os.uname().release,
        realtime_started_ns=time.time_ns(),
        monotonic_started_ns=time.monotonic_ns(),
        requested_frames=args.frames, requested_interval_ms=args.interval_ms,
        discarded_settling_frames=DISCARD_FRAMES,
        layout=dict(format='Gray8', width=WIDTH, height=HEIGHT, stride=WIDTH,
                    storage_height=STORAGE_HEIGHT, header_rows=1, footer_rows=1),
        exposure_gain_sampled=False, per_frame_exposure_binding=False,
        sensor_metadata_note='This sampler does not read exposure/gain. Frame identity does not bind sensor exposure registers to individual frames.',
        recognition_before=original_state, preview_before=preview_before,
        errors=[], frames=[],
    )
    from camera_control import APPLIED, effective_profile
    profile, profile_bytes, profile_source = effective_profile()
    applied = json.loads(APPLIED.read_text()) if APPLIED.exists() else None
    record.update(camera_startup_metadata(profile, profile_bytes, profile_source, applied,
                                         record['boot_id'], preview_before['source_epoch'],
                                         record['runtime_manifest_sha256']))
    frames = []
    capture = producer = None
    stop_attempted = False
    producer_quarantined = False
    interrupted = False

    def terminate(_signum, _frame):
        raise KeyboardInterrupt('Sampler received SIGTERM')

    old_term = signal.signal(signal.SIGTERM, terminate)
    try:
        stop_attempted = True
        systemctl('stop', RECOGNITION)
        if service_state(RECOGNITION) != 'inactive':
            raise RuntimeError('Recognition did not stop; refusing to open its exclusive capture device.')
        preview_ready = require_preview(DisplayDevice)
        if preview_ready['source_epoch'] != preview_before['source_epoch']:
            raise RuntimeError('Preview source lifetime changed before sampling.')
        capture = GrayCapture(prefetch=True)
        expected = (WIDTH, HEIGHT, STORAGE_HEIGHT, WIDTH, WIDTH * STORAGE_HEIGHT)
        actual = tuple(int(getattr(capture.info, name)) for name in
                       ('width', 'visible_height', 'storage_height', 'stride', 'frame_bytes'))
        if actual != expected:
            raise RuntimeError('Unexpected capture geometry: ' + repr(actual))
        record['capture_info'] = {name: int(getattr(capture.info, name))
                                  for name, _ in capture.info._fields_}
        record['capture_counters_before'] = capture.counters()
        producer = GrayCaptureProducer(capture, display=None)
        producer.start()
        seen_sources = set()
        discarded = 0
        next_sample = time.monotonic()
        while len(frames) < args.frames:
            with producer.next(timeout=5) as lease:
                snapshot = lease.snapshot
                identity = (int(snapshot.source_epoch), int(snapshot.source_frame))
                if identity[0] != preview_before['source_epoch']:
                    raise RuntimeError('Preview source lifetime changed during sampling.')
                if identity in seen_sources:
                    raise RuntimeError('Repeated source-frame identity in diagnostic capture.')
                seen_sources.add(identity)
                if discarded < DISCARD_FRAMES:
                    discarded += 1
                    continue
                if time.monotonic() < next_sample:
                    continue
                # Copy while holding the immutable private lease. Defer all file
                # writes until the lease, capture thread and DMA have been released.
                raw = lease.storage.tobytes()
                frozen = bytes(snapshot.frozen)
                metadata = dict(
                    sample_number=len(frames) + 1,
                    source_epoch=identity[0], source_frame=identity[1],
                    pl_epoch=int(snapshot.epoch), pl_frame=int(snapshot.frame),
                    pl_config=int(snapshot.config),
                    capture_sequence=int(lease.buffer.sequence),
                    capture_completed_monotonic_ns=int(lease.buffer.monotonic_ns),
                    copied_monotonic_ns=time.monotonic_ns(),
                    descriptor_flags=int(snapshot.frozen.flags),
                    roi_count=int(snapshot.roi_count),
                    regions=[list(region) for region in snapshot.regions],
                    guards_and_source_tag_validated=True,
                )
                if len(raw) != WIDTH * STORAGE_HEIGHT:
                    raise RuntimeError('Private Gray8 snapshot has an unexpected size.')
                frames.append((metadata, raw, frozen))
                next_sample = time.monotonic() + args.interval_ms / 1000
    except BaseException as exc:
        interrupted = isinstance(exc, KeyboardInterrupt)
        record['errors'].append(type(exc).__name__ + ': ' + str(exc))
    finally:
        if producer is not None and producer.thread.ident is not None:
            try:
                record['producer_summary'] = producer.close()
            except BaseException as exc:
                record['errors'].append('producer cleanup: ' + type(exc).__name__ + ': ' + str(exc))
            producer_quarantined = producer.thread.is_alive()
        record['capture_thread_quarantined'] = producer_quarantined
        if capture is not None and not producer_quarantined:
            try:
                after = capture.counters()
                record['capture_counters_after'] = after
                before = record.get('capture_counters_before', {})
                record['capture_counter_delta'] = {key: value - before[key]
                                                    for key, value in after.items() if key in before}
                if record['capture_counter_delta'].get('dma_errors', 0) > 0:
                    record['errors'].append('Capture DMA error count increased during sampling.')
            except BaseException as exc:
                record['errors'].append('capture counters: ' + type(exc).__name__ + ': ' + str(exc))
            try:
                capture.close()
            except BaseException as exc:
                record['errors'].append('capture cleanup: ' + type(exc).__name__ + ': ' + str(exc))
        capture_released = capture is None or getattr(capture, 'fd', -1) < 0
        safe_to_restore = not producer_quarantined and capture_released
        record['capture_owner_released'] = capture_released
        if not safe_to_restore:
            record['errors'].append('Capture cleanup is incomplete: recognition was not restarted. Restart it manually after this sampler exits.')
        try:
            preview_after = read_preview(DisplayDevice)
            record['preview_after'] = preview_after
            record['camera_service_after'] = service_state(CAMERA)
            record['preview_lifetime_preserved'] = bool(
                record['camera_service_after'] == 'active' and preview_after['running'] and
                preview_after['source_epoch'] == preview_before['source_epoch'])
            if not record['preview_lifetime_preserved']:
                record['errors'].append('Independent preview stopped or its source lifetime changed.')
            record['preview_error_counter_delta'] = {
                key: preview_after[key] - preview_before[key]
                for key in ('dma_errors', 'monitor_errors', 'recoveries', 'quarantined')}
            if preview_after['flags'] & 6 or any(value > 0 for value in record['preview_error_counter_delta'].values()):
                record['errors'].append('Independent preview reports new hardware errors or invalid/error flags.')
        except BaseException as exc:
            record['errors'].append('preview status: ' + type(exc).__name__ + ': ' + str(exc))
        if stop_attempted and original_state == 'active' and safe_to_restore:
            try:
                systemctl('start', RECOGNITION, timeout=40)
            except BaseException as exc:
                record['errors'].append('recognition restore: ' + type(exc).__name__ + ': ' + str(exc))
        try:
            record['recognition_after'] = service_state(RECOGNITION)
            record['recognition_state_restored'] = record['recognition_after'] == original_state
            if not record['recognition_state_restored']:
                record['errors'].append('Recognition active/inactive state was not restored.')
        except BaseException as exc:
            record['errors'].append('recognition status: ' + type(exc).__name__ + ': ' + str(exc))
        signal.signal(signal.SIGTERM, old_term)

    # The production worker is restored before potentially slow SD-card writes.
    for metadata, raw, frozen in frames:
        stem = 'frame-%03d' % metadata['sample_number']
        pixels = raw[WIDTH:WIDTH * (HEIGHT + 1)]
        metadata['raw'] = write_new_file(output, stem + '.bin', raw)
        metadata['pgm'] = write_new_file(output, stem + '.pgm',
                                       b'P5\n1280 720\n255\n' + pixels)
        metadata['frozen_descriptor'] = write_new_file(output, stem + '.frozen.bin', frozen)
        record['frames'].append(metadata)
    record['saved_frames'] = len(record['frames'])
    record['elapsed_seconds'] = time.monotonic() - started
    record['passed'] = not record['errors'] and len(frames) == args.frames
    (output / 'manifest.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(passed=record['passed'], saved_frames=record['saved_frames'],
                          output=str(output), errors=record['errors'])), flush=True)
    return 0 if record['passed'] else 130 if interrupted else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True,
                        help='New output directory; an existing directory is never overwritten')
    parser.add_argument('--frames', type=frames_argument, default=5,
                        help='Number of samples after discarding six settling frames (1..20; default 5)')
    parser.add_argument('--interval-ms', type=int, default=0,
                        help='Minimum spacing between copied samples, 0..1000 ms; intervening frames are consumed without saving')
    parser.add_argument('--runtime', type=Path, default=Path('/opt/zynq-qr/runtime'),
                        help='Existing matching runtime (default /opt/zynq-qr/runtime)')
    args = parser.parse_args()
    if not 0 <= args.interval_ms <= 1000:
        parser.error('--interval-ms must be between 0 and 1000')
    try:
        if sys.platform != 'linux' or os.geteuid() != 0:
            raise RuntimeError('Run on the Linux board with sudo and the pynq-venv Python interpreter.')
        import fcntl
        control = Path('/run/zynq-qr-camera')
        control.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (control / 'control.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return collect(args)
    except (OSError, RuntimeError, subprocess.SubprocessError, ImportError) as exc:
        print('capture_gray: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
