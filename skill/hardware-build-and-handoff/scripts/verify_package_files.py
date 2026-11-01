"""Verify a package's files-mapping SHA256 manifest without accessing hardware."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath, PureWindowsPath


def verify(package, manifest_name):
    root = Path(package).resolve(strict=True)
    if not root.is_dir():
        raise ValueError("Package is not a directory")
    manifest = safe_path(root, manifest_name)
    data = json.loads(manifest.read_text(encoding="utf-8-sig"))
    files = data.get("files") if isinstance(data, dict) else None
    if not isinstance(files, dict) or not files:
        raise ValueError("Expected a non-empty files mapping of relative paths to SHA256")
    results = []
    for name, expected in sorted(files.items()):
        row = {"path": name, "expected_sha256": expected}
        try:
            if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
                raise ValueError("Invalid SHA256 value")
            target = safe_path(root, name)
            digest = hashlib.sha256()
            with target.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
            row["actual_sha256"] = digest.hexdigest()
            row["status"] = "verified" if digest.hexdigest() == expected.lower() else "mismatch"
        except (OSError, ValueError) as exc:
            row.update(status="error", error=str(exc))
        results.append(row)
    return {"package": str(root), "manifest": manifest_name,
            "status": "verified" if all(r["status"] == "verified" for r in results) else "failed",
            "files": results}


def safe_path(root, name):
    if not isinstance(name, str) or not name or "\\" in name or ":" in name:
        raise ValueError("Use a non-empty relative path with forward slashes")
    posix, windows = PurePosixPath(name), PureWindowsPath(name)
    if posix.is_absolute() or windows.is_absolute() or windows.drive or ".." in posix.parts:
        raise ValueError("Absolute paths and parent traversal are not allowed")
    target = (root / name).resolve()
    if not target.is_relative_to(root):
        raise ValueError("Resolved path leaves the package")
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--manifest", default="manifest.json")
    parser.add_argument("--output", type=Path, help="New result JSON; existing paths are never overwritten")
    args = parser.parse_args()
    try:
        if args.output and args.output.exists():
            raise ValueError("Output already exists; select a new result path")
        result = verify(args.package, args.manifest)
        output = json.dumps(result, ensure_ascii=False, indent=2)
        if args.output:
            # Exclusive creation also protects against a race after the check above.
            with args.output.open("x", encoding="utf-8", newline="\n") as stream:
                stream.write(output + "\n")
        print(output)
        return 0 if result["status"] == "verified" else 1
    except (OSError, ValueError, TypeError) as exc:
        print(json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=False))
        return 2


if __name__ == "__main__":
    sys.exit(main())
