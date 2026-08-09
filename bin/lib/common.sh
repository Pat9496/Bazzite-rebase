#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
IFS=$'\n\t'

log() {
    printf '[bazzite-rebase] %s\n' "$*" >&2
}

warn() {
    printf '[bazzite-rebase] warning: %s\n' "$*" >&2
}

err() {
    printf '[bazzite-rebase] error: %s\n' "$*" >&2
}

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        err "Required command '${cmd}' not found on PATH."
        exit 1
    fi
}

require_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "This script must be run as your normal user, not root. It elevates with sudo internally only for the rpm-ostree rebase step."
        exit 1
    fi
}

confirm() {
    local prompt="${1:-Are you sure?}"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then
        return 0
    fi
    local reply=""
    read -r -p "${prompt} [y/N] " reply || true
    case "${reply}" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

BACKUP_ROOT="${HOME}/.local/share/bazzite-rebase/backups"

new_backup_dir() {
    local dir
    dir="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${dir}"
    printf '%s\n' "${dir}"
}

latest_backup_dir() {
    local dir=""
    if [[ -d "${BACKUP_ROOT}" ]]; then
        dir="$(find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | head -n1 | cut -d' ' -f2-)"
    fi
    if [[ -z "${dir}" ]]; then
        err "No backups found under ${BACKUP_ROOT}."
        return 1
    fi
    printf '%s\n' "${dir}"
}

# rpm-ostree's JSON schema for the container image reference has shifted
# across releases, so fall back to parsing the plain-text status output
# (the line prefixed with the booted marker) if the jq lookup comes up empty.
get_current_image_ref() {
    local ref=""
    if command -v rpm-ostree >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        ref="$(rpm-ostree status --json 2>/dev/null \
            | jq -r '.deployments[] | select(.booted==true) | ."container-image-reference" // empty' 2>/dev/null || true)"
    fi
    if [[ -z "${ref}" ]] && command -v rpm-ostree >/dev/null 2>&1; then
        ref="$(rpm-ostree status 2>/dev/null | awk '/^● / {print $2; exit}' || true)"
    fi
    if [[ -z "${ref}" ]]; then
        err "Unable to determine the currently booted container image reference from rpm-ostree status."
        return 1
    fi
    printf '%s\n' "${ref}"
}

# Splits <transport>://<registry-path>/<image-name>:<tag> (or the
# single-colon transport form) into its parts, toggles the "-gnome" segment
# per bazzite[-deck][-gnome][-nvidia[-open]], and reassembles the ref.
compute_target_image_ref() {
    local current_ref="$1" direction="$2"

    if [[ "${direction}" != "gnome" && "${direction}" != "kde" ]]; then
        err "compute_target_image_ref: direction must be 'gnome' or 'kde', got '${direction}'."
        return 1
    fi

    local prefix="" rest="${current_ref}"
    if [[ "${rest}" == *"://"* ]]; then
        prefix="${rest%%://*}://"
        rest="${rest#*://}"
    elif [[ "${rest}" == *:* ]]; then
        prefix="${rest%%:*}:"
        rest="${rest#*:}"
    else
        err "Unrecognized image reference (no transport prefix): ${current_ref}"
        return 1
    fi

    local tag="" digest=""
    if [[ "${rest}" == *"@sha256:"* ]]; then
        # Digest-pinned reference: the "tag" portion is really "sha256:<hex>"
        # after the '@', and must be kept intact rather than colon-split.
        digest="${rest#*@}"
        rest="${rest%%@*}"
    elif [[ "${rest}" == *:* ]]; then
        tag="${rest##*:}"
        rest="${rest%:*}"
    else
        err "Unrecognized image reference (no tag): ${current_ref}"
        return 1
    fi

    local repo_path="${rest%/*}"
    local image_name="${rest##*/}"
    if [[ "${repo_path}" == "${rest}" ]]; then
        err "Unrecognized image reference (no registry path): ${current_ref}"
        return 1
    fi

    if [[ ! "${image_name}" =~ ^bazzite(-deck)?(-gnome)?(-nvidia(-open)?)?$ ]]; then
        err "Image name '${image_name}' does not look like a recognized bazzite* image."
        return 1
    fi
    local deck="${BASH_REMATCH[1]:-}"
    local gnome_seg="${BASH_REMATCH[2]:-}"
    local nvidia_seg="${BASH_REMATCH[3]:-}"

    case "${direction}" in
        gnome)
            if [[ -n "${gnome_seg}" ]]; then
                err "Current image is already a GNOME variant: ${image_name}"
                return 1
            fi
            gnome_seg="-gnome"
            ;;
        kde)
            if [[ -z "${gnome_seg}" ]]; then
                err "Current image is already a KDE Plasma variant: ${image_name}"
                return 1
            fi
            gnome_seg=""
            ;;
    esac

    local new_image_name="bazzite${deck}${gnome_seg}${nvidia_seg}"
    if [[ -n "${digest}" ]]; then
        printf '%s\n' "${prefix}${repo_path}/${new_image_name}@${digest}"
    else
        printf '%s\n' "${prefix}${repo_path}/${new_image_name}:${tag}"
    fi
}
