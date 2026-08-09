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
KEYBOARD_LAYOUTS=""
NIGHT_LIGHT_ENABLED=""
NIGHT_LIGHT_TEMPERATURE=""
REGION_FORMAT=""
SCREEN_LOCK_ENABLED=""
SCREEN_LOCK_TIMEOUT_SECONDS=""
# shellcheck source=/dev/null
source "${settings_file}"
log "Settings were captured on: ${SOURCE_DESKTOP:-unknown desktop}"

kde_write() {
    local file="$1" group="$2" key="$3" value="$4"
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file "${file}" --group "${group}" --key "${key}" "${value}"
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
        kwriteconfig5 --file "${file}" --group "${group}" --key "${key}" "${value}"
    else
        err "Neither kwriteconfig6 nor kwriteconfig5 found on PATH."
        exit 1
    fi
}

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

if [[ -n "${KEYBOARD_LAYOUTS}" ]]; then
    IFS=',' read -r -a _kb_entries <<< "${KEYBOARD_LAYOUTS}"
    if [[ "${target_desktop}" == "gnome" ]]; then
        require_cmd gsettings
        _kb_tuples=()
        for entry in "${_kb_entries[@]}"; do
            layout="${entry%%:*}"
            if [[ "${entry}" == *:* ]]; then
                _kb_tuples+=("('xkb', '${layout}+${entry#*:}')")
            else
                _kb_tuples+=("('xkb', '${layout}')")
            fi
        done
        gsettings set org.gnome.desktop.input-sources sources "[$(IFS=','; printf '%s' "${_kb_tuples[*]}")]"
    else
        _kb_layouts=()
        _kb_variants=()
        for entry in "${_kb_entries[@]}"; do
            _kb_layouts+=("${entry%%:*}")
            if [[ "${entry}" == *:* ]]; then
                _kb_variants+=("${entry#*:}")
            else
                _kb_variants+=("")
            fi
        done
        kde_write kxkbrc Layout LayoutList "$(IFS=','; printf '%s' "${_kb_layouts[*]}")"
        kde_write kxkbrc Layout VariantList "$(IFS=','; printf '%s' "${_kb_variants[*]}")"
        warn "Keyboard layout written to kxkbrc; a logout/login may be needed for it to take effect."
    fi
    applied+=("keyboard layout")
else
    warn "No KEYBOARD_LAYOUTS recorded in ${settings_file}; skipping."
    skipped+=("keyboard layout")
fi

if [[ -n "${NIGHT_LIGHT_ENABLED}" ]]; then
    if [[ "${target_desktop}" == "gnome" ]]; then
        require_cmd gsettings
        gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled "${NIGHT_LIGHT_ENABLED}"
        [[ -n "${NIGHT_LIGHT_TEMPERATURE}" ]] && gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature "${NIGHT_LIGHT_TEMPERATURE}"
    else
        kde_write kwinrc NightColor Active "${NIGHT_LIGHT_ENABLED}"
        [[ -n "${NIGHT_LIGHT_TEMPERATURE}" ]] && kde_write kwinrc NightColor NightTemperature "${NIGHT_LIGHT_TEMPERATURE}"
        if command -v qdbus6 >/dev/null 2>&1; then
            qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || warn "Could not reload KWin config; a logout/login may be needed for Night Light to take effect."
        elif command -v qdbus >/dev/null 2>&1; then
            qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || warn "Could not reload KWin config; a logout/login may be needed for Night Light to take effect."
        else
            warn "qdbus not found; a logout/login may be needed for Night Light to take effect."
        fi
    fi
    applied+=("Night Light")
else
    warn "No NIGHT_LIGHT_ENABLED recorded in ${settings_file}; skipping."
    skipped+=("Night Light")
fi

if [[ -n "${REGION_FORMAT}" ]]; then
    if [[ "${target_desktop}" == "gnome" ]]; then
        require_cmd gsettings
        gsettings set org.gnome.system.locale region "${REGION_FORMAT}"
    else
        kde_write plasma-localerc Formats LANG "${REGION_FORMAT}"
    fi
    warn "Region format applied; a logout/login is needed for it to fully take effect."
    applied+=("region format")
else
    warn "No REGION_FORMAT recorded in ${settings_file}; skipping."
    skipped+=("region format")
fi

if [[ -n "${SCREEN_LOCK_ENABLED}" ]]; then
    if [[ "${target_desktop}" == "gnome" ]]; then
        require_cmd gsettings
        gsettings set org.gnome.desktop.screensaver lock-enabled "${SCREEN_LOCK_ENABLED}"
        if [[ "${SCREEN_LOCK_ENABLED}" == "true" && "${SCREEN_LOCK_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]]; then
            gsettings set org.gnome.desktop.session idle-delay "${SCREEN_LOCK_TIMEOUT_SECONDS}"
            gsettings set org.gnome.desktop.screensaver lock-delay 0
        fi
    else
        kde_write kscreenlockerrc Daemon Autolock "${SCREEN_LOCK_ENABLED}"
        if [[ "${SCREEN_LOCK_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]]; then
            kde_write kscreenlockerrc Daemon Timeout $(( SCREEN_LOCK_TIMEOUT_SECONDS / 60 ))
        fi
    fi
    applied+=("screen lock timeout")
else
    warn "No SCREEN_LOCK_ENABLED recorded in ${settings_file}; skipping."
    skipped+=("screen lock timeout")
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
    printf -- '- Suspend/sleep and display-off timeouts (KDE per-profile power settings have no clean 1:1 mapping to GNOME power settings)\n'
    printf -- '- Non-xkb input methods (e.g. ibus engines); only xkb keyboard layouts are migrated\n'
    printf -- '- Saved passwords/secrets (GNOME Keyring vs KWallet use incompatible on-disk formats); WiFi/browser/email passwords stored in one are not readable by the other after switching\n'
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
