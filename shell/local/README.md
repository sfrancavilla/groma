# Your own widgets

Every `.qml` file in this folder is a widget in the bar, at the left of the
right-hand group, in name order — prefix a number (`10-Weather.qml`) to choose
the order. Nothing else needs changing: a file added while the shell runs
appears straight away, and one that fails to load leaves only itself out.

git ignores everything here except this README, so a widget for your job, your
servers or your home stays on your machine and never becomes part of Groma.
Keep it somewhere of your own if you want it backed up.

## Writing one

A widget is the same kind of thing as the bar's own controls in `modules/`,
and can use everything they use. Most are a `BarPopup`: a glyph in the bar,
and the card it opens.

```qml
import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import "../ui"

BarPopup {
	id: root

	name: "hello"           // names its surfaces in hyprctl layers
	title: "Hello"

	trigger: Text {
		text: "Hi"
		font.pixelSize: Theme.fontBody
		color: Theme.glassTextPrimary
		opacity: root.active ? 1.0 : 0.85
	}

	CardRow {
		title: "Uptime"
		detail: uptime.text

		Process {
			id: uptime

			property string text: ""

			running: root.open
			command: ["uptime", "-p"]
			stdout: StdioCollector {
				onStreamFinished: uptime.text = text.trim()
			}
		}
	}
}
```

- `..` is `Theme` and `Settings`; `../ui` the controls (`CardRow`, `Switch`,
  `Chip`, `SectionLabel`); `../icons` the glyphs. Colours, sizes and type
  come from `Theme`, never literals.
- `ui/GUIDELINES.md` applies here as it does everywhere: what a card holds,
  how it is worded, how it closes.
- There is a bar on every screen, and so a copy of the widget on each. Gate
  an `IpcHandler` on `root.hasIpc`, as `modules/PowerControl.qml` does, so
  only the one on the screen in use answers.
- Saving a file here reloads the whole shell, as saving any of its files does.
