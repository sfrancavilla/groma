# Changelog

## v0.2.0-alpha — 2026-10-29

The second alpha. A settings window, screenshots and recordings, a calendar
and notification centre under the clock, power modes, and a bar on every
screen.

### What is new

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
  file: keyboard layouts (SUPER+SPACE switches once there are two), what Caps
  Lock does, key repeat, natural scrolling, tap to click, ignoring the
  touchpad while typing, the three-finger workspace swipe, scroll and pointer
  speed; display scale and refresh rate, offering only the scales a display
  shows sharply and trying a new one for 15 seconds before it is kept; when
  the screen dims, locks, turns off and suspends, plugged in and on battery;
  a 12- or 24-hour clock and the date in the bar; a picture for the desktop;
  the earbuds' pause and resume; and the public address. Changes apply as
  they are made. Hyprland's share is
  written to `~/.config/hypr/groma.lua`, loaded before `machine.lua`, so a
  hand-written override still wins; a display `machine.lua` sets says so in
  Settings rather than offering a choice it would undo.
- **Calendar and notification centre** — the clock in the bar opens a card
  hung centred under it. On the right, a month: today lit, the ISO week
  number, arrows or a scroll to turn the page and Today to come back
  (Settings → Date & Time chooses whether the week starts on Monday or
  Sunday). On the left, every notification not yet dealt with, newest first,
  with its buttons and how long ago it came: a toast going away no longer
  ends a notification, it moves here. Clear all, and Do Not Disturb, which
  keeps every toast but a critical one away and marks the clock with a
  crescent, and with a dot when something arrived quietly. Toasts pause while
  pointed at, open on a click and go on a right-click, and the centre keeps
  its notifications through a reload of the shell.
- **Power mode** — Power saver, Balanced and Performance in the Battery
  card, through power-profiles-daemon (now installed and enabled), which
  sets the firmware's platform profile and the processor's energy
  preference. The choice is kept for the source it was made on, plugged in
  or on battery, and comes back when the machine next changes to it. When
  the firmware holds Performance back, the card says why.
- **Screenshots and recordings** — Print freezes the screen and lays a
  chooser over it: drag out an area, point at a window, or pick the whole
  screen, from the mouse or the keyboard (Tab walks the windows, Ctrl+Enter
  takes the screen). Shift+Print takes the screen at once. Pictures are
  saved to Pictures/Screenshots and copied; a card in the corner opens one in
  Satty to annotate, or drags it into another window. Alt+Print records the
  same way - an area that can be adjusted before it starts, or a screen -
  with the computer's sound and, if asked, the microphone; a red dot in the
  bar counts the time and stops it. Both are in the launcher as well.
- **More than one screen** — every screen has the wallpaper and a bar of its
  own. Each bar shows the workspaces on its screen and opens its cards under
  itself, and keys such as SUPER+N act on the screen you are using.

### Tested

- **Daily use:** the same Framework Laptop 13 (AMD Ryzen AI 7 350), with a
  Dell P2421D (2560 × 1440) as a second screen, through the Framework HDMI
  Expansion Card and through a USB-C to HDMI adapter.
- **Checked by hand on it:** the capture overlay's keys and dragging a
  picture out of its card; clicking a notification to open its app; the
  idle chain after changing its times; the three-finger swipe turned off;
  the power mode following the charger in and out; a `machine.lua` monitor
  rule against Settings.
- **Not run again:** the fresh install in the virtual machine. The installer
  now adds grim, Satty, gpu-screen-recorder and power-profiles-daemon, and
  has not been through a fresh install since.
- **Versions:** Hyprland 0.56.2, Quickshell 0.3.2, Linux 7.2.11, Satty 0.22.0,
  gpu-screen-recorder 6.1.6, power-profiles-daemon 0.30.

### Known gaps

- **One real machine,** as before; the second screen is the only new
  hardware.
- **Laptop screen alone** has not been looked at again since the bar went to
  every screen.
- **Not placed per screen:** the volume and brightness display, notification
  toasts, the launcher and sheets name no screen, and Hyprland puts them
  where it chooses.
- **Notifications** do not survive a restart of the shell, and a reload
  forgets how long ago each arrived.
- **Disk encryption on a fresh install, NVIDIA and Secure Boot** are as they
  were in v0.1.0-alpha: untried.

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
