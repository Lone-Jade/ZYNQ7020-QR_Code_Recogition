"""Compare hash-bound typed binary stages without executing or rewriting code."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

TYPES = {'u8': ('<B', 1), 'u16le': ('<H', 2), 'i16le': ('<h', 2),
         'u32le': ('<I', 4), 'i32le': ('<i', 4), 'f32le': ('<f', 4), 'f64le': ('<d', 8)}


def tolerance(value):
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        raise ValueError('tolerance must be finite, nonnegative and numeric')
    return value


def compare_stage(stage, base):
    out = {'name': stage.get('name'), 'passed': False, 'mismatches': [], 'mismatch_count': 0}
    try:
        fmt, size = TYPES[stage['dtype']]
        shape = stage['shape']
        if not isinstance(shape, list) or not shape or any(type(n) is not int or n <= 0 for n in shape):
            raise ValueError('shape must contain positive integer extents')
        count = math.prod(shape)
        absolute, relative = tolerance(stage.get('abs_tol', 0)), tolerance(stage.get('rel_tol', 0))
        expected_hash = stage['reference_sha256']
        if not isinstance(expected_hash, str) or len(expected_hash) != 64 or any(c not in '0123456789abcdefABCDEF' for c in expected_hash):
            raise ValueError('reference_sha256 must have 64 hex digits')
        ref_path, actual_path = base / stage['reference'], base / stage['actual']
        reference, actual = ref_path.read_bytes(), actual_path.read_bytes()
        out.update(dtype=stage['dtype'], shape=shape,
                   reference_sha256=hashlib.sha256(reference).hexdigest(),
                   actual_sha256=hashlib.sha256(actual).hexdigest(),
                   abs_tol=absolute, rel_tol=relative)
        if out['reference_sha256'] != expected_hash.lower():
            raise ValueError('frozen reference SHA-256 mismatch')
        if len(reference) != count * size or len(actual) != count * size:
            raise ValueError('byte lengths do not match declared shape and dtype')
        max_error = 0
        nonfinite = 0
        for i, (r, a) in enumerate(zip(struct.iter_unpack(fmt, reference), struct.iter_unpack(fmt, actual))):
            r, a = r[0], a[0]
            if not math.isfinite(r) or not math.isfinite(a):
                nonfinite += 1
                delta, passed = None, False
            else:
                delta = abs(a - r)
                limit = absolute + relative * abs(r)
                if not math.isfinite(delta) or not math.isfinite(limit):
                    nonfinite += 1
                    delta, passed = None, False
                else:
                    max_error = max(max_error, delta)
                    passed = delta <= limit
            if not passed:
                out['mismatch_count'] += 1
                if len(out['mismatches']) < 10:
                    out['mismatches'].append({'flat_index': i,
                        'reference': r if math.isfinite(r) else str(r),
                        'actual': a if math.isfinite(a) else str(a), 'abs_error': delta})
        out.update(elements=count, max_finite_abs_error=max_error, nonfinite_errors=nonfinite)
        out['passed'] = out['mismatch_count'] == 0
    except (OSError, ValueError, KeyError, TypeError, OverflowError, struct.error) as error:
        out['error'] = str(error)
    return out


def inspect(path):
    report = {'schema_version': 1, 'stages': [], 'passed': False,
              'limitations': ['Checks only declared ordered numeric arrays, not algorithm semantics or target execution.']}
    try:
        raw = path.read_bytes()
        obj = json.loads(raw.decode('utf-8-sig'))
        if not isinstance(obj, dict) or type(obj.get('schema_version')) is not int or obj['schema_version'] != 1:
            raise ValueError('expected manifest object schema_version=1')
        stages = obj['stages']
        if not isinstance(stages, list) or not stages:
            raise ValueError('stages must be a nonempty list')
        names = set()
        for stage in stages:
            if not isinstance(stage, dict) or not isinstance(stage.get('name'), str) or not stage['name'] or stage['name'] in names:
                raise ValueError('stage names must be nonempty and unique')
            names.add(stage['name'])
        report['manifest_sha256'] = hashlib.sha256(raw).hexdigest()
        report['stages'] = [compare_stage(s, path.resolve().parent) for s in stages]
        report['first_failing_stage'] = next((s['name'] for s in report['stages'] if not s['passed']), None)
        report['passed'] = all(s['passed'] for s in report['stages'])
    except (OSError, ValueError, KeyError, TypeError) as error:
        report['error'] = str(error)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = inspect(args.manifest)
    text = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    if args.report:
        try:
            with args.report.open('x', encoding='utf-8', newline='\n') as stream:
                stream.write(text)
        except OSError as error:
            print(str(error), file=sys.stderr)
            return 2
    print(text, end='')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
