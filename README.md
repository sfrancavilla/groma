# dotfiles

Configuration for **Groma**, an Arch Linux / Hyprland desktop built from
scratch on a Framework laptop.

Named for the Roman surveying instrument used to lay out a camp or a new city:
sight along it and you get the two axes everything else is built from. Every
camp was laid out identically with one, anywhere in the empire — which is the
point of this repository.

## Layout

```
quickshell/groma/        the desktop shell: bar, polkit agent, notifications
```

Directories are symlinked into place rather than copied, so the live config and
the repository are the same files:

```bash
ln -s ~/dotfiles/quickshell ~/.config/quickshell
```

## quickshell/groma

One long-running Quickshell process provides the whole desktop shell. It is
started by Hyprland (`hl.on("hyprland.start", ...)` in `hyprland.lua`) and runs
as `qs -c groma`.

| File | Role |
|---|---|
| `shell.qml` | Root. The bar, and it instantiates the components below |
| `PolkitDialog.qml` | Polkit authentication agent and its password dialog |
| `Notifications.qml` | Notification daemon; owns `org.freedesktop.Notifications` |
| `NotificationToast.qml` | A single notification card |
| `DialogButton.qml` | Shared button used by dialogs and notification actions |

Each window sets a layer-shell namespace (`groma:bar`, `groma:polkit`,
`groma:notifications`), so `hyprctl layers` identifies them individually.

Because it is one process, restarting it restarts all of those at once.

```bash
qs -c groma log          # read its log, including QML console output
```

### Caution

Quickshell hot-reloads on file save, which recreates its service objects. Do not
save a QML file while a polkit prompt is open: the agent unregisters and the
in-flight request dies with "Request dismissed".

Moving this directory while the shell is running will kill the process. Restart
it with `qs -c groma` afterwards.
