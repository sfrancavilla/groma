pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Processor, graphics, memory and disk readings from system-worker.py, for
// the System glyph and card in every bar (SystemControl.qml).
//
// One worker however many screens there are: each bar draws the same
// figures, and a Python process per monitor would be paying twice to know
// them. Kept alive for as long as the shell runs, because the glyph shows
// them too. It reads every three seconds, and every second while any bar's
// card is open.
Singleton {
	id: root

	// The last reading, or null until the first one arrives.
	property var reading: null

	// How many System cards are open. Counted rather than a flag, so one bar
	// closing its card does not slow the readings another is showing.
	property int looking: 0

	onLookingChanged: if (worker.running) worker.write((root.looking > 0 ? "1" : "3") + "\n")

	Process {
		id: worker

		command: ["python3", `${Quickshell.shellDir}/modules/system-worker.py`]
		stdinEnabled: true

		// Started here rather than bound: a binding on `running` is broken
		// the first time the process exits on its own, and then it never
		// comes back.
		Component.onCompleted: worker.running = true
		onExited: reviveWorker.start()

		stdout: SplitParser {
			onRead: line => {
				try {
					root.reading = JSON.parse(line);
				} catch (e) {
					console.warn("System worker:", line);
				}
			}
		}

		stderr: SplitParser {
			onRead: line => console.warn("System worker:", line)
		}
	}

	Timer {
		id: reviveWorker

		interval: 2000
		onTriggered: if (!worker.running) worker.running = true
	}
}
