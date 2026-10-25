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
#   3. Add sd-btrfs-overlayfs to the initramfs, after "filesystems"
#   4. Install both tools (built from source by yay - several minutes)
#   5. Generate the kernel entries and the snapshot entries
#   6. Show the new limine.conf, the firmware entries and the boot partition

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
	*rootflags=subvol=@*) ;;
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

# --- 3. the overlay hook -----------------------------------------------------

# Booting a snapshot mounts it read-only; sd-btrfs-overlayfs puts a throwaway
# writable layer over it so the system can start normally. The systemd
# variant, because this initramfs uses the systemd hooks.
step "3. Adding sd-btrfs-overlayfs to the initramfs hooks"
if grep -q '^HOOKS=.*sd-btrfs-overlayfs' /etc/mkinitcpio.conf; then
	echo "already there"
else
	grep -q '^HOOKS=(.* filesystems ' /etc/mkinitcpio.conf || fail "no 'filesystems' in HOOKS to put it after"
	sudo sed -i '/^HOOKS=/ s/ filesystems / filesystems sd-btrfs-overlayfs /' /etc/mkinitcpio.conf
fi
grep '^HOOKS=' /etc/mkinitcpio.conf

# --- 4. install -------------------------------------------------------------

step "4. Installing limine-mkinitcpio-hook and limine-snapper-sync (AUR)"
echo "Both are built from source with GraalVM: a large download and a long compile."
yay -S --needed limine-mkinitcpio-hook limine-snapper-sync

# --- 5. generate ---------------------------------------------------------------

step "5. Generating kernel entries (limine-update) and snapshot entries"
sudo limine-update
sudo limine-snapper-sync
sudo systemctl enable --now limine-snapper-sync.service

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
overlay). Only then retire a previous loader, if there was one - on the
machine this was written on:
  sudo efibootmgr -b 0005 -B
  sudo rm -r /boot/EFI/arch-limine
  sudo rm /boot/vmlinuz-linux /boot/initramfs-linux.img
EOF
