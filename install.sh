#!/usr/bin/env bash
#
# Set Groma up on an Arch machine: packages, then the symlinks that put the
# configuration where Hyprland and Quickshell look for it.
#
# Safe to re-run. pacman --needed skips what is already installed, and every
# link is replaced rather than stacked.

set -euo pipefail

GROMA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# What the shell actually calls. Anything here is reached from QML or from a
# keybinding; nothing is included on the grounds that it is probably useful.
PACKAGES=(
	quickshell          # the shell itself
	hyprland            # the compositor, which starts it
	qt6-declarative     # QML
	qt6-svg             # so Image can render themed icons

	pipewire            # audio, read and written by the volume tile
	pipewire-pulse
	wireplumber         # provides wpctl
	upower              # battery state
	networkmanager      # the network tile, and nmcli behind it
	bluez               # bluetooth
	bluez-utils
	polkit              # the authentication agent talks to polkitd

	brightnessctl       # the idle chain dims with this, the OSD reads it
	playerctl           # media keys, and pausing when an earbud comes out
	python              # integrations/nothingear only; harmless without the buds
	curl                # the public-address lookup in the network tile

	xdg-desktop-portal  # screen sharing, file pickers
	xdg-desktop-portal-hyprland
	xdg-desktop-portal-gtk

	foot                # the terminal the keybinding opens, and "run in terminal"
	wl-clipboard        # wl-copy and wl-paste: copying from the launcher, and feeding cliphist
	cliphist            # clipboard history, kept by the shell for the launcher's ":" mode
	libqalculate        # qalc: units and conversions in the launcher; arithmetic works without it
	fd                  # file search in the launcher, under the applications and behind "/"
	udisks2             # mounting and ejecting drives from the Files sidebar, through polkit
	pacman-contrib      # checkupdates, which Software uses to see official updates without a half-synced database
	libnotify           # notify-send, for testing the notification daemon
	desktop-file-utils  # update-desktop-database, after the Files entry is linked in

	# Screenshots. hyprshot is a script over grim and slurp, so this is also
	# how the shell gets compared against the design it is built from - grim
	# comes in as a dependency and takes a full frame on its own.
	hyprshot
)

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

say "Installing packages"
sudo pacman -S --needed "${PACKAGES[@]}"

say "Linking the shell into ~/.config/quickshell/groma"
mkdir -p "$HOME/.config/quickshell"
ln -sfn "$GROMA/shell" "$HOME/.config/quickshell/groma"

say "Linking the compositor config into ~/.config/hypr"
mkdir -p "$HOME/.config/hypr"
ln -sfn "$GROMA/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"

say "Registering Files as the folder handler"
# A desktop entry for the shell's own file manager, so xdg-open on a folder -
# from a browser's downloads, from the launcher - lands in it.
mkdir -p "$HOME/.local/share/applications"
ln -sfn "$GROMA/system/groma-files.desktop" "$HOME/.local/share/applications/groma-files.desktop"
ln -sfn "$GROMA/system/groma-software.desktop" "$HOME/.local/share/applications/groma-software.desktop"
ln -sfn "$GROMA/system/groma-snapshots.desktop" "$HOME/.local/share/applications/groma-snapshots.desktop"
update-desktop-database "$HOME/.local/share/applications"
xdg-mime default groma-files.desktop inode/directory

# An editor for text, only where one is installed. Files asks "Open with…"
# for anything nothing claims, so this is a convenience, not a requirement.
if [ -f /usr/share/applications/code.desktop ]; then
	say "Making VS Code the editor for text"
	xdg-mime default code.desktop text/plain text/markdown
fi

say "Setting up snapshots"
# snapper for /, and snap-pac around every pacman transaction. Its own script,
# because it rearranges a mounted subvolume and is worth reading on its own.
"$GROMA/system/setup-snapshots.sh"
"$GROMA/system/setup-home-snapshots.sh"

say "Installing the lock-before-sleep unit"
# Symlinked rather than copied, so editing it in the repo is enough. The unit
# hardcodes a user, uid and display - see the comments in it for another
# machine.
sudo ln -sfn "$GROMA/system/groma-lock-on-sleep.service" \
	/etc/systemd/system/groma-lock-on-sleep.service
sudo systemctl daemon-reload
sudo systemctl enable groma-lock-on-sleep.service

say "Done"
cat <<'NOTE'
Log out and back in, or run `qs -c groma` to start the shell now.

Snapshots in the boot menu need two AUR packages, so they are a separate step
once yay exists: system/setup-limine-snapshots.sh (it stops before any reboot
and says how to test), then system/theme-limine.sh for Groma's colours.
Recovery: system/BOOT-RECOVERY.md.

Two things this does not do, deliberately:

  - `/etc/security/faillock.conf` sets unlock_time = 120 on the machine this
    was developed on. The default is 600, which means ten minutes locked out
    of your own session after three mistyped passwords.

  - Nothing here sets a wallpaper. Groma draws its own; point
    Wallpaper.source at a file if you would rather have one.
NOTE
