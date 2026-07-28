#!/usr/bin/env bash
set -euo pipefail

wallpaper_dir="/home/mika/System/dotfiles/.config/hypr/wallpapers"
config_file="/home/mika/System/dotfiles/.config/hypr/hyprpaper.conf"
lock_config="/home/mika/System/dotfiles/.config/hypr/hyprlock.conf"
state_file="/home/mika/.cache/quickshell/wallpaper-engine-current"
preview_file="/home/mika/.cache/quickshell/wallpaper-engine-preview"
thumbnail_helper="/home/mika/.config/quickshell/scripts/wallpaper-thumbnail.py"
terminal_theme_helper="/home/mika/.config/quickshell/scripts/terminal-theme.py"
spicetify_sync="/home/mika/System/dotfiles/.config/spicetify/scripts/sync-rice-theme.py"
wallpaper="${1:-}"
transition="${2:-animated}"

if [[ -z "$wallpaper" || ! -f "$wallpaper" ]]; then
    exit 2
fi

wallpaper="$(realpath --canonicalize-existing "$wallpaper")"
wallpaper_dir="$(realpath --canonicalize-existing "$wallpaper_dir")"

case "$wallpaper" in
    "$wallpaper_dir"/*) ;;
    *) exit 3 ;;
esac

extension="${wallpaper##*.}"
case "${extension,,}" in
    png|jpg|jpeg|webp) render_wallpaper="$wallpaper" ;;
    gif|mp4|webm|mkv|mov)
        render_wallpaper="$("$thumbnail_helper" "$wallpaper")"
        ;;
    *) exit 3 ;;
esac

if [[ ! -s "$render_wallpaper" ]]; then
    exit 4
fi

for _ in {1..20}; do
    if awww query >/dev/null 2>&1; then
        break
    fi
    sleep 0.05
done

if [[ "$transition" == "instant" ]]; then
    awww img "$render_wallpaper" \
        --outputs DP-1,HDMI-A-1 \
        --resize crop \
        --transition-type none
else
    awww img "$render_wallpaper" \
        --outputs DP-1,HDMI-A-1 \
        --resize crop \
        --transition-type fade \
        --transition-duration 0.7 \
        --transition-fps 120 \
        --transition-bezier .22,1,.36,1
fi

temp_file="$(mktemp "${config_file}.XXXXXX")"
trap 'rm -f "$temp_file"' EXIT

awk -v selected="$render_wallpaper" '
    /^[[:space:]]*path[[:space:]]*=/ {
        match($0, /^[[:space:]]*/)
        print substr($0, 1, RLENGTH) "path = " selected
        next
    }
    { print }
' "$config_file" > "$temp_file"

chmod --reference="$config_file" "$temp_file"
mv "$temp_file" "$config_file"
trap - EXIT

lock_temp="$(mktemp "${lock_config}.XXXXXX")"
trap 'rm -f "$lock_temp"' EXIT
awk -v selected="$render_wallpaper" '
    /^\$wallpaper[[:space:]]*=/ {
        print "$wallpaper = " selected
        next
    }
    { print }
' "$lock_config" > "$lock_temp"
chmod --reference="$lock_config" "$lock_temp"
mv "$lock_temp" "$lock_config"
trap - EXIT

mkdir -p "$(dirname "$state_file")"
state_temp="$(mktemp "${state_file}.XXXXXX")"
trap 'rm -f "$state_temp"' EXIT
printf '%s\n%s\n' "$wallpaper" "$render_wallpaper" > "$state_temp"
chmod 600 "$state_temp"
mv "$state_temp" "$state_file"
trap - EXIT

"$terminal_theme_helper" "$wallpaper" || true

preview_temp="$(mktemp "${preview_file}.XXXXXX")"
trap 'rm -f "$preview_temp"' EXIT
chmod 600 "$preview_temp"
mv "$preview_temp" "$preview_file"
trap - EXIT

if [[ -x "$spicetify_sync" ]] && command -v spicetify >/dev/null 2>&1; then
    (
        "$spicetify_sync" --apply \
            >"/home/mika/.cache/quickshell/spicetify-sync.log" 2>&1
    ) &
fi
