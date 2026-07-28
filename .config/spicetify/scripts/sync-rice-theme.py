#!/usr/bin/env python3

from __future__ import annotations

import argparse
import colorsys
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


STATE_PATH = Path("/home/mika/.cache/quickshell/wallpaper-engine-current")
COLOR_CACHE_PATH = Path("/home/mika/.cache/quickshell/wallpaper-colors.json")
THEME_PATH = Path(
    "/home/mika/System/dotfiles/.config/spicetify/Themes/RiceBlur"
)
SPICETIFY_THEME_PATH = Path(
    "/home/mika/.config/spicetify/Themes/RiceBlur"
)


def parse_hex(value: str) -> tuple[int, int, int]:
    value = value.strip().lstrip("#")
    if len(value) != 6:
        raise ValueError(f"invalid colour: {value}")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def to_hex(rgb: tuple[int, int, int]) -> str:
    return "".join(f"{max(0, min(255, channel)):02x}" for channel in rgb)


def mix(
    first: tuple[int, int, int],
    second: tuple[int, int, int],
    amount: float,
) -> tuple[int, int, int]:
    return tuple(
        round(a * (1.0 - amount) + b * amount)
        for a, b in zip(first, second)
    )


def with_lightness(
    rgb: tuple[int, int, int],
    lightness: float,
    saturation_floor: float = 0.0,
) -> tuple[int, int, int]:
    hue, current_lightness, saturation = colorsys.rgb_to_hls(
        *(channel / 255.0 for channel in rgb)
    )
    saturation = max(saturation, saturation_floor)
    converted = colorsys.hls_to_rgb(
        hue,
        max(0.0, min(1.0, lightness)),
        max(0.0, min(1.0, saturation)),
    )
    return tuple(round(channel * 255) for channel in converted)


def current_wallpapers() -> tuple[Path, Path]:
    lines = STATE_PATH.read_text(encoding="utf-8").splitlines()
    source = Path(lines[0]).expanduser().resolve()
    render = (
        Path(lines[1]).expanduser().resolve()
        if len(lines) > 1 and lines[1].strip()
        else source
    )
    if not source.is_file() or not render.is_file():
        raise FileNotFoundError("current wallpaper is missing")
    return source, render


def wallpaper_colours(source: Path) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    cache = json.loads(COLOR_CACHE_PATH.read_text(encoding="utf-8"))
    entry = cache.get("files", {}).get(str(source), {}).get("colors", {})
    accent = parse_hex(entry.get("familyColor", "#668fc2"))
    dominant = parse_hex(entry.get("dominantColor", "#405079"))
    return accent, dominant


def build_palette(
    accent: tuple[int, int, int],
    dominant: tuple[int, int, int],
) -> dict[str, tuple[int, int, int]]:
    white = (244, 247, 255)
    black = (5, 7, 12)
    accent = with_lightness(accent, 0.62, 0.38)
    accent_active = with_lightness(accent, 0.72, 0.38)
    base_tint = with_lightness(dominant, 0.17, 0.18)

    return {
        "text": white,
        "subtext": mix(white, base_tint, 0.30),
        "sidebar-text": mix(white, base_tint, 0.16),
        "main": mix(black, base_tint, 0.20),
        "sidebar": mix(black, base_tint, 0.31),
        "player": mix(black, base_tint, 0.26),
        "card": mix(black, base_tint, 0.44),
        "shadow": black,
        "selected-row": mix(base_tint, accent, 0.28),
        "button": accent,
        "button-active": accent_active,
        "button-disabled": mix(base_tint, (125, 130, 140), 0.34),
        "tab-active": mix(base_tint, accent, 0.28),
        "notification": accent,
        "notification-error": (226, 99, 99),
        "misc": mix(white, base_tint, 0.40),
    }


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(content)
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except OSError:
            pass
        raise


def write_palette(palette: dict[str, tuple[int, int, int]]) -> None:
    width = max(len(name) for name in palette)
    lines = ["[RiceBlur]"]
    lines.extend(
        f"{name.ljust(width)} = {to_hex(value)}"
        for name, value in palette.items()
    )
    atomic_write(THEME_PATH / "color.ini", "\n".join(lines) + "\n")


def write_wallpaper(render: Path) -> None:
    destination = THEME_PATH / "assets" / "wallpaper-current.jpg"
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(".wallpaper-current.tmp.jpg")
    command = [
        "ffmpeg",
        "-v",
        "error",
        "-y",
        "-i",
        str(render),
        "-frames:v",
        "1",
        "-vf",
        "scale=1920:-2:force_original_aspect_ratio=decrease",
        "-q:v",
        "4",
        str(temporary),
    ]
    try:
        subprocess.run(command, check=True)
        os.replace(temporary, destination)
    finally:
        try:
            temporary.unlink()
        except OSError:
            pass


def ensure_theme_link() -> None:
    SPICETIFY_THEME_PATH.parent.mkdir(parents=True, exist_ok=True)
    if SPICETIFY_THEME_PATH.is_symlink():
        if SPICETIFY_THEME_PATH.resolve() == THEME_PATH.resolve():
            return
        SPICETIFY_THEME_PATH.unlink()
    elif SPICETIFY_THEME_PATH.exists():
        if SPICETIFY_THEME_PATH.is_dir():
            shutil.rmtree(SPICETIFY_THEME_PATH)
        else:
            SPICETIFY_THEME_PATH.unlink()
    SPICETIFY_THEME_PATH.symlink_to(THEME_PATH, target_is_directory=True)


def apply_spicetify() -> None:
    subprocess.run(
        [
            "spicetify",
            "config",
            "current_theme",
            "RiceBlur",
            "color_scheme",
            "RiceBlur",
            "inject_css",
            "1",
            "replace_colors",
            "1",
            "overwrite_assets",
            "1",
        ],
        check=True,
    )
    subprocess.run(["spicetify", "apply"], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Synchronise Spicetify with the current Quickshell wallpaper."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="apply the regenerated theme to the running Spotify client",
    )
    arguments = parser.parse_args()

    source, render = current_wallpapers()
    accent, dominant = wallpaper_colours(source)
    palette = build_palette(accent, dominant)
    write_palette(palette)
    write_wallpaper(render)
    ensure_theme_link()

    if arguments.apply:
        apply_spicetify()

    print(
        f"RiceBlur synced: wallpaper={source.name} "
        f"accent=#{to_hex(palette['button'])}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"sync-rice-theme: {error}", file=sys.stderr)
        raise SystemExit(1)
