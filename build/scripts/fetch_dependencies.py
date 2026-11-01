"""Fetch hash-pinned build inputs from this repository's GitHub Release."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request

from paths import PROJECT


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def lock():
    return json.loads((PROJECT / 'build/DEPENDENCIES.json').read_text())


def valid(path, asset):
    return (path.is_file() and not path.is_symlink()
            and path.stat().st_size == asset['bytes']
            and digest(path) == asset['sha256'])


def destination(group, asset):
    name = asset['file']
    if Path(name).name != name or name in ('.', '..'):
        raise ValueError('Invalid dependency filename')
    root = PROJECT / 'build/deps'
    path = root / group / name
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Dependency path escapes build/deps')
    return path


def acquire(group, source_dir=None, check=False):
    meta = lock()
    if group not in meta['groups']:
        raise ValueError('Unknown dependency group: ' + group)
    result = []
    gh = shutil.which('gh')
    authenticated = bool(not check and not source_dir and gh and subprocess.run(
        [gh, 'auth', 'status', '--hostname', 'github.com'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0)
    for asset in meta['groups'][group]:
        target = destination(group, asset)
        if not valid(target, asset):
            if check:
                raise ValueError('Missing or corrupt dependency: ' + str(target)
                                 + '; run build/scripts/fetch_dependencies.py --group ' + group)
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='.download-', dir=target.parent) as folder:
                temporary = Path(folder) / asset['file']
                if source_dir:
                    shutil.copyfile(Path(source_dir) / asset['file'], temporary)
                elif authenticated:
                    subprocess.run([gh, 'release', 'download', meta['release_tag'],
                                    '--repo', meta['repository'], '--pattern', asset['file'],
                                    '--dir', folder], check=True)
                else:
                    url = ('https://github.com/' + meta['repository'] + '/releases/download/'
                           + meta['release_tag'] + '/' + asset['file'])
                    try:
                        request = urllib.request.Request(url, headers={'User-Agent': 'zynq-qr-source-build'})
                        with urllib.request.urlopen(request, timeout=60) as response, temporary.open('wb') as handle:
                            shutil.copyfileobj(response, handle)
                    except (urllib.error.URLError, TimeoutError) as error:
                        raise RuntimeError('Cannot download ' + asset['file']
                                           + '. For a private repository, install GitHub CLI and run gh auth login; '
                                           'or use --source-dir with the original dependency files.') from error
                if not valid(temporary, asset):
                    raise ValueError('Dependency size/SHA-256 mismatch: ' + asset['file'])
                os.replace(temporary, target)
        result.append(asset['file'])
    return dict(group=group, passed=True, files=result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', choices=['kernel-sdk', 'platform', 'all'], default='all')
    parser.add_argument('--source-dir', type=Path,
                        help='Use existing files by asset basename instead of downloading')
    parser.add_argument('--check', action='store_true', help='Verify cached dependencies without fetching')
    args = parser.parse_args()
    if args.group == 'all' and args.source_dir:
        parser.error('--source-dir requires one explicit --group')
    groups = ['kernel-sdk', 'platform'] if args.group == 'all' else [args.group]
    print(json.dumps([acquire(group, args.source_dir, args.check) for group in groups], indent=2))


if __name__ == '__main__':
    main()
