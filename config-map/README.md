# KDE Plasma ↔ GNOME setting equivalents

KDE Plasma and GNOME store almost nothing in a compatible format, so this is
a short, explicit list rather than a generic mapping engine. `restore-config.sh`
implements exactly these translations in code — nothing more.

## Actively migrated

| Concept        | KDE Plasma (read/write)                                                                 | GNOME (read/write)                                                          |
|-----------------|-------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| Dark/light mode | `kreadconfig6`/`kreadconfig5` (`kdeglobals`, group `General`, key `ColorScheme`); applied with `plasma-apply-colorscheme` | `gsettings get/set org.gnome.desktop.interface color-scheme` (`prefer-dark`/`default`) |
| Wallpaper image | Plasma per-monitor wallpaper config (read via the current `plasma-org.kde.plasma.desktop-appletsrc`); applied with `plasma-apply-wallpaperimage` | `gsettings get/set org.gnome.desktop.background picture-uri` (and `picture-uri-dark`) |

Both are best-effort: if the value can't be read on the source desktop, the
script logs a warning and skips it rather than failing the whole run.

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

`restore-config.sh` writes these out as a checklist to `MANUAL-STEPS.txt`
alongside each backup so nothing is silently lost.
