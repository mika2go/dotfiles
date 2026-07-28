#!/usr/bin/env python3

import colorsys
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path


FAMILY_ORDER = [
    "red",
    "orange",
    "yellow",
    "green",
    "cyan",
    "blue",
    "purple",
    "pink",
    "neutral",
]

FAMILY_COLORS = {
    "red": "#e26363",
    "orange": "#dc8b58",
    "yellow": "#d8bd62",
    "green": "#69ad78",
    "cyan": "#67b9b3",
    "blue": "#668fc2",
    "purple": "#9274bc",
    "pink": "#c5769e",
    "neutral": "#a5a5a5",
}

STATIC_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp"}
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov"}
GIF_EXTENSIONS = {".gif"}
EXTENSIONS = STATIC_EXTENSIONS | VIDEO_EXTENSIONS | GIF_EXTENSIONS
CACHE_VERSION = 3
CACHE_PATH = Path("/home/mika/.cache/quickshell/wallpaper-colors.json")
THUMBNAIL_DIR = Path("/home/mika/.cache/quickshell/wallpaper-thumbnails")
QT_MULTIMEDIA_DIR = Path("/usr/lib/qt6/qml/QtMultimedia")
CURRENT_PATH_FILE = Path(
    "/home/mika/.cache/quickshell/wallpaper-engine-current"
)
HYPRPAPER_CONFIG = Path(
    "/home/mika/System/dotfiles/.config/hypr/hyprpaper.conf"
)


def current_wallpaper_path() -> str:
    try:
        current = CURRENT_PATH_FILE.read_text(
            encoding="utf-8"
        ).splitlines()[0].strip()
        if current:
            return current
    except (OSError, IndexError):
        pass

    try:
        config = HYPRPAPER_CONFIG.read_text(encoding="utf-8")
    except OSError:
        return ""

    match = re.search(r"^\s*path\s*=\s*(.+?)\s*$", config, re.MULTILINE)
    return match.group(1) if match else ""


def media_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in VIDEO_EXTENSIONS:
        return "video"
    if suffix in GIF_EXTENSIONS:
        return "gif"
    return "static"


def thumbnail_path(path: Path) -> Path:
    digest = hashlib.sha256(str(path.resolve()).encode("utf-8")).hexdigest()
    return THUMBNAIL_DIR / f"{digest[:24]}.jpg"


def ensure_thumbnail(path: Path) -> Path:
    thumbnail = thumbnail_path(path)
    try:
        if (thumbnail.stat().st_mtime_ns >= path.stat().st_mtime_ns
                and thumbnail.stat().st_size > 0):
            return thumbnail
    except OSError:
        pass

    THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
    temporary = thumbnail.with_name(thumbnail.name + ".tmp.jpg")
    command = [
        "ffmpeg",
        "-v",
        "error",
        "-y",
        "-ss",
        "1",
        "-i",
        str(path),
        "-frames:v",
        "1",
        "-vf",
        "scale=960:-2:force_original_aspect_ratio=decrease",
        "-q:v",
        "3",
        str(temporary),
    ]
    try:
        subprocess.run(
            command,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.replace(temporary, thumbnail)
    finally:
        try:
            temporary.unlink()
        except OSError:
            pass
    return thumbnail


def family_for_pixel(red: int, green: int, blue: int) -> str:
    hue, saturation, value = colorsys.rgb_to_hsv(
        red / 255.0,
        green / 255.0,
        blue / 255.0,
    )
    if saturation < 0.10 or value < 0.07:
        return "neutral"

    degrees = hue * 360.0
    if degrees < 18 or degrees >= 345:
        return "red"
    if degrees < 48:
        return "orange"
    if degrees < 72:
        return "yellow"
    if degrees < 155:
        return "green"
    if degrees < 195:
        return "cyan"
    if degrees < 255:
        return "blue"
    if degrees < 295:
        return "purple"
    return "pink"


def sample_pixels(path: Path) -> list[tuple[int, int, int]]:
    command = [
        "ffmpeg",
        "-v",
        "error",
        "-i",
        str(path),
        "-vf",
        "scale=48:48:force_original_aspect_ratio=decrease",
        "-frames:v",
        "1",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-",
    ]
    result = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    data = result.stdout
    return [
        (data[index], data[index + 1], data[index + 2])
        for index in range(0, len(data) - 2, 3)
    ]


def analyze(path: Path) -> dict[str, object]:
    pixels = sample_pixels(path)
    if not pixels:
        return {
            "family": "neutral",
            "familyColor": FAMILY_COLORS["neutral"],
            "dominantColor": "#777777",
            "hue": 360.0,
        }

    family_scores = Counter()
    for red, green, blue in pixels:
        family_name = family_for_pixel(red, green, blue)
        _, saturation, value = colorsys.rgb_to_hsv(
            red / 255.0,
            green / 255.0,
            blue / 255.0,
        )
        if family_name == "neutral":
            weight = 0.16
        else:
            weight = (0.45 + saturation * 1.55) * (0.55 + value * 0.45)
        family_scores[family_name] += weight

    family = max(
        FAMILY_ORDER,
        key=lambda name: (family_scores[name], -FAMILY_ORDER.index(name)),
    )
    family_pixels = [
        pixel for pixel in pixels if family_for_pixel(*pixel) == family
    ] or pixels

    red = round(sum(pixel[0] for pixel in family_pixels) / len(family_pixels))
    green = round(sum(pixel[1] for pixel in family_pixels) / len(family_pixels))
    blue = round(sum(pixel[2] for pixel in family_pixels) / len(family_pixels))
    hue = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)[0] * 360

    return {
        "family": family,
        "familyColor": FAMILY_COLORS[family],
        "dominantColor": f"#{red:02x}{green:02x}{blue:02x}",
        "hue": round(hue, 2),
    }


