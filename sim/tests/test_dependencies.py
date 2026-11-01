"""Check dependency corruption handling and camera binding after a source rebuild."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'build/scripts'))
import fetch_dependencies as dependencies

spec = importlib.util.spec_from_file_location('source_installer', ROOT / 'board/control/install_manual.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class SourceDependencies(unittest.TestCase):
    def test_corrupt_download_is_rejected_and_never_cached(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'inputs'
            source.mkdir()
            payload = b'exact matched platform input'
            asset = dict(file='zImage', bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())
            metadata = dict(repository='unused', release_tag='unused', groups={'platform': [asset]})
            (source / 'zImage').write_bytes(b'x' * len(payload))
            with patch.object(dependencies, 'PROJECT', root), patch.object(dependencies, 'lock', return_value=metadata):
                with self.assertRaises(ValueError):
                    dependencies.acquire('platform', source)
                target = root / 'build/deps/platform/zImage'
                self.assertFalse(target.exists())
                (source / 'zImage').write_bytes(payload)
                dependencies.acquire('platform', source)
                self.assertEqual(target.read_bytes(), payload)
                target.write_bytes(b'x' * len(payload))
                with self.assertRaises(ValueError):
                    dependencies.acquire('platform', check=True)

    def test_dependency_cannot_escape_cache_directory(self):
        for name in ['../zImage', '/tmp/zImage']:
            with self.assertRaises(ValueError):
                dependencies.destination('platform', {'file': name})

    def test_rebuilt_camera_controller_uses_new_runtime_identity(self):
        source = (ROOT / 'board/control/camera/camera_control.py').read_text()
        expected = hashlib.sha256(b'rebuilt runtime manifest').hexdigest()
        installed = installer.bind_camera_runtime(source, expected)
        module = ast.parse(installed)
        assignments = {node.targets[0].id: node.value for node in module.body
                       if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)}
        self.assertEqual(ast.literal_eval(assignments['RUNTIME_SHA']), expected)
        with tempfile.TemporaryDirectory() as temporary:
            controller_path = Path(temporary) / 'camera_control.py'
            controller_path.write_text(installed)
            controller_spec = importlib.util.spec_from_file_location('rebuilt_camera', controller_path)
            controller = importlib.util.module_from_spec(controller_spec)
            controller_spec.loader.exec_module(controller)
            self.assertEqual(controller.make_auto_profile()['runtime_manifest_sha256'], expected)
            with patch.object(controller, 'RUNTIME', Path(temporary)):
                (Path(temporary) / 'RUNTIME_MANIFEST.json').write_bytes(b'wrong runtime')
                with self.assertRaises(RuntimeError):
                    controller.runtime_modules()
        with self.assertRaises(ValueError):
            installer.bind_camera_runtime(source, 'invalid')


if __name__ == '__main__':
    unittest.main()
