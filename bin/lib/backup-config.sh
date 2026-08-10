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

if command -v rpm-ostree >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    requested_packages_raw="$(rpm-ostree status --json 2>/dev/null \
        | jq -r '.deployments[] | select(.booted==true) | (."requested-packages" // [])[]' 2>/dev/null || true)"
    if [[ -z "${requested_packages_raw}" ]]; then
        warn "Could not determine requested rpm-ostree packages; skipping layered-package capture."
    else
        mapfile -t requested_packages <<< "${requested_packages_raw}"
        layered_matches=()
        for pkg in "${WELL_KNOWN_LAYERED_PACKAGES[@]}"; do
            for requested in "${requested_packages[@]}"; do
                if [[ "${pkg}" == "${requested}" ]]; then
                    layered_matches+=("${pkg}")
                    break
                fi
            done
        done
        if ((${#layered_matches[@]})); then
            printf '%s\n' "${layered_matches[@]}" > "${backup_dir}/rpm-ostree-layered-packages.txt"
        else
            log "None of the well-known layered packages are currently layered."
        fi
    fi
else
    warn "rpm-ostree or jq not found; skipping layered-package capture."
fi

source_desktop=""
dark_mode=""
wallpaper_path=""
keyboard_layouts=""
night_light_enabled=""
night_light_temperature=""
region_format=""
screen_lock_enabled=""
screen_lock_timeout_seconds=""

kde_read() {
    local file="$1" group="$2" key="$3"
    local val=""
    if command -v kreadconfig6 >/dev/null 2>&1; then
        val="$(kreadconfig6 --file "${file}" --group "${group}" --key "${key}" 2>/dev/null || true)"
    fi
    if [[ -z "${val}" ]] && command -v kreadconfig5 >/dev/null 2>&1; then
        val="$(kreadconfig5 --file "${file}" --group "${group}" --key "${key}" 2>/dev/null || true)"
    fi
    printf '%s' "${val}"
}

if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* || -n "${KDE_FULL_SESSION:-}" ]]; then
    source_desktop="kde"

    scheme="$(kde_read kdeglobals General ColorScheme)"
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

    layout_list="$(kde_read kxkbrc Layout LayoutList)"
    if [[ -n "${layout_list}" ]]; then
        variant_list="$(kde_read kxkbrc Layout VariantList)"
        IFS=',' read -r -a _kb_layouts <<< "${layout_list}"
        IFS=',' read -r -a _kb_variants <<< "${variant_list}"
        _kb_entries=()
        for i in "${!_kb_layouts[@]}"; do
            layout="${_kb_layouts[$i]}"
            variant="${_kb_variants[$i]:-}"
            if [[ -n "${variant}" ]]; then
                _kb_entries+=("${layout}:${variant}")
            else
                _kb_entries+=("${layout}")
            fi
        done
        keyboard_layouts="$(IFS=','; printf '%s' "${_kb_entries[*]}")"
    else
        warn "Could not determine KDE keyboard layout (kxkbrc LayoutList)."
    fi

    night_color_active="$(kde_read kwinrc NightColor Active)"
    if [[ -n "${night_color_active}" ]]; then
        night_light_enabled="${night_color_active}"
        night_light_temperature="$(kde_read kwinrc NightColor NightTemperature)"
    else
        warn "Could not determine KDE Night Color state (kwinrc NightColor)."
    fi

    region_format="$(kde_read plasma-localerc Formats LANG)"
    if [[ -z "${region_format}" ]]; then
        warn "Could not determine KDE region format (plasma-localerc)."
    fi

    autolock="$(kde_read kscreenlockerrc Daemon Autolock)"
    if [[ -n "${autolock}" ]]; then
        screen_lock_enabled="${autolock}"
        lock_timeout_minutes="$(kde_read kscreenlockerrc Daemon Timeout)"
        if [[ "${lock_timeout_minutes}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            screen_lock_timeout_seconds=$(( ${lock_timeout_minutes%%.*} * 60 ))
        elif [[ -n "${lock_timeout_minutes}" ]]; then
            warn "Ignoring non-numeric kscreenlockerrc Timeout value: ${lock_timeout_minutes}"
        fi
    else
        warn "Could not determine KDE screen lock state (kscreenlockerrc)."
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

        sources_raw="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null || true)"
        if [[ -n "${sources_raw}" ]]; then
            _kb_entries=()
            while IFS= read -r xkb_id; do
                [[ -z "${xkb_id}" ]] && continue
                _kb_entries+=("${xkb_id/+/:}")
            done < <(grep -oP "\('xkb', '\K[^']+" <<< "${sources_raw}" 2>/dev/null || true)
            if grep -q "'ibus'" <<< "${sources_raw}"; then
                warn "Skipping non-xkb (ibus) input sources; no KDE equivalent."
            fi
            if ((${#_kb_entries[@]})); then
                keyboard_layouts="$(IFS=','; printf '%s' "${_kb_entries[*]}")"
            else
                warn "No xkb keyboard layouts found in GNOME input sources."
            fi
        else
            warn "Could not determine GNOME keyboard layout (input-sources)."
        fi

        night_light_enabled="$(gsettings get org.gnome.settings-daemon.plugins.color night-light-enabled 2>/dev/null || true)"
        if [[ -n "${night_light_enabled}" ]]; then
            night_light_temperature="$(gsettings get org.gnome.settings-daemon.plugins.color night-light-temperature 2>/dev/null || true)"
        else
            warn "Could not determine GNOME Night Light state."
        fi

        region_format="$(gsettings get org.gnome.system.locale region 2>/dev/null || true)"
        if [[ -n "${region_format}" ]]; then
            region_format="${region_format#\'}"
            region_format="${region_format%\'}"
        else
            warn "Could not determine GNOME region format."
        fi

        screen_lock_enabled="$(gsettings get org.gnome.desktop.screensaver lock-enabled 2>/dev/null || true)"
        if [[ -n "${screen_lock_enabled}" ]]; then
            idle_delay="$(gsettings get org.gnome.desktop.session idle-delay 2>/dev/null || true)"
            lock_delay="$(gsettings get org.gnome.desktop.screensaver lock-delay 2>/dev/null || true)"
            if [[ "${idle_delay}" =~ ^[0-9]+$ && "${lock_delay}" =~ ^[0-9]+$ ]]; then
                screen_lock_timeout_seconds=$(( idle_delay + lock_delay ))
            else
                warn "Could not parse GNOME idle-delay/lock-delay as numbers; skipping screen lock timeout."
            fi
        else
            warn "Could not determine GNOME screen lock state."
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
[[ -n "${keyboard_layouts}" ]] && printf 'KEYBOARD_LAYOUTS=%q\n' "${keyboard_layouts}" >> "${settings_file}"
[[ -n "${night_light_enabled}" ]] && printf 'NIGHT_LIGHT_ENABLED=%s\n' "${night_light_enabled}" >> "${settings_file}"
[[ -n "${night_light_temperature}" ]] && printf 'NIGHT_LIGHT_TEMPERATURE=%s\n' "${night_light_temperature}" >> "${settings_file}"
[[ -n "${region_format}" ]] && printf 'REGION_FORMAT=%q\n' "${region_format}" >> "${settings_file}"
[[ -n "${screen_lock_enabled}" ]] && printf 'SCREEN_LOCK_ENABLED=%s\n' "${screen_lock_enabled}" >> "${settings_file}"
[[ -n "${screen_lock_timeout_seconds}" ]] && printf 'SCREEN_LOCK_TIMEOUT_SECONDS=%s\n' "${screen_lock_timeout_seconds}" >> "${settings_file}"

log "Backup written to ${backup_dir}"
printf '%s\n' "${backup_dir}"
