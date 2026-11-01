#!/usr/local/share/pynq-venv/bin/python
"""OV5640 exposure and automatic gain profiles for the matched board runtime."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time

# The immutable runtime's inventory deliberately rejects generated .pyc files.
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
RUNTIME = Path('/opt/zynq-qr/runtime')
RUNTIME_SHA = '9de5a17bda837cecab830cc661046ed31f5d5a7b51b3fee7e0155c61ec96a936'
CAMERA = 'c04-r4-camera.service'
RECOGNITION = 'c04-r4-recognition.service'
STATE = Path('/run/zynq-qr-camera')
PROFILE = STATE / 'profile.json'
APPLIED = STATE / 'applied.json'
DROP_IN = Path('/run/systemd/system') / (CAMERA + '.d') / 'zz-qr-camera.conf'
MARKER = '# Managed by zynq-qr-camera\n'
TABLE_SHA = 'e4eda7868c96c80d56d68c0bf87d10d72e3d922e87efccbe8535f48ff07bee49'
EXPECTED = {0x3034: 0x1a, 0x3035: 0x11, 0x3036: 0x60, 0x3037: 0x13,
            0x3108: 0x01, 0x3808: 5, 0x3809: 0, 0x380a: 2, 0x380b: 0xd0,
            0x380c: 0x0c, 0x380d: 0x80, 0x380e: 3, 0x380f: 0x20}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    temp.replace(path)


def checked(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE, timeout=70).strip()


def active(unit):
    state = checked('systemctl', 'show', unit, '-p', 'ActiveState', '--value')
    if state not in ('active', 'inactive', 'failed'):
        raise RuntimeError(unit + ' is transitioning: ' + state)
    return state == 'active'


def runtime_modules():
    if sha((RUNTIME / 'RUNTIME_MANIFEST.json').read_bytes()) != RUNTIME_SHA:
        raise RuntimeError('This add-on requires the original matched final runtime.')
    sys.path.insert(0, str(RUNTIME / 'python'))
    from ax7021b_qr.r4_display import DisplayDevice
    return DisplayDevice


def display_status():
    device = runtime_modules()()
    try:
        return device.status()
    finally:
        device.close()


def clock_hz(regs, xclk_hz=24000000):
    """OV5640 SCLK formula used by Linux ov5640_get_sysclk, not DVP PCLK."""
    bits = regs[0x3034] & 15
    if bits not in (8, 10):
        raise ValueError('Unsupported sensor bit divider')
    prediv = regs[0x3037] & 15
    sysdiv = (regs[0x3035] >> 4) or 16
    pll_rdiv = ((regs[0x3037] >> 4) & 1) + 1
    sclk_rdiv = (1, 2, 4, 8)[regs[0x3108] & 3]
    if not prediv:
        raise ValueError('Invalid PLL predivider')
    return xclk_hz * regs[0x3036] / prediv / sysdiv / pll_rdiv * 2 / (bits / 2) / sclk_rdiv


def make_profile(exposure_ms, gain):
    if not math.isfinite(exposure_ms) or not .1 <= exposure_ms <= 20:
        raise ValueError('Exposure must be 0.1..20 ms.')
    if not math.isfinite(gain) or not 1 <= gain <= 8:
        raise ValueError('Gain must be 1..8 (linear real-gain mode).')
    line_us = 3200 / clock_hz(EXPECTED) * 1e6
    lines = int(exposure_ms * 1000 / line_us + .5)
    if not 1 <= lines <= 800 - 4:
        raise ValueError('Exposure exceeds the unchanged frame timing.')
    return dict(schema_version=1, runtime_manifest_sha256=RUNTIME_SHA,
                exposure_lines=lines, exposure_ms_requested=exposure_ms,
                exposure_ms_theoretical=lines * line_us / 1000,
                gain_raw=int(gain * 16 + .5), gain_requested=gain,
                qualification='Register configuration verified; physical moving-target performance requires validation')


def make_auto_profile(max_exposure_ms=4, max_gain=8):
    if not math.isfinite(max_exposure_ms) or not .1 <= max_exposure_ms <= 4:
        raise ValueError('Automatic exposure ceiling must be 0.1..4 ms for this motion profile.')
    if not math.isfinite(max_gain) or not 1 <= max_gain <= 8:
        raise ValueError('Automatic gain ceiling must be 1..8.')
    line_us = 3200 / clock_hz(EXPECTED) * 1e6
    # A maximum is rounded down, unlike the nearest-line manual setting.
    lines = math.floor(max_exposure_ms * 1000 / line_us + 1e-9)
    return dict(schema_version=2, mode='auto', runtime_manifest_sha256=RUNTIME_SHA,
                max_exposure_lines=lines, max_exposure_ms_requested=max_exposure_ms,
                max_exposure_ms_theoretical=lines * line_us / 1000,
                max_gain_raw=math.floor(max_gain * 16 + 1e-9), max_gain_requested=max_gain,
                qualification='Sensor AEC/AGC limits configured; runtime enforcement requires physical validation')


def validate_profile(profile):
    if profile.get('mode') == 'auto':
        expected = make_auto_profile(profile['max_exposure_ms_requested'], profile['max_gain_requested'])
    else:
        expected = make_profile(profile['exposure_ms_requested'], profile['gain_requested'])
    # Qualification text is descriptive metadata, so existing profiles remain
    # usable when release wording changes. All operational fields stay exact.
    actual = dict(profile)
    actual['qualification'] = expected['qualification']
    if actual != expected:
        raise RuntimeError('Exposure profile validation failed.')


def adapter_path():
    matches = []
    for path in Path('/sys/bus/i2c/devices').glob('i2c-*'):
        if (path / 'of_node').resolve().name == 'i2c@41600000':
            matches.append(Path('/dev') / path.name)
    if len(matches) != 1:
        raise RuntimeError('Expected exactly one camera I2C adapter at 41600000.')
    return matches[0]


class Sensor:
    def __init__(self, path):
        import fcntl
        self.fd = os.open(path, os.O_RDWR | os.O_CLOEXEC)
        try:
            fcntl.ioctl(self.fd, 0x0703, 0x3c)
        except BaseException:
            os.close(self.fd)
            raise

    def read(self, reg):
        # Match the existing validated camera HAL's SCCB transaction form.
        if os.write(self.fd, reg.to_bytes(2, 'big')) != 2:
            raise OSError('Short SCCB address write at %04x' % reg)
        value = os.read(self.fd, 1)
        if len(value) != 1:
            raise OSError('Short SCCB read at %04x' % reg)
        return value[0]

    def write(self, reg, value):
        if os.write(self.fd, reg.to_bytes(2, 'big') + bytes([value])) != 3:
            raise OSError('Short SCCB register write at %04x' % reg)

    def close(self):
        os.close(self.fd)


def program_manual(sensor, profile):
    before = {r: sensor.read(r) for r in (*EXPECTED, 0x3500, 0x3501, 0x3502, 0x3503, 0x350a, 0x350b)}
    if any(before[r] != expected for r, expected in EXPECTED.items()):
        raise RuntimeError('Sensor geometry/PLL differs from the accepted 720p table.')
    if before[0x3503] & 4:
        raise RuntimeError('Unexpected sensor gain encoding; refusing gain conversion.')
    raw = profile['exposure_lines'] << 4
    gain = profile['gain_raw']
    sensor.write(0x3503, before[0x3503] | 3)
    sensor.write(0x3502, raw & 0xff)
    sensor.write(0x3501, (raw >> 8) & 0xff)
    sensor.write(0x3500, (before[0x3500] & 0xf0) | ((raw >> 16) & 15))
    sensor.write(0x350b, gain & 0xff)
    sensor.write(0x350a, (before[0x350a] & 0xfc) | ((gain >> 8) & 3))
    after = {r: sensor.read(r) for r in before}
    exposure_read = ((after[0x3500] & 15) << 16) | (after[0x3501] << 8) | after[0x3502]
    gain_read = ((after[0x350a] & 3) << 8) | after[0x350b]
    if exposure_read != raw or gain_read != gain or after[0x3503] != (before[0x3503] | 3):
        raise RuntimeError('Manual exposure/gain register readback differs.')
    if any(before[r] != after[r] for r in EXPECTED):
        raise RuntimeError('Unexpected geometry/clock register change.')
    return dict(readback_stage='before_stream_on; not per-frame metadata',
                before={hex(r): v for r, v in before.items()},
                after={hex(r): v for r, v in after.items()},
                exposure_lines=exposure_read >> 4, gain_raw=gain_read,
                gain_linear=gain_read / 16, line_time_us=3200 / clock_hz(after) * 1e6,
                xclk_hz_assumed_from_board_module=24000000,
                register_readback_verified=True, geometry_and_clock_unchanged=True)


def program_auto(sensor, profile):
    controls = (0x3500, 0x3501, 0x3502, 0x3503, 0x350a, 0x350b,
                0x3a00, 0x3a05, 0x3a02, 0x3a03, 0x3a14, 0x3a15, 0x3a18, 0x3a19)
    before = {r: sensor.read(r) for r in (*EXPECTED, *controls)}
    if any(before[r] != value for r, value in EXPECTED.items()):
        raise RuntimeError('Sensor geometry/PLL differs from the accepted 720p table.')
    if before[0x3503] & 4:
        raise RuntimeError('Unexpected sensor gain encoding; refusing auto gain conversion.')
    lines, gain = profile['max_exposure_lines'], profile['max_gain_raw']
    # Seed from the proven short-shutter setting, then hand both controls to
    # the sensor. These seed values are NOT reported as live automatic values.
    seed = make_profile(max(.1, lines * 3200 / clock_hz(EXPECTED) * 1000), min(4, gain / 16))
    program_manual(sensor, seed)
    writes = {
        0x3a02: (lines >> 8) & 0xff, 0x3a03: lines & 0xff,
        0x3a14: (before[0x3a14] & 0xf0) | ((lines >> 8) & 15), 0x3a15: lines & 0xff,
        0x3a18: (before[0x3a18] & 0xfc) | ((gain >> 8) & 3), 0x3a19: gain & 0xff,
        # Keep sub-band auto operation; disable night extension and freeze.
        0x3a00: (before[0x3a00] & ~5) | 0x30,
        0x3a05: before[0x3a05] & ~0x40,
    }
    for reg, value in writes.items():
        sensor.write(reg, value)
    sensor.write(0x3503, before[0x3503] & ~3)
    after = {r: sensor.read(r) for r in before}
    if any(after[r] != value for r, value in writes.items()) or after[0x3503] != (before[0x3503] & ~3):
        raise RuntimeError('Automatic control/ceiling register readback differs.')
    if any(after[r] != value for r, value in EXPECTED.items()):
        raise RuntimeError('Unexpected geometry/clock register change.')
    return dict(mode='auto', readback_stage='before_stream_on; not per-frame metadata',
                before={hex(r): v for r, v in before.items()},
                after={hex(r): v for r, v in after.items()},
                aec_auto=True, agc_auto=True, configured_max_exposure_lines=lines,
                configured_max_gain_raw=gain, seed_exposure_lines=seed['exposure_lines'],
                seed_gain_raw=seed['gain_raw'], night_extension_disabled=True,
                automatic_frame_insertion_disabled=True,
                line_time_us=3200 / clock_hz(after) * 1e6,
                xclk_hz_assumed_from_board_module=24000000,
                register_readback_verified=True, geometry_and_clock_unchanged=True,
                live_automatic_exposure_and_gain_readback_available=False,
                limit_validation='Configured registers verified; runtime enforcement needs physical validation.')


def init_sensor(profile):
    import fcntl
    raw_table = (HERE / 'ov5640_720p.json').read_bytes()
    if sha(raw_table) != TABLE_SHA:
        raise RuntimeError('Camera initialization table binding differs.')
    table = json.loads(raw_table)
    if table['profile'] != 'VIDEO_PROFILE_1280x720_30FPS':
        raise RuntimeError('Wrong camera initialization profile.')
    sensor_fd = os.open('/dev/ax7021b-qr0', os.O_RDWR | os.O_CLOEXEC)
    sensor = None
    try:
        fcntl.ioctl(sensor_fd, (ord('Q') << 8) | 7)
        sensor = Sensor(adapter_path())
        if (sensor.read(0x300a), sensor.read(0x300b)) != (0x56, 0x40):
            raise RuntimeError('OV5640 identification failed after reset.')
        receipt = None
        for reg, value in table['entries']:
            if reg == 0xffff:
                break
            if reg == 0xfffe:
                time.sleep(value / 1000)
                continue
            if (reg, value) == (0x3008, 2):
                receipt = program_auto(sensor, profile) if profile.get('mode') == 'auto' else program_manual(sensor, profile)
            sensor.write(reg, value)
        if receipt is None:
            raise RuntimeError('Initialization table has no stream-on boundary.')
        return receipt
    finally:
        if sensor is not None:
            sensor.close()
        os.close(sensor_fd)


def effective_profile():
    if PROFILE.exists():
        raw = PROFILE.read_bytes()
        profile = json.loads(raw)
        source = 'current_boot_override'
    else:
        profile = make_auto_profile()
        raw = (json.dumps(profile, indent=2) + '\n').encode()
        source = 'installed_default'
    validate_profile(profile)
    return profile, raw, source


def start_preview():
    DisplayDevice = runtime_modules()
    from ax7021b_qr.r4_startup import verify_board
    verify_board(RUNTIME)
    profile, profile_bytes, profile_source = effective_profile()
    device = DisplayDevice()
    start_attempted = False
    try:
        if device.status()['running']:
            raise RuntimeError('Stop the preview before applying a sensor profile.')
        receipt = init_sensor(profile)
        start_attempted = True
        device.start()
        receipt.update(profile=profile, profile_sha256=sha(profile_bytes),
                       profile_source=profile_source,
                       boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                       source_epoch=device.status()['source_epoch'], applied_unix_ns=time.time_ns())
        atomic_json(APPLIED, receipt)
    except BaseException:
        # A failed oneshot start may not receive ExecStop from systemd. Ensure
        # startup recovery cannot mistake this configured preview for a
        # previously initialized camera and skip restoring the sensor table.
        if start_attempted:
            device.stop()
        raise
    finally:
        device.close()


@contextmanager
def control_lock():
    import fcntl
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / 'control.lock').open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def wait_ready(was_recognition):
    deadline = time.monotonic() + 60
    initial = display_status()
    while True:
        display = display_status()
        if any(display[k] for k in ('monitor_errors', 'dma_errors', 'recoveries', 'quarantined')):
            raise RuntimeError('Display hardware errors after profile change.')
        ready = bool(display['running'] and display['source_epoch'] == initial['source_epoch'] and
                     display['source_frames'] != initial['source_frames'])
        if was_recognition:
            pid = checked('systemctl', 'show', RECOGNITION, '-p', 'MainPID', '--value')
            try:
                process = Path('/proc') / pid
                targets = []
                for path in (process / 'fd').iterdir():
                    try:
                        targets.append(os.readlink(path))
                    except FileNotFoundError:
                        pass
                ready = ready and '/libqr_mainline.so.1' in (process / 'maps').read_text() and '/dev/ax7021b-qr0' in targets
            except FileNotFoundError:
                ready = False
        if ready:
            return
        if time.monotonic() >= deadline:
            raise TimeoutError('Preview/recognition did not become ready.')
        time.sleep(.5)


def configure(profile):
    runtime_modules()
    previous = {path: path.read_bytes() if path.exists() else None for path in (DROP_IN, PROFILE)}
    if previous[DROP_IN] is not None and not previous[DROP_IN].startswith(MARKER.encode()):
        raise RuntimeError('Refusing to replace an unmanaged camera override.')
    if profile is None and previous[DROP_IN] is None and previous[PROFILE] is None:
        return
    was_recognition, was_camera = active(RECOGNITION), active(CAMERA)
    def start_previous_state():
        if was_recognition or was_camera:
            checked('systemctl', 'start', RECOGNITION if was_recognition else CAMERA)
            wait_ready(was_recognition)
    try:
        checked('systemctl', 'stop', RECOGNITION, CAMERA)
        if profile is None:
            DROP_IN.unlink(missing_ok=True)
            PROFILE.unlink(missing_ok=True)
        else:
            atomic_json(PROFILE, profile)
            DROP_IN.parent.mkdir(parents=True, exist_ok=True)
            DROP_IN.write_text(MARKER + '[Service]\nExecStart=\nExecStart=' +
                               '/usr/local/share/pynq-venv/bin/python -B ' + str(HERE / 'camera_control.py') + ' start-preview\n')
        checked('systemctl', 'daemon-reload')
        start_previous_state()
        if profile is not None and was_camera and status()['active_profile_readback'] is None:
            raise RuntimeError('The active camera has no readback for this profile; inspect other service overrides.')
    except BaseException as error:
        rollback_errors = []
        try:
            checked('systemctl', 'stop', RECOGNITION, CAMERA)
        except BaseException as stop_error:
            rollback_errors.append('stop: %r' % stop_error)
        for path, content in previous.items():
            try:
                if content is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_bytes(content)
            except BaseException as file_error:
                rollback_errors.append(str(path) + ': %r' % file_error)
        try:
            checked('systemctl', 'daemon-reload')
            if not rollback_errors:
                start_previous_state()
        except BaseException as restart_error:
            rollback_errors.append('restart: %r' % restart_error)
        if rollback_errors:
            raise RuntimeError('Profile change failed: %r; restoration incomplete: %s' %
                               (error, '; '.join(rollback_errors))) from error
        raise RuntimeError('Profile change failed; previous configuration and service state restored: %r' % error) from error


def status():
    display = display_status()
    profile, profile_bytes, profile_source = effective_profile()
    applied = json.loads(APPLIED.read_text()) if APPLIED.exists() else None
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    current = bool(applied and profile and applied['boot_id'] == boot and
                   applied['source_epoch'] == display['source_epoch'] and display['running'] and
                   applied['profile_sha256'] == sha(profile_bytes))
    return dict(configured_profile=profile, active_profile_readback=applied if current else None,
                camera_active=active(CAMERA), recognition_active=active(RECOGNITION), display=display,
                live_sccb_readback_available=False,
                explanation='Control modes and configured limits are verified before stream-on; live SCCB reads return EIO. '
                            'Automatic exposure/gain values are not available as per-frame telemetry.',
                default_control_mode='auto', default_max_exposure_ms=4, default_max_gain=8,
                default_persistence='installed_configuration', override_persistence='current_boot',
                configured_profile_source=profile_source, runtime_manifest_sha256=RUNTIME_SHA)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('status')
    commands.add_parser('restore', help='Remove the current-boot override and restore automatic exposure/gain defaults')
    commands.add_parser('start-preview', help=argparse.SUPPRESS)
    apply = commands.add_parser('apply', help='Override automatic defaults for this boot; restart previously active services')
    apply.add_argument('--exposure-ms', type=float, required=True)
    apply.add_argument('--gain', type=float, default=1, help='Linear real-gain multiplier, 1..8')
    automatic = commands.add_parser('auto', help='Override automatic exposure/gain ceilings for this boot')
    automatic.add_argument('--max-exposure-ms', type=float, default=4)
    automatic.add_argument('--max-gain', type=float, default=8)
    args = parser.parse_args()
    try:
        if os.geteuid() != 0:
            raise RuntimeError('Run with sudo.')
        if args.command == 'start-preview':
            start_preview()
            return 0
        if args.command in ('apply', 'restore', 'auto'):
            profile = (make_profile(args.exposure_ms, args.gain) if args.command == 'apply' else
                       make_auto_profile(args.max_exposure_ms, args.max_gain) if args.command == 'auto' else None)
            with control_lock():
                configure(profile)
        print(json.dumps(status(), indent=2))
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print('zynq-qr-camera: ' + str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
