# Changelog

## Unreleased

- **Named workspaces** — right-click a workspace in the bar, or SUPER+N, to
  name it for what it holds and give it a colour, as with Chrome's tab
  groups. A named workspace keeps its place in the bar when it is empty.
  Pointing at one shows a live miniature of its windows.
- **Bar cards** — everything the bar opens hangs from its icon like a tab and
  grows out of it, in one dense slate glass: sound, battery, Wi-Fi,
  Bluetooth, power, and a workspace's preview and name field.
- **Other apps' questions** — the "Save changes?" that VS Code, Chromium and
  Slack ask through GTK 3 is drawn as Groma's sheet: dense glass, the glass
  edge, chip buttons with the default one bright. Every floating window gets
  the same corners and edge. An app picks it up when it next starts.
- **Fingerprint unlock** — on a laptop with a reader fprintd supports, touch it
  at the lock screen instead of typing; the password field works alongside
  it. The installer adds fprintd when it finds a reader. Off while the lid is
  shut, and after five misses until the next lock. Polkit prompts take a
  finger as well: the reader gets ten seconds first, and a password typed
  meanwhile goes in as soon as it gives up.
- **Fingerprint** — add and remove fingers from the launcher: pick the finger,
  then touch the reader as the print fills in. On a laptop with a reader and
  nothing enrolled, Groma says so once, shortly after login.
- **System** — a glyph in the bar, before the power button, whose three cells
  fill with how much processor, memory and disk is in use. Its card lists
  each with a figure: processor load and temperature, graphics (on AMD),
  memory, swap when there is any, and disk free space. A cell turns amber
  when memory or a disk passes 90% or the processor runs hot.
- **Settings** — a window, from the launcher, for what used to mean editing a
  file: keyboard layouts (SUPER+SPACE switches once there are two), natural
  scrolling, tap to click and pointer speed; display scale, offering only the
  scales a display shows sharply and trying a new one for 15 seconds before
  it is kept; when the screen dims, locks, turns off and suspends, plugged in
  and on battery; a picture for the desktop; the earbuds' pause and resume;
  and the public address. Changes apply as they are made. Hyprland's share is
  written to `~/.config/hypr/groma.lua`, loaded before `machine.lua`, so a
  hand-written override still wins.

## v0.1.0-alpha — 2026-10-27

The first alpha. Groma provides the whole desktop shell for Hyprland as one
Quickshell process, and installs on a machine it was not written on.

### What it does

- **Bar** — workspaces, clock, Wi-Fi, Bluetooth, volume, battery and power,
  each opening its own tile.
- **Launcher** — applications, a calculator (qalc for units), files (fd),
  clipboard history and commands, from one search field.
- **Files** — a file manager of its own: list and grid views, copy and move
  with progress and name conflicts, drag and drop in and out, Trash, drives
  through udisks2, properties, and Open with.
- **Groma Store** — install, remove and update from the official repositories
  and the AUR, with the source marked on every row.
- **Desktop services** — notifications, the polkit agent, and an on-screen
  display for volume and brightness.
- **Locking** — lock screen, an idle chain (dim, lock, blank, and suspend on
  battery), and locking before every sleep.
- **Power menu** — lock, suspend, log out, restart and power off.
- **Snapshots** — snapper for `/`, around every pacman transaction, and for
  `/home` on a timeline; a Snapshots view with Undo and Browse; Limine's boot
  menu lists system snapshots, and the shell says when it is running one.
- **Nothing earbuds** — per-bud battery, and playback paused when the buds
  come out, read over the earbuds' own protocol.
- **Installer** — `install.sh` from a bare Arch install: hardware detected,
  snapshot steps that check the disk and say why they skip, Hyprland started
  after login on the first console. Safe to re-run.

### Tested

- **Daily use:** Framework Laptop 13 (AMD Ryzen AI 7 350), Arch Linux on
  LUKS2 and Btrfs, booting with Limine.
- **Fresh install:** an `archinstall` machine (Btrfs default layout, Limine, no
  disk encryption) in QEMU/KVM with OVMF, made by `tools/vm.sh`: the installer,
  Hyprland starting on login, system and `/home` snapshots, and booting a
  snapshot from the Limine menu with its overlay.
- **Versions:** Hyprland 0.56.2, Quickshell 0.3.2, Limine 12.9.4, snapper
  0.13.2, Linux 7.2.11.

### Known gaps

- **One real machine.** Wi-Fi, Bluetooth, battery and backlight are proven on
  the Framework only; the virtual machine has none of them.
- **Disk encryption on a fresh install** is untested: the test machine's disk
  was not encrypted.
- **NVIDIA** is detected and left alone; it has never been tried.
- **Secure Boot** is not set up.
- **No settings window.** Choices live in `shell/Theme.qml`,
  `shell/Settings.qml` and `hypr/hyprland.lua`, and machine-only overrides in
  `~/.config/hypr/machine.lua`.
