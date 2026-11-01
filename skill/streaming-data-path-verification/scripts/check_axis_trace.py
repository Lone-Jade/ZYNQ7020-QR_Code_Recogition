"""Check complete cycle samples for a one-pixel/full-keep AXIS video profile."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import sys


def integer(text):
    if not re.fullmatch(r'(?:0[xX][0-9a-fA-F]+|[0-9]+)', text):
        raise ValueError('unknown or invalid unsigned sample: ' + repr(text))
    return int(text, 16 if text.lower().startswith('0x') else 10)


def inspect(path, width, height, data_bits, frames, allow_reset_abort=False, expected=None, expected_sha=None):
    result = {'schema_version': 1, 'errors': [], 'error_count': 0, 'accepted_beats': 0,
              'completed_frames': 0, 'aborted_frames': 0,
              'profile': {'width': width, 'height': height, 'data_bits': data_bits, 'requested_frames': frames},
              'limitations': ['Single-pixel/full-keep/scalar-SOF profile; no CDC or timing proof.',
                              'Payload correctness is checked only with explicit golden data.']}
    def error(message):
        result['error_count'] += 1
        if len(result['errors']) < 20:
            result['errors'].append(message)
    position, held, previous_cycle, samples = 0, None, None, 0
    golden = None
    try:
        if any(type(n) is not int or n <= 0 for n in (width, height, frames)) or data_bits not in (8, 16, 32, 64):
            raise ValueError('positive geometry/frames and data_bits 8/16/32/64 required')
        if allow_reset_abort and expected is not None:
            raise ValueError('golden comparison cannot index aborted frames')
        if expected is not None:
            golden = expected.read_bytes()
            result['expected_sha256'] = hashlib.sha256(golden).hexdigest()
            if result['expected_sha256'].lower() != str(expected_sha).lower():
                error('golden SHA-256 mismatch')
            if len(golden) != frames * width * height * (data_bits // 8):
                raise ValueError('golden byte length does not match declared complete frames')
        raw = path.read_bytes()
        result['trace_sha256'] = hashlib.sha256(raw).hexdigest()
        reader = csv.DictReader(raw.decode('utf-8-sig').splitlines())
        required = ['cycle', 'reset_n', 'valid', 'ready', 'data', 'keep', 'user', 'last']
        if not reader.fieldnames or any(reader.fieldnames.count(k) != 1 for k in required):
            raise ValueError('missing or repeated required CSV columns')
        for row in reader:
            samples += 1
            cycle = integer(row['cycle'])
            if previous_cycle is not None and cycle != previous_cycle + 1:
                raise ValueError('trace cycles must be consecutive')
            previous_cycle = cycle
            bits = {k: integer(row[k]) for k in ('reset_n', 'valid', 'ready')}
            if any(v not in (0, 1) for v in bits.values()):
                raise ValueError('reset/valid/ready must be 0 or 1')
            if not bits['reset_n']:
                if position or held is not None:
                    if not allow_reset_abort:
                        error('cycle %d: reset aborts an in-flight item/frame' % cycle)
                    result['aborted_frames'] += 1
                position, held = 0, None
                continue
            bundle = None
            if bits['valid']:
                bundle = tuple(integer(row[k]) for k in ('data', 'keep', 'user', 'last'))
                data, keep, user, last = bundle
                if data >= 1 << data_bits or keep >= 1 << (data_bits // 8) or user not in (0, 1) or last not in (0, 1):
                    raise ValueError('valid payload/sideband exceeds declared width')
            if held is not None and (not bits['valid'] or bundle != held):
                error('cycle %d: stalled valid item changed before acceptance' % cycle)
            if bits['valid'] and bits['ready']:
                if keep != (1 << (data_bits // 8)) - 1:
                    error('cycle %d: partial TKEEP outside supported profile' % cycle)
                if user != int(position == 0):
                    error('cycle %d: SOF does not match accepted pixel position' % cycle)
                if last != int(position % width == width - 1):
                    error('cycle %d: EOL does not match accepted pixel position' % cycle)
                if golden is not None:
                    offset = result['accepted_beats'] * (data_bits // 8)
                    chunk = golden[offset:offset + data_bits // 8]
                    if len(chunk) != data_bits // 8 or data != int.from_bytes(chunk, 'little'):
                        error('cycle %d: accepted payload differs at beat %d' % (cycle, result['accepted_beats']))
                result['accepted_beats'] += 1
                position += 1
                if position == width * height:
                    position = 0
                    result['completed_frames'] += 1
            held = bundle if bits['valid'] and not bits['ready'] else None
        if not samples:
            error('trace contains no samples')
        if position:
            error('EOF contains a partial frame')
        if held is not None:
            error('EOF contains an unaccepted stalled item')
        if result['completed_frames'] != frames:
            error('completed frame count differs from request')
    except (OSError, ValueError, KeyError, TypeError) as exc:
        error(str(exc))
    result['samples'] = samples
    result['passed'] = result['error_count'] == 0
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    for name in ('width', 'height', 'data-bits', 'frames'):
        parser.add_argument('--' + name, type=int, required=True)
    parser.add_argument('--allow-reset-abort', action='store_true')
    parser.add_argument('--expected-data', type=Path)
    parser.add_argument('--expected-sha256')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if bool(args.expected_data) != bool(args.expected_sha256):
        parser.error('golden data and its SHA-256 must be supplied together')
    report = inspect(args.trace, args.width, args.height, args.data_bits, args.frames,
                     args.allow_reset_abort, args.expected_data, args.expected_sha256)
    text = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
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
