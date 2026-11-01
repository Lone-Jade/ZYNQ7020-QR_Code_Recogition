"""Verify SDK chunks and optionally restore the exact source archive."""
from pathlib import Path
from paths import PROJECT
from fetch_dependencies import acquire, destination
import argparse
import hashlib
import json


def restore(vendor, output=None):
    vendor = Path(vendor)
    meta = json.loads((vendor / 'kernel-sdk.json').read_text())
    acquire('kernel-sdk', check=True)
    digest = hashlib.sha256()
    size = 0
    temporary = Path(str(output) + '.tmp') if output else None
    if temporary:
        temporary.parent.mkdir(parents=True, exist_ok=True)
    handle = temporary.open('wb') if temporary else None
    try:
        for chunk in meta['chunks']:
            chunk_digest = hashlib.sha256()
            chunk_size = 0
            with destination('kernel-sdk', chunk).open('rb') as source:
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    chunk_digest.update(block)
                    digest.update(block)
                    chunk_size += len(block)
                    if handle:
                        handle.write(block)
            if chunk_size != chunk['bytes'] or chunk_digest.hexdigest() != chunk['sha256']:
                raise ValueError('SDK chunk checksum mismatch: ' + chunk['file'])
            size += chunk_size
        if size != meta['bytes'] or digest.hexdigest() != meta['sha256']:
            raise ValueError('SDK archive checksum mismatch')
        if handle:
            handle.close()
            handle = None
            temporary.replace(output)
    finally:
        if handle:
            handle.close()
        if temporary and temporary.exists():
            temporary.unlink()
    return dict(passed=True, chunks=len(meta['chunks']), bytes=size, sha256=digest.hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assemble', action='store_true', help='Restore under build/work/ after verification')
    args = parser.parse_args()
    output = PROJECT / 'build/work/kernel-sdk.tar.gz' if args.assemble else None
    print(json.dumps(restore(PROJECT / 'src/vendor', output), indent=2))
