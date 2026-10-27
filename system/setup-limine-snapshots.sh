#!/usr/bin/env bash
#
# Phase 2 of snapshots: Limine's boot menu lists snapshots, so a system that
# will not start can be booted as it was before the last update.
#
# Two AUR tools, the same pair Omarchy uses:
#   limine-mkinitcpio-hook  keeps kernels, initramfs and limine.conf in step
#   limine-snapper-sync     turns snapper snapshots into boot entries
#
# This script stops BEFORE any reboot. It backs up, configures, installs and
# generates, then shows what it made so it can be read before trusting it.
# Recovery, if ever needed: system/BOOT-RECOVERY.md.
#
#   1. Back up /boot, the firmware entries, mkinitcpio.conf and the cmdline
#   2. Write /etc/default/limine with this machine's kernel command line
#   3. Install both tools (built from source by yay - several minutes)
#   4. Add the overlay hook to the initramfs, and prove it builds
#   5. Generate the kernel and snapshot entries, and check them
#   6. Show the new limine.conf, the firmware entries and the boot partition
#
# Every step that could leave the machine unbootable is checked before the
# next one runs; a failure stops here with what was changed and how to undo it.

set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m!! %s\033[0m\n' "$1" >&2; exit 1; }

command -v yay >/dev/null || fail "yay is needed to build the AUR packages"
snapper -c root get-config >/dev/null 2>&1 || fail "run setup-snapshots.sh first"
findmnt -n /boot >/dev/null || fail "/boot is not mounted"

# --- 1. backup -------------------------------------------------------------

backup="$HOME/boot-backup-$(date +%Y%m%d-%H%M)"
step "1. Backing up to $backup"
mkdir -p "$backup"
sudo tar -C /boot -cpf "$backup/boot.tar" .
sudo chown "$USER:" "$backup/boot.tar"
sudo efibootmgr -v >"$backup/efibootmgr.txt"
cp /etc/mkinitcpio.conf "$backup/mkinitcpio.conf"
cat /proc/cmdline >"$backup/cmdline"
tar -tf "$backup/boot.tar" | grep -q 'vmlinuz-linux' || fail "the backup has no kernel in it - stopping"
ls -la "$backup"

# --- 2. /etc/default/limine ------------------------------------------------

# The command line this machine booted with, as it is: LUKS by UUID, root on
# the mapper device, the @ subvolume. limine-snapper-sync rewrites
# rootflags=subvol= for each snapshot entry, so it must be here as written.
cmdline="$(cat /proc/cmdline)"
case "$cmdline" in
	*rootflags=subvol=@*|*rootflags=subvol=/@*) ;;
	*) fail "the running cmdline has no rootflags=subvol=@: $cmdline" ;;
esac

step "2. Writing /etc/default/limine"
if [ -f /etc/default/limine ]; then
	sudo cp /etc/default/limine "$backup/default-limine.before"
fi
sudo tee /etc/default/limine >/dev/null <<EOF
# Read by limine-entry-tool (limine-mkinitcpio-hook) and limine-snapper-sync.
# Written by groma/system/setup-limine-snapshots.sh.

ESP_PATH="/boot"

KERNEL_CMDLINE[default]+="$cmdline"
EOF
cat /etc/default/limine

# --- 3. install -------------------------------------------------------------

step "3. Installing limine-mkinitcpio-hook and limine-snapper-sync (AUR)"
echo "Both are built from source with GraalVM: a large download and a long compile."
yay -S --needed limine-mkinitcpio-hook limine-snapper-sync

# --- 4. the overlay hook -----------------------------------------------------

# Booting a snapshot mounts it read-only; the overlay hook puts a throwaway
# writable layer over it so the system can start normally. It comes in two
# kinds, and the wrong one stops mkinitcpio cold: sd-btrfs-overlayfs for an
# initramfs built on the systemd hook (the book's chapter 1), btrfs-overlayfs
# for one built on base and udev (archinstall's).
if grep -qE '^HOOKS=\(.*\bsystemd\b' /etc/mkinitcpio.conf; then
	hook=sd-btrfs-overlayfs; other=btrfs-overlayfs
else
	hook=btrfs-overlayfs; other=sd-btrfs-overlayfs
fi
step "4. Adding $hook to the initramfs hooks"
# The other kind goes, if an earlier run put it there.
sudo sed -i -E "/^HOOKS=/ s/ $other\b//" /etc/mkinitcpio.conf
if grep -qE "^HOOKS=.* $hook\b" /etc/mkinitcpio.conf; then
	echo "already there"
