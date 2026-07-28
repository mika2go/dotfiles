#!/usr/bin/env bash
set -euo pipefail

wallpaper_dir="/home/mika/System/dotfiles/.config/hypr/wallpapers"
state_file="/home/mika/.cache/quickshell/wallpaper-engine-current"
preview_file="/home/mika/.cache/quickshell/wallpaper-engine-preview"
thumbnail_helper="/home/mika/.config/quickshell/scripts/wallpaper-thumbnail.py"
action="${1:-preview}"
requested="${2:-}"

show_render() {
    local render_path="$1"
    [[ -s "$render_path" ]] || return 0
    awww img "$render_path" \
        --outputs DP-1,HDMI-A-1 \
        --resize crop \
        --transition-type fade \
        --transition-duration 0.24 \
        --transition-fps 120 \
        --transition-bezier .22,1,.36,1
}

write_preview() {
    local original="$1"
    local render_path="$2"
    local temporary

    mkdir -p "$(dirname "$preview_file")"
    temporary="$(mktemp "${preview_file}.XXXXXX")"
    trap 'rm -f "$temporary"' EXIT
    printf '%s\n%s\n' "$original" "$render_path" > "$temporary"
    chmod 600 "$temporary"
    mv "$temporary" "$preview_file"
    trap - EXIT
}

if [[ "$action" == "clear" ]]; then
    write_preview "" ""
    if [[ -s "$state_file" ]]; then
        restore_path="$(sed -n '2p' "$state_file")"
        [[ -n "$restore_path" ]] || restore_path="$(sed -n '1p' "$state_file")"
        show_render "$restore_path"
    fi
    exit 0
fi

if [[ "$action" != "preview" || -z "$requested" || ! -f "$requested" ]]; then
    exit 2
fi

wallpaper="$(realpath --canonicalize-existing "$requested")"
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

[[ -s "$render_wallpaper" ]] || exit 4
write_preview "$wallpaper" "$render_wallpaper"
show_render "$render_wallpaper"
