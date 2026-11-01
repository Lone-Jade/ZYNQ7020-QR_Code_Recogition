from __future__ import annotations

import ctypes
import fcntl
import json
import mmap
import os
import select
import subprocess
from pathlib import Path
from typing import Iterator

DEVICE = "/dev/ax7021b-qr0"
ABI_VERSION = 0x00010000
PL_ABI_VERSION = 0x00020003


class Info(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint32) for name in (
        "abi_version", "pl_abi_version", "width", "visible_height",
        "storage_height", "stride", "buffer_count", "frame_bytes",
        "mmap_slot_bytes", "reserved0", "reserved1", "reserved2",
        "reserved3", "reserved4", "reserved5", "reserved6")]


class Buffer(ctypes.Structure):
    _fields_ = [
        ("index", ctypes.c_uint32), ("bytes_used", ctypes.c_uint32),
        ("sequence", ctypes.c_uint64), ("monotonic_ns", ctypes.c_uint64),
    ]


class Counters(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in (
        "frames_completed", "dequeue_count", "queue_count", "dma_errors",
        "stop_count", "reserved0", "reserved1", "reserved2")]


def _ioc(direction: int, number: int, size: int) -> int:
    return (direction << 30) | (size << 16) | (ord("Q") << 8) | number


IOC_GET_INFO = _ioc(2, 0x00, ctypes.sizeof(Info))
IOC_START = _ioc(0, 0x01, 0)
IOC_STOP = _ioc(0, 0x02, 0)
IOC_DEQUEUE = _ioc(2, 0x03, ctypes.sizeof(Buffer))
IOC_QUEUE = _ioc(1, 0x04, ctypes.sizeof(Buffer))
IOC_GET_COUNTERS = _ioc(2, 0x05, ctypes.sizeof(Counters))


def _ioctl_struct(fd: int, command: int, value: ctypes.Structure) -> None:
    raw = bytearray(bytes(value))
    fcntl.ioctl(fd, command, raw, True)
    ctypes.memmove(ctypes.addressof(value), bytes(raw), len(raw))


class FrameSnapshot(ctypes.Structure):
    _fields_=[('index',ctypes.c_uint32),('flags',ctypes.c_uint32),('sequence',ctypes.c_uint64),
              ('data',ctypes.c_uint32*496),('diag',ctypes.c_uint32*48)]


class Capture:
    """Single-owner, explicit dequeue/queue access to the three DMA slots."""

    def __init__(self, device: str = DEVICE, prefetch: bool = False):
        self.fd = os.open(device, os.O_RDWR | os.O_CLOEXEC)
        self.running = False
        self.prefetch = prefetch
        self.owned_sequences = {}
        self.maps = []
        self.info = Info()
        _ioctl_struct(self.fd, IOC_GET_INFO, self.info)
        if (self.info.abi_version, self.info.pl_abi_version) != (ABI_VERSION, PL_ABI_VERSION):
            self.close()
            raise RuntimeError("capture/PL ABI mismatch")
        if prefetch:
            if not self.info.reserved0 & 1:
                self.close()
                raise RuntimeError('C04 prefetch requires the candidate capture module; current driver is paced')
            try:
                fcntl.ioctl(self.fd,_ioc(1,8,4),(1).to_bytes(4,'little'))
            except BaseException:
                self.close()
                raise
        if not prefetch and self.info.reserved0 & 1:
            fcntl.ioctl(self.fd,_ioc(1,8,4),(0).to_bytes(4,'little'))
        self.maps = [
            mmap.mmap(self.fd, self.info.mmap_slot_bytes,
                      flags=mmap.MAP_SHARED, prot=mmap.PROT_READ,
                      offset=index * self.info.mmap_slot_bytes)
            for index in range(self.info.buffer_count)
        ]
        self.running = False

    def start(self) -> None:
        fcntl.ioctl(self.fd, IOC_START)
        self.running = True

    def stop(self) -> None:
        if self.running:
            fcntl.ioctl(self.fd, IOC_STOP)
            self.running = False

    def dequeue(self, timeout: float = 5.0) -> tuple[Buffer, memoryview]:
        poller = select.poll()
        poller.register(self.fd, select.POLLIN)
        events = poller.poll(int(timeout * 1000))
        if not events:
            raise TimeoutError("camera frame did not complete")
        if not events[0][1] & select.POLLIN:
            raise RuntimeError("capture stopped or device failed")
        value = Buffer()
        _ioctl_struct(self.fd, IOC_DEQUEUE, value)
        self.owned_sequences[int(value.index)] = int(value.sequence)
        image_offset = self.info.stride
        end = image_offset + self.info.stride * self.info.visible_height
        return value, memoryview(self.maps[value.index])[image_offset:end]

    def queue(self, index: int) -> None:
        value = Buffer(index=index,sequence=self.owned_sequences[index])
        _ioctl_struct(self.fd, IOC_QUEUE, value)
        del self.owned_sequences[index]

    def frame_snapshot(self, buffer):
        value=FrameSnapshot(index=buffer.index,sequence=buffer.sequence)
        _ioctl_struct(self.fd,_ioc(3,9,ctypes.sizeof(value)),value)
        if value.index!=buffer.index or value.sequence!=buffer.sequence or not value.flags&1:
            raise RuntimeError('Stale cached frame descriptor')
        return value

    def counters(self) -> dict[str, int]:
        value = Counters()
        _ioctl_struct(self.fd, IOC_GET_COUNTERS, value)
        return {name: int(getattr(value, name)) for name, _ in Counters._fields_ if not name.startswith("reserved")}

    def close(self) -> None:
        self.stop()
        for mapping in getattr(self, "maps", []):
            mapping.close()
        if getattr(self, "fd", -1) >= 0:
            os.close(self.fd)
            self.fd = -1

    def __enter__(self) -> "Capture":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def load_static_overlay(bitfile: str = "/usr/local/share/ax7021b-qr/ax7021b_linux_qr_desktop.bit"):
    """Load HWH metadata only; the matching bitstream was loaded by BOOT.BIN."""
    from pynq import Overlay
    return Overlay(bitfile, download=False)


def stream_json(count: int = 0, initialize_camera: bool = False) -> Iterator[dict]:
    command = ["qr-mainline"]
    if initialize_camera:
        command.append("--init-camera")
    command.append("--capture")
    if count:
        command.append(str(count))
    process = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    assert process.stdout is not None
    try:
        for line in process.stdout:
            yield json.loads(line)
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait()
