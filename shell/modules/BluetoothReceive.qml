import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick

// Files from a phone, over Bluetooth: share to "Bluetooth" on the phone and
// pick this computer.
//
// Nothing to draw. bluetooth-receive.py beside this file is obexd's agent:
// it asks about each share in a notification, with Accept and Decline, and
// says what arrived the same way. This keeps it running while there is an
// adapter, and does the two things a notification can ask for that only
// the shell can: open a file, and show the folder in Files.
Scope {
	id: root

	required property var files

	readonly property bool wanted: (Bluetooth.defaultAdapter ?? null) !== null

	// Started and stopped by hand, as NothingEar's helper is: Quickshell
	// writes running = false when a process exits, which would break a
	// binding the first time the helper died.
	onWantedChanged: {
		root.setbacks = 0;
		helper.running = false;
		if (root.wanted)
			helper.running = true;
	}

	Component.onCompleted: if (root.wanted) helper.running = true

	// Exit 2 is another program being obexd's agent already; trying again
	// every two seconds would only fill the log, so the wait doubles up to
	// a minute. Registering resets it.
	property int setbacks: 0

	Timer {
		id: revive

		interval: Math.min(60000, 2000 * Math.pow(2, root.setbacks))
		onTriggered: {
			if (root.wanted && !helper.running) {
				root.setbacks += 1;
				helper.running = true;
			}
		}
	}

	Process {
		id: helper

		command: ["python3", `${Quickshell.shellDir}/modules/bluetooth-receive.py`]

		onExited: if (root.wanted) revive.start()

		stdout: SplitParser {
			onRead: line => root.handle(line)
		}

		stderr: SplitParser {
			onRead: line => console.warn("Bluetooth receive:", line)
		}
	}

	function handle(line) {
		let msg;
		try {
			msg = JSON.parse(line);
		} catch (err) {
			return;
		}
		switch (msg.event) {
		case "ready":
			root.setbacks = 0;
			return;
		case "show":
			root.files.show(msg.path);
			return;
		case "open":
			Quickshell.execDetached(["xdg-open", msg.path]);
			return;
		}
	}
}
