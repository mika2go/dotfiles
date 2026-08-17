# Credits

## blackhole-sprite.png

The fastfetch logo is a pixel-art black hole — accretion disk, event horizon
and two polar jets. `blackhole-sprite.png` is the source asset: 64×47 pixels,
eight palette colours, background and event horizon transparent.

It was traced from a reference image supplied by the repository owner, by
quantising that reference back to its eight-colour palette and resampling it
onto its native pixel grid. **The original artist is unknown.** If the
reference turns out to be third-party work, credit it here and check its
licence before relying on this file — as it stands this is an unattributed
derivative, which is fine for a private machine and not fine for redistribution.

`scripts/fastfetch-theme.py` remaps those eight colours onto the dominant
colour of the current wallpaper and writes `blackhole.png`, which fastfetch
draws through the kitty graphics protocol. The sprite's own light-to-dark
ordering is preserved, so only the hue changes; the darkest palette entry is
dropped to full transparency, which is what keeps the event horizon and the
outlines between the rings showing the terminal background.
