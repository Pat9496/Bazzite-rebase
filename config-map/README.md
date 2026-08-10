# KDE Plasma ↔ GNOME setting equivalents

KDE Plasma and GNOME store almost nothing in a compatible format, so this is
a short, explicit list rather than a generic mapping engine. `restore-config.sh`
implements exactly these translations in code — nothing more.

## Actively migrated

| Concept        | KDE Plasma (read/write)                                                                 | GNOME (read/write)                                                          |
|-----------------|-------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| Dark/light mode | `kreadconfig6`/`kreadconfig5` (`kdeglobals`, group `General`, key `ColorScheme`); applied with `plasma-apply-colorscheme` | `gsettings get/set org.gnome.desktop.interface color-scheme` (`prefer-dark`/`default`) |
| Wallpaper image | Plasma per-monitor wallpaper config (read via the current `plasma-org.kde.plasma.desktop-appletsrc`); applied with `plasma-apply-wallpaperimage` | `gsettings get/set org.gnome.desktop.background picture-uri` (and `picture-uri-dark`) |
| Keyboard layout(s) | `kxkbrc`, group `Layout`, keys `LayoutList`/`VariantList` (xkb layout/variant only — non-xkb input methods like ibus engines aren't migrated) | `gsettings get/set org.gnome.desktop.input-sources sources` |
| Night Light / blue-light filter | `kwinrc`, group `NightColor`, keys `Active`/`NightTemperature`; reloaded via `qdbus6`/`qdbus org.kde.KWin /KWin reconfigure` | `gsettings get/set org.gnome.settings-daemon.plugins.color night-light-enabled`/`night-light-temperature` |
| Region format (dates/numbers/currency) | `plasma-localerc`, group `Formats`, key `LANG` | `gsettings get/set org.gnome.system.locale region` |
| Screen lock (on/off + timeout) | `kscreenlockerrc`, group `Daemon`, keys `Autolock`/`Timeout` (minutes) | `gsettings get/set org.gnome.desktop.screensaver lock-enabled` and `org.gnome.desktop.session idle-delay` + `org.gnome.desktop.screensaver lock-delay` (seconds, summed) |

All of these are best-effort: if a value can't be read on the source desktop,
the script logs a warning and skips it rather than failing the whole run.

## Layered packages

Separately from the desktop-setting table above, `backup-config.sh` also
checks whether any of a curated, well-known set of `rpm-ostree`-layered
packages are currently requested — everyday CLI tools (`alacritty`,
`chezmoi`, `htop`, `btop`, `neovim`, `tmux`, `fastfetch`, `git`, `git-lfs`,
`git-delta`, `gh`, `lazygit`, `tig`, `git-credential-libsecret`, `vim-enhanced`,
`cmatrix`, `topgrade`, `rpmdevtools`, `xclip`, `xdotool`, `xsel`) and the
virtualization stack (`libvirt`, `qemu-kvm`, `virt-install`, `edk2-ovmf`,
`swtpm`, `podman-compose`, `distrobox` — see `WELL_KNOWN_LAYERED_PACKAGES`
in `bin/lib/common.sh`), and records any matches to
`rpm-ostree-layered-packages.txt` in the backup directory. NVIDIA driver
packages (`akmod-nvidia`, `xorg-x11-drv-nvidia`, and friends) are
deliberately **not** tracked here — Bazzite ships a dedicated `-nvidia`
image variant for that (see the image-name pattern in
`compute_target_image_ref`/`current_desktop` in `bin/lib/common.sh`), so
switching NVIDIA support is a rebase to the right image, not a layered
package to restore.
`restore-config.sh` reads that file back after the rebase and reboot, checks
which of those packages are missing on the new deployment, and re-layers any
that didn't carry over with `sudo rpm-ostree install` (which requires another
reboot to take effect). This is a safety net, not a general package manager —
only the well-known set above is tracked; any other `rpm-ostree install`ed
package is your own responsibility to check and re-layer.

## Not migrated (set manually after switching)

These have no reliable 1:1 equivalent, or depend on desktop-specific
components that don't exist on the other side:

- Panel/dock/taskbar layout, widgets, and system tray configuration
- Global and per-application keyboard shortcuts
- Default application associations (`~/.config/mimeapps.list` entries
  reference desktop-specific app IDs, e.g. `org.kde.dolphin.desktop` vs
  `org.gnome.Nautilus.desktop`)
- Per-application settings for desktop-bundled apps (Dolphin/Konsole vs
  Nautilus/Console, etc.)
- KDE Activities and virtual desktop setup; GNOME workspaces configuration
- GNOME Shell extensions; KDE Plasma widgets and window rules
- Icon theme and GTK/Qt application style (the two desktops don't share a
  theme format)
- Suspend/sleep and display-off timeouts (KDE's per-profile AC/Battery/
  LowBattery power settings have no clean 1:1 mapping to GNOME's power
  settings)
- Non-xkb input methods (e.g. ibus engines); only xkb keyboard layouts are
  migrated
- Saved passwords/secrets (GNOME Keyring `~/.local/share/keyrings/` vs KWallet
  `~/.local/share/kwalletd/`): both implement the Secret Service D-Bus API,
  but their on-disk formats are mutually incompatible, so WiFi/browser/email
  passwords stored in one aren't readable by the other after switching
- `rpm-ostree`-layered packages outside the well-known set tracked above —
  check `rpm-ostree status` and re-layer manually with `rpm-ostree install
  <package>` if something you'd installed is missing after switching

`restore-config.sh` writes these out as a checklist to `MANUAL-STEPS.txt`
alongside each backup so nothing is silently lost.
