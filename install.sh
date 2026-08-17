#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SOURCE_HOME="/home/mika"
readonly TARGET_HOME="${HOME}"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_ROOT="${TARGET_HOME}/.local/state/mika-dotfiles/backups/${TIMESTAMP}"

DRY_RUN=false
WITH_SDDM=false
CHECK_ONLY=false

USER_ITEMS=(
    ".config/brrtfetch"
    ".config/fastfetch"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".config/hypr"
    ".config/kitty"
    ".config/qt6ct"
    ".config/quickshell"
    ".config/spicetify/Themes/RiceBlur"
    ".config/spicetify/scripts"
    ".config/systemd/user/xdg-desktop-portal-hyprland.service.d/20-dark-qt.conf"
    ".config/systemd/user/xdg-desktop-portal.service.d/10-hyprland-backends.conf"
    ".config/systemd/user/payment-stream-privacy.service"
    ".config/systemd/user/equicord-guard.service"
    ".config/systemd/user/equicord-guard.timer"
    ".config/waybar"
    ".config/wireplumber"
    ".local/bin/brrt"
    ".local/bin/discord"
    ".local/bin/equicord"
    ".local/bin/equicord-bridge"
    ".local/bin/equicord-guard"
    ".local/bin/payment-stream-privacy"
    ".local/share/applications/discord.desktop"
    ".local/share/applications/equicord.desktop"
    ".local/share/icons/default/index.theme"
)

REQUIRED_COMMANDS=(
    Hyprland
    hyprctl
    qs
    awww
    kitty
    nmcli
    playerctl
    wpctl
    python3
)

OPTIONAL_COMMANDS=(
    brrtfetch
    fastfetch
    ffmpeg
    hypridle
    hyprlock
    ollama
    qt6ct
    spicetify
)

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --dry-run     Show which files would be installed or backed up
  --check       Check runtime commands without installing files
  --with-sddm   Also install the SDDM theme and configuration via sudo
  -h, --help    Show this help

The installer backs up every replaced path below:
  ~/.local/state/mika-dotfiles/backups/<timestamp>/
EOF
}

log() {
    printf '  %s\n' "$*"
}

