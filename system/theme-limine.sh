#!/usr/bin/env bash
#
# The Limine menu in Groma's colours: the desktop's deep teal for the
# background, its green wash for the branding, and an eight-colour palette
# built from the shell's own theme (shell/Theme.qml).
#
# The settings go at the top of /boot/limine.conf, before the first entry.
# limine-entry-tool regenerates the entries below them; this script checks,
# by regenerating, that the top survives - the same arrangement Omarchy uses.

set -euo pipefail

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m!! %s\033[0m\n' "$1" >&2; exit 1; }

conf=/boot/limine.conf
[ -f "$conf" ] || fail "$conf not found - run setup-limine-snapshots.sh first"

# key  value. Colours are RRGGBB; palettes are eight of them, separated by ';'
# in the order black red green yellow blue magenta cyan white.
settings=(
	"interface_branding|Groma"
	"interface_branding_color|9cc86c"
	"interface_help_color|b9a6ff"
	"interface_help_color_bright|d4c9ff"
	"term_background|0d3242"
	"backdrop|0d3242"
	"term_foreground|e8eef2"
	"term_foreground_bright|ffffff"
	"term_background_bright|1d4a5e"
	"term_palette|0d3242;cc3333;9cc86c;f5b942;7aa7d6;886de9;6fc3c9;e8eef2"
	"term_palette_bright|1d4a5e;e06666;b8dc8f;ffd27a;a3c4ea;a996f2;9adbe0;ffffff"
)

step "Backing up $conf"
sudo cp "$conf" "$conf.before-theme"

step "Writing the theme into the top of $conf"
tmp="$(mktemp)"
sudo cat "$conf" >"$tmp"
for pair in "${settings[@]}"; do
	key="${pair%%|*}"
	value="${pair#*|}"
	# Drop any line setting this key, commented or not, in the header only -
	# the part before the first entry, which starts with "/".
	awk -v key="$key" '
		/^\// { body = 1 }
		body || !($0 ~ "^#?" key ":") { print }
	' "$tmp" >"$tmp.next" && mv "$tmp.next" "$tmp"
done
{
	printf '### Groma theme - written by groma/system/theme-limine.sh\n'
	for pair in "${settings[@]}"; do
		printf '%s: %s\n' "${pair%%|*}" "${pair#*|}"
	done
	printf '\n'
	cat "$tmp"
} >"$tmp.themed"
sudo cp "$tmp.themed" "$conf"
rm -f "$tmp" "$tmp.themed"

step "Regenerating, to prove the theme survives"
sudo limine-update >/dev/null
sudo limine-snapper-sync >/dev/null
for pair in "${settings[@]}"; do
	key="${pair%%|*}"
	if ! grep -q "^$key: ${pair#*|}\$" "$conf"; then
		sudo cp "$conf.before-theme" "$conf"
		fail "$key did not survive regeneration - the backup is restored"
	fi
done
echo "All $((${#settings[@]})) settings are still there after regeneration."

step "The top of the menu now"
sed -n '1,/^\//p' "$conf" | head -40
