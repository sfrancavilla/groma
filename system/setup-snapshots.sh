#!/usr/bin/env bash
#
# Phase 1 of snapshots: snapper for the root subvolume, and snap-pac so that
# every pacman transaction is bracketed by a pre and a post snapshot. Nothing
# here touches the boot loader.
#
# Snapshots live in an @snapshots subvolume mounted at /.snapshots, made here
# if the disk does not have one yet. snapper insists on creating its own .snapshots subvolume inside @ when a config is
# made, so the usual Arch dance applies: unmount ours, let snapper create its
# nested one, delete that, and mount ours back in its place. Snapshots then
# live in @snapshots - a sibling of @, not inside it - which is what lets a
# rollback replace @ without deleting the snapshots it is rolling back to.
#
# Safe to re-run: every step checks before it acts.

set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

# / must be a Btrfs subvolume called @ - the book's chapter 1 layout, and
# archinstall's Btrfs default. Anything else is skipped, not guessed at.
if [ "$(findmnt -n -o FSTYPE /)" != btrfs ]; then
	echo "Skipping system snapshots: / is not Btrfs."
	exit 0
fi
if ! findmnt -n -o OPTIONS / | grep -qE 'subvol=/?@(,|$)'; then
	echo "Skipping system snapshots: / is not the @ subvolume."
	exit 0
fi

# Snapshots go in an @snapshots subvolume beside @, mounted at /.snapshots.
# Chapter 1 makes it by hand; archinstall does not make it at all. Where it is
# missing it is made here, the way chapter 1 does: create it at the top of the
# filesystem, then mount it with the same options as /, by an fstab line.
if ! grep -qE '[[:space:]]/\.snapshots[[:space:]]' /etc/fstab; then
	if [ -e /.snapshots ] && ! sudo rmdir /.snapshots 2>/dev/null; then
		echo "Skipping system snapshots: /.snapshots already exists and is not an empty folder."
		exit 0
	fi

	step "Creating an @snapshots subvolume beside @"
	device="$(findmnt -n -o SOURCE / | sed 's/\[.*//')"
	top="$(mktemp -d)"
	sudo mount -o subvolid=5 "$device" "$top"
	[ -d "$top/@snapshots" ] || sudo btrfs subvolume create "$top/@snapshots"
	sudo umount "$top"
	rmdir "$top"

	# The / line with its mount point and subvolume swapped. subvolid goes:
	# it names @'s id, and would contradict the new subvol=.
	line="$(awk '$2 == "/" && $3 == "btrfs" {
		n = split($4, opt, ","); out = ""
		for (i = 1; i <= n; i++) {
			if (opt[i] ~ /^subvolid=/) continue
			if (opt[i] ~ /^subvol=/) opt[i] = "subvol=/@snapshots"
			out = out (out == "" ? "" : ",") opt[i]
		}
		$2 = "/.snapshots"; $4 = out
		print; exit
	}' /etc/fstab)"
	[ -n "$line" ] || { echo "Skipping system snapshots: no Btrfs line for / in /etc/fstab."; exit 0; }

	sudo cp /etc/fstab /etc/fstab.before-groma
	printf '\n# @snapshots, added by Groma'"'"'s setup-snapshots.sh\n%s\n' "$line" | sudo tee -a /etc/fstab >/dev/null
	sudo systemctl daemon-reload
	sudo mkdir -p /.snapshots
	sudo mount /.snapshots
	echo "  Added to /etc/fstab (the old one is /etc/fstab.before-groma):"
	echo "  $line"
fi

step "Installing snapper and snap-pac (official repositories)"
sudo pacman -S --needed snapper snap-pac

fresh=no
if ! sudo snapper -c root get-config >/dev/null 2>&1; then
	fresh=yes
	step "Creating the snapper config for /, keeping @snapshots as the store"
	sudo umount /.snapshots
	sudo rmdir /.snapshots
	sudo snapper -c root create-config /
	# snapper has just made /.snapshots a nested subvolume inside @. Replace
	# it with our own @snapshots, as the fstab already describes.
	sudo btrfs subvolume delete /.snapshots
	sudo mkdir /.snapshots
	sudo mount /.snapshots
	sudo chmod 750 /.snapshots
else
	step "snapper config for / already exists - leaving it"
fi

step "Setting retention: no timeline, the last 10 numbered, 5 important"
# Timeline snapshots are off: snap-pac's pre/post pairs around every update
# are the ones worth having, and hourly copies of an unchanged system are not.
# ALLOW_USERS lets this user list and create snapshots through snapperd, so
# Groma can show them without a password.
sudo snapper -c root set-config \
	TIMELINE_CREATE=no \
	NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 \
	ALLOW_USERS="$USER" SYNC_ACL=yes

step "Enabling the cleanup timer"
sudo systemctl enable --now snapper-cleanup.timer

if [ "$fresh" = yes ]; then
	step "Taking the first snapshot, as $USER"
	snapper -c root create --description "Groma: first snapshot" --cleanup-algorithm number
fi

step "What is there now"
snapper -c root list
findmnt -n /.snapshots -o TARGET,SOURCE
