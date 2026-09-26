import Quickshell
import Quickshell.Io
import QtQuick

// Clipboard history, as a shell service.
//
// Wayland has no clipboard history; something has to watch the clipboard and
// keep what passes through it. cliphist is that something - wl-paste hands it
// every new selection, it stores them, and lists or restores them on demand.
// The watching process is the shell's to keep alive, like the earbud helper,
// and for the same reason: it is only useful while it is running.
//
// Idle until both tools exist. The launcher's ":" mode says what to install
// rather than showing an empty list that looks like a bug.
Scope {
	id: root

	property bool available: false

	// id -> preview line, in cliphist's order: newest first.
	property var entries: []

	Process {
		id: tools

		command: ["bash", "-c", "command -v cliphist && command -v wl-paste && command -v wl-copy"]
		running: true
		onExited: code => {
			root.available = code === 0;
			if (root.available)
				watcher.running = true;
		}
	}

	// Started by hand and revived on exit: a binding on `running` would be
	// broken by the write Quickshell makes when the process ends.
	Process {
		id: watcher

		command: ["wl-paste", "--watch", "cliphist", "store"]
		onExited: if (root.available) revive.start()
	}

	Timer {
		id: revive

		interval: 3000
		onTriggered: if (root.available && !watcher.running) watcher.running = true
	}

	// Re-checks for the tools when asked while idle, so installing them does
	// not need a reload: the next ":" finds them and starts the watcher.
	function refresh() {
		if (root.available)
			lister.running = true;
		else
			tools.running = true;
	}

	Process {
		id: lister

		command: ["cliphist", "list"]

		stdout: StdioCollector {
			onStreamFinished: {
				root.entries = text.split("\n")
					.filter(line => line !== "")
					.map(line => {
						const tab = line.indexOf("\t");
						return { id: line.slice(0, tab), preview: line.slice(tab + 1) };
					});
			}
		}
	}

	// Put an entry back on the clipboard.
	function copy(id) {
		Quickshell.execDetached(["sh", "-c",
			'cliphist decode "$1" | wl-copy', "sh", id]);
	}

	function remove(id) {
		Quickshell.execDetached(["sh", "-c",
			'printf "%s\\t\\n" "$1" | cliphist delete', "sh", id]);
	}

	function wipe() {
		Quickshell.execDetached(["cliphist", "wipe"]);
		root.entries = [];
	}
}
