#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=SCRIPTDIR/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_not_root

DIRECTION="kde"
DRY_RUN=0
ASSUME_YES="${ASSUME_YES:-0}"

usage() {
    printf 'Usage: %s [-y|--yes] [--dry-run]\n' "$(basename "${BASH_SOURCE[0]}")" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
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

require_cmd jq
require_cmd rpm-ostree
require_cmd sudo

current_ref="$(get_current_image_ref)"
target_ref="$(compute_target_image_ref "${current_ref}" "${DIRECTION}")"

log "Current image: ${current_ref}"
log "Target image:  ${target_ref}"
warn "Rebasing between desktop environments is unsupported by the Bazzite project; see README.md."
verify_target_matches_hardware "${target_ref}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "Dry run: would back up current settings, then run: sudo rpm-ostree rebase ${target_ref}"
    exit 0
fi

if ! confirm "Proceed with rebasing to ${target_ref}?"; then
    log "Aborted by user."
    exit 1
fi

backup_dir="$("${SCRIPT_DIR}/lib/backup-config.sh")"
log "Settings backed up to ${backup_dir}"

sudo rpm-ostree rebase "${target_ref}"

log "Rebase staged successfully."
log "Next steps:"
log "  1. Reboot into the new deployment."
log "  2. Run: ${SCRIPT_DIR}/lib/restore-config.sh --to ${DIRECTION}"
