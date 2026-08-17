#!/usr/bin/env python3
"""Quickshell-only persistence and wallpaper state for ShellSettings."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


HOME = Path.home()
CONFIG = HOME / ".config/quickshell/settings.json"
STATE = HOME / ".cache/quickshell/wallpaper-engine-current"
PREVIEW = HOME / ".cache/quickshell/wallpaper-engine-preview"
THUMBNAIL_HELPER = HOME / ".config/quickshell/scripts/wallpaper-thumbnail.py"
CONSUMER_HELPER = HOME / ".config/quickshell/scripts/wallpaper-consumers.py"


def atomic_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_config(payload: str) -> None:
    parsed = json.loads(payload)
    encoded = (json.dumps(parsed, indent=2, ensure_ascii=False) + "\n").encode()
    atomic_bytes(CONFIG, encoded)


def apply_wallpaper(
    source_name: str, transition_name: str, duration_name: str
) -> None:
    source = Path(source_name).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(source)

    suffix = source.suffix.lower()
    static_suffixes = {".png", ".jpg", ".jpeg", ".webp"}
    animated_suffixes = {".gif", ".mp4", ".webm", ".mkv", ".mov"}
    if suffix not in static_suffixes | animated_suffixes:
        raise ValueError(f"unsupported wallpaper type: {suffix}")

    fallback = source
    if suffix in animated_suffixes:
        result = subprocess.run(
            [str(THUMBNAIL_HELPER), str(source)],
            check=True,
            capture_output=True,
            text=True,
        )
        fallback = Path(result.stdout.strip()).resolve()
        if not fallback.is_file():
            raise FileNotFoundError(fallback)

    if shutil.which("awww"):
        transition = transition_name if transition_name in {
            "grow", "wipe", "fade"
        } else "fade"
        duration = max(100, min(1800, int(duration_name))) / 1000
        subprocess.run(
            [
                "awww", "img", str(fallback),
                "--resize", "crop",
                "--transition-type", transition,
                "--transition-duration", f"{duration:.3f}",
                "--transition-fps", "120",
                "--transition-bezier", ".22,1,.36,1",
            ],
            check=True,
        )
    elif suffix in static_suffixes:
        raise RuntimeError("awww is required for static wallpapers")

    atomic_bytes(STATE, f"{source}\n{fallback}\n".encode())
    atomic_bytes(PREVIEW, b"")

    subprocess.run(
        [str(CONSUMER_HELPER), str(source), str(fallback)],
        check=False,
    )


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "write":
        write_config(sys.argv[2])
        return 0
    if len(sys.argv) == 5 and sys.argv[1] == "wallpaper":
        apply_wallpaper(sys.argv[2], sys.argv[3], sys.argv[4])
        return 0
    print(
        "usage: shell-settings.py write JSON | wallpaper PATH TRANSITION MS",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
