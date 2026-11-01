"""Read-only structural checks for explicit Zynq-7000 handoff files.

Exit 0 only attests to the checks in the JSON report, never hardware/software
compatibility or timing. Python standard library only; no vendor tools invoked.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile


def digest(stream):
    hasher = hashlib.sha256()
    size = 0
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        hasher.update(chunk)
        size += len(chunk)
    return hasher.hexdigest(), size


def file_record(path):
    with path.open("rb") as stream:
        sha, size = digest(stream)
    return {"path": str(path.resolve()), "sha256": sha, "bytes": size}


def contains_marker(path, marker):
    tail = b""
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            data = tail + chunk
            if marker in data:
                return True
            tail = data[-(len(marker) - 1):] if len(marker) > 1 else b""
    return False


def inspect(xsa, bit, elf, marker=None):
    report = {
        "schema_version": 1,
        "scope": "read-only structural inspection; not a release qualification",
        "files": {},
        "checks": [],
        "limitations": [
            "Does not validate bitstream syntax, target device or implementation timing.",
            "Does not prove ELF/BSP/XSA profile, address-map or source compatibility.",
            "Does not validate program segments, runtime execution or board behavior.",
        ],
    }

    def check(name, passed, detail):
        report["checks"].append({"name": name, "passed": bool(passed), "detail": detail})

    for role, path in (("xsa", xsa), ("bit", bit), ("elf", elf)):
        try:
            report["files"][role] = file_record(path)
            check(role + "_readable_nonempty", report["files"][role]["bytes"] > 0,
                  str(path.resolve()))
        except OSError as error:
            check(role + "_readable_nonempty", False, str(error))

    try:
        with zipfile.ZipFile(xsa) as archive:
            infos = [i for i in archive.infolist() if not i.is_dir()]
            bits = [i for i in infos if i.filename.lower().endswith(".bit")]
            hwh = [i.filename for i in infos if i.filename.lower().endswith(".hwh")]
            init = [i.filename for i in infos
                    if i.filename.replace("\\", "/").split("/")[-1].lower() == "ps7_init.tcl"]
            check("xsa_single_bit_member", len(bits) == 1, [i.filename for i in bits])
            check("xsa_hwh_present", bool(hwh), hwh)
            check("xsa_ps7_init_present", bool(init), init)
            if len(bits) == 1 and "bit" in report["files"]:
                with archive.open(bits[0]) as stream:
                    sha, size = digest(stream)
                check("embedded_bit_matches_external",
                      sha == report["files"]["bit"]["sha256"] and size > 0,
                      {"member": bits[0].filename, "sha256": sha, "bytes": size})
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile, NotImplementedError) as error:
        check("xsa_archive_readable", False, str(error))

    try:
        with elf.open("rb") as stream:
            header = stream.read(52)
        valid_ident = (len(header) == 52 and header[:4] == b"\x7fELF"
                       and header[4] == 1 and header[5] in (1, 2) and header[6] == 1)
        check("elf32_ident", valid_ident, "ELF32, recognized byte order and ident version")
        if valid_ident:
            order = "<" if header[5] == 1 else ">"
            kind, machine, version = struct.unpack_from(order + "HHI", header, 16)
            header_size = struct.unpack_from(order + "H", header, 40)[0]
            check("elf_arm_executable_header",
                  kind == 2 and machine == 40 and version == 1 and header_size == 52,
                  {"type": kind, "machine": machine, "version": version,
                   "header_bytes": header_size})
        if marker is not None:
            check("elf_marker_present", contains_marker(elf, marker.encode("ascii")), marker)
    except (OSError, ValueError, struct.error) as error:
        check("elf_readable", False, str(error))

    report["structural_checks_passed"] = all(c["passed"] for c in report["checks"])
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xsa", required=True, type=Path)
    parser.add_argument("--bit", required=True, type=Path)
    parser.add_argument("--elf", required=True, type=Path)
    parser.add_argument("--elf-marker", help="Optional nonempty ASCII build/profile marker")
    parser.add_argument("--report", type=Path, help="Create a new JSON report; never overwrite")
    args = parser.parse_args()
    if args.elf_marker is not None:
        try:
            if not args.elf_marker:
                raise ValueError("empty marker")
            args.elf_marker.encode("ascii")
        except (ValueError, UnicodeEncodeError):
            parser.error("--elf-marker must be nonempty ASCII")
    report = inspect(args.xsa, args.bit, args.elf, args.elf_marker)
    serialized = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report is not None:
        try:
            with args.report.open("x", encoding="utf-8", newline="\n") as stream:
                stream.write(serialized)
        except OSError as error:
            print("Report was not written: " + str(error), file=sys.stderr)
            return 2
    print(serialized, end="")
    return 0 if report["structural_checks_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
