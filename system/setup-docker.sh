#!/usr/bin/env bash
#
# Docker, for the machines that want it. Not part of install.sh: run it by
# hand when a machine needs containers.
#
# Docker keeps its data in two places: /var/lib/docker (volumes, containers,
# their logs) and /var/lib/containerd (images, since Docker 29 stores them
# through containerd). Both would sit inside @, so every snapshot of / would
# carry them and a rollback would take them back too. Each gets its own
# subvolume beside @ instead - @docker and @containerd - mounted by fstab
# lines like @var_log's, which a snapshot of @ skips and a rollback leaves
# alone. They must be in place before the package is installed, so Docker
# writes into them from the first run.
#
# Safe to re-run: every step checks before it acts.

set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

# After a kernel update and before the reboot, the running kernel's modules
# are gone from disk, and Docker needs two it may not have loaded yet:
# overlay for container files and nf_tables for its network rules. Better to
# stop here than at the end, with Docker installed but not starting.
if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
	echo "Stopping: the kernel was updated since the last boot. Reboot, then run this again."
	exit 1
fi

# Without the Btrfs @ layout there is nothing to keep out of snapshots, so
# Docker goes in as a plain install.
layout=yes
if [ "$(findmnt -n -o FSTYPE /)" != btrfs ] || ! findmnt -n -o OPTIONS / | grep -qE 'subvol=/?@(,|$)'; then
	layout=no
	echo "/ is not the Btrfs @ subvolume: Docker's data stays where it is."
fi

# subvolume NAME MOUNTPOINT: make @NAME at the top of the filesystem and
# mount it at MOUNTPOINT through an fstab line, the way setup-snapshots.sh
# does for @snapshots.
subvolume() {
	local name="$1" target="$2"

	if grep -qE "[[:space:]]$target[[:space:]]" /etc/fstab; then
		step "$target is already in /etc/fstab - leaving it"
		return
	fi
	# A mount over a folder that has files hides them, so a folder already in
	# use stops the script rather than being covered.
	if [ -e "$target" ] && [ -n "$(sudo ls -A "$target")" ]; then
		echo "Stopping: $target already has files in it. Move them aside first."
		exit 1
	fi

	step "Creating an @$name subvolume beside @, for $target"
	local device top line
	device="$(findmnt -n -o SOURCE / | sed 's/\[.*//')"
	top="$(mktemp -d)"
	sudo mount -o subvolid=5 "$device" "$top"
	[ -d "$top/@$name" ] || sudo btrfs subvolume create "$top/@$name"
	sudo umount "$top"
	rmdir "$top"

	# The / line with its mount point and subvolume swapped. subvolid goes:
	# it names @'s id, and would contradict the new subvol=.
	line="$(awk -v subvol="subvol=/@$name" -v dir="$target" '$2 == "/" && $3 == "btrfs" {
		n = split($4, opt, ","); out = ""
		for (i = 1; i <= n; i++) {
			if (opt[i] ~ /^subvolid=/) continue
			if (opt[i] ~ /^subvol=/) opt[i] = subvol
			out = out (out == "" ? "" : ",") opt[i]
		}
		$2 = dir; $4 = out
		print; exit
	}' /etc/fstab)"
	[ -n "$line" ] || { echo "Stopping: no Btrfs line for / in /etc/fstab."; exit 1; }

	[ -e /etc/fstab.before-groma-docker ] || sudo cp /etc/fstab /etc/fstab.before-groma-docker
	printf '\n# @%s, added by Groma'"'"'s setup-docker.sh\n%s\n' "$name" "$line" | sudo tee -a /etc/fstab >/dev/null
	sudo systemctl daemon-reload
	sudo mkdir -p "$target"
	sudo mount "$target"
	echo "  Added to /etc/fstab (the old one is /etc/fstab.before-groma-docker):"
	echo "  $line"
}

if [ "$layout" = yes ]; then
	subvolume docker /var/lib/docker
	subvolume containerd /var/lib/containerd
fi

step "Installing Docker, Compose and Buildx (official repositories)"
sudo pacman -S --needed docker docker-compose docker-buildx

# Docker's default json-file logs grow without end. Five files of 10 MB per
# container is plenty to read back. An existing daemon.json is someone's own.
if [ ! -e /etc/docker/daemon.json ]; then
	step "Capping container logs at 5 x 10 MB"
	sudo mkdir -p /etc/docker
	printf '{\n  "log-driver": "json-file",\n  "log-opts": { "max-size": "10m", "max-file": "5" }\n}\n' |
		sudo tee /etc/docker/daemon.json >/dev/null
else
	step "/etc/docker/daemon.json already exists - leaving it"
fi

# The socket, not the service: the daemon starts on the first docker command
# instead of at every boot. The cost is that containers set to restart come
# back at the first docker command after boot, not at boot itself; for them,
# enable docker.service as well.
step "Enabling docker.socket"
sudo systemctl enable --now docker.socket

# The docker group can reach the daemon without sudo. That is as good as root
# - anyone in it can mount / into a container - so it is for the machine's
# owner only.
if ! id -nG "$USER" | grep -qw docker; then
	step "Adding $USER to the docker group"
	sudo usermod -aG docker "$USER"
	echo "  Takes effect at the next login. Until then, docker needs sudo."
else
	step "$USER is already in the docker group"
fi

step "What is there now"
# A daemon that does not start is reported, not fatal: the mounts below are
# worth seeing either way.
# docker info prints its template half-empty before failing, so ask first.
if sudo docker info >/dev/null 2>&1; then
	sudo docker info --format 'Docker {{.ServerVersion}}, data in {{.DockerRootDir}}, storage {{.Driver}}'
else
	echo "  Docker did not start. journalctl -u docker.service -b says why."
fi
if [ "$layout" = yes ]; then
	findmnt -n -o TARGET,SOURCE /var/lib/docker
	findmnt -n -o TARGET,SOURCE /var/lib/containerd
fi
