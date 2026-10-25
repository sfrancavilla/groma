#!/usr/bin/env bash
#
# Phase 1 of snapshots: snapper for the root subvolume, and snap-pac so that
# every pacman transaction is bracketed by a pre and a post snapshot. Nothing
# here touches the boot loader.
#
# The disk already has an @snapshots subvolume mounted at /.snapshots. snapper
# insists on creating its own .snapshots subvolume inside @ when a config is
# made, so the usual Arch dance applies: unmount ours, let snapper create its
# nested one, delete that, and mount ours back in its place. Snapshots then
# live in @snapshots - a sibling of @, not inside it - which is what lets a
# rollback replace @ without deleting the snapshots it is rolling back to.
#
# Safe to re-run: every step checks before it acts.

set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

# This layout - / on a Btrfs subvolume @, with @snapshots mounted beside it at
# /.snapshots - is the one the book's chapter 1 creates, and the one
# archinstall's Btrfs default creates. Anything else is skipped, not guessed at.
if [ "$(findmnt -n -o FSTYPE /)" != btrfs ]; then
	echo "Skipping system snapshots: / is not Btrfs."
	exit 0
fi
if ! findmnt -n -o OPTIONS / | grep -qE 'subvol=/?@(,|$)'; then
	echo "Skipping system snapshots: / is not the @ subvolume."
	exit 0
fi
if ! grep -qE '[[:space:]]/\.snapshots[[:space:]]' /etc/fstab; then
	echo "Skipping system snapshots: there is no /.snapshots line in /etc/fstab."
	echo "Create an @snapshots subvolume and mount it there first (book, chapter 1)."
	exit 0
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
