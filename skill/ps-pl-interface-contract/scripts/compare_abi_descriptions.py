#!/usr/bin/env python3
"""Validate and compare supplied normalized descriptions, never live hardware."""
import argparse
import copy
import json
import sys
from pathlib import Path


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key: ' + key)
        result[key] = value
    return result


def keys(value, expected):
    if not isinstance(value, dict) or set(value) != set(expected.split()):
        raise ValueError('expected object keys: ' + expected)


def integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError('invalid integer')


def string(value):
    if not isinstance(value, str) or not value.strip():
        raise ValueError('expected nonempty string')


def spans(items, limit):
    end = 0
    for start, stop in sorted(items):
        if start < end or stop > limit:
            raise ValueError('overlap or out-of-bounds span')
        end = stop


def normalize(data):
    data = copy.deepcopy(data)
    if not isinstance(data, dict):
        raise ValueError('expected contract object')
    provenance = data.pop('provenance', {})
    if not isinstance(provenance, dict):
        raise ValueError('provenance must be an object')
    keys(data, 'format target abi_version mmio structures ioctls identity_fields completion')
    if type(data['format']) is not int or data['format'] != 1:
        raise ValueError('expected format 1')
    string(data['target']); string(data['completion']); integer(data['abi_version'])
    mmio = data['mmio']
    keys(mmio, 'base size byte_order registers')
    integer(mmio['base']); integer(mmio['size'], 1)
    if mmio['byte_order'] not in ('little', 'big') or not isinstance(mmio['registers'], list):
        raise ValueError('invalid MMIO byte order/registers')
    names, ranges = set(), []
    for reg in mmio['registers']:
        keys(reg, 'name offset width access reset semantics')
        string(reg['name']); string(reg['semantics']); integer(reg['offset'])
        if reg['name'] in names:
            raise ValueError('duplicate register name')
        names.add(reg['name'])
        if type(reg['width']) is not int or reg['width'] not in (8, 16, 32, 64):
            raise ValueError('unsupported register width')
        integer(reg['reset'])
        if (reg['offset'] % (reg['width'] // 8)
                or (mmio['base'] + reg['offset']) % (reg['width'] // 8)
                or reg['reset'] >= 2 ** reg['width']
                or reg['access'] not in ('ro', 'rw', 'wo', 'w1c', 'rc')):
            raise ValueError('invalid register alignment/reset/access')
        ranges.append((reg['offset'], reg['offset'] + reg['width'] // 8))
    spans(ranges, mmio['size'])
    mmio['registers'].sort(key=lambda r: r['name'])
    if not isinstance(data['structures'], dict):
        raise ValueError('structures must be an object')
    for name, structure in data['structures'].items():
        string(name); keys(structure, 'size alignment fields')
        integer(structure['size'], 1); integer(structure['alignment'], 1)
        align = structure['alignment']
        if align & (align - 1) or structure['size'] % align or not isinstance(structure['fields'], list):
            raise ValueError('invalid structure size/alignment/fields')
        names, ranges = set(), []
        for field in structure['fields']:
            keys(field, 'name offset size type')
            string(field['name']); string(field['type']); integer(field['offset']); integer(field['size'], 1)
            if field['name'] in names:
                raise ValueError('duplicate structure field')
            names.add(field['name'])
            ranges.append((field['offset'], field['offset'] + field['size']))
        spans(ranges, structure['size'])
        if sum(b - a for a, b in ranges) != structure['size']:
            raise ValueError('all structure bytes need explicit fields/padding')
        structure['fields'].sort(key=lambda f: f['name'])
    if not isinstance(data['ioctls'], list):
        raise ValueError('ioctls must be an array')
    names, numbers = set(), set()
    for command in data['ioctls']:
        keys(command, 'name number direction argument')
        string(command['name']); integer(command['number'])
        if command['name'] in names or command['number'] in numbers:
            raise ValueError('duplicate ioctl name/number')
        names.add(command['name']); numbers.add(command['number'])
        if command['direction'] not in ('none', 'read', 'write', 'readwrite'):
            raise ValueError('invalid ioctl direction')
        arg = command['argument']
        if ((command['direction'] == 'none' and arg is not None)
                or (command['direction'] != 'none' and (not isinstance(arg, str) or arg not in data['structures']))):
            raise ValueError('invalid or missing ioctl structure reference')
    data['ioctls'].sort(key=lambda c: c['name'])
    identities = data['identity_fields']
    if not isinstance(identities, list) or not identities:
        raise ValueError('identity_fields must be nonempty')
    for identity in identities:
        string(identity)
    if len(set(identities)) != len(identities):
        raise ValueError('duplicate identity field')
    return data


def changes(before, after, path='$'):
    if isinstance(before, dict) and isinstance(after, dict):
        result = []
        for key in sorted(before.keys() | after.keys()):
            if key not in before or key not in after:
                result.append({'path': path + '.' + key, 'change': 'added' if key not in before else 'removed'})
            else:
                result.extend(changes(before[key], after[key], path + '.' + key))
        return result
    if before != after:
        return [{'path': path, 'before': before, 'after': after}]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    args = parser.parse_args()
    try:
        before, after = [normalize(json.loads(p.read_text(), object_pairs_hook=unique)) for p in (args.before, args.after)]
        delta = changes(before, after)
    except (ValueError, TypeError, OSError) as error:
        print(json.dumps({'status': 'invalid_contract', 'error': str(error)}))
        return 2
    print(json.dumps({'status': 'requires_review' if delta else 'same_description', 'changes': delta}))
    return 1 if delta else 0


if __name__ == '__main__':
    sys.exit(main())
