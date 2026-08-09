# Bazzite-rebase

Helper scripts to switch a [Bazzite](https://bazzite.gg) installation between its
KDE Plasma and GNOME desktop-environment images, while keeping as much of the
existing user configuration intact as is realistically possible.

## Why this exists

Bazzite ships separate container images per desktop environment (e.g.
`ghcr.io/ublue-os/bazzite` for KDE Plasma vs `ghcr.io/ublue-os/bazzite-gnome`
for GNOME), swapped via `rpm-ostree rebase`. The
[official rebase guide](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/)
is explicit that **rebasing between desktop environments is unsupported and
may cause issues** — these scripts do not change that fact, they just try to
make the transition less painful.

> [!WARNING]
> Rebasing KDE Plasma ↔ GNOME is unsupported by the Bazzite project. Use at
> your own risk, on a system you can afford to reinstall or roll back.

## What actually happens on a rebase

On an ostree-based system like Bazzite, only `/usr` is replaced wholesale and
`/etc` is three-way merged on a rebase — `/home` and `/var` (which is where
`/var/lib/flatpak` lives) are untouched. In practice this means:

- Your files, shell config, SSH keys, Flatpak apps, and Flatpak per-app data
  already survive a rebase on their own — nothing needs to be "restored" for
  those.
- What does **not** carry over automatically is anything that only makes
  sense inside one desktop's configuration system: KDE Plasma settings live
  in KConfig/`kwriteconfig` files under `~/.config`, GNOME settings live in
  `dconf`/`gsettings`. Neither desktop reads the other's format, so after a
  rebase the new desktop simply starts from its own defaults for anything
  it's never been configured before.

These scripts back up a snapshot of your current settings for reference, and
actively re-apply a small, well-defined set of equivalent preferences
(dark/light mode, wallpaper) in the new desktop's native config system. See
[`config-map/README.md`](config-map/README.md) for exactly what is and isn't
migrated.

## Requirements

- A running Bazzite install (KDE Plasma or GNOME variant), with `rpm-ostree`,
  `jq`, and `sudo` available (all present by default on Bazzite).
- Run as your normal user, not root — the scripts elevate with `sudo`
  internally only for the `rpm-ostree rebase` step itself, since the
  dconf/gsettings/flatpak inspection needs to run in your own user session.

## Usage

```bash
./Bazzite-rebase.sh
```

This detects whether you're currently on KDE Plasma or GNOME and runs the
matching script for you (`bin/rebase-to-gnome.sh` or `bin/rebase-to-kde.sh`).
Any arguments are forwarded, e.g. `./Bazzite-rebase.sh --dry-run` or
`./Bazzite-rebase.sh -y`.

You can also call either script directly if you'd rather be explicit about
direction:

```bash
# From KDE Plasma, switch to GNOME
bin/rebase-to-gnome.sh

# From GNOME, switch to KDE Plasma
bin/rebase-to-kde.sh
```

Both scripts:

1. Detect your current image (device type, GPU driver, and channel/tag are
   all preserved — only the desktop-environment component is swapped).
2. Run `bin/lib/backup-config.sh` to snapshot current settings under
   `~/.local/share/bazzite-rebase/backups/<timestamp>/`.
3. Print the exact target image and ask for confirmation before doing
   anything (skip the prompt with `-y`/`--yes`; preview only with
   `--dry-run`).
4. Run `rpm-ostree rebase` (via `sudo`) to stage the new deployment.
5. Tell you to reboot, and to run `bin/lib/restore-config.sh` afterwards.

After rebooting into the new desktop:

```bash
bin/lib/restore-config.sh --to gnome   # or --to kde
```

This re-applies the settings captured in step 2 that have a known
equivalent in the new desktop, and writes a `MANUAL-STEPS.txt` next to the
backup listing what it could *not* migrate (panel/dock layout, keyboard
shortcuts, per-application settings, default app associations, GNOME
extensions, KDE Activities, and similar desktop-specific setup).

## Rolling back

If something goes wrong, `rpm-ostree` keeps the previous deployment around:

```bash
sudo rpm-ostree rollback
```

reboot, and you're back on the prior image untouched.

## Contributing

Bug reports, feature requests, and pull requests are welcome — see
[`CONTRIBUTING.md`](CONTRIBUTING.md) for coding style and how to test
changes. Security issues should be reported privately per
[`SECURITY.md`](SECURITY.md) rather than filed as public issues.

## Credits

- [Bazzite](https://bazzite.gg) and the [ublue-os](https://github.com/ublue-os)
  project, for the images, rebase mechanism, and
  [documentation](https://docs.bazzite.gg) these scripts build on.
- The [KDE Plasma](https://kde.org/plasma-desktop/) project, for the
  `kreadconfig`/`plasma-apply-colorscheme`/`plasma-apply-wallpaperimage`
  CLI tooling used to read and apply KDE settings.
- The [GNOME](https://www.gnome.org/) project, for `gsettings`/`dconf`,
  used to read and apply GNOME settings.

## License

[MIT](LICENSE)
