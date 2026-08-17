#!/usr/bin/env python3
"""Recolour the fastfetch black hole and render config.jsonc from the wallpaper.

The logo is a pixel-art sprite drawn with a fixed eight-colour palette
(blackhole-sprite.png). Rather than reducing it to text, which threw away the
ring banding, it is recoloured in place: every palette entry is remapped onto
the dominant wallpaper colour, keeping the sprite's own light-to-dark ordering,
and written out as blackhole.png for fastfetch's kitty-direct logo. The darkest
entry becomes fully transparent, so the event horizon and the outlines between
the rings show the terminal background.

The frame, key icons and swatches around the module list are derived from the
same wallpaper colour, so the whole block stays one palette.
"""

from __future__ import annotations

import colorsys
import json
import os
from pathlib import Path
import sys
import tempfile

from PIL import Image


HOME = Path.home()
STATE_FILE = HOME / ".cache/quickshell/wallpaper-engine-current"
COLOR_CACHE = HOME / ".cache/quickshell/wallpaper-colors.json"
FASTFETCH = HOME / "System/dotfiles/.config/fastfetch"
TEMPLATE = FASTFETCH / "config.template.jsonc"
OUTPUT = FASTFETCH / "config.jsonc"
SPRITE = FASTFETCH / "blackhole-sprite.png"
LOGO = FASTFETCH / "blackhole.png"
FALLBACK_SOURCE = "#405079"

SCALE = 6   # nearest-neighbour upscale, so the pixels stay square and hard

# The sprite's palette, brightest first, and where each entry lands on the
# wallpaper ramp as (lightness, saturation factor). The last one is the black
# used for both the event horizon and the outlines: it becomes transparent.
SPRITE_PALETTE: list[tuple[tuple[int, int, int], tuple[float, float] | None]] = [
    ((237, 192, 118), (0.90, 0.38)),
    ((214, 85, 28), (0.68, 0.95)),
    ((181, 32, 41), (0.50, 1.00)),
    ((111, 31, 41), (0.38, 0.92)),
    ((71, 21, 35), (0.30, 0.80)),
    ((58, 23, 37), (0.26, 0.74)),
    ((30, 14, 21), (0.18, 0.60)),
    ((5, 6, 7), None),
]


def current_wallpaper() -> str:
    if len(sys.argv) > 1 and sys.argv[1].strip():
        return str(Path(sys.argv[1]).expanduser().resolve())
    try:
        return STATE_FILE.read_text(encoding="utf-8").splitlines()[0].strip()
    except (OSError, IndexError):
        return ""


def source_color(wallpaper: str) -> str:
    try:
        cache = json.loads(COLOR_CACHE.read_text(encoding="utf-8"))
        value = (
            cache.get("files", {})
            .get(wallpaper, {})
            .get("colors", {})
            .get("dominantColor", "")
        )
        if isinstance(value, str) and len(value) == 7:
            return value
    except (OSError, ValueError, TypeError):
        pass
    return FALLBACK_SOURCE


def hue_of(hex_value: str) -> tuple[float, float]:
    red, green, blue = (
        int(hex_value[index : index + 2], 16) / 255 for index in (1, 3, 5)
    )
    hue, _, saturation = colorsys.rgb_to_hls(red, green, blue)
    return hue, saturation


def rgb(hue: float, lightness: float, saturation: float) -> tuple[int, int, int]:
    channels = colorsys.hls_to_rgb(hue % 1.0, lightness, saturation)
    return tuple(max(0, min(255, round(channel * 255))) for channel in channels)


def ansi(hue: float, lightness: float, saturation: float) -> str:
    return "38;2;{};{};{}".format(*rgb(hue, lightness, saturation))


def base_saturation(source_saturation: float) -> float:
    # A grey wallpaper must not produce a grey shell, so keep a floor.
    return max(0.32, min(0.62, source_saturation))


def palette(source: str) -> dict[str, str]:
    hue, source_saturation = hue_of(source)
    base = base_saturation(source_saturation)

    values = {
        "frame": ansi(hue, 0.78, base * 0.42),
        "label": ansi(hue, 0.82, base * 0.36),
        "output": ansi(hue, 0.80, base * 0.30),
    }
    for index, shift in enumerate((0.0, 0.07, -0.07, 0.14), start=1):
        values[f"accent{index}"] = ansi(hue + shift, 0.68, base * 0.78)
    for index in range(7):
        shift = -0.18 + index * 0.06
        values[f"swatch{index + 1}"] = ansi(hue + shift, 0.72, base * 0.85)
    return values


def recolor_sprite(source: str) -> bool:
    """Map the sprite's palette onto the wallpaper hue and write blackhole.png."""
    if not SPRITE.is_file():
        print(f"fastfetch-theme: missing {SPRITE}", file=sys.stderr)
        return False

    hue, source_saturation = hue_of(source)
    base = base_saturation(source_saturation)
    # Saturation is pushed well past the shell's, because a disk that is only
    # as saturated as the frame reads as grey mush next to it.
    mapping = {
        original: (
            None if target is None
            else rgb(hue, target[0], min(0.95, base * 1.6 * target[1]))
        )
        for original, target in SPRITE_PALETTE
    }

    sprite = Image.open(SPRITE).convert("RGBA")
    pixels = sprite.load()
    out = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    target_pixels = out.load()
    for y in range(sprite.height):
        for x in range(sprite.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            replacement = mapping.get((red, green, blue))
            if replacement is None:
                continue        # horizon and outlines stay transparent
            target_pixels[x, y] = replacement + (255,)

    out = out.resize(
        (sprite.width * SCALE, sprite.height * SCALE), Image.NEAREST
    )
    fd, temporary = tempfile.mkstemp(prefix=".blackhole.", suffix=".png",
                                     dir=FASTFETCH)
    os.close(fd)
    try:
        out.save(temporary, "PNG")
        os.chmod(temporary, 0o644)
        os.replace(temporary, LOGO)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def main() -> int:
    if not TEMPLATE.is_file():
        print(f"fastfetch-theme: missing {TEMPLATE}", file=sys.stderr)
        return 1

    source = source_color(current_wallpaper())
    recolor_sprite(source)

    content = TEMPLATE.read_text(encoding="utf-8")
    body = content.split("\n")
    while body and body[0].startswith("//"):
        body.pop(0)
    content = (
        "// Generated from config.template.jsonc by fastfetch-theme.py.\n"
        f"// Source colour: {source}\n"
        "// Edits here are lost on the next wallpaper change.\n"
        + "\n".join(body)
    )

    for name, value in palette(source).items():
        content = content.replace(f"{{{{{name}}}}}", value)

    if "{{" in content:
        print("fastfetch-theme: unresolved placeholder", file=sys.stderr)
        return 1

    fd, temporary = tempfile.mkstemp(prefix=".config.jsonc.", dir=FASTFETCH)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, OUTPUT)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
