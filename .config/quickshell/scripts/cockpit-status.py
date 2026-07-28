#!/usr/bin/env python3

import json
import os
import subprocess
import time
from pathlib import Path


def run(*command):
    try:
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=1.5,
        ).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def discord_status():
    runtime_directory = Path(
        os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    )
    state_path = runtime_directory / "quickshell-discord-cockpit.json"
    try:
        state = json.loads(state_path.read_text())
    except (OSError, json.JSONDecodeError):
        state = {}

    updated_at = int(state.get("updatedAt") or 0)
    available = updated_at > 0 and time.time() * 1000 - updated_at < 4_000
    avatar_url = state.get("avatarUrl") or ""
    if ".webp" in avatar_url:
        avatar_url = avatar_url.replace(".webp", ".png", 1)

    return {
        "available": available,
        "connected": available and bool(state.get("connected")),
        "displayName": state.get("displayName") or "Discord",
        "username": state.get("username") or "",
        "avatarUrl": avatar_url,
        "channelName": state.get("channelName") or "",
        "guildName": state.get("guildName") or "",
        "participantCount": int(state.get("participantCount") or 0),
        "muted": bool(state.get("muted")),
        "deafened": bool(state.get("deafened")),
        "joinedAt": int(state.get("joinedAt") or 0),
    }


def recording_status():
    output = run(
        "/home/mika/.local/bin/boltsnap",
        "recording",
        "status",
        "--json",
    )
    try:
        status = json.loads(output or "{}")
    except json.JSONDecodeError:
        status = {}
    return {
        "state": status.get("state") or "idle",
        "elapsedMs": int(status.get("elapsed_ms") or 0),
        "actionsEnabled": bool(status.get("actions_enabled")),
    }


discord = discord_status()
recording = recording_status()

print(
    json.dumps(
        {
            "discord": discord,
            "recordingState": recording["state"],
            "recordingElapsedMs": recording["elapsedMs"],
            "recordingActionsEnabled": recording["actionsEnabled"],
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )
)
