#!/usr/bin/env python3
"""Create/verify a bounded frozen Gray8 case; no devices or runner execution."""
import argparse
import hashlib
import json
import re
import stat
import sys
from pathlib import Path, PurePosixPath


def unique(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError('duplicate JSON key: ' + key)
        obj[key] = value
    return obj


def keys(obj, names):
    if not isinstance(obj, dict) or set(obj) != set(names.split()):
        raise ValueError('expected object keys: ' + names)


def integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError('invalid integer')


def name(value):
    if not isinstance(value, str) or re.fullmatch(r'[a-z][a-z0-9_-]{0,63}', value) is None:
        raise ValueError('invalid case/role name')


def relative(value):
    if not isinstance(value, str) or not value:
        raise ValueError('expected relative path')
    p = PurePosixPath(value)
    if p.is_absolute() or ':' in value or '..' in p.parts or '\\' in value or p.as_posix() != value or value == '.':
        raise ValueError('unsafe/noncanonical path: ' + value)
    return p


def regular(root, value):
    p = root
    for part in relative(value).parts:
        p = p / part
        if p.is_symlink():
            raise ValueError('symlink component: ' + value)
    if not stat.S_ISREG(p.stat().st_mode):
        raise ValueError('expected regular file: ' + value)
    return p


def load(path):
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique)


def metadata(obj):
    if type(obj['format']) is not int or obj['format'] != 1:
        raise ValueError('expected format 1')
    name(obj['case_id'])
    if not isinstance(obj['failure'], str) or not obj['failure'].strip():
        raise ValueError('failure must be nonempty text')
    keys(obj['identity'], 'epoch frame config generation')
    if any(not (type(v) is int or isinstance(v, str) and v) for v in obj['identity'].values()):
        raise ValueError('invalid source identity')
    keys(obj['provenance'], 'source_commit package_sha256 kernel_release boot_id clock_domain')
    for key, value in obj['provenance'].items():
        if value is not None and (not isinstance(value, str) or not value.strip()):
            raise ValueError('invalid provenance: ' + key)
    digest = obj['provenance']['package_sha256']
    if digest is not None and re.fullmatch(r'[a-fA-F0-9]{64}', digest) is None:
        raise ValueError('invalid package SHA-256')
    image = obj['image']
    keys(image, 'path pixel_format width height stride')
    relative(image['path'])
    if image['pixel_format'] != 'gray8':
        raise ValueError('this helper supports frozen Gray8 only')
    for key in ('width', 'height', 'stride'):
        integer(image[key], 1)
    if image['stride'] < image['width']:
        raise ValueError('stride is smaller than width')
    if not isinstance(obj['rois'], list):
        raise ValueError('rois must be an array')
    for roi in obj['rois']:
        keys(roi, 'x y width height')
        integer(roi['x']); integer(roi['y']); integer(roi['width'], 1); integer(roi['height'], 1)
        if roi['x'] + roi['width'] > image['width'] or roi['y'] + roi['height'] > image['height']:
            raise ValueError('ROI outside original frame')
    if not isinstance(obj['artifacts'], dict):
        raise ValueError('artifacts must be an object')
    for role, path in obj['artifacts'].items():
        name(role); relative(path)
    return ['unknown provenance: ' + key for key, v in obj['provenance'].items() if v is None]


def read_limited(path, remaining):
    if path.stat().st_size > remaining:
        raise ValueError('aggregate payload budget exceeded')
    with path.open('rb') as source:
        data = source.read(remaining + 1)
    if len(data) > remaining:
        raise ValueError('aggregate payload budget exceeded')
    return data


def create(spec_path, output, budget):
    obj = load(spec_path)
    keys(obj, 'format case_id failure identity provenance image rois artifacts')
    warnings = metadata(obj)
    root = spec_path.parent.resolve(strict=True)
    sources = {'inputs/frame.raw': obj['image']['path']}
    sources.update({'inputs/artifacts/' + role: path for role, path in obj['artifacts'].items()})
    payload, total = {}, 0
    for destination, source in sources.items():
        data = read_limited(regular(root, source), budget - total)
        total += len(data)
        payload[destination] = data
    if len(payload['inputs/frame.raw']) != obj['image']['height'] * obj['image']['stride']:
        raise ValueError('image byte count must equal height times stride')
    obj['image']['path'] = 'inputs/frame.raw'
    obj['artifacts'] = {role: 'inputs/artifacts/' + role for role in obj['artifacts']}
    obj['files'] = {path: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                    for path, data in payload.items()}
    output.mkdir(parents=True, exist_ok=False)
    for path, data in payload.items():
        dest = output / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open('xb') as stream:
            stream.write(data)
    with (output / 'manifest.json').open('x', encoding='utf-8') as stream:
        json.dump(obj, stream, indent=2, ensure_ascii=True)
        stream.write('\n')
    result = verify(output, budget)
    result['warnings'] = warnings
    return result


def verify(root, budget):
    root = root.resolve(strict=True)
    obj = load(regular(root, 'manifest.json'))
    keys(obj, 'format case_id failure identity provenance image rois artifacts files')
    warnings = metadata(obj)
    expected = {'inputs/frame.raw'} | {'inputs/artifacts/' + role for role in obj['artifacts']}
    if (obj['image']['path'] != 'inputs/frame.raw'
            or any(path != 'inputs/artifacts/' + role for role, path in obj['artifacts'].items())
            or not isinstance(obj['files'], dict) or set(obj['files']) != expected):
        raise ValueError('manifest payload paths do not match metadata')
    actual = set()
    for path in root.rglob('*'):
        if path.is_symlink():
            raise ValueError('bundle contains symlink')
        if not path.is_dir():
            actual.add(path.relative_to(root).as_posix())
    if actual != expected | {'manifest.json'}:
        raise ValueError('unlisted or missing bundle files')
    total = 0
    for path, info in obj['files'].items():
        keys(info, 'bytes sha256'); integer(info['bytes'])
        if not isinstance(info['sha256'], str) or re.fullmatch(r'[a-fA-F0-9]{64}', info['sha256']) is None:
            raise ValueError('invalid file SHA-256')
        data = read_limited(regular(root, path), budget - total)
        total += len(data)
        if len(data) != info['bytes'] or hashlib.sha256(data).hexdigest() != info['sha256'].lower():
            raise ValueError('payload length/hash mismatch: ' + path)
    if obj['files']['inputs/frame.raw']['bytes'] != obj['image']['height'] * obj['image']['stride']:
        raise ValueError('image geometry/length mismatch')
    return {'integrity': 'verified', 'case_id': obj['case_id'], 'files': len(expected),
            'payload_bytes': total, 'warnings': warnings, 'failure_reproduced': None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    make = sub.add_parser('create')
    make.add_argument('--spec', required=True, type=Path)
    make.add_argument('--output', required=True, type=Path)
    read = sub.add_parser('verify')
    read.add_argument('--bundle', required=True, type=Path)
    for p in (make, read):
        p.add_argument('--max-bytes', type=int, default=64 * 1024 * 1024)
    args = parser.parse_args()
    try:
        integer(args.max_bytes, 1)
        result = create(args.spec, args.output, args.max_bytes) if args.command == 'create' else verify(args.bundle, args.max_bytes)
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(json.dumps({'integrity': 'failed', 'error': str(error)}))
        return 1
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
