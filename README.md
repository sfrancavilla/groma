# Groma

A desktop shell for Hyprland, written in QML on [Quickshell](https://quickshell.org).

Named for the Roman surveying instrument used to lay out a military camp or a
new city. Sight along it and you get the *cardo* and *decumanus*, the two axes
everything else is built from — and every camp in the empire was laid out
identically with one. That is the goal here: a desktop you can reproduce
exactly, on any machine, from this repository.

> **Status:** v0.2.0-alpha. In daily use on one laptop, and installed from
> scratch on a second machine; see [CHANGELOG.md](CHANGELOG.md) for what was
> tested where and what was not.

## What it does

One long-running process provides the whole desktop shell:

| File | Role |
|---|---|
| `hypr/hyprland.lua` | Compositor config: keybinds, input, look and feel, and starting the shell |
| `shell/shell.qml` | Entry point. The bar, and it instantiates everything else |
| `shell/Theme.qml` | Every colour, radius, spacing and type size |
| `shell/ui/` | Generic pieces with no domain knowledge: glass, slider, chip, button |
| `shell/icons/` | Drawn glyphs, as paths rather than an icon font |
| `shell/modules/` | The features: volume, battery, network, notifications, polkit, lock, idle, OSD, wallpaper |

The network tile can show a public address — the one thing in this shell that
contacts a third party, since nothing local knows it: the router translates on
the way out. **It is off by default** and has a switch beside it in the tile.
Turned on, it asks `api.ipify.org` only while the tile is open, only with a
route out, and at most once every five minutes.

A DNS lookup would avoid the web service and was tried; on this connection the
ISP intercepts port 53, so the nameserver reports its own resolver rather than
this machine. The comment in `NetworkControl.qml` has the numbers.

That choice lives in `Settings.qml`, which is the one place holding what the
user decided rather than what the shell looks like. It is written to
`Quickshell.statePath("settings.json")` whenever it changes.

The Settings window (`qs -c groma ipc call settings opened`, or Settings in
the launcher) is where those choices are made, the switch above among them.
The ones that belong to Hyprland - keyboard layouts, touchpad, pointer speed,
display scale - are written by `HyprConfig.qml` to `~/.config/hypr/groma.lua`,
holding only what was changed. `hyprland.lua` loads it before `machine.lua`,
so a hand-written override still wins, and Hyprland reloads by itself when
the file changes. A display scale is the exception: it is tried on the
running compositor and goes back after 15 seconds unless it is kept.

Print opens the capture overlay (`ipc call capture open`): every screen is
frozen by `grim` first, and the overlay lies over the frozen frames, so a
picture is cut from what was on screen at the moment Print was pressed, not
taken again once a menu has closed. Shift+Print takes the whole screen at once;
Alt+Print chooses what to record, and Print again stops it. Pictures go to
`Pictures/Screenshots` and the clipboard, recordings to `Videos/Screen
Recordings`, and a card in the corner opens either in Satty or a player, or
drags the file into another window. `gpu-screen-recorder` is started by
`modules/capture-record.sh`, outside the shell, so a reload of the shell does
not cut a recording off; the shell reads the state file it leaves in
`$XDG_RUNTIME_DIR/groma-capture`.

The volume and brightness keys call the shell (`ipc call keys …`) rather than
running `wpctl` and `brightnessctl` themselves, so the change and its on-screen
readout are one action. The shell does not have to discover what a keybind just
did. The cost is that those keys need the shell running.

Being one process rather than a collection of daemons means components share
live state directly — the bar and a future volume popup read the same PipeWire
object, not two independent queries that can disagree. The trade is a shared
fate: if the process dies, all of it dies at once.

There is no Waybar, Mako, Dunst or polkit-gnome. Those roles are claimed at
runtime by owning a D-Bus name or registering with `polkitd`, and this shell
claims them itself.

## UI conventions

The volume tile is the reference. Anything new should be built from these
rather than deciding its own numbers, so that changing one value moves the
whole shell instead of leaving one widget behind.

| Component | Use for |
|---|---|
| `Theme.qml` | Every colour, radius, spacing and type size. A singleton; needs `import QtQuick` as well as `import Quickshell`, or the whole config fails to load |
| `ui/GlassPanel.qml` | Any glass surface: gradient rim, inset body, feathered shadow. Falls back to flat when `Theme.glass` is off |
| `ui/GlassTile.qml` | Panel-sized things. Standard padding, a header naming what it is and what it acts on |
| `ui/Slider.qml` | Any 0..1 value. The lens sits inside the track; the caller owns the value and handles `moved` |
| `ui/Lens.qml` | The sphere of glass. The slider's knob and a dialog's icon disc are this at different sizes |
| `ui/GlassDialog.qml` | Modal sheet: dimmed, blurred desktop with a centred pane. The caller owns the window |
| `ui/GlassField.qml` | Text entry as a glass track, with a focus ring rather than a thicker border |
| `ui/BarPopup.qml` | A readout in the bar and the tile it opens: window, click-catcher, animation, positioning |
| `ui/Chip.qml` | One option among a few, the chosen one brighter |
| `ui/Switch.qml` | Two states and no third: the lens as a knob on a track |
| `ui/Checkbox.qml` | A box and its label, clickable as one thing |
| `ui/DialogButton.qml` | Buttons in dialogs and notification actions. `variant`: secondary, primary, destructive |
| `SpeakerIcon.qml` / `BatteryIcon.qml` / `BoltIcon.qml` | Drawn glyphs, as paths rather than an icon font |

### Two kinds of icon

The shell's own glyphs - the bar, the power menu, search, the marks on glass
discs - are drawn as `QtQuick.Shapes` paths, not taken from a font or an SVG
set. They carry state: the speaker's waves follow the level, the battery's
cell fills with the charge, the Wi-Fi arcs follow the signal. They share one
24-unit grid, and their line weights come from two values in `Theme.qml`,
`barIconLine` and `markLine`.

Applications, files and folders are a large, open-ended set, and for those
the shell uses an icon theme: **Papirus**, chosen through `QS_ICON_THEME` in
`hypr/hyprland.lua` and looked up with `Quickshell.iconPath`. Files maps file
types to Papirus names in `shell/icons/fileicons.js`. Groma's own applications
have their own icons in `system/icons/`.

The layering runs one way — `icons` depend on nothing, `ui` only on `Theme` and
each other, `modules` on all three, and `shell.qml` only on `modules`. A `ui`
file importing `../modules` would be the signal something is in the wrong place.

QML does not find components in subdirectories on its own, so each file declares
what it uses — `import ".."` for the `Theme` singleton, then `import "../ui"`
and `import "../icons"`. A bare `qmldir` is not a substitute: a singleton at the
root stays invisible to a subfolder without the import, and the failure is a
runtime `ReferenceError` rather than a load error, so it would ship looking fine.

Tokens are named by **role**, never by value: `Theme.danger` rather than
`Theme.red`, `Theme.surface` rather than `Theme.white`. A component asking for
`danger` keeps working when danger stops being red.

Two rules worth stating because breaking them is easy:

- **Never write a colour, radius or spacing literal in a component.** If no
  token fits, add one — that is the signal the scale is incomplete.
- **Controls on glass are films, not surfaces.** Use `glassControl*`. An opaque
  control on a translucent panel looks pasted on.

`Theme.glass` toggles the translucent look off for the whole shell, so every
component must read sensibly both ways.

Every colour, spacing, radius and type size in the shell now comes from
`Theme.qml`; there are no literals left in any component.

## Requirements

An Arch Linux base install with a user in the `wheel` group, made with the
[Arch installation guide](https://wiki.archlinux.org/title/Installation_guide)
or `archinstall`. Everything else, including Hyprland and Quickshell, comes
from the installer.

For snapshots, the root filesystem should be Btrfs with `/` on a subvolume
named `@` - the layout `archinstall`'s Btrfs option makes. An `@snapshots`
subvolume beside it is created and mounted at `/.snapshots` if it is not there
yet. Without Btrfs, everything but snapshots still installs.

Tested on Arch Linux with Hyprland 0.56 (its Lua configuration) and
Quickshell 0.3.2: daily on a Framework Laptop 13 with AMD graphics, and as a
fresh `archinstall` machine in a virtual machine. Both projects move quickly; a
newer release may need small changes here.

## Install

```bash
git clone https://github.com/sfrancavilla/groma.git ~/groma
~/groma/install.sh
```

Then log out and log in again on the first console: the desktop starts.

The installer is not tied to one machine. It detects the CPU and graphics and
installs the matching microcode and Vulkan driver, and fprintd where there is
a fingerprint reader; it sets up snapshots only
where the disk has the Btrfs `@` / `@snapshots` layout, and says why when it
skips; NVIDIA is detected but untested, and the installer says so. It links
the shell and the compositor config into `~/.config`, registers Groma's own
applications, starts Hyprland after login on tty1, installs the
lock-before-sleep unit, builds an AUR helper, and shortens the faillock lockout
to two minutes. Safe to re-run.

On a machine that boots with Limine, the boot menu can also list snapshots.
That is a separate step because it changes the boot loader:
`system/setup-limine-snapshots.sh` stops before rebooting so the result can be
read first. Read `system/BOOT-RECOVERY.md` before running it.

### Machine-local overrides

Anything specific to one machine — a monitor layout, a keybind you want on this
laptop only — goes in `~/.config/hypr/machine.lua`, which is not tracked here.
It is loaded last, so it wins over the defaults. Start from
`hypr/machine.lua.example`:

```bash
cp ~/groma/hypr/machine.lua.example ~/.config/hypr/machine.lua
```

Leave it out entirely and nothing breaks — the config only loads it if present.

## Development

```bash
qs -c groma            # run it
qs -c groma log        # read its log, including QML console.log output
```

Each window sets a layer-shell namespace, so surfaces are identifiable from
outside the process:

```bash
hyprctl layers | grep 'namespace: groma'
```

```text
Layer ...: xywh: 0 0 1440 32, a: 1, namespace: groma:bar, pid: 3652
Layer ...: xywh: 1048 40 380 74, a: 1, namespace: groma:notifications, pid: 3652
```

### If the lock screen ever holds

Under `ext-session-lock` the compositor keeps the session shut if the locking
client dies or never authenticates. That is the protocol working — a crashed
lock screen must not expose the desktop — but it means the way out is not on
the desktop:

```bash
qs -c groma ipc call lock unlock    # from another shell, if you have one
```

Otherwise Ctrl+Alt+F2 to a TTY and `hyprctl dispatch exit`, which ends the
session. Do not save a QML file while locked.

Three wrong passwords locks the account for a while, and during it a *correct*
password is rejected too. The installer sets `unlock_time = 120` in
`/etc/security/faillock.conf`, rather than the 600s default.

Authentication goes through PAM's `system-auth`. A service name with no file in
`/etc/pam.d` falls through to `other`, which is `pam_deny` — every password
would fail, inside something with no way out.

A fingerprint is a second, separate conversation, on Groma's own stack
(`shell/modules/fingerprint.pam`) rather than one in `/etc/pam.d`: it runs
beside the password, not before it, its misses are not faillock strikes, and
nothing outside the lock screen changes. Any reader libfprint drives works;
without one, or without an enrolled finger, the lock screen shows the password
alone. Five misses and it stops until the next lock.

Polkit prompts take a finger too, but not side by side: polkitd trusts only
its own helper's PAM stack, so the installer puts `pam_fprintd` before the
password in `/etc/pam.d/polkit-1` (`system/polkit-1.pam`) — ten seconds, three
tries, skipped with the lid shut. A password typed meanwhile is sent when the
reader gives up. `sudo rm /etc/pam.d/polkit-1` goes back to password only.

Fingers are added and
removed in Fingerprint, from the launcher (`qs -c groma ipc call fingerprint
opened`).

### Two things that will waste your time

Quickshell **hot-reloads on file save**, which destroys and recreates its
service objects. Do not save a QML file while a polkit prompt is open: the agent
unregisters and the in-flight request dies with `Request dismissed`. Stop
editing before you test authentication.

Cancelling a polkit prompt **counts as a failed attempt** for `pam_faillock`.
Abandoning the prompt makes `pam_unix` fail and faillock counts that; nothing
in the shell can prevent it. Three of them and the account locks for ten
minutes — on TTYs too — after which every password is rejected unread,
including correct ones. Check `faillock --user "$USER"` before concluding the
dialog is broken.

The dialog therefore confirms the first cancel rather than acting on it, so a
stray Escape does not spend one of the three.

Moving this directory while the shell is running kills the process. Restart with
`qs -c groma`.

### Testing a fresh install

`tools/vm.sh` makes a throwaway UEFI virtual machine (QEMU with KVM, OVMF
firmware) to install Arch and Groma into from nothing - the test that the
installer is not relying on the machine it was written on:

```bash
sudo pacman -S qemu-desktop edk2-ovmf   # pick pipewire-jack if asked
tools/vm.sh create                      # disk, firmware store, signed Arch ISO
tools/vm.sh install                     # boot the ISO; run archinstall
tools/vm.sh run                         # boot the installed system
```

Its disk lives in `~/vms`, made its own Btrfs subvolume without copy-on-write
so `/home` snapshots leave it out. Inside the window, Ctrl+Alt+G grabs the
keyboard, which is how SUPER reaches the guest.

## Credits

- [Omarchy](https://github.com/basecamp/omarchy), by DHH and contributors - the
  reference for most of the choices here, from the components a Hyprland
  desktop needs to Limine with snapper for bootable snapshots. Groma follows
  its picks unless there is a reason not to, and says so when it differs.
- [EarA-linux](https://github.com/oneydef/EarA-linux), by oneydef - the
  community's decode of the Nothing earbuds' own protocol, which
  `shell/integrations/nothingear/` is built on. That integration only wakes
  when a pair of Nothing earbuds connects.
- [Quickshell](https://quickshell.org) and [Hyprland](https://hypr.land), which
  this is built on.
- The interface follows a design made with Claude in claude.ai.

## Licence

MIT - see [LICENSE](LICENSE).