else
	grep -q '^HOOKS=(.* filesystems' /etc/mkinitcpio.conf || fail "no 'filesystems' in HOOKS to put it after"
	sudo sed -i -E "/^HOOKS=/ s/ filesystems\b/ filesystems $hook/" /etc/mkinitcpio.conf
fi
grep '^HOOKS=' /etc/mkinitcpio.conf

# Build one initramfs into a scratch file before anything on /boot is
# regenerated. limine-update reports a failed build as "skipping" and carries
# on, so this is where a bad hook line has to be caught.
kver="$(basename "$(dirname "$(ls /usr/lib/modules/*/vmlinuz | sort -V | tail -1)")")"
scratch="$(mktemp -d)"
if ! sudo mkinitcpio -k "$kver" -g "$scratch/test.img" >"$scratch/log" 2>&1; then
	sudo cp "$backup/mkinitcpio.conf" /etc/mkinitcpio.conf
	cat "$scratch/log"
	fail "a test initramfs did not build with $hook - mkinitcpio.conf is put back, /boot is untouched"
fi
sudo rm -rf "$scratch"
echo "a test initramfs for $kver builds with it"

# --- 5. generate ---------------------------------------------------------------

step "5. Generating kernel entries (limine-update) and snapshot entries"
sudo limine-update

# Check what it wrote before anything relies on it: the OS entry
# limine-snapper-sync hangs the snapshots under, and every kernel and
# initramfs the config names, on disk. Kernels are "path:" (older configs say
# "kernel_path:"), and each path may end in "#" and its checksum.
os_name="$(. /etc/os-release && echo "$NAME")"
sudo grep -q "^/+\?$os_name\$" /boot/limine.conf \
	|| fail "/boot/limine.conf has no '$os_name' entry. Do not reboot; see $backup"
missing=0
while read -r path; do
	if ! sudo test -f "/boot/$path"; then
		echo "missing: /boot/$path"
		missing=1
	fi
done < <(sudo sed -nE 's#^[[:space:]]*(path|kernel_path|module_path):[[:space:]]*boot\(\):/([^\#]*).*#\2#p' /boot/limine.conf | sort -u)
[ "$missing" = 0 ] || fail "/boot/limine.conf points at files that are not there. Do not reboot; see $backup"
echo "limine.conf has '$os_name', and every kernel and initramfs it names exists"

sudo limine-snapper-sync
sudo systemctl enable --now limine-snapper-sync.service

# Limine reads the first limine.conf it finds, and one beside its own
# executable comes before /boot/limine.conf - archinstall leaves one in
# EFI/BOOT. Any other is moved into the backup, now that the new one is
# known to be good.
while read -r other_conf; do
	mkdir -p "$backup/other-limine-conf"
	sudo mv "$other_conf" "$backup/other-limine-conf/$(echo "${other_conf#/boot/}" | tr / _)"
	echo "moved aside: $other_conf (kept in $backup/other-limine-conf)"
done < <(sudo find /boot -name limine.conf -not -path /boot/limine.conf -not -path '*/limine_history/*')

# --- 6. show -------------------------------------------------------------------

step "6. What was made - read this before rebooting"
echo "--- /boot/limine.conf"
sudo cat /boot/limine.conf
echo
echo "--- firmware entries"
sudo efibootmgr
echo
echo "--- /boot"
sudo find /boot -maxdepth 3 -not -path '*/limine_history/*' | sort
echo
echo "--- the overlay hook is in the new initramfs?"
for img in $(sudo find /boot -name 'initramfs*' -newer "$backup/boot.tar"); do
	printf '%s: ' "$img"
	sudo lsinitcpio "$img" 2>/dev/null | grep -q 'btrfs-overlayfs' && echo yes || echo NO
done

cat <<EOF

Stopped before rebooting, as planned. Backup: $backup
Paste the output above back for checking. Do not reboot yet.

After it has been read: reboot once normally (BootCurrent should be the new
"Limine" entry), then once into a snapshot from the menu (findmnt / says
overlay). Only then retire a previous loader, if there was one: its firmware
entry (sudo efibootmgr -b <number> -B, the number from the list above), its
folder under /boot/EFI, and the kernel and initramfs it booted, if
limine.conf no longer names them.
EOF
