#!/usr/bin/env bash
#
# Snapshots of /home: the work files, not the system.
#
# Root snapshots protect against a bad update; these protect against deleting
# or overwriting a file by mistake. They are timeline snapshots - hourly for a
# day, daily for a week, weekly for a month - because a mistake with a file has
# nothing to do with pacman. Btrfs snapshots are copy-on-write, so they cost
# only what changes between them.
#
# limine-snapper-sync reads only the "root" config, so none of these appear in
# the boot menu, which is right: /home is not something to boot.
#
# The snapshots live in /home/.snapshots, a subvolume nested in @home. That is
# the standard layout for a non-root config; @home is never rolled back as a
# whole, so the arrangement root needed does not apply.

set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

if [ "$(findmnt -n -o FSTYPE --target /home)" != btrfs ] || ! findmnt -n /home >/dev/null; then
	echo "Skipping home snapshots: /home is not its own Btrfs subvolume."
	exit 0
fi

fresh=no
if ! sudo snapper -c home get-config >/dev/null 2>&1; then
	fresh=yes
	step "Creating the snapper config for /home"
	sudo snapper -c home create-config /home
else
	step "snapper config for /home already exists - leaving it"
fi

step "Setting retention: 24 hourly, 7 daily, 4 weekly; none monthly or yearly"
sudo snapper -c home set-config \
	TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
	TIMELINE_MIN_AGE=3600 \
	TIMELINE_LIMIT_HOURLY=24 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=4 \
	TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_QUARTERLY=0 TIMELINE_LIMIT_YEARLY=0 \
	NUMBER_CLEANUP=yes NUMBER_LIMIT=10 \
	ALLOW_USERS="$USER" SYNC_ACL=yes

step "Enabling the timeline and cleanup timers"
# The timeline timer creates snapshots only for configs with
# TIMELINE_CREATE=yes; root keeps it off.
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

# A nested subvolume is not part of its parent's snapshots, so ~/.cache as
# its own subvolume keeps browser caches and AUR build trees - most of what
# changes in /home every hour - out of every snapshot. Done as this user, by
# reflink copy and swap: instant, and no extra space.
if [ "$(stat -c %i "$HOME/.cache" 2>/dev/null)" != 256 ]; then
	step "Making ~/.cache its own subvolume, so snapshots leave it out"
	mkdir -p "$HOME/.cache"
	btrfs subvolume create "$HOME/.cache.new" >/dev/null
	cp -a --reflink=always "$HOME/.cache/." "$HOME/.cache.new/"
	mv "$HOME/.cache" "$HOME/.cache.old"
	mv "$HOME/.cache.new" "$HOME/.cache"
	rm -rf "$HOME/.cache.old"
else
	step "~/.cache is already its own subvolume"
fi

if [ "$fresh" = yes ]; then
	step "Taking the first /home snapshot, as $USER"
	snapper -c home create --description "Groma: first home snapshot" --cleanup-algorithm number
fi

step "What is there now"
snapper -c home list
cat /etc/conf.d/snapper | grep SNAPPER_CONFIGS