def load_cache() -> dict[str, object]:
    try:
        cache = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        if cache.get("version") == CACHE_VERSION:
            return cache
    except (OSError, ValueError, TypeError):
        pass
    return {"version": CACHE_VERSION, "files": {}}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: wallpaper-index.py WALLPAPER_DIRECTORY", file=sys.stderr)
        return 2

    directory = Path(sys.argv[1]).expanduser().resolve()
    cache = load_cache()
    cached_files = cache.get("files", {})
    entries = []
    updated_cache = {}

    paths = sorted(
        directory.rglob("*"),
        key=lambda item: str(item.relative_to(directory)).lower(),
    )
    for path in paths:
        if not path.is_file() or path.suffix.lower() not in EXTENSIONS:
            continue

        stat = path.stat()
        entry_media_type = media_type(path)
        preview_path = (
            ensure_thumbnail(path)
            if entry_media_type != "static"
            else path
        )
        cache_key = str(path)
        signature = f"{stat.st_mtime_ns}:{stat.st_size}"
        cached = cached_files.get(cache_key, {})

        if cached.get("signature") == signature:
            colors = cached.get("colors", {})
        else:
            try:
                colors = analyze(preview_path)
            except (OSError, subprocess.SubprocessError):
                colors = {
                    "family": "neutral",
                    "familyColor": FAMILY_COLORS["neutral"],
                    "dominantColor": "#777777",
                    "hue": 360.0,
                }

        updated_cache[cache_key] = {
            "signature": signature,
            "colors": colors,
        }
        entries.append(
            {
                "filePath": str(path),
                "fileUrl": preview_path.as_uri(),
                "fileName": path.name,
                "relativePath": str(path.relative_to(directory)),
                "mediaType": entry_media_type,
                "isAnimated": entry_media_type != "static",
                **colors,
            }
        )

    order = {name: index for index, name in enumerate(FAMILY_ORDER)}
    entries.sort(
        key=lambda entry: (
            order.get(entry["family"], len(FAMILY_ORDER)),
            entry["hue"],
            entry["fileName"].lower(),
        )
    )

    present_families = []
    for family in FAMILY_ORDER:
        count = sum(entry["family"] == family for entry in entries)
        if count:
            present_families.append(
                {
                    "name": family,
                    "paletteColor": FAMILY_COLORS[family],
                    "count": count,
                    "firstIndex": next(
                        index
                        for index, entry in enumerate(entries)
                        if entry["family"] == family
                    ),
                }
            )

    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = CACHE_PATH.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(
            {"version": CACHE_VERSION, "files": updated_cache},
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    os.replace(temporary, CACHE_PATH)

    print(
        json.dumps(
            {
                "wallpapers": entries,
                "families": present_families,
                "currentPath": current_wallpaper_path(),
                "videoSupport": QT_MULTIMEDIA_DIR.is_dir(),
            },
            ensure_ascii=False,
            separators=(",", ":"),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
