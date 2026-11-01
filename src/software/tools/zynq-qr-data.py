#!/usr/bin/python3
"""Show only decoded QR text from the existing R4 recognition journal."""
import argparse
from collections import OrderedDict
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

UNIT = 'c04-r4-recognition.service'
DROP_IN = Path('/run/systemd/system') / (UNIT + '.d') / 'zz-qr-payloads.conf'
MARKER = '# Managed by zynq-qr-data\n'


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def effective_exec(text):
    """Read the effective single ExecStart, including ordered systemd drop-ins."""
    section = ''
    commands = []
    for line in text.replace('\\\n', '').splitlines():
        line = line.strip()
        if not line or line.startswith(('#', ';')):
            continue
        if line.startswith('['):
            section = line
        elif section == '[Service]' and line.startswith('ExecStart='):
            value = line.partition('=')[2].strip()
            if value:
                commands.append(value)
            else:
                commands.clear()
    if len(commands) != 1:
        raise RuntimeError('Expected one R4 ExecStart; inspect systemctl cat ' + UNIT)
    return commands[0]


def service_exec():
    value = effective_exec(command('systemctl', 'cat', '--no-pager', UNIT))
    args = shlex.split(value)
    if '/opt/zynq-qr/runtime/launch_r4.py' not in args or '--run' not in args:
        raise RuntimeError('This helper requires the final-version R4 service.')
    return value


def active():
    return command('systemctl', 'show', '-p', 'ActiveState', '--value', UNIT) == 'active'


def worker_streaming():
    pid = command('systemctl', 'show', '-p', 'MainPID', '--value', UNIT)
    try:
        return b'--stream-events' in Path('/proc', pid, 'cmdline').read_bytes().split(b'\0')
    except FileNotFoundError:
        return False


def configure(enable):
    if os.geteuid() != 0:
        raise RuntimeError('Run with sudo for --enable / --disable.')
    previous = DROP_IN.read_text() if DROP_IN.exists() else None
    if previous is not None and not previous.startswith(MARKER):
        raise RuntimeError('Refusing to replace an unmanaged file: ' + str(DROP_IN))
    current = service_exec()
    if enable and '--stream-events' in shlex.split(current):
        if active() and not worker_streaming():
            subprocess.run(['systemctl', 'restart', UNIT], check=True)
        print('QR events already enabled. Run: sudo zynq-qr start; sudo zynq-qr-data', file=sys.stderr)
        return
    if not enable and previous is None:
        print('No helper override to remove; existing service settings kept.', file=sys.stderr)
        return
    was_active = active()
    try:
        if enable:
            DROP_IN.parent.mkdir(parents=True, exist_ok=True)
            DROP_IN.write_text(MARKER + '[Service]\nExecStart=\nExecStart=' + current + ' --stream-events\n')
        else:
            DROP_IN.unlink()
        subprocess.run(['systemctl', 'daemon-reload'], check=True)
        if enable and '--stream-events' not in shlex.split(service_exec()):
            raise RuntimeError('Another service override takes precedence.')
        if was_active:
            subprocess.run(['systemctl', 'restart', UNIT], check=True)
    except BaseException:
        if previous is None:
            DROP_IN.unlink(missing_ok=True)
        else:
            DROP_IN.write_text(previous)
        subprocess.run(['systemctl', 'daemon-reload'], check=False)
        if was_active:
            subprocess.run(['systemctl', 'restart', UNIT], check=False)
        raise
    print('QR events enabled for the current boot. Run: sudo zynq-qr start; sudo zynq-qr-data'
          if enable else 'Helper override removed; previous service settings restored.', file=sys.stderr)


def single_line(payload):
    # Prevent QR control characters from clearing a terminal or splitting a row.
    escapes = {'\n': r'\n', '\r': r'\r', '\t': r'\t'}
    return ''.join(c if c.isprintable() else escapes.get(c, '\\u%04x' % ord(c)) for c in payload)


def payload_lines(lines, all_frames=False):
    seen = OrderedDict()
    for line in lines:
        try:
            entry = json.loads(line)
            if not isinstance(entry, dict):
                continue
            event = entry.get('MESSAGE', entry)
            if isinstance(event, str):
                event = json.loads(event)
            if not isinstance(event, dict) or event.get('type') != 'decode':
                continue
            symbols = event.get('symbols', [])
            if not isinstance(symbols, list):
                continue
        except (ValueError, TypeError):
            continue
        for index, symbol in enumerate(symbols):
            if not isinstance(symbol, dict) or not isinstance(symbol.get('payload'), str):
                continue
            publication = symbol.get('publication_id')
            identity = (entry.get('_BOOT_ID'), entry.get('_SYSTEMD_INVOCATION_ID', entry.get('_PID')),
                        event.get('source_epoch'))
            # Zero publication ID is still a decode: don't suppress later frames.
            key = identity + ((publication,) if publication else
                              (None, event.get('source_frame'), index, symbol['payload']))
            if not all_frames:
                if key in seen:
                    seen.move_to_end(key)
                    continue
                seen[key] = None
                if len(seen) > 8192:
                    seen.popitem(last=False)
            yield single_line(symbol['payload'])


def follow(all_frames):
    if '--stream-events' not in shlex.split(service_exec()):
        raise RuntimeError('First run: sudo zynq-qr-data --enable')
    if not active():
        raise RuntimeError('Recognition is stopped. Run: sudo zynq-qr start')
    if not worker_streaming():
        raise RuntimeError('Running worker has no events. Run: sudo zynq-qr-data --enable; sudo zynq-qr start')
    # Start at the live edge. Don't show old results when recording a new video.
    process = subprocess.Popen(['journalctl', '-b', '-u', UNIT, '-n', '0', '-f',
                                '-o', 'json', '--all', '--no-pager'], stdout=subprocess.PIPE,
                               text=True, encoding='utf-8')
    try:
        for payload in payload_lines(process.stdout, all_frames):
            print(payload, flush=True)
        return process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--enable', action='store_true', help='Enable existing --stream-events until reboot; restart recognition only if active')
    modes.add_argument('--disable', action='store_true', help='Remove only this helper override; restart recognition only if active')
    modes.add_argument('--stdin', action='store_true', help='Filter journal JSON or worker JSON from stdin (also works on the host)')
    parser.add_argument('--all', action='store_true', help='Print every decoded frame instead of deduplicating publication identities')
    args = parser.parse_args()
    try:
        if args.enable or args.disable:
            configure(args.enable)
        elif args.stdin:
            for payload in payload_lines(sys.stdin, args.all):
                print(payload, flush=True)
        else:
            return follow(args.all)
    except (KeyboardInterrupt, BrokenPipeError):
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print('zynq-qr-data: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
