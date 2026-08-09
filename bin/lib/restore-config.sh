#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# shellcheck source=SCRIPTDIR/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_not_root

usage() {
    printf 'Usage: %s --to gnome|kde [--from <backup-dir>]\n' "$(basename "${BASH_SOURCE[0]}")" >&2
}

target_desktop=""
from_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --to)
            [[ $# -ge 2 ]] || { err "--to requires an argument."; exit 1; }
            target_desktop="$2"
            shift 2
            ;;
        --from)
            [[ $# -ge 2 ]] || { err "--from requires an argument."; exit 1; }
            from_dir="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ "${target_desktop}" != "gnome" && "${target_desktop}" != "kde" ]]; then
    err "You must specify --to gnome or --to kde."
    usage
    exit 1
fi

if [[ -z "${from_dir}" ]]; then
    from_dir="$(latest_backup_dir)"
fi

if [[ ! -d "${from_dir}" ]]; then
    err "Backup directory not found: ${from_dir}"
    exit 1
fi

settings_file="${from_dir}/settings.env"
if [[ ! -f "${settings_file}" ]]; then
    err "No settings.env found in ${from_dir}"
    exit 1
fi

SOURCE_DESKTOP=""
DARK_MODE=""
WALLPAPER_PATH=""
# shellcheck source=/dev/null
source "${settings_file}"
log "Settings were captured on: ${SOURCE_DESKTOP:-unknown desktop}"

applied=()
skipped=()

if [[ -n "${DARK_MODE}" ]]; then
    if [[ "${target_desktop}" == "gnome" ]]; then
        require_cmd gsettings
        if [[ "${DARK_MODE}" == "true" ]]; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        else
            gsettings set org.gnome.desktop.interface color-scheme 'default'
        fi
    else
        require_cmd plasma-apply-colorscheme
        if [[ "${DARK_MODE}" == "true" ]]; then
            plasma-apply-colorscheme BreezeDark
        else
            plasma-apply-colorscheme BreezeClassic
        fi
    fi
    applied+=("dark/light mode")
else
    warn "No DARK_MODE recorded in ${settings_file}; skipping."
    skipped+=("dark/light mode")
fi

if [[ -n "${WALLPAPER_PATH}" ]]; then
    if [[ "${target_desktop}" == "gnome" ]]; then
        require_cmd gsettings
        wallpaper_uri="file://${WALLPAPER_PATH}"
        gsettings set org.gnome.desktop.background picture-uri "${wallpaper_uri}"
        gsettings set org.gnome.desktop.background picture-uri-dark "${wallpaper_uri}"
    else
        require_cmd plasma-apply-wallpaperimage
        plasma-apply-wallpaperimage "${WALLPAPER_PATH}"
    fi
    applied+=("wallpaper")
else
    warn "No WALLPAPER_PATH recorded in ${settings_file}; skipping."
    skipped+=("wallpaper")
fi

manual_steps_file="${from_dir}/MANUAL-STEPS.txt"
{
    printf 'Not migrated (set manually after switching):\n\n'
    printf -- '- Panel/dock/taskbar layout, widgets, and system tray configuration\n'
    printf -- '- Global and per-application keyboard shortcuts\n'
    printf -- '- Default application associations (~/.config/mimeapps.list entries reference desktop-specific app IDs, e.g. org.kde.dolphin.desktop vs org.gnome.Nautilus.desktop)\n'
    printf -- '- Per-application settings for desktop-bundled apps (Dolphin/Konsole vs Nautilus/Console, etc.)\n'
    printf -- '- KDE Activities and virtual desktop setup; GNOME workspaces configuration\n'
    printf -- '- GNOME Shell extensions; KDE Plasma widgets and window rules\n'
    printf -- "- Icon theme and GTK/Qt application style (the two desktops don't share a theme format)\n"
} > "${manual_steps_file}"

applied_str="none"
if ((${#applied[@]})); then
    applied_str="$(IFS=', '; printf '%s' "${applied[*]}")"
fi
skipped_str="none"
if ((${#skipped[@]})); then
    skipped_str="$(IFS=', '; printf '%s' "${skipped[*]}")"
fi
log "Applied: ${applied_str}"
log "Skipped: ${skipped_str}"
log "Manual steps checklist written to ${manual_steps_file}"
