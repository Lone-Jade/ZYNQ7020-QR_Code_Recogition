"""Stage board installation sources with a verified boot/runtime pair; never deploy."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

from paths import PROJECT


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--firmware', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    runtime, firmware, output = args.runtime.resolve(), args.firmware.resolve(), args.output.resolve()
    if not output.is_relative_to((PROJECT / 'build/outputs').resolve()) or output.exists():
        parser.error('--output must be a new directory under build/outputs')
    manifest = json.loads((runtime / 'RUNTIME_MANIFEST.json').read_text())
    actual = {p.relative_to(runtime).as_posix() for p in runtime.rglob('*')
              if p.is_file() and p.name != 'RUNTIME_MANIFEST.json'}
    if actual != set(manifest['sha256']):
        raise ValueError('Runtime inventory differs')
    for name, wanted in manifest['sha256'].items():
        path = runtime / name
        if not path.resolve().is_relative_to(runtime) or path.is_symlink() or sha(path) != wanted:
            raise ValueError('Runtime integrity: ' + name)
    boot = manifest.get('boot_sha256', {})
    if set(boot) != {'BOOT.BIN', 'image.ub', 'boot.scr'}:
        raise ValueError('Runtime must bind all three boot files')
    for name, wanted in boot.items():
        if sha(firmware / name) != wanted:
            raise ValueError('Boot/runtime mismatch: ' + name)
    shutil.copytree(PROJECT / 'board', output,
                    ignore=shutil.ignore_patterns('boot', 'runtime', '__pycache__', '*.pyc'))
    shutil.copytree(runtime, output / 'runtime')
    (output / 'boot').mkdir()
    for name in boot:
        shutil.copy2(firmware / name, output / 'boot' / name)
    print(json.dumps(dict(staged=str(output), runtime_manifest_sha256=sha(runtime / 'RUNTIME_MANIFEST.json'),
                          installed=False, board_tested=False), indent=2))


if __name__ == '__main__':
    main()
