#!/usr/bin/env python3
"""Push the active wallpaper into every consumer that is not a file watcher.

Quickshell picks the colour up by watching the cache itself. Kitty, hyprpaper,
hyprlock and Spicetify do not, so they only follow when something writes to
them. Both wallpaper entry points — set-wallpaper.sh and shell-settings.py —
end here, so no path can silently skip a consumer.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


HOME = Path.home()
DOTFILES = HOME / "System/dotfiles"
HYPRPAPER = DOTFILES / ".config/hypr/hyprpaper.conf"
HYPRLOCK = DOTFILES / ".config/hypr/hyprlock.conf"
TERMINAL_THEME = HOME / ".config/quickshell/scripts/terminal-theme.py"
FASTFETCH_THEME = HOME / ".config/quickshell/scripts/fastfetch-theme.py"
SPICETIFY_SYNC = DOTFILES / ".config/spicetify/scripts/sync-rice-theme.py"
SPICETIFY_LOG = HOME / ".cache/quickshell/spicetify-sync.log"


def rewrite(path: Path, pattern: re.Pattern[str], replacement: str) -> None:
    if not path.is_file():
        return
    original = path.read_text(encoding="utf-8")
    updated = pattern.sub(replacement, original)
    if updated == original:
        return

    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(updated)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, path.stat().st_mode & 0o7777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def sync(source: Path, render: Path) -> None:
    rewrite(
        HYPRPAPER,
        re.compile(r"^([ \t]*)path[ \t]*=.*$", re.MULTILINE),
        lambda match: f"{match.group(1)}path = {render}",
    )
    rewrite(
        HYPRLOCK,
        re.compile(r"^\$wallpaper[ \t]*=.*$", re.MULTILINE),
        lambda match: f"$wallpaper = {render}",
    )

    for helper in (TERMINAL_THEME, FASTFETCH_THEME):
        if helper.is_file():
            subprocess.run([str(helper), str(source)], check=False)

    if SPICETIFY_SYNC.is_file() and shutil.which("spicetify"):
        SPICETIFY_LOG.parent.mkdir(parents=True, exist_ok=True)
        with SPICETIFY_LOG.open("wb") as log:
            subprocess.Popen(
                [str(SPICETIFY_SYNC), "--apply"],
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(
            "usage: wallpaper-consumers.py SOURCE [RENDER]",
            file=sys.stderr,
        )
        return 2

    source = Path(sys.argv[1]).expanduser().resolve()
    render = (
        Path(sys.argv[2]).expanduser().resolve()
        if len(sys.argv) == 3
        else source
    )
    sync(source, render)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
