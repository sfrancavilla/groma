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
| `shell/shell.qml` | Root. The bar, and it instantiates the components below |
| `shell/PolkitDialog.qml` | Polkit authentication agent and its password dialog |
| `shell/Notifications.qml` | Notification daemon; owns `org.freedesktop.Notifications` |
| `shell/NotificationToast.qml` | A single notification card |
| `shell/DialogButton.qml` | Shared button used by dialogs and notification actions |

Being one process rather than a collection of daemons means components share
live state directly — the bar and a future volume popup read the same PipeWire
object, not two independent queries that can disagree. The trade is a shared
fate: if the process dies, all of it dies at once.

There is no Waybar, Mako, Dunst or polkit-gnome. Those roles are claimed at
runtime by owning a D-Bus name or registering with `polkitd`, and this shell
claims them itself.

## Requirements

- Hyprland
- Quickshell 0.3.1 or later
- polkit (for the authentication agent)

## Install

```bash
git clone <this repo> ~/groma

mkdir -p ~/.config/quickshell ~/.config/hypr
ln -s ~/groma/shell ~/.config/quickshell/groma
ln -s ~/groma/hypr/hyprland.lua ~/.config/hypr/hyprland.lua
```

The compositor config starts the shell itself, so there is nothing further to
wire up:

```lua
hl.on("hyprland.start", function ()
  hl.exec_cmd("qs -c groma")
end)
```

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

### Two things that will waste your time

Quickshell **hot-reloads on file save**, which destroys and recreates its
service objects. Do not save a QML file while a polkit prompt is open: the agent
unregisters and the in-flight request dies with `Request dismissed`. Stop
editing before you test authentication.

Cancelling a polkit prompt **counts as a failed attempt** for `pam_faillock`.
Three of them and the account locks for ten minutes, after which every password
is rejected unread — including correct ones. Check `faillock --user "$USER"`
before concluding the dialog is broken.

Moving this directory while the shell is running kills the process. Restart with
`qs -c groma`.
