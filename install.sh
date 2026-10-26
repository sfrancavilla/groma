#!/usr/bin/env bash
#
# Set Groma up on an Arch machine: packages, the drivers this hardware needs,
# the links that put the configuration where Hyprland and Quickshell look for
# it, and the system pieces - snapshots, locking before sleep, starting the
# desktop at login.
#
# Not tied to one machine. Hardware is detected, not listed; steps that need a
# particular disk layout or boot loader check for it and say why they skip.
# Anything only one machine wants goes in ~/.config/hypr/machine.lua, outside
# this repository.
#
# Starts from a working Arch base install with a user in the wheel group
# (the book's chapter 1, or archinstall). Safe to re-run: pacman --needed skips
# what is installed, links are replaced, and every system step checks first.

set -euo pipefail

GROMA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
note() { printf '  %s\n' "$1"; }

[ "$(id -u)" -ne 0 ] || { echo "Run this as your user, not root - it asks for sudo when it needs it."; exit 1; }

# --- packages --------------------------------------------------------------

# What the shell actually calls. Anything here is reached from QML, from a
# keybinding or from one of the scripts in system/; nothing is included on the
# grounds that it is probably useful.
PACKAGES=(
	quickshell          # the shell itself
	hyprland            # the compositor, which starts it
	qt6-declarative     # QML
	qt6-svg             # so Image can render themed icons

	pipewire            # audio, read and written by the volume tile
	pipewire-pulse
	wireplumber         # provides wpctl
	rtkit               # realtime priority for PipeWire, so audio does not crackle under load
	upower              # battery state; without a battery the tile says so
	networkmanager      # the network tile, and nmcli behind it
	bluez               # bluetooth; without an adapter the tile has nothing to show
	bluez-utils
	polkit              # the authentication agent talks to polkitd

	brightnessctl       # the idle chain dims with this, the OSD reads it
	playerctl           # media keys, and pausing when an earbud comes out
	python              # the Files, Software and earbud helpers
	curl                # the public-address lookup in the network tile

	xdg-desktop-portal  # screen sharing, file pickers
	xdg-desktop-portal-hyprland
	xdg-desktop-portal-gtk
	xdg-utils           # xdg-open and xdg-mime: opening files, default applications
	glib2               # gio launch, behind Files' "Open with"

	foot                # the terminal the keybinding opens, and "run in terminal"
	wl-clipboard        # wl-copy and wl-paste: copying from the launcher, and feeding cliphist
	cliphist            # clipboard history, kept by the shell for the launcher's ":" mode
	libqalculate        # qalc: units and conversions in the launcher; arithmetic works without it
	fd                  # file search in the launcher, under the applications and behind "/"
	udisks2             # mounting and ejecting drives from the Files sidebar, through polkit
	pacman-contrib      # checkupdates, which Groma Store uses to see updates without a half-synced database
	libnotify           # notify-send, for testing the notification daemon
	desktop-file-utils  # update-desktop-database, after the desktop entries are linked in
	papirus-icon-theme  # application icons, one consistent set (QS_ICON_THEME in hyprland.lua)
	archlinux-appstream-data  # icons for applications Groma Store shows before they are installed

	git                 # cloning this repository, and building AUR packages
	base-devel          # makepkg, for the AUR helper Groma Store uses

	# Screenshots. hyprshot is a script over grim and slurp, so this is also
	# how the shell gets compared against the design it is built from - grim
	# comes in as a dependency and takes a full frame on its own.
	hyprshot
)

# --- hardware: detected, not listed ------------------------------------------

# CPU microcode, by vendor. The base install usually has it already.
case "$(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $3}')" in
	AuthenticAMD) PACKAGES+=(amd-ucode) ;;
	GenuineIntel) PACKAGES+=(intel-ucode) ;;
esac

