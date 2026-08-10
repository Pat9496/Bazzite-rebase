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

# shellcheck disable=SC2034 # used by bin/lib/backup-config.sh and bin/lib/restore-config.sh
WELL_KNOWN_LAYERED_PACKAGES=(
    alacritty chezmoi htop btop neovim tmux fastfetch git git-lfs git-delta gh lazygit tig
    cmatrix distrobox edk2-ovmf git-credential-libsecret libvirt podman-compose qemu-kvm
    rpmdevtools swtpm topgrade vim-enhanced virt-install xclip xdotool xsel
)

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
            | sort -rn | awk 'NR==1 { sub(/^[^ ]+ /, ""); print }')"
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
        # A digest is a content hash of the *specific* image named in
        # current_ref; it doesn't identify any manifest under a different
        # image name, so it can't be carried over as-is. Fall back to the
        # ":latest" tag of the target image instead, so the rebase still
        # resolves to a real, current image rather than a nonexistent ref.
        warn "Current image is pinned to a digest (@${digest}), which is specific to '${image_name}' and does not carry over to '${new_image_name}'; rebasing to '${new_image_name}:latest' instead."
        printf '%s\n' "${prefix}${repo_path}/${new_image_name}:latest"
    else
        printf '%s\n' "${prefix}${repo_path}/${new_image_name}:${tag}"
    fi
}

# Determines whether the currently booted image is a KDE Plasma or GNOME
# variant, using the same bazzite[-deck][-gnome][-nvidia[-open]] pattern
# compute_target_image_ref validates against, so the two never disagree.
current_desktop() {
    local ref="" name=""
    ref="$(get_current_image_ref)" || return 1

    name="${ref##*/}"
    name="${name%%@*}"
    name="${name%%:*}"

    if [[ ! "${name}" =~ ^bazzite(-deck)?(-gnome)?(-nvidia(-open)?)?$ ]]; then
        err "Image name '${name}' does not look like a recognized bazzite* image."
        return 1
    fi

    if [[ -n "${BASH_REMATCH[2]:-}" ]]; then
        printf 'gnome\n'
    else
        printf 'kde\n'
    fi
}

detect_has_nvidia_gpu() {
    command -v lspci >/dev/null 2>&1 || return 1
    lspci -mm 2>/dev/null | awk -F'"' '{print $4}' | grep -qi 'NVIDIA'
}

detect_is_steam_deck() {
    local product=""
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
    [[ "${product}" == "Jupiter" || "${product}" == "Galileo" ]]
}

# Best-effort sanity check that a computed target ref's hardware-specific
# segments (-deck, -nvidia[-open]) match what's actually detected on this
# machine. Warns only -- never blocks the rebase -- since detection here
# (lspci output, DMI product name) is a heuristic, not authoritative, and
# these segments aren't something compute_target_image_ref ever changes
# (only the -gnome segment is toggled).
verify_target_matches_hardware() {
    local target_ref="$1"
    local name="${target_ref##*/}"
    name="${name%%@*}"
    name="${name%%:*}"

    if [[ ! "${name}" =~ ^bazzite(-deck)?(-gnome)?(-nvidia(-open)?)?$ ]]; then
        return 0
    fi
    local deck_seg="${BASH_REMATCH[1]:-}" nvidia_seg="${BASH_REMATCH[3]:-}"

    if command -v lspci >/dev/null 2>&1; then
        if detect_has_nvidia_gpu && [[ -z "${nvidia_seg}" ]]; then
            warn "An NVIDIA GPU was detected, but '${name}' is not an -nvidia image variant."
        elif ! detect_has_nvidia_gpu && [[ -n "${nvidia_seg}" ]]; then
            warn "No NVIDIA GPU was detected, but '${name}' is an -nvidia image variant."
        fi
    else
        warn "lspci not found; skipping NVIDIA hardware/image match check."
    fi

    if [[ -r /sys/class/dmi/id/product_name ]]; then
        if detect_is_steam_deck && [[ -z "${deck_seg}" ]]; then
            warn "This looks like a Steam Deck, but '${name}' is not a -deck image variant."
        elif ! detect_is_steam_deck && [[ -n "${deck_seg}" ]]; then
            warn "This doesn't look like a Steam Deck, but '${name}' is a -deck image variant."
        fi
    else
        warn "Could not read DMI product name; skipping Steam Deck/image match check."
    fi
}
