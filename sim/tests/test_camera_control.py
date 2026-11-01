"""Offline guardrail checks; these do not qualify the physical camera."""
import importlib.util
from pathlib import Path
import tempfile
import json
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('camera_control', Path(__file__).resolve().parents[2] / 'src/software/camera/camera_control.py')
camera = importlib.util.module_from_spec(spec)
spec.loader.exec_module(camera)

sampler_spec = importlib.util.spec_from_file_location('capture_gray', Path(__file__).resolve().parents[2] / 'src/software/camera/capture_gray.py')
sampler = importlib.util.module_from_spec(sampler_spec)
sampler_spec.loader.exec_module(sampler)


class FakeSensor:
    def __init__(self):
        self.regs = dict(camera.EXPECTED)
        self.regs.update({0x3500: 0xa0, 0x3501: 0x20, 0x3502: 0,
                          0x3503: 0x80, 0x350a: 0xc0, 0x350b: 16,
                          0x3a00: 0x7d, 0x3a05: 0x70, 0x3a02: 3, 0x3a03: 0x20,
                          0x3a14: 0xa3, 0x3a15: 0x20, 0x3a18: 0xc3, 0x3a19: 0xf8})
        self.writes = []

    def read(self, reg):
        return self.regs[reg]

    def write(self, reg, value):
        self.writes.append((reg, value))
        self.regs[reg] = value

    def close(self):
        pass


