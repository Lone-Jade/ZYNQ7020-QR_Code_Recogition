#!/usr/bin/env python3
"""Check a normalized exclusive-consumer DMA lifecycle trace, without devices."""
import argparse
import json
import sys
from pathlib import Path


def unique(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError('duplicate JSON key: ' + key)
        obj[key] = value
    return obj


def check(data):
    if not isinstance(data, dict) or set(data) != {'format', 'complete', 'events'}:
        raise ValueError('expected format, complete and events')
    if type(data['format']) is not int or data['format'] != 1 or type(data['complete']) is not bool:
        raise ValueError('expected format 1 and boolean complete')
    if not isinstance(data['events'], list) or not data['events']:
        raise ValueError('events must be nonempty')
    fields = {'alloc': set(), 'free': set(), 'arm': {'token'},
              'complete': {'token', 'confirmed'}, 'acquire': {'token', 'lease'},
              'read': {'token', 'lease'}, 'release': {'token', 'lease'},
              'snapshot': {'token', 'lease', 'snapshot'}, 'timeout': {'token'},
              'quiesce': {'token', 'confirmed'}, 'quarantine': {'token'}}
    slots, used, leases, snapshots, violations = {}, {}, set(), set(), []
    for index, event in enumerate(data['events']):
        if not isinstance(event, dict) or not isinstance(event.get('event'), str):
            raise ValueError(f'event {index}: expected event name')
        kind = event['event']
        if kind == 'read_snapshot':
            if set(event) != {'event', 'snapshot'} or not isinstance(event['snapshot'], str) or not event['snapshot']:
                raise ValueError(f'event {index}: invalid snapshot reference')
            if event['snapshot'] not in snapshots:
                violations.append({'index': index, 'error': 'unknown private snapshot'})
            continue
        if kind not in fields or set(event) != fields[kind] | {'event', 'slot'}:
            raise ValueError(f'event {index}: unknown event or fields')
        slot = event['slot']
        if type(slot) is not int or slot < 0:
            raise ValueError(f'event {index}: invalid slot')
        if 'token' in event:
            token = event['token']
            if (not isinstance(token, dict) or set(token) != {'epoch', 'frame', 'config', 'generation'}
                    or any(not (type(v) is int or isinstance(v, str) and v) for v in token.values())):
                raise ValueError(f'event {index}: invalid lifetime token')
        for key in ('lease', 'snapshot'):
            if key in event and (not isinstance(event[key], str) or not event[key]):
                raise ValueError(f'event {index}: invalid {key}')
        if 'confirmed' in event and type(event['confirmed']) is not bool:
            raise ValueError(f'event {index}: confirmed must be boolean')
        try:
            old = slots.get(slot, {'state': 'FREED'})
            state = old['state']
            if kind == 'alloc':
                if state != 'FREED':
                    raise RuntimeError('allocation still exists')
                slots[slot] = {'state': 'FREE'}
                continue
            if state == 'FREED':
                raise RuntimeError('slot not allocated')
            if kind == 'arm':
                if state != 'FREE':
                    raise RuntimeError('arm requires FREE ownership')
                identity = json.dumps(event['token'], sort_keys=True)
                if identity in used.setdefault(slot, set()):
                    raise RuntimeError('reused lifetime token')
                used[slot].add(identity)
                slots[slot] = {'state': 'ARMED', 'token': event['token']}
                continue
            if 'token' in event and event['token'] != old.get('token'):
                raise RuntimeError('stale or mismatched lifetime token')
            if kind in {'read', 'snapshot', 'release'}:
                if state != 'USER' or event['lease'] != old.get('lease'):
                    raise RuntimeError('operation requires current USER lease')
            if kind == 'complete':
                if state != 'ARMED' or not event['confirmed']:
                    raise RuntimeError('completion needs ARMED and confirmed commit')
                old['state'] = 'DONE'
            elif kind == 'acquire':
                if state != 'DONE' or event['lease'] in leases:
                    raise RuntimeError('acquire needs DONE and unique lease')
                leases.add(event['lease'])
                old.update(state='USER', lease=event['lease'])
            elif kind == 'snapshot':
                if event['snapshot'] in snapshots:
                    raise RuntimeError('snapshot identity already exists')
                snapshots.add(event['snapshot'])
            elif kind == 'release':
                old['state'] = 'FREE'
                old.pop('lease')
            elif kind == 'timeout':
                if state != 'ARMED':
                    raise RuntimeError('timeout requires ARMED')
                old['state'] = 'TIMEOUT'
            elif kind == 'quiesce':
                if state not in {'ARMED', 'TIMEOUT'} or not event['confirmed']:
                    raise RuntimeError('quiesce needs outstanding DMA and confirmed drain')
                old['state'] = 'FREE'
            elif kind == 'quarantine':
                if state != 'TIMEOUT':
                    raise RuntimeError('quarantine requires TIMEOUT')
                old['state'] = 'QUARANTINED'
            elif kind == 'free':
                if state not in {'FREE', 'DONE'}:
                    raise RuntimeError('cannot free active, leased or quarantined storage')
                old['state'] = 'FREED'
        except RuntimeError as error:
            violations.append({'index': index, 'slot': slot, 'error': str(error)})
    remaining = {str(k): v['state'] for k, v in slots.items() if v['state'] != 'FREED'}
    if data['complete'] and any(s != 'QUARANTINED' for s in remaining.values()):
        violations.append({'error': 'complete lifecycle still has unreclaimed non-quarantined slots'})
    status = 'violations' if violations else 'consistent' if data['complete'] else 'incomplete'
    return {'status': status, 'violations': violations, 'remaining': remaining,
            'quarantined': [k for k, s in remaining.items() if s == 'QUARANTINED']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trace', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = check(json.loads(args.trace.read_text(), object_pairs_hook=unique))
    except (ValueError, TypeError, OSError) as error:
        print(json.dumps({'status': 'invalid_input', 'error': str(error)}))
        return 2
    print(json.dumps(result))
    return {'consistent': 0, 'violations': 1, 'incomplete': 3}[result['status']]


if __name__ == '__main__':
    sys.exit(main())
