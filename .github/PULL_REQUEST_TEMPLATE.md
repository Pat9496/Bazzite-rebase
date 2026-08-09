## What does this change?

<!-- A clear description of the change and why it's needed. -->

## How was this tested?

<!--
These scripts touch real system state, so please describe manual testing:
- bash -n on every changed script
- shellcheck on every changed script
- --dry-run output (for the top-level rebase scripts)
- Actual run against a real Bazzite system, if applicable — which desktop
  (KDE Plasma / GNOME), and what you confirmed afterwards
-->

## Checklist

- [ ] All text (code comments, docs, commit messages) is in English.
- [ ] `shellcheck bin/*.sh bin/lib/*.sh` passes.
- [ ] If this changes what is/isn't migrated between desktops,
      `config-map/README.md` was updated to match.
