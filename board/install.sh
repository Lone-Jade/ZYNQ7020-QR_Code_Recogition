#!/bin/sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$(id -u)" -ne 0 ]; then echo 'Run: sudo sh board/install.sh' >&2;exit 1;fi
runtime=${1:-$here/runtime}
if [ ! -f "$runtime/RUNTIME_MANIFEST.json" ]; then
    echo 'Runtime missing. Build and stage a board directory with build/scripts/stage_board.py; see README.md.' >&2
    exit 1
fi
exec /usr/bin/python3 -B "$here/control/install_manual.py" "$runtime"
