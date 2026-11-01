#!/usr/bin/env python3
"""Verify an explicit regular-file release manifest; never execute or alter it."""
import argparse
import hashlib
import json
import re
import stat
import sys
from pathlib import Path, PurePosixPath


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def verify(root, manifest):
    if not isinstance(manifest, dict) or type(manifest.get('format')) is not int or manifest['format'] != 1:
        raise ValueError('expected manifest format 1')
    files = manifest.get('files')
    if not isinstance(files, dict) or not files:
        raise ValueError('files must be a nonempty relative-path/SHA-256 object')
    checked, errors = 0, []
    for relative, digest in files.items():
        path = PurePosixPath(relative)
        if (not relative or ':' in relative or '\\' in relative or path.is_absolute()
                or '..' in path.parts or path.as_posix() != relative or relative == '.'):
            raise ValueError(f'noncanonical or escaping path: {relative}')
        if not isinstance(digest, str) or re.fullmatch(r'[0-9a-fA-F]{64}', digest) is None:
            raise ValueError(f'invalid SHA-256: {relative}')
        current = root
        try:
            for part in path.parts:
                current = current / part
                if current.is_symlink():
                    raise ValueError('symlink component')
            if not stat.S_ISREG(current.stat().st_mode):
                raise ValueError('not a regular file')
            value = hashlib.sha256()
            with current.open('rb') as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    value.update(chunk)
            if value.hexdigest() != digest.lower():
                raise ValueError('SHA-256 mismatch')
            checked += 1
        except (OSError, ValueError) as error:
            errors.append({'path': relative, 'error': str(error)})
    return {'passed': not errors, 'checked': checked, 'declared': len(files), 'errors': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        if not root.is_dir():
            raise ValueError('root must be a directory')
        manifest = json.loads(args.manifest.read_text(encoding='utf-8'), object_pairs_hook=unique_object)
        result = verify(root, manifest)
    except (OSError, ValueError, TypeError) as error:
        print(json.dumps({'passed': False, 'input_error': str(error)}))
        return 2
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
