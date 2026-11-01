"""Check explicit flat PS/PL reservations and selected C literals; read-only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


def number(value):
    if type(value) is int:
        return value
    if isinstance(value, str) and re.fullmatch(r'(?:0[xX][0-9a-fA-F]+|[0-9]+)', value):
        return int(value, 16 if value.lower().startswith('0x') else 10)
    raise ValueError('expected an integer or unsigned decimal/hex string')


def power_two(n):
    return n > 0 and n & (n - 1) == 0


def load_contract(path):
    raw = path.read_bytes()
    obj = json.loads(raw.decode('utf-8-sig'))
    errors, symbols, regions = [], {}, []
    if not isinstance(obj, dict) or type(obj.get('schema_version')) is not int or obj['schema_version'] != 1:
        raise ValueError('expected contract object schema_version=1')
    bits = number(obj['address_bits'])
    line = number(obj['cache_line_bytes'])
    if bits not in (32, 64) or not power_two(line):
        raise ValueError('address_bits must be 32/64; cache_line_bytes a power of two')

    def symbol(name, value):
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name):
            raise ValueError('invalid C symbol name')
        if name in symbols:
            raise ValueError('repeated selected symbol: ' + name)
        symbols[name] = value

    for name, value in obj.get('symbols', {}).items():
        symbol(name, number(value))
    items = obj['regions']
    if not isinstance(items, list) or not items:
        raise ValueError('regions must be a nonempty list')
    names = set()
    for item in items:
        name = item['name']
        if not isinstance(name, str) or not name or name in names:
            raise ValueError('region names must be nonempty and unique')
        names.add(name)
        base, size, align = (number(item[k]) for k in ('base', 'size', 'alignment'))
        if base < 0 or size <= 0 or base + size > 1 << bits:
            errors.append(name + ': invalid/overflowing region')
        if not power_two(align) or base % align:
            errors.append(name + ': base alignment failure')
        if item['kind'] not in ('memory', 'mmio'):
            raise ValueError(name + ': unknown region kind')
        normalized = {'name': name, 'kind': item['kind'], 'base': base, 'size': size,
                      'alignment': align, 'registers': []}
        for field, value in (('base_symbol', base), ('size_symbol', size)):
            if field in item:
                symbol(item[field], value)
        regs = item.get('registers', [])
        if regs and item['kind'] != 'mmio':
            errors.append(name + ': registers require mmio kind')
        reg_names = set()
        for reg in regs:
            rn = reg['name']
            if not isinstance(rn, str) or not rn or rn in reg_names:
                raise ValueError(name + ': repeated/invalid register name')
            reg_names.add(rn)
            offset, width = number(reg['offset']), number(reg['width_bytes'])
            if width not in (1, 2, 4, 8) or offset < 0 or offset + width > size or offset % width:
                errors.append(name + '/' + rn + ': invalid width, offset or extent')
            access = reg['access']
            if not isinstance(access, str) or not access.strip():
                raise ValueError(name + '/' + rn + ': missing access label')
            normalized['registers'].append({'name': rn, 'offset': offset, 'width_bytes': width, 'access': access})
            if 'symbol' in reg:
                symbol(reg['symbol'], offset)
        rr = sorted(normalized['registers'], key=lambda x: x['offset'])
        for i, a in enumerate(rr):
            for b in rr[i + 1:]:
                if b['offset'] < a['offset'] + a['width_bytes']:
                    errors.append(name + ': overlapping registers ' + a['name'] + '/' + b['name'])
        normalized['registers'].sort(key=lambda r: r['name'])
        regions.append(normalized)
    for i, a in enumerate(regions):
        for b in regions[i + 1:]:
            if max(a['base'], b['base']) < min(a['base'] + a['size'], b['base'] + b['size']):
                errors.append('overlapping regions: ' + a['name'] + '/' + b['name'])
    normalized = {'address_bits': bits, 'cache_line_bytes': line,
                  'regions': sorted(regions, key=lambda x: x['name']), 'symbols': dict(sorted(symbols.items()))}
    return normalized, errors, hashlib.sha256(raw).hexdigest()


def check_header(path, symbols):
    text = path.read_text(encoding='utf-8-sig')
    # Strip comments before matching; expressions stay unsupported, never eval().
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    definitions = {}
    for name, value in re.findall(r'^\s*#\s*define\s+([A-Za-z_]\w*)[ \t]+([^\n]+)', text, re.M):
        definitions.setdefault(name, []).append(value.split('//')[0].strip())
    errors = []
    for name, expected in symbols.items():
        values = definitions.get(name, [])
        if len(values) != 1:
            errors.append(name + ': missing or repeated macro')
            continue
        value = values[0]
        while value.startswith('(') and value.endswith(')'):
            value = value[1:-1].strip()
        match = re.fullmatch(r'(0[xX][0-9a-fA-F]+|[0-9]+)[uUlL]*', value)
        if not match:
            errors.append(name + ': unsupported nonliteral macro')
        elif number(match.group(1)) != expected:
            errors.append(name + ': literal mismatch')
    return errors


def inspect(path, header=None, baseline=None):
    report = {'schema_version': 1, 'errors': [], 'definition_drift': False,
              'limitations': ['Only listed leaf ranges and selected numeric macros are checked.',
                              'No RTL, XSA, descriptor layout, linker occupancy or cache/transaction proof.']}
    try:
        contract, errors, digest = load_contract(path)
        report.update(contract_sha256=digest, checked_contract=contract)
        report['errors'].extend(errors)
        if header:
            report['header_sha256'] = hashlib.sha256(header.read_bytes()).hexdigest()
            report['errors'].extend(check_header(header, contract['symbols']))
        if baseline:
            previous, old_errors, old_sha = load_contract(baseline)
            report['baseline_sha256'] = old_sha
            report['errors'].extend('baseline: ' + e for e in old_errors)
            changes = [k for k in contract if contract[k] != previous[k]]
            report['definition_drift'] = bool(changes)
            report['changed_sections'] = {k: {'before': previous[k], 'after': contract[k]} for k in changes}
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        report['errors'].append(str(error))
    report['passed'] = not report['errors'] and not report['definition_drift']
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('contract', type=Path)
    parser.add_argument('--header', type=Path)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = inspect(args.contract, args.header, args.baseline)
    payload = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if args.report:
        try:
            with args.report.open('x', encoding='utf-8', newline='\n') as stream:
                stream.write(payload)
        except OSError as error:
            print(str(error), file=sys.stderr)
            return 2
    print(payload, end='')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
