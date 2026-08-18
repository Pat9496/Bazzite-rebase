# Bazzite-rebase

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](Bazzite-rebase.sh)
[![ShellCheck](https://github.com/Pat9496/Bazzite-rebase/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Pat9496/Bazzite-rebase/actions/workflows/shellcheck.yml)

Hilfsskripte zum Wechsel einer [Bazzite](https://bazzite.gg)-Installation zwischen den KDE-Plasma- und GNOME-Desktopumgebungsabbildern, wobei so viel wie möglich von der vorhandenen Benutzerkonfiguration erhalten bleibt.

[English version](README.md)

## Inhaltsverzeichnis

- [Warum es das gibt](#warum-es-das-gibt)
- [Was beim Rebase tatsächlich geschieht](#was-beim-rebase-tatsächlich-geschieht)
- [Voraussetzungen](#voraussetzungen)
- [Verwendung](#verwendung)
- [Zurückrollen](#zurückrollen)
- [Beitragen](#beitragen)
- [Danksagungen](#danksagungen)
- [Lizenz](#lizenz)

## Warum es das gibt

Bazzite wird mit separaten Container-Abbildern für jede Desktopumgebung ausgeliefert (z. B. `ghcr.io/ublue-os/bazzite` für KDE Plasma gegenüber `ghcr.io/ublue-os/bazzite-gnome` für GNOME), die über `rpm-ostree rebase` ausgetauscht werden. Das [offizielle Rebase-Handbuch](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/) macht deutlich, dass das **Rebasing zwischen Desktopumgebungen nicht unterstützt wird und Probleme verursachen kann** – diese Skripte ändern diese Tatsache nicht, sie versuchen lediglich, den Übergang weniger schmerzhaft zu gestalten.

> [!WARNING]
> Das Rebasing zwischen KDE Plasma ↔ GNOME wird vom Bazzite-Projekt nicht unterstützt. Verwendung auf eigenes Risiko, auf einem System, das neu installiert oder zurückgerollt werden kann.

## Was beim Rebase tatsächlich geschieht

Auf einem ostree-basierten System wie Bazzite wird nur `/usr` vollständig ersetzt und `/etc` wird beim Rebasing dreiseitig zusammengeführt – `/home` und `/var` (wo `/var/lib/flatpak` sich befindet) bleiben unverändert. In der Praxis bedeutet dies:

- Dateien, Shell-Konfiguration, SSH-Schlüssel, Flatpak-Anwendungen und Flatpak-Daten pro Anwendung überstehen ein Rebase bereits von selbst – nichts davon muss „wiederhergestellt" werden.
- Was **nicht** automatisch übertragen wird, sind Einstellungen, die nur innerhalb eines Desktops sinnvoll sind: KDE-Plasma-Einstellungen befinden sich in KConfig-/`kwriteconfig`-Dateien unter `~/.config`, GNOME-Einstellungen befinden sich in `dconf`/`gsettings`. Kein Desktop liest das Format des anderen, daher beginnt der neue Desktop nach einem Rebase einfach mit seinen eigenen Standardwerten für alles, das noch nie konfiguriert wurde.

Diese Skripte erstellen eine Sicherung eines Snapshots der aktuellen Einstellungen zur Referenz und wenden aktiv einen kleinen, klar definierten Satz gleichwertiger Einstellungen (dunkler/heller Modus, Hintergrundbild) im nativen Konfigurationssystem des neuen Desktops erneut an. Außerdem wird ein kuratierten Satz bekannter `rpm-ostree`-geschichteter Pakete (Alacritty, chezmoi, htop, btop, Neovim, tmux, fastfetch, git und Verwandte sowie den libvirt/QEMU-Virtualisierungsstapel) verfolgt, und alle davon, die nicht auf das neue Abbild übertragen wurden, werden neu geschichtet. Unter [`config-map/README.md`](config-map/README.md) kann nachgesehen werden, was genau migriert wird und was nicht.

## Voraussetzungen

- Eine laufende Bazzite-Installation (KDE-Plasma- oder GNOME-Variante) mit verfügbarem `rpm-ostree`, `jq` und `sudo` (alle standardmäßig auf Bazzite vorhanden).
- Ausführung als normaler Benutzer, nicht als Root – die Skripte erhöhen Berechtigungen mit `sudo` intern nur für den `rpm-ostree rebase`-Schritt selbst, da die dconf/gsettings/flatpak-Inspektion in der eigenen Benutzersitzung ausgeführt werden muss.

## Verwendung

```bash
./Bazzite-rebase.sh
```

Dies erkennt, ob sich das System derzeit auf KDE Plasma oder GNOME befindet, und führt das entsprechende Skript aus (`bin/rebase-to-gnome.sh` oder `bin/rebase-to-kde.sh`). Alle Argumente werden weitergeleitet, z. B. `./Bazzite-rebase.sh --dry-run` oder `./Bazzite-rebase.sh -y`.

Beide Skripte können auch direkt aufgerufen werden, um die Richtung explizit anzugeben:

```bash
# Von KDE Plasma zu GNOME wechseln
bin/rebase-to-gnome.sh

# Von GNOME zu KDE Plasma wechseln
bin/rebase-to-kde.sh
```

Beide Skripte:

1. Das aktuelle Abbild wird erkannt (Gerätetyp, GPU-Treiber und Kanal/Tag werden alle beibehalten – nur die Desktopumgebungskomponente wird ausgetauscht). Falls das aktuelle Tag zu einem Digest-Pin wird, wird der Digest nicht auf das Abbild des anderen Desktops übertragen (es ist ein Hash des *aktuellen* Abbildinhalts), daher greift das Skript stattdessen auf das `:latest`-Tag des Abbilds zurück und warnt darüber.
2. Es wird gewarnt (best-effort, über `lspci`/DMI), falls das berechnete Zielabbild nicht dem tatsächlichen Hardware des Computers zu entsprechen scheint – z. B. wurde eine NVIDIA-GPU erkannt, aber das Ziel ist nicht eine `-nvidia`-Variante, oder umgekehrt, oder dies sieht wie ein Steam Deck aus, aber das Ziel ist nicht eine `-deck`-Variante. Dies blockiert das Rebasing niemals, da die Erkennung hier eine Heuristik ist.
3. `bin/lib/backup-config.sh` wird ausgeführt, um die aktuellen Einstellungen unter `~/.local/share/bazzite-rebase/backups/<timestamp>/` zu sichern.
4. Das genaue Zielabbild wird ausgegeben und um Bestätigung gebeten, bevor etwas getan wird (Eingabeaufforderung mit `-y`/`--yes` überspringen; nur Vorschau mit `--dry-run`).
5. `rpm-ostree rebase` wird ausgeführt (via `sudo`), um die neue Bereitstellung bereitzustellen.
6. Es wird aufgefordert, neu zu starten und danach `bin/lib/restore-config.sh` auszuführen.

Nach dem Neustart auf dem neuen Desktop:

```bash
bin/lib/restore-config.sh --to gnome   # oder --to kde
```

Dies wendet die in Schritt 2 erfassten Einstellungen erneut an, die ein bekanntes Äquivalent auf dem neuen Desktop haben, schichtet (über `sudo rpm-ostree install`) bekannte CLI-Pakete neu, die nicht automatisch übernommen wurden, und schreibt eine `MANUAL-STEPS.txt` neben der Sicherung, die auflistet, was *nicht* migriert werden konnte (Panel-/Dock-Layout, Tastaturkürzel, anwendungsspezifische Einstellungen, Standard-App-Zuordnungen, GNOME-Erweiterungen, KDE-Aktivitäten und ähnliches desktopspezifisches Setup). Falls Pakete neu geschichtet wurden, einmal mehr neu starten, um sie zu übernehmen.

## Zurückrollen

Falls etwas schiefgeht, behält `rpm-ostree` die vorherige Bereitstellung bei:

```bash
sudo rpm-ostree rollback
```

Nach dem Neustart befindet sich das System wieder auf dem vorherigen Abbild.

## Beitragen

Fehlermeldungen, Funktionsanfragen und Pull Requests sind willkommen – unter [`CONTRIBUTING.md`](CONTRIBUTING.md) finden sich Codierungsstil und wie Änderungen getestet werden. Sicherheitsprobleme sollten privat gemäß [`SECURITY.md`](SECURITY.md) gemeldet werden, anstatt als öffentliche Probleme eingereicht zu werden.

## Danksagungen

- [Bazzite](https://bazzite.gg) und das [ublue-os](https://github.com/ublue-os)-Projekt für die Abbilder, den Rebase-Mechanismus und die [Dokumentation](https://docs.bazzite.gg), auf die diese Skripte aufbauen.
- Das [KDE Plasma](https://kde.org/plasma-desktop/)-Projekt für das CLI-Tooling `kreadconfig`/`plasma-apply-colorscheme`/`plasma-apply-wallpaperimage`, das zum Lesen und Anwenden von KDE-Einstellungen verwendet wird.
- Das [GNOME](https://www.gnome.org/)-Projekt für `gsettings`/`dconf`, das zum Lesen und Anwenden von GNOME-Einstellungen verwendet wird.

## Lizenz

[MIT](LICENSE)
