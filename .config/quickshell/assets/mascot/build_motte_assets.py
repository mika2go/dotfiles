#!/usr/bin/env python3
"""Build the final clean Motte mascot exports."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


HERE = Path(__file__).resolve().parent
MASTER = HERE / "motte-transparent-master.png"


def normalized_master(size: int) -> Image.Image:
    image = Image.open(MASTER).convert("RGBA")
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("mascot master has no visible pixels")

    left, top, right, bottom = bbox
    side = max(right - left, bottom - top) + 92
    center_x = (left + right) // 2
    center_y = (top + bottom) // 2
    crop = image.crop((
        center_x - side // 2,
        center_y - side // 2,
        center_x + side // 2,
        center_y + side // 2,
    ))
    return crop.resize((size, size), Image.Resampling.LANCZOS)


def dark_backdrop(size: int) -> Image.Image:
    base = Image.new("RGBA", (size, size), "#14151b")
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    margin = round(size * 0.15)
    draw.ellipse(
        (margin, margin, size - margin, size - margin),
        fill=(151, 125, 190, 38),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(round(size * 0.16)))
    return Image.alpha_composite(base, glow)


def save_transparent(master: Image.Image) -> None:
    master.resize((512, 512), Image.Resampling.LANCZOS).save(
        HERE / "motte-transparent.png", optimize=True
    )


def save_card(master: Image.Image) -> None:
    card = dark_backdrop(1024)
    mascot = master.resize((760, 760), Image.Resampling.LANCZOS)
    card.alpha_composite(mascot, (132, 126))
    card.convert("RGB").save(HERE / "motte-card.png", optimize=True)


def save_idle_gif(master: Image.Image) -> None:
    frames: list[Image.Image] = []
    frame_count = 20
    base = dark_backdrop(512)

    for index in range(frame_count):
        phase = 2 * math.pi * index / frame_count
        y_offset = round(4 * math.sin(phase))
        breathe = 1.0 + 0.006 * math.sin(phase - math.pi / 2)
        width = round(372 * breathe)
        height = round(372 / breathe)
        mascot = master.resize((width, height), Image.Resampling.LANCZOS)
        frame = base.copy()
        frame.alpha_composite(
            mascot,
            ((512 - width) // 2, (512 - height) // 2 + y_offset),
        )
        frames.append(frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=192))

    frames[0].save(
        HERE / "motte-idle.gif",
        save_all=True,
        append_images=frames[1:],
        duration=90,
        loop=0,
        disposal=2,
        optimize=True,
    )


def main() -> None:
    master = normalized_master(900)
    save_transparent(master)
    save_card(master)
    save_idle_gif(master)


if __name__ == "__main__":
    main()