class CameraControls(unittest.TestCase):
    def _start_profile_with_sensor(self, profile=None):
        class Display:
            running = False
            def status(self):
                return {'running': self.running, 'source_epoch': 7}
            def start(self):
                self.running = True
            def stop(self):
                self.running = False
            def close(self):
                pass
        sensor = FakeSensor()
        sensor.regs.update({0x300a: 0x56, 0x300b: 0x40})
        test_root = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(dir=test_root) as folder:
            root = Path(folder)
            profile_path, applied = root / 'profile.json', root / 'applied.json'
            if profile is not None:
                profile_path.write_text(json.dumps(profile))
            table = json.dumps(dict(profile='VIDEO_PROFILE_1280x720_30FPS',
                                    entries=[[0x3008, 2], [0xffff, 0]])).encode()
            (root / 'ov5640_720p.json').write_bytes(table)
            read_text = Path.read_text
            def read_boot(path, *args, **kwargs):
                if str(path) == '/proc/sys/kernel/random/boot_id':
                    return 'test-boot'
                return read_text(path, *args, **kwargs)
            modules = {'ax7021b_qr.r4_startup': SimpleNamespace(verify_board=lambda root: None),
                       'fcntl': SimpleNamespace(ioctl=lambda *args: None)}
            device = Display()
            with patch.object(camera, 'PROFILE', profile_path), patch.object(camera, 'APPLIED', applied), \
                 patch.object(camera, 'HERE', root), patch.object(camera, 'TABLE_SHA', camera.sha(table)), \
                 patch.object(camera, 'runtime_modules', return_value=lambda: device), \
                 patch.object(camera, 'Sensor', return_value=sensor), \
                 patch.object(camera, 'adapter_path', return_value=Path('/dev/mock-camera')), \
                 patch.object(camera.os, 'open', return_value=77), patch.object(camera.os, 'close'), \
                 patch.object(camera.Path, 'read_text', read_boot), patch.dict(sys.modules, modules):
                camera.start_preview()
            receipt = json.loads(applied.read_text())
            self.assertTrue(device.running)
            self.assertEqual(receipt['source_epoch'], 7)
            self.assertEqual(receipt['boot_id'], 'test-boot')
            self.assertEqual(profile_path.exists(), profile is not None)
        return sensor, receipt

    def test_default_start_programs_automatic_exposure_and_gain(self):
        sensor, receipt = self._start_profile_with_sensor()
        self.assertEqual(receipt['profile_source'], 'installed_default')
        self.assertEqual(receipt['profile'], camera.make_auto_profile(4, 8))
        self.assertTrue(receipt['aec_auto'] and receipt['agc_auto'])
        self.assertEqual(receipt['configured_max_exposure_lines'], 96)
        self.assertEqual(receipt['configured_max_gain_raw'], 128)
        self.assertEqual(sensor.regs[0x3503] & 3, 0)
        self.assertEqual(sensor.writes[-1], (0x3008, 2))

    def test_explicit_manual_profile_overrides_automatic_default(self):
        sensor, receipt = self._start_profile_with_sensor(camera.make_profile(2, 2))
        self.assertEqual(receipt['profile_source'], 'current_boot_override')
        self.assertEqual(receipt['profile'], camera.make_profile(2, 2))
        self.assertEqual(receipt['exposure_lines'], 48)
        self.assertEqual(receipt['gain_raw'], 32)
        self.assertEqual(sensor.regs[0x3503] & 3, 3)

    def test_restore_removes_profile_even_if_override_file_is_absent(self):
        test_root = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(dir=test_root) as folder:
            profile = Path(folder) / 'profile.json'
            drop = Path(folder) / 'override.conf'
            profile.write_text(json.dumps(camera.make_profile(2, 2)))
            calls = []
            with patch.object(camera, 'PROFILE', profile), patch.object(camera, 'DROP_IN', drop), \
                 patch.object(camera, 'runtime_modules'), patch.object(camera, 'active', return_value=True), \
                 patch.object(camera, 'checked', side_effect=lambda *args: calls.append(args)), \
                 patch.object(camera, 'wait_ready'):
                camera.configure(None)
                self.assertFalse(profile.exists())
                self.assertFalse(drop.exists())
                effective, _, source = camera.effective_profile()
                self.assertEqual(effective, camera.make_auto_profile())
                self.assertEqual(source, 'installed_default')
            self.assertEqual(calls[-1], ('systemctl', 'start', camera.RECOGNITION))

    def test_sampler_includes_default_auto_startup_receipt_without_override(self):
        test_root = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(dir=test_root) as folder:
            with patch.object(camera, 'PROFILE', Path(folder) / 'profile.json'):
                profile, raw, source = camera.effective_profile()
            self.assertEqual(source, 'installed_default')
            self.assertEqual(profile, camera.make_auto_profile(4, 8))
            applied = dict(profile=profile, profile_sha256=camera.sha(raw),
                           profile_source=source, boot_id='boot', source_epoch=7)
            result = sampler.camera_startup_metadata(profile, raw, source, applied,
                                                     'boot', 7, camera.RUNTIME_SHA)
            self.assertTrue(result['camera_startup_readback_matches_lifetime'])
            self.assertEqual(result['camera_startup_readback'], applied)
            self.assertEqual(result['camera_control_profile_source'], 'installed_default')
            for changes in ({'boot_id': 'previous-boot'}, {'source_epoch': 6},
                            {'profile_sha256': 'stale'}, {'profile_source': 'current_boot_override'}):
                with self.subTest(changes=changes):
                    stale = dict(applied, **changes)
                    result = sampler.camera_startup_metadata(profile, raw, source, stale,
                                                             'boot', 7, camera.RUNTIME_SHA)
                    self.assertFalse(result['camera_startup_readback_matches_lifetime'])
                    self.assertIsNone(result['camera_startup_readback'])

    def test_sampler_keeps_manual_override_binding_and_rejects_stale_receipts(self):
        profile = camera.make_profile(2, 2)
        raw = json.dumps(profile).encode()
        # Existing manual receipts predate the profile_source field.
        applied = dict(profile=profile, profile_sha256=camera.sha(raw),
                       boot_id='boot', source_epoch=7)
        source = 'current_boot_override'
        result = sampler.camera_startup_metadata(profile, raw, source, applied,
                                                 'boot', 7, camera.RUNTIME_SHA)
        self.assertTrue(result['camera_startup_readback_matches_lifetime'])
        self.assertEqual(result['camera_control_profile'], profile)
        for receipt in (None, dict(applied, source_epoch=8),
                        dict(applied, profile=camera.make_auto_profile())):
            with self.subTest(receipt=receipt):
                result = sampler.camera_startup_metadata(profile, raw, source, receipt,
                                                         'boot', 7, camera.RUNTIME_SHA)
                self.assertFalse(result['camera_startup_readback_matches_lifetime'])
                self.assertIsNone(result['camera_startup_readback'])
        result = sampler.camera_startup_metadata(profile, raw, source, applied,
                                                 'boot', 7, 'other-runtime')
        self.assertFalse(result['camera_startup_readback_matches_lifetime'])

    def test_reference_exposure_conversion(self):
        self.assertAlmostEqual(camera.clock_hz(camera.EXPECTED), 76800000)
        for ms, lines in ((1, 24), (2, 48), (4, 96), (8, 192)):
            self.assertEqual(camera.make_profile(ms, 1)['exposure_lines'], lines)

    def test_no_nonfinite_or_out_of_range_parameters(self):
        for exposure, gain in ((float('nan'), 1), (float('inf'), 1), (0, 1),
                               (33, 1), (2, 0), (2, 9), (2, float('nan'))):
            with self.subTest(exposure=exposure, gain=gain), self.assertRaises(ValueError):
                camera.make_profile(exposure, gain)

    def test_auto_ceiling_rounds_down_and_rejects_unsafe_inputs(self):
        self.assertEqual(camera.make_auto_profile(4, 8)['max_exposure_lines'], 96)
        profile = camera.make_auto_profile(3.99, 3.99)
        self.assertEqual(profile['max_exposure_lines'], 95)
        self.assertLessEqual(profile['max_exposure_ms_theoretical'], 3.99)
        self.assertLessEqual(profile['max_gain_raw'] / 16, 3.99)
        for exposure, gain in ((float('nan'), 1), (4.01, 1), (0, 1), (4, float('inf')), (4, 9)):
            with self.subTest(exposure=exposure, gain=gain), self.assertRaises(ValueError):
                camera.make_auto_profile(exposure, gain)

    def test_legacy_manual_profile_still_validates(self):
        camera.validate_profile(camera.make_profile(4, 4))
        camera.validate_profile(camera.make_auto_profile())
        for profile in (camera.make_profile(4, 4), camera.make_auto_profile()):
            profile['qualification'] = 'legacy descriptive metadata'
            camera.validate_profile(profile)
        bad = camera.make_auto_profile()
        bad['max_exposure_lines'] += 1
        with self.assertRaises(RuntimeError):
            camera.validate_profile(bad)

    def test_auto_control_registers_caps_reserved_bits_and_seed(self):
        sensor = FakeSensor()
        result = camera.program_auto(sensor, camera.make_auto_profile(4, 8))
        self.assertTrue(result['aec_auto'] and result['agc_auto'])
        self.assertEqual(sensor.regs[0x3503], 0x80)
        self.assertEqual((sensor.regs[0x3a02] << 8) | sensor.regs[0x3a03], 96)
        self.assertEqual(((sensor.regs[0x3a14] & 15) << 8) | sensor.regs[0x3a15], 96)
        self.assertEqual(sensor.regs[0x3a14] & 0xf0, 0xa0)
        self.assertEqual(sensor.regs[0x3a18] & 0xfc, 0xc0)
        self.assertEqual(((sensor.regs[0x3a18] & 3) << 8) | sensor.regs[0x3a19], 128)
        self.assertEqual(sensor.regs[0x3a00] & 5, 0)
        self.assertEqual(sensor.regs[0x3a00] & 0x30, 0x30)
        self.assertEqual(sensor.regs[0x3a05] & 0x40, 0)
        self.assertEqual(result['seed_exposure_lines'], 96)
        self.assertEqual(result['seed_gain_raw'], 64)
        self.assertEqual(sensor.writes[-1], (0x3503, 0x80))
        for reg, value in camera.EXPECTED.items():
            self.assertEqual(sensor.regs[reg], value)
        self.assertTrue(set(reg for reg, _ in sensor.writes) <=
                        {0x3500, 0x3501, 0x3502, 0x3503, 0x350a, 0x350b,
                         0x3a00, 0x3a05, 0x3a02, 0x3a03, 0x3a14, 0x3a15, 0x3a18, 0x3a19})

    def test_minimum_auto_seed_does_not_exceed_ceiling(self):
        profile = camera.make_auto_profile(.1, 1)
        result = camera.program_auto(FakeSensor(), profile)
        self.assertLessEqual(result['seed_exposure_lines'], profile['max_exposure_lines'])
        self.assertEqual(result['seed_gain_raw'], 16)

    def test_bad_auto_limit_readback_is_rejected(self):
        sensor = FakeSensor()
        write = sensor.write
        def broken_write(reg, value):
            if reg != 0x3a03:
                write(reg, value)
        sensor.write = broken_write
        with self.assertRaises(RuntimeError):
            camera.program_auto(sensor, camera.make_auto_profile())

    def test_changes_only_manual_controls_preserving_reserved_bits(self):
        sensor = FakeSensor()
        result = camera.program_manual(sensor, camera.make_profile(2, 2))
        self.assertEqual(result['exposure_lines'], 48)
        self.assertEqual(result['gain_raw'], 32)
        self.assertEqual(sensor.regs[0x3500] & 0xf0, 0xa0)
        self.assertEqual(sensor.regs[0x350a] & 0xfc, 0xc0)
        self.assertEqual(sensor.regs[0x3503], 0x83)
        self.assertEqual(sensor.regs[0x3502] & 15, 0)
        self.assertEqual(set(reg for reg, _ in sensor.writes),
                         {0x3500, 0x3501, 0x3502, 0x3503, 0x350a, 0x350b})
        for reg, value in camera.EXPECTED.items():
            self.assertEqual(sensor.regs[reg], value)

    def test_unexpected_timing_or_gain_mode_rejected_before_write(self):
        for reg in (0x3036, 0x380f, 0x3503):
            sensor = FakeSensor()
            sensor.regs[reg] ^= 4
            with self.assertRaises(RuntimeError):
                camera.program_manual(sensor, camera.make_profile(2, 1))
            self.assertEqual(sensor.writes, [])

    def test_bad_readback_is_rejected(self):
        sensor = FakeSensor()
        real_write = sensor.write
        def broken_write(reg, value):
            if reg != 0x350b:
                real_write(reg, value)
        sensor.write = broken_write
        with self.assertRaises(RuntimeError):
            camera.program_manual(sensor, camera.make_profile(2, 2))

    def test_start_failure_restores_previous_files_and_running_services(self):
        test_root = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(dir=test_root) as folder:
            self.assertTrue(Path(folder).resolve().is_relative_to(test_root))
            drop = Path(folder) / 'override.conf'
            profile = Path(folder) / 'profile.json'
            old_drop = camera.MARKER.encode() + b'old override\n'
            old_profile = b'{"old":true}\n'
            drop.write_bytes(old_drop)
            profile.write_bytes(old_profile)
            calls = []
            starts = 0
            def command(*args):
                nonlocal starts
                calls.append(args)
                if args[:2] == ('systemctl', 'start'):
                    starts += 1
                    if starts == 1:
                        raise RuntimeError('Injected failed sensor startup')
                return ''
            with patch.object(camera, 'DROP_IN', drop), patch.object(camera, 'PROFILE', profile), \
                 patch.object(camera, 'runtime_modules'), patch.object(camera, 'active', return_value=True), \
                 patch.object(camera, 'checked', side_effect=command), patch.object(camera, 'wait_ready'):
                with self.assertRaisesRegex(RuntimeError, 'previous configuration and service state restored'):
                    camera.configure(camera.make_profile(2, 1))
            self.assertEqual(drop.read_bytes(), old_drop)
            self.assertEqual(profile.read_bytes(), old_profile)
            self.assertEqual(starts, 2)
            self.assertEqual(calls[-1], ('systemctl', 'start', camera.RECOGNITION))

    def test_receipt_failure_stops_preview_before_stock_rollback(self):
        class Display:
            stopped = False
            def status(self):
                return {'running': 0, 'source_epoch': 1}
            def start(self):
                pass
            def stop(self):
                self.stopped = True
            def close(self):
                pass
        device = Display()
        test_root = Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(dir=test_root) as folder:
            self.assertTrue(Path(folder).resolve().is_relative_to(test_root))
            profile = Path(folder) / 'profile.json'
            profile.write_text(json.dumps(camera.make_profile(8, 1)))
            with patch.object(camera, 'PROFILE', profile), \
                 patch.object(camera, 'runtime_modules', return_value=lambda: device), \
                 patch.dict(sys.modules, {'ax7021b_qr.r4_startup': SimpleNamespace(verify_board=lambda root: None)}), \
                 patch.object(camera, 'init_sensor', return_value={}), \
                 patch.object(camera.Path, 'read_text', side_effect=lambda *args, **kwargs: json.dumps(camera.make_profile(8, 1))), \
                 patch.object(camera, 'atomic_json', side_effect=OSError('injected failed receipt write')):
                with self.assertRaises(OSError):
                    camera.start_preview()
            self.assertTrue(device.stopped)


if __name__ == '__main__':
    unittest.main()
