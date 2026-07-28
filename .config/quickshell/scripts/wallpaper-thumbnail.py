#!/usr/bin/env python3

import hashlib
import os
import subprocess
import sys
from pathlib import Path


CACHE_DIR = Path("/home/mika/.cache/quickshell/wallpaper-thumbnails")


def thumbnail_path(path: Path) -> Path:
    digest = hashlib.sha256(str(path.resolve()).encode("utf-8")).hexdigest()
    return CACHE_DIR / f"{digest[:24]}.jpg"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: wallpaper-thumbnail.py MEDIA_FILE", file=sys.stderr)
        return 2

    source = Path(sys.argv[1]).expanduser().resolve()
    if not source.is_file():
        return 3

    target = thumbnail_path(source)
    try:
        if (target.stat().st_mtime_ns >= source.stat().st_mtime_ns
                and target.stat().st_size > 0):
            print(target)
            return 0
    except OSError:
        pass

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp.jpg")
    try:
        subprocess.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-y",
                "-ss",
                "1",
                "-i",
                str(source),
                "-frames:v",
                "1",
                "-vf",
                "scale=1920:-2:force_original_aspect_ratio=decrease",
                "-q:v",
                "2",
                str(temporary),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.replace(temporary, target)
    except (OSError, subprocess.SubprocessError):
        return 4
    finally:
        try:
            temporary.unlink()
        except OSError:
            pass

    print(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
