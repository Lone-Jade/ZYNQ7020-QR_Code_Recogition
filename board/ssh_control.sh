#!/bin/sh
set -eu
if [ "$#" -ne 2 ]; then echo 'Usage: sh board/ssh_control.sh xilinx@BOARD_IP start|stop|restart|status|check|logs' >&2;exit 2;fi
case "$1" in -*) echo 'Invalid SSH host' >&2;exit 2;; esac
case "$2" in start|stop|restart|status|check|logs) ;; *) echo 'Invalid command' >&2;exit 2;; esac
exec ssh -t "$1" "sudo /usr/local/sbin/zynq-qr $2"