# Graphics: the Vulkan driver for each display device's vendor, read from sysfs
# so that nothing has to be installed to find out. Mesa's OpenGL comes with
# Hyprland either way.
gpu_note=""
for dev in /sys/bus/pci/devices/*; do
	case "$(cat "$dev/class")" in 0x03*) ;; *) continue ;; esac
	case "$(cat "$dev/vendor")" in
		0x1002) PACKAGES+=(vulkan-radeon) ;;
		0x8086) PACKAGES+=(vulkan-intel intel-media-driver) ;;
		0x10de) gpu_note="NVIDIA graphics detected. Groma has not been tested on NVIDIA; Hyprland needs the
  proprietary driver and settings described at https://wiki.hypr.land/Nvidia/" ;;
		*) ;;  # a virtual machine's display: Mesa covers it
	esac
done

say "Installing packages"
sudo pacman -S --needed "${PACKAGES[@]}"

# --- the configuration ---------------------------------------------------------

say "Linking the shell into ~/.config/quickshell/groma"
mkdir -p "$HOME/.config/quickshell"
ln -sfn "$GROMA/shell" "$HOME/.config/quickshell/groma"

say "Linking the compositor config into ~/.config/hypr"
mkdir -p "$HOME/.config/hypr"
ln -sfn "$GROMA/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"

say "Registering Groma's applications"
# Desktop entries for the shell's own windows, so the launcher lists them and
# xdg-open on a folder - from a browser's downloads, from anywhere - lands in
# Files.
mkdir -p "$HOME/.local/share/applications"
for entry in groma-files groma-software groma-snapshots; do
	ln -sfn "$GROMA/system/$entry.desktop" "$HOME/.local/share/applications/$entry.desktop"
done
# Their icons, drawn for Groma (system/icons), in the user's hicolor theme so
# every icon theme falls back to them.
mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"
for icon in "$GROMA"/system/icons/*.svg; do
	ln -sfn "$icon" "$HOME/.local/share/icons/hicolor/scalable/apps/$(basename "$icon")"
done
update-desktop-database "$HOME/.local/share/applications"
xdg-mime default groma-files.desktop inode/directory

# GTK applications - file pickers, pavucontrol - take their icons from here;
# the shell takes them from QS_ICON_THEME in the compositor config.
gsettings set org.gnome.desktop.interface icon-theme Papirus 2>/dev/null || true

# An editor for text, only where one is installed. Files asks "Open with…"
# for anything nothing claims, so this is a convenience, not a requirement.
if [ -f /usr/share/applications/code.desktop ]; then
	xdg-mime default code.desktop text/plain text/markdown
fi

# --- starting the desktop -------------------------------------------------------

say "Starting Hyprland after logging in on the first console"
# Log in on tty1 and the desktop starts; leaving Hyprland returns to the login
# prompt. The other consoles stay plain, which is the way in if the desktop
# ever will not start: Ctrl+Alt+F2.
profile="$HOME/.bash_profile"
touch "$profile"
if ! grep -q 'groma: start Hyprland' "$profile"; then
	cat >>"$profile" <<'EOF'

# groma: start Hyprland on the first console after login (install.sh)
if [ -z "$WAYLAND_DISPLAY" ] && [ "${XDG_VTNR:-}" = 1 ] && command -v start-hyprland >/dev/null; then
	exec start-hyprland
fi
EOF
	note "Added to $profile."
else
	note "Already in $profile."
fi

# --- the system ----------------------------------------------------------------

say "Locking every session before sleep"
# Copied, not linked: the unit runs as root, so neither it nor the script it
# runs may be a file the user can edit. Re-run this to pick up changes.
sudo install -Dm755 "$GROMA/system/groma-lock-sessions" /usr/local/lib/groma/groma-lock-sessions
sudo rm -f /etc/systemd/system/groma-lock-on-sleep.service
sudo install -Dm644 "$GROMA/system/groma-lock-on-sleep.service" /etc/systemd/system/groma-lock-on-sleep.service
sudo systemctl daemon-reload
sudo systemctl enable groma-lock-on-sleep.service

say "Shortening the lockout after mistyped passwords"
# pam_faillock locks an account for ten minutes after three wrong passwords -
# at the lock screen that is ten minutes outside your own session. Two is
# enough to slow guessing down. faillock.conf has no drop-in directory, so the
# one setting is set in place.
if sudo grep -qE '^unlock_time[[:space:]]*=' /etc/security/faillock.conf; then
	sudo sed -i -E 's/^unlock_time[[:space:]]*=.*/unlock_time = 120/' /etc/security/faillock.conf
else
	echo 'unlock_time = 120' | sudo tee -a /etc/security/faillock.conf >/dev/null
fi

say "An AUR helper, for Groma Store and the boot menu"
if ! command -v yay >/dev/null && ! command -v paru >/dev/null; then
	build="$(mktemp -d)"
	git clone https://aur.archlinux.org/yay-bin.git "$build/yay-bin"
	(cd "$build/yay-bin" && makepkg -si --noconfirm)
	rm -rf "$build"
else
	note "Already here."
fi

say "Snapshots of the system and of /home"
# Each script checks the disk layout first and says so if it skips.
"$GROMA/system/setup-snapshots.sh"
"$GROMA/system/setup-home-snapshots.sh"

# --- what is left ----------------------------------------------------------------

say "Done"
cat <<'NOTE'
Log out and log in again on the first console, and the desktop starts.
To start the shell inside a running Hyprland instead: qs -c groma
NOTE

if pacman -Q limine >/dev/null 2>&1 && command -v snapper >/dev/null && sudo snapper -c root get-config >/dev/null 2>&1; then
	cat <<'NOTE'

This machine boots with Limine and has snapshots, so the boot menu can list
them - a separate step, because it changes the boot loader and stops before
rebooting for you to check: system/setup-limine-snapshots.sh, then
system/theme-limine.sh for Groma's colours. Read system/BOOT-RECOVERY.md
first.
NOTE
fi

if [ -n "$gpu_note" ]; then
	printf '\n%s\n' "$gpu_note"
fi

cat <<'NOTE'

Nothing here sets a wallpaper. Groma draws its own; point Wallpaper.source at
a file if you would rather have one. Anything only this machine wants - a
monitor layout, a keybind - goes in ~/.config/hypr/machine.lua, outside the
repository (see hypr/machine.lua.example).
NOTE
