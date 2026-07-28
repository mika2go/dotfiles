#!/usr/bin/env python3

import json
import select
import subprocess
import time
from datetime import datetime


def send(process, message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def receive(process, request_id, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select(
            [process.stdout], [], [], max(0, deadline - time.monotonic())
        )
        if not ready:
            break
        line = process.stdout.readline()
        if not line:
            break
        response = json.loads(line)
        if response.get("id") == request_id:
            return response
    raise TimeoutError("Codex app-server did not answer in time")


def read_rate_limit():
    process = subprocess.Popen(
        ["/usr/bin/codex", "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )

    try:
        send(
            process,
            {
                "method": "initialize",
                "id": 1,
                "params": {
                    "clientInfo": {
                        "name": "quickshell-limit",
                        "title": "Quickshell Codex Limit",
                        "version": "1.0.0",
                    },
                    "capabilities": {"experimentalApi": True},
                },
            },
        )
        receive(process, 1)
        send(process, {"method": "initialized", "params": {}})
        send(process, {"method": "account/rateLimits/read", "id": 2, "params": {}})
        response = receive(process, 2)

        primary = response["result"]["rateLimits"]["primary"]
        used = max(0.0, min(100.0, float(primary.get("usedPercent", 0))))
        remaining = max(0, min(100, round(100 - used)))
        resets_at = int(primary.get("resetsAt", 0) or 0)
        reset = datetime.fromtimestamp(resets_at) if resets_at else None

        return {
            "available": True,
            "remaining": remaining,
            "used": round(used),
            "resetText": reset.strftime("%d.%m. · %H:%M") if reset else "unbekannt",
            "resetsAt": resets_at,
            "windowMinutes": int(primary.get("windowDurationMins", 0) or 0),
        }
    finally:
        process.terminate()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()


try:
    result = read_rate_limit()
except (KeyError, TypeError, ValueError, OSError, TimeoutError, json.JSONDecodeError):
    result = {
        "available": False,
        "remaining": 0,
        "used": 0,
        "resetText": "keine Daten",
        "resetsAt": 0,
        "windowMinutes": 0,
    }

print(json.dumps(result, separators=(",", ":")))
