#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=SCRIPTDIR/bin/lib/common.sh
source "${SCRIPT_DIR}/bin/lib/common.sh"

require_cmd rpm-ostree
require_cmd jq

desktop="$(current_desktop)"

case "${desktop}" in
    kde)
        log "Detected KDE Plasma; running bin/rebase-to-gnome.sh."
        exec "${SCRIPT_DIR}/bin/rebase-to-gnome.sh" "$@"
        ;;
    gnome)
        log "Detected GNOME; running bin/rebase-to-kde.sh."
        exec "${SCRIPT_DIR}/bin/rebase-to-kde.sh" "$@"
        ;;
    *)
        err "Unrecognized desktop '${desktop}' detected."
        exit 1
        ;;
esac
