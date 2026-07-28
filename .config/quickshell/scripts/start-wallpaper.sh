#!/usr/bin/env bash
set -euo pipefail

config_file="/home/mika/System/dotfiles/.config/hypr/hyprpaper.conf"
setter="/home/mika/.config/quickshell/scripts/set-wallpaper.sh"
state_file="/home/mika/.cache/quickshell/wallpaper-engine-current"

if [[ -s "$state_file" ]]; then
    wallpaper="$(head -n 1 "$state_file")"
else
    wallpaper="$(
        awk '
            /^[[:space:]]*path[[:space:]]*=/ {
                sub(/^[[:space:]]*path[[:space:]]*=[[:space:]]*/, "")
                print
                exit
            }
        ' "$config_file"
    )"
fi

for _ in {1..30}; do
    if awww query >/dev/null 2>&1; then
        exec "$setter" "$wallpaper" instant
    fi
    sleep 0.05
done

exit 1
