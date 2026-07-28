#!/usr/bin/env python3

import os
import sys
from pathlib import Path


ALLOWED_COMMANDS = {"toggle-mute", "toggle-deaf"}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ALLOWED_COMMANDS:
        raise SystemExit("usage: cockpit-discord-command.py toggle-mute|toggle-deaf")

    runtime_directory = Path(
        os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    )
    command_path = runtime_directory / "quickshell-discord-cockpit-command"
    temporary_path = command_path.with_suffix(".tmp")
    temporary_path.write_text(sys.argv[1])
    temporary_path.chmod(0o600)
    temporary_path.replace(command_path)


if __name__ == "__main__":
    main()
