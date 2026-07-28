#!/usr/bin/env bash
set -euo pipefail

step="${1:-0}"
if [[ "$step" != "-1" && "$step" != "1" ]]; then
    exit 2
fi

current="$(
    hyprctl monitors | awk '
        /^Monitor DP-1 / {
            on_primary = 1
            next
        }
        /^Monitor / {
            on_primary = 0
        }
        on_primary && /^[[:space:]]*active workspace:/ {
            print $3
            exit
        }
    '
)"

if [[ ! "$current" =~ ^[1-7]$ ]]; then
    current=1
fi

target=$((current + step))
if ((target < 1 || target > 7)); then
    exit 0
fi

hyprctl dispatch "hl.dsp.focus({ workspace = $target })" >/dev/null
