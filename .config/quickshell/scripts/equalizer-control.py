#!/usr/bin/env python3

import json
import subprocess
import sys
from typing import Any


FILTER_NAME = "filter.sink.dynamic-island-equalizer"
BAND_PORTS = (
    "band_60:Gain",
    "band_150:Gain",
    "band_400:Gain",
    "band_1000:Gain",
    "band_3000:Gain",
    "band_10000:Gain",
)


def command(arguments: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        check=False,
        capture_output=True,
        text=True,
        timeout=4,
    )


def filter_node_id() -> int | None:
    result = command(["/usr/bin/pw-dump"])
    if result.returncode != 0:
        return None
    try:
        objects: list[dict[str, Any]] = json.loads(result.stdout)
    except (TypeError, ValueError):
        return None

    for item in objects:
        if item.get("type") != "PipeWire:Interface:Node":
            continue
        properties = item.get("info", {}).get("props", {})
        if properties.get("filter.smart.name") == FILTER_NAME:
            return int(item["id"])
    return None


def set_bypass(node_id: int, enabled: bool) -> None:
    # Smart-filter metadata uses `disabled`, hence the inverted value.
    result = command(
        [
            "/usr/bin/pw-metadata",
            "-n",
            "filters",
            str(node_id),
            "filter.smart.disabled",
            "false" if enabled else "true",
            "Spa:String:JSON",
        ]
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "could not change bypass")


def set_gains(node_id: int, gains: list[float]) -> None:
    values: list[str] = []
    for port, gain in zip(BAND_PORTS, gains, strict=True):
        values.extend((json.dumps(port), f"{gain:.2f}"))
    payload = "{ params = [ " + " ".join(values) + " ] }"
    result = command(
        ["/usr/bin/pw-cli", "set-param", str(node_id), "Props", payload]
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "could not apply gains")


def response(ok: bool, **extra: object) -> int:
    print(json.dumps({"ok": ok, **extra}, separators=(",", ":")), end="")
    return 0 if ok else 1


def main() -> int:
    node_id = filter_node_id()
    if node_id is None:
        return response(False, error="Equalizer filter is not running")

    if len(sys.argv) == 2 and sys.argv[1] == "status":
        return response(True, node=node_id)

    if len(sys.argv) != 9 or sys.argv[1] != "apply":
        return response(False, error="usage: apply ENABLED GAIN60 ... GAIN10000")

    try:
        enabled = sys.argv[2] == "1"
        gains = [
            max(-12.0, min(12.0, float(value)))
            for value in sys.argv[3:]
        ]
        set_gains(node_id, gains)
        set_bypass(node_id, enabled)
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
        return response(False, error=str(error))

    return response(True, node=node_id, enabled=enabled, gains=gains)


if __name__ == "__main__":
    raise SystemExit(main())
