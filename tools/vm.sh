#!/usr/bin/env bash
#
# A throwaway virtual machine for installing Arch and Groma from nothing -
# the test that install.sh is not quietly relying on this laptop.
#
#   tools/vm.sh create    make the disk and firmware store, fetch and check the ISO
#   tools/vm.sh install   boot it with the Arch ISO in the drive
#   tools/vm.sh run       boot what is installed on the disk
#   tools/vm.sh destroy   delete the machine, ISO and all
#
# QEMU with KVM, booting UEFI firmware (OVMF), because that is how real
# machines boot and what Limine and the snapshot entries are written for. A
# machine left on QEMU's default BIOS would be testing some other computer.
#
# Inside the window, Ctrl+Alt+G lets go of the mouse.

set -euo pipefail

VMS="$HOME/vms"
VM="$VMS/groma-test"
ISO="$VM/archlinux-x86_64.iso"
# Arch's own mirror, which redirects to a nearby one.
MIRROR="https://geo.mirror.pkgbuild.com/iso/latest"
FIRMWARE=/usr/share/edk2/x64

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

create() {
	# Its own subvolume, so /home's hourly snapshots leave it out: a nested
	# subvolume is not part of its parent's snapshots, and a VM disk that
	# rewrites gigabytes would otherwise be kept in every one. No
	# copy-on-write (+C) either - Btrfs does it badly under a disk image's
	# small random writes. Set on the empty directory, so everything created
	# inside inherits it.
	if [ ! -d "$VMS" ]; then
		say "Making $VMS"
		if [ "$(stat -f -c %T "$HOME")" = btrfs ]; then
			btrfs subvolume create "$VMS"
			chattr +C "$VMS"
		else
			mkdir -p "$VMS"
		fi
	fi
	mkdir -p "$VM"

	# 40 GB is what the guest sees; the file holds only what it writes.
	if [ ! -f "$VM/disk.qcow2" ]; then
		say "Creating the disk"
		qemu-img create -f qcow2 "$VM/disk.qcow2" 40G
	fi

	# The firmware's settings - boot entries above all - live in their own
	# writable file, per machine. The firmware code itself is shared and read-only.
	[ -f "$VM/vars.fd" ] || cp "$FIRMWARE/OVMF_VARS.4m.fd" "$VM/vars.fd"

	if [ ! -f "$ISO" ]; then
		say "Fetching the Arch ISO"
		curl -fL --progress-bar -o "$ISO" "$MIRROR/archlinux-x86_64.iso"
		curl -fsL -o "$ISO.sig" "$MIRROR/archlinux-x86_64.iso.sig"
		# Signed by an Arch release engineer whose key is in archlinux-keyring,
		# so pacman's keyring can vouch for it. An ISO that does not check out
		# is removed rather than left to boot.
		say "Checking its signature"
		if ! pacman-key -v "$ISO.sig"; then
			rm -f "$ISO" "$ISO.sig"
			echo "The ISO's signature did not verify; it has been deleted."
			exit 1
		fi
	fi

	say "Ready: tools/vm.sh install"
}

boot() {
	[ -f "$VM/disk.qcow2" ] || { echo "No machine yet: tools/vm.sh create"; exit 1; }

	# 4 cores and 6 GB: enough for Hyprland and a package build, a fraction of
	# this machine. virtio-vga-gl hands the guest a GPU that draws through this
	# machine's OpenGL, which Hyprland needs - without it there is no desktop
	# to test. The tablet makes the pointer follow the host's exactly.
	qemu-system-x86_64 \
		-name "Groma test" \
		-enable-kvm -machine q35 -cpu host -smp 4 -m 6G \
		-drive if=pflash,format=raw,readonly=on,file="$FIRMWARE/OVMF_CODE.4m.fd" \
		-drive if=pflash,format=raw,file="$VM/vars.fd" \
		-drive file="$VM/disk.qcow2",if=virtio,format=qcow2 \
		-nic user,model=virtio-net-pci \
		-device virtio-vga-gl -display gtk,gl=on \
		-audiodev pipewire,id=sound -device intel-hda -device hda-duplex,audiodev=sound \
		-device qemu-xhci -device usb-tablet \
		"$@"
}

case "${1:-}" in
	create) create ;;
	# An empty disk has nothing to boot, so the firmware falls through to the
	# ISO; once Arch is installed, the disk's own boot entry comes first.
	install)
		[ -f "$ISO" ] || { echo "No ISO yet: tools/vm.sh create"; exit 1; }
		boot -drive file="$ISO",media=cdrom,readonly=on
		;;
	run) boot ;;
	destroy)
		read -rp "Delete $VM and everything in it? [y/N] " answer
		[ "$answer" = y ] && rm -rf "$VM" && echo "Deleted."
		;;
	*)
		sed -n '6,9p' "$0" | sed 's/^# \{0,1\}//'
		exit 1
		;;
esac
