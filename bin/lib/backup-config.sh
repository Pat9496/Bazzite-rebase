#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# shellcheck source=SCRIPTDIR/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_not_root

backup_dir="$(new_backup_dir)"

if command -v dconf >/dev/null 2>&1; then
    if ! dconf dump / > "${backup_dir}/dconf-dump.ini" 2>/dev/null; then
        warn "Failed to dump dconf settings."
        rm -f "${backup_dir}/dconf-dump.ini"
    fi
else
    warn "dconf not found; skipping dconf dump."
fi

if command -v flatpak >/dev/null 2>&1; then
    if ! flatpak list --user --app --columns=application,version,branch,origin > "${backup_dir}/flatpak-user-apps.txt" 2>/dev/null; then
        warn "Failed to list flatpak user apps."
        rm -f "${backup_dir}/flatpak-user-apps.txt"
    fi
else
    warn "flatpak not found; skipping flatpak app list."
fi

if command -v rpm-ostree >/dev/null 2>&1; then
    if ! rpm-ostree status --json > "${backup_dir}/rpm-ostree-status.json" 2>/dev/null; then
        warn "Failed to capture rpm-ostree status."
        rm -f "${backup_dir}/rpm-ostree-status.json"
    fi
else
    warn "rpm-ostree not found; skipping status capture."
fi

source_desktop=""
dark_mode=""
wallpaper_path=""

if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* || -n "${KDE_FULL_SESSION:-}" ]]; then
    source_desktop="kde"

    scheme=""
    if command -v kreadconfig6 >/dev/null 2>&1; then
        scheme="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)"
    fi
    if [[ -z "${scheme}" ]] && command -v kreadconfig5 >/dev/null 2>&1; then
        scheme="$(kreadconfig5 --file kdeglobals --group General --key ColorScheme 2>/dev/null || true)"
    fi
    if [[ -n "${scheme}" ]]; then
        if [[ "${scheme,,}" == *dark* ]]; then
            dark_mode="true"
        else
            dark_mode="false"
        fi
    else
        warn "Could not determine KDE color scheme."
    fi

    appletsrc="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f "${appletsrc}" ]]; then
        image_line="$(awk '/^\[.*Wallpaper\]\[org\.kde\.image\]\[General\]/{flag=1;next} /^\[/{flag=0} flag && /^Image=/{print;exit}' "${appletsrc}" 2>/dev/null || true)"
        if [[ -n "${image_line}" ]]; then
            wallpaper_uri="${image_line#Image=}"
            wallpaper_path="${wallpaper_uri#file://}"
        else
            warn "Could not find a wallpaper Image= entry in ${appletsrc}."
        fi
    else
        warn "Plasma appletsrc config not found at ${appletsrc}."
    fi
elif [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]]; then
    source_desktop="gnome"

    if command -v gsettings >/dev/null 2>&1; then
        color_scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
        if [[ -n "${color_scheme}" ]]; then
            if [[ "${color_scheme}" == *prefer-dark* ]]; then
                dark_mode="true"
            else
                dark_mode="false"
            fi
        else
            warn "Could not determine GNOME color-scheme."
        fi

        picture_uri="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)"
        if [[ -n "${picture_uri}" ]]; then
            picture_uri="${picture_uri#\'}"
            picture_uri="${picture_uri%\'}"
            wallpaper_path="${picture_uri#file://}"
        else
            warn "Could not determine GNOME wallpaper picture-uri."
        fi
    else
        warn "gsettings not found; skipping GNOME settings read."
    fi
else
    warn "Could not determine current desktop environment (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset})."
fi

settings_file="${backup_dir}/settings.env"
: > "${settings_file}"
[[ -n "${source_desktop}" ]] && printf 'SOURCE_DESKTOP=%s\n' "${source_desktop}" >> "${settings_file}"
[[ -n "${dark_mode}" ]] && printf 'DARK_MODE=%s\n' "${dark_mode}" >> "${settings_file}"
[[ -n "${wallpaper_path}" ]] && printf 'WALLPAPER_PATH=%q\n' "${wallpaper_path}" >> "${settings_file}"

log "Backup written to ${backup_dir}"
printf '%s\n' "${backup_dir}"
