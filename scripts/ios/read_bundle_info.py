#!/usr/bin/env python3
"""Read CFBundle* from a .app directory or .ipa. Prints JSON to stdout."""
from __future__ import annotations

import json
import plistlib
import sys
import zipfile
from pathlib import Path


def from_plist_bytes(data: bytes) -> dict:
    p = plistlib.loads(data)
    return {
        "bundle_id": p.get("CFBundleIdentifier"),
        "version": p.get("CFBundleShortVersionString"),
        "build": p.get("CFBundleVersion"),
    }


def read_path(path: Path) -> dict:
    if path.is_dir() and path.suffix.lower() == ".app":
        plist = path / "Info.plist"
        if not plist.is_file():
            raise SystemExit(f"Info.plist missing: {plist}")
        return from_plist_bytes(plist.read_bytes())
    if path.is_file() and path.suffix.lower() == ".ipa":
        with zipfile.ZipFile(path) as zf:
            names = [
                n
                for n in zf.namelist()
                if n.endswith("Info.plist") and n.startswith("Payload/") and n.count("/") == 2
            ]
            if not names:
                raise SystemExit(f"no Payload/*.app/Info.plist in {path}")
            return from_plist_bytes(zf.read(names[0]))
    raise SystemExit(f"expected .app dir or .ipa file: {path}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: read_bundle_info.py <path.app|.ipa>")
    info = read_path(Path(sys.argv[1]).resolve())
    print(json.dumps(info, separators=(",", ":")))


if __name__ == "__main__":
    main()
