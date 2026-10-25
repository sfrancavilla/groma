# Groma

A desktop shell for Hyprland, written in QML on [Quickshell](https://quickshell.org).

Named for the Roman surveying instrument used to lay out a military camp or a
new city. Sight along it and you get the *cardo* and *decumanus*, the two axes
everything else is built from — and every camp in the empire was laid out
identically with one. That is the goal here: a desktop you can reproduce
exactly, on any machine, from this repository.

> **Status:** early. Working, in daily use, and changing often.

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

### Why no icon pack

Shell glyphs are drawn as `QtQuick.Shapes` paths, not taken from a font or an
SVG set. They carry state: the speaker's waves follow the level, the battery's
cell fills with the charge, and a bolt appears over it when charging. A pack
would need a separate icon for each of those and code to swap between them.

It also means no font to install, which matters for something meant to be
cloned, and the glyphs match the panels because they are built the same way.

This does not scale to dozens of icons. When something needs a large set - a
launcher, a settings panel - use SVGs from Material Symbols or Lucide (qt6-svg
is present, so `Image` renders them), and `Quickshell.iconPath` for
*application* icons, which the notification toasts already do.

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

An Arch Linux base install with a user in the `wheel` group — the
[book](https://github.com/sfrancavilla/learning-linux-guide)'s chapter 1, or
`archinstall`. Everything else, including Hyprland and Quickshell, comes from
the installer.

## Install

```bash
git clone https://github.com/sfrancavilla/groma.git ~/groma
~/groma/install.sh
```

Then log out and log in again on the first console: the desktop starts.

The installer is not tied to one machine. It detects the CPU and graphics and
installs the matching microcode and Vulkan driver; it sets up snapshots only
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
