#!/usr/bin/env python3

import colorsys
import json
import os
import signal
import subprocess
import sys
from pathlib import Path


STATE_FILE = Path("/home/mika/.cache/quickshell/wallpaper-engine-current")
COLOR_CACHE = Path("/home/mika/.cache/quickshell/wallpaper-colors.json")
OUTPUT_FILE = Path(
    "/home/mika/System/dotfiles/.config/kitty/wallpaper-theme.conf"
)
FALLBACK_SOURCE = "#405079"


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


def rgb(hex_value: str) -> tuple[float, float, float]:
    return tuple(
        int(hex_value[index : index + 2], 16) / 255
        for index in (1, 3, 5)
    )


def hex_color(red: float, green: float, blue: float) -> str:
    channels = [
        max(0, min(255, round(channel * 255)))
        for channel in (red, green, blue)
    ]
    return "#{:02x}{:02x}{:02x}".format(*channels)


def tone(
    hue: float,
    source_saturation: float,
    lightness: float,
    saturation_scale: float,
    maximum: float = 0.82,
) -> str:
    saturation = max(
        0.08,
        min(maximum, max(0.16, source_saturation) * saturation_scale),
    )
    return hex_color(*colorsys.hls_to_rgb(hue, lightness, saturation))


def fixed_tone(hue: float, saturation: float, lightness: float) -> str:
    return hex_color(*colorsys.hls_to_rgb(hue, lightness, saturation))


def palette(source: str) -> dict[str, str]:
    red, green, blue = rgb(source)
    hue, _, source_saturation = colorsys.rgb_to_hls(red, green, blue)

    surface_deep = tone(hue, source_saturation, 0.045, 1.10)
    surface = tone(hue, source_saturation, 0.085, 1.15)
    surface_raised = tone(hue, source_saturation, 0.13, 1.18)
    surface_active = tone(hue, source_saturation, 0.26, 1.25)
    outline = tone(hue, source_saturation, 0.38, 1.10)
    text_muted = tone(hue, source_saturation, 0.60, 0.34)
    text_secondary = tone(hue, source_saturation, 0.78, 0.28)
    text_primary = tone(hue, source_saturation, 0.93, 0.24)
    text_bright = tone(hue, source_saturation, 0.985, 0.12)
    accent = tone(hue, source_saturation, 0.72, 1.70)
    accent_hover = tone(hue, source_saturation, 0.84, 1.45)

    return {
        "background": surface,
        "foreground": text_primary,
        "selection_background": surface_active,
        "selection_foreground": text_bright,
        "cursor": accent,
        "cursor_text_color": surface_deep,
        "url_color": accent_hover,
        "color0": surface_raised,
        "color1": fixed_tone(0.985, 0.46, 0.63),
        "color2": fixed_tone(0.38, 0.30, 0.60),
        "color3": fixed_tone(0.12, 0.38, 0.64),
        "color4": tone(hue, source_saturation, 0.62, 1.85),
        "color5": fixed_tone(0.79, 0.28, 0.63),
        "color6": fixed_tone(0.52, 0.32, 0.61),
        "color7": text_secondary,
        "color8": outline,
        "color9": fixed_tone(0.985, 0.58, 0.72),
        "color10": fixed_tone(0.38, 0.40, 0.70),
        "color11": fixed_tone(0.12, 0.48, 0.74),
        "color12": accent,
        "color13": fixed_tone(0.79, 0.38, 0.73),
        "color14": fixed_tone(0.52, 0.42, 0.71),
        "color15": text_bright,
        "active_tab_foreground": surface_deep,
        "active_tab_background": accent,
        "inactive_tab_foreground": text_muted,
        "inactive_tab_background": surface_raised,
    }


def render(source: str, values: dict[str, str]) -> str:
    ordered_names = [
        "background",
        "foreground",
        "selection_background",
        "selection_foreground",
        "cursor",
        "cursor_text_color",
        "url_color",
        "",
        *[f"color{index}" for index in range(16)],
        "",
        "active_tab_foreground",
        "active_tab_background",
        "inactive_tab_foreground",
        "inactive_tab_background",
    ]
    lines = [
        "# Generated from the active wallpaper by terminal-theme.py.",
        f"# Source colour: {source}",
    ]
    for name in ordered_names:
        if not name:
            lines.append("")
        else:
            lines.append(f"{name:<26} {values[name]}")
    return "\n".join(lines) + "\n"


def reload_kitty() -> None:
    """Kitty reads the palette once at startup; SIGUSR1 makes it re-read."""
    try:
        listed = subprocess.run(
            ["pgrep", "-x", "-u", str(os.getuid()), "kitty"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return

    for line in listed.stdout.split():
        try:
            os.kill(int(line), signal.SIGUSR1)
        except (ValueError, OSError):
            pass


def main() -> int:
    wallpaper = current_wallpaper()
    source = source_color(wallpaper)
    content = render(source, palette(source))

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUTPUT_FILE.with_suffix(".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, OUTPUT_FILE)
    reload_kitty()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
