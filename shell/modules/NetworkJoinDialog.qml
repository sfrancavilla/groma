import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// Joining a secured network: the design's 5c, on the shared dialog pattern.
//
// The connection is made with nmcli rather than through Quickshell, whose
// Network can only ask to connect with settings it has no way to build from
// QML - there is nothing to put a password into.
Scope {
	id: root

	// The network being joined, set by whoever opened this.
	property var network: null
	property int bars: 0
	property bool secured: true

	property bool open: false
	property string error: ""
	property bool joining: false

	signal joined

	function ask(name, signalBars, isSecured) {
		root.network = name;
		root.bars = signalBars;
		root.secured = isSecured;
		root.error = "";
		root.joining = false;
		root.open = true;
	}

	function join() {
		if (root.joining || password.text === "")
			return;

		root.joining = true;
		root.error = "";

		// --ask makes nmcli read the secret from stdin rather than taking it
		// as an argument, which would put the password in the process list for
		// anything on the machine to read.
		connect.running = true;
	}

	Process {
		id: connect

		command: ["nmcli", "--ask", "device", "wifi", "connect", root.network ?? ""]
		stdinEnabled: true

		onStarted: {
			connect.write(password.text + "\n");
			password.clear();
		}

		stdout: StdioCollector {}

		stderr: StdioCollector {
			onStreamFinished: {
				if (text.trim() !== "")
					root.error = text.trim().replace(/^Error:\s*/, "");
			}
		}

		onExited: code => {
			root.joining = false;

			if (code === 0) {
				root.open = false;
				root.joined();
				return;
			}

			if (root.error === "")
				root.error = "Could not join the network";
		}
	}

	PanelWindow {
		id: window

		visible: root.open || dialog.sheet.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:network-join"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		onVisibleChanged: {
			if (window.visible) {
				password.clear();
				password.focusInput();
			}
		}

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			Keys.onEscapePressed: root.open = false

			// 5c puts the network's own strength in the lens, which says which
			// network this is about better than repeating the name would.
			icon: Lens {
				sheen: false

				SignalBars {
					anchors.centerIn: parent
					width: 20
					height: width / aspect
					level: root.bars
					color: Theme.glassTextOnLens
				}
			}

			title: `Join “${root.network ?? ""}”`
			body: root.secured
				? "This network is secured. Enter its password to connect."
				: "This network is open. No password is needed."

			GlassField {
				id: password

				width: parent.width
				visible: root.secured
				placeholder: "Password"
				echoMode: TextInput.Password
				revealable: true
				enabled: !root.joining

				onAccepted: root.join()
			}

			Checkbox {
				id: remember

				text: "Remember this network"
				checked: true
				onToggled: remember.checked = !remember.checked
			}

			Text {
				width: parent.width
				wrapMode: Text.WordWrap
				visible: root.error !== ""
				text: root.error
				font.pixelSize: Theme.fontCaption
				lineHeight: 1.4
				color: Theme.warning
			}

			Row {
				anchors.right: parent.right
				spacing: Theme.spacingS

				DialogButton {
					text: "Cancel"
					onClicked: root.open = false
				}

				DialogButton {
					text: root.joining ? "Joining…" : "Join"
					variant: "primary"
					enabled: !root.joining
					onClicked: root.join()
				}
			}
		}
	}
}