run() {
    if "${DRY_RUN}"; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

check_commands() {
    local missing=0
    local command_name

    printf 'Required commands:\n'
    for command_name in "${REQUIRED_COMMANDS[@]}"; do
        if command -v "${command_name}" >/dev/null 2>&1; then
            log "OK      ${command_name}"
        else
            log "MISSING ${command_name}"
            missing=1
        fi
    done
    if python3 -c \
            'import gi; gi.require_version("Atspi", "2.0")' \
            >/dev/null 2>&1; then
        log "OK      python3-gi/Atspi"
    else
        log "MISSING python3-gi/Atspi"
        missing=1
    fi

    printf '\nOptional integrations:\n'
    for command_name in "${OPTIONAL_COMMANDS[@]}"; do
        if command -v "${command_name}" >/dev/null 2>&1; then
            log "OK      ${command_name}"
        else
            log "SKIP    ${command_name}"
        fi
    done

    return "${missing}"
}

backup_path() {
    local destination="$1"
    local relative="${destination#"${TARGET_HOME}/"}"
    local backup="${BACKUP_ROOT}/${relative}"

    if [[ ! -e "${destination}" && ! -L "${destination}" ]]; then
        return
    fi

    log "Backup ${destination}"
    run mkdir -p -- "$(dirname -- "${backup}")"
    run mv -- "${destination}" "${backup}"
}

rewrite_home_paths() {
    local root="$1"
    local source_escaped target_escaped
    local file

    source_escaped="$(printf '%s' "${SOURCE_HOME}" | sed 's/[][\\.^$*|&/]/\\&/g')"
    target_escaped="$(printf '%s' "${TARGET_HOME}" | sed 's/[\\&|]/\\&/g')"

    while IFS= read -r -d '' file; do
        if grep -Iq . "${file}" && grep -qF "${SOURCE_HOME}" "${file}"; then
            run sed -i "s|${source_escaped}|${target_escaped}|g" "${file}"
        fi
    done < <(find "${root}" -type f -print0)
}

install_user_item() {
    local relative="$1"
    local source="${REPO_ROOT}/${relative}"
    local destination="${TARGET_HOME}/${relative}"

    if [[ ! -e "${source}" && ! -L "${source}" ]]; then
        log "Skip missing source ${relative}"
        return
    fi

    backup_path "${destination}"
    log "Install ${relative}"
    run mkdir -p -- "$(dirname -- "${destination}")"
    run cp -a -- "${source}" "${destination}"

    if ! "${DRY_RUN}"; then
        rewrite_home_paths "${destination}"
    fi
}

install_sddm() {
    local sudo_command=()
    local theme_target="/usr/share/sddm/themes/mika-mono"
    local config_target="/etc/sddm.conf.d/10-mika-rice.conf"

    if [[ "${EUID}" -ne 0 ]]; then
        sudo_command=(sudo)
    fi

    if [[ -e "${theme_target}" ]]; then
        log "Backup ${theme_target}"
        run "${sudo_command[@]}" mv -- \
            "${theme_target}" "${theme_target}.backup-${TIMESTAMP}"
    fi
    if [[ -e "${config_target}" ]]; then
        log "Backup ${config_target}"
        run "${sudo_command[@]}" cp -a -- \
            "${config_target}" "${config_target}.backup-${TIMESTAMP}"
    fi

    log "Install SDDM theme mika-mono"
    run "${sudo_command[@]}" install -d "${theme_target}"
    run "${sudo_command[@]}" cp -a \
        "${REPO_ROOT}/usr/share/sddm/themes/mika-mono/." \
        "${theme_target}/"
    run "${sudo_command[@]}" install -Dm644 \
        "${REPO_ROOT}/etc/sddm.conf.d/10-mika-rice.conf" \
        "${config_target}"
}

while (($#)); do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            ;;
        --check)
            CHECK_ONLY=true
            ;;
        --with-sddm)
            WITH_SDDM=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ "${EUID}" -eq 0 && "${TARGET_HOME}" == "/root" && -n "${SUDO_USER:-}" ]]; then
    printf 'Do not run the complete installer with sudo.\n' >&2
    printf 'Run it as your normal user; --with-sddm invokes sudo only where needed.\n' >&2
    exit 2
fi

printf 'Mika dotfiles installer\n'
printf 'Source: %s\n' "${REPO_ROOT}"
printf 'Target: %s\n\n' "${TARGET_HOME}"

if ! check_commands; then
    printf '\nSome required commands are missing. The files can still be installed,\n'
    printf 'but the full desktop will not work until the dependencies are present.\n'
fi

if "${CHECK_ONLY}"; then
    exit 0
fi

printf '\nInstalling user configuration:\n'
for item in "${USER_ITEMS[@]}"; do
    install_user_item "${item}"
done

if "${WITH_SDDM}"; then
    printf '\nInstalling system configuration:\n'
    install_sddm
fi

if ! "${DRY_RUN}"; then
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable payment-stream-privacy.service >/dev/null 2>&1 || true
    systemctl --user enable --now equicord-guard.timer >/dev/null 2>&1 || true
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        systemctl --user restart payment-stream-privacy.service
    fi
    update-desktop-database "${TARGET_HOME}/.local/share/applications" \
        >/dev/null 2>&1 || true
fi

printf '\nDone.\n'
if "${DRY_RUN}"; then
    printf 'No files were changed. Run ./install.sh without --dry-run to install.\n'
else
    printf 'Replaced files were backed up in:\n  %s\n' "${BACKUP_ROOT}"
    printf 'Review the monitor section in ~/.config/hypr/hyprland.lua, then restart Hyprland.\n'
fi
