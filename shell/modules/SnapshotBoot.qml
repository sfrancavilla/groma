import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"
import "snapshots.js" as Snapshots

// Booted into a snapshot from the Limine menu? Then say so.
//
// limine-snapper-sync has its own notifier, but it starts through XDG
// autostart, and nothing runs XDG autostart here - Hyprland starts only the
// shell. So the shell looks for itself: a kernel command line naming a
// subvolume under @snapshots means the root is a read-only snapshot with a
// throwaway layer over it (see system/BOOT-RECOVERY.md).
//
// It says so twice: a sheet when the session starts, and an amber chip in the
// bar for as long as the session lasts, because a desktop that looks exactly
// like the real one is the one where work gets lost.
Scope {
	id: root

	// For the bar's chip.
	readonly property bool active: root.number > 0
	property int number: 0
	property string date: ""
	property string description: ""
	property string kind: ""

	property bool open: false

	FileView {
		id: cmdline

		path: "/proc/cmdline"
		onLoaded: root.readCmdline(cmdline.text())
	}

	function readCmdline(text) {
		const m = /rootflags=subvol=\/?@snapshots\/(\d+)\/snapshot/.exec(text);
		root.number = m ? parseInt(m[1]) : 0;
		if (root.number > 0) {
			lister.running = true;
			root.open = true;
		}
	}

	// What the snapshot was: its date and the pacman run it brackets.
	Process {
		id: lister

		command: ["snapper", "--jsonout", "-c", "root", "list"]

		stdout: StdioCollector {
			onStreamFinished: {
				let list = [];
				try {
					list = JSON.parse(text).root ?? [];
				} catch (err) {
					return;
				}
				const snap = list.find(s => s.number === root.number);
				if (!snap)
					return;
				root.date = snap.date;
				root.kind = snap.type;
				root.description = snap.description ?? "";
			}
		}
	}

	readonly property string when: {
		if (root.date === "")
			return "";
		const d = new Date(root.date.replace(" ", "T"));
		return Qt.formatDateTime(d, "d MMM 'at' hh:mm");
	}

	// A pre snapshot is the system just before the command it names; a post
	// is the system just after it.
	readonly property string body: {
		const what = Snapshots.phrase(root.kind, root.description);
		const lead = root.when !== "" ? `This is the system as it was on ${root.when}` : "This is an earlier version of the system";
		const which = what === "" ? "." : root.kind === "pre" ? `, just before ${what}.` : `, just after changing ${what}.`;
		return lead + which + " It is read-only underneath: anything you change now is gone at the next restart.";
	}

	function restore() {
		root.open = false;
		Quickshell.execDetached(["foot", "--app-id=groma-snapshot-restore", "--title=Restore a Snapshot", "--",
			"bash", "-c", 'echo "Restoring makes this snapshot the system again. The current one is kept as a backup entry in the boot menu."; echo; sudo limine-snapper-restore; echo; read -rp "Press Enter to close. Restart to boot the restored system."']);
	}

	function restartToCurrent() {
		root.open = false;
		Quickshell.execDetached(["systemctl", "reboot"]);
	}

	IpcHandler {
		target: "snapshot"

		function opened(): void { if (root.active) root.open = true; }
		function closed(): void { root.open = false; }
		function status(): string { return root.active ? `snapshot ${root.number}` : "current system"; }
	}

	PanelWindow {
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
		WlrLayershell.namespace: "groma:snapshot-boot"
		WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: dialog.sheet
			radius: Theme.radiusPanel
		}

		onVisibleChanged: if (visible) keys.forceActiveFocus()

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			sheetWidth: Theme.dialogWidthPrompt
			title: `You are running snapshot ${root.number}`
			body: root.body

			icon: Lens {
				width: 44
				height: 44
				sheen: false

				PowerIcon {
					anchors.centerIn: parent
					width: 22
					height: 22
					lineWidth: 2.5
					kind: "restart"
					color: Theme.calcInk
				}
			}

			Item {
				id: keys

				width: parent.width
				height: Theme.chipHeight
				focus: true

				Keys.onPressed: event => {
					if (event.key === Qt.Key_Escape) {
						root.open = false;
						event.accepted = true;
					} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						root.restore();
						event.accepted = true;
					}
				}

				// The secondary action on the left; the answer on the right.
				DialogButton {
					anchors.left: parent.left
					text: "Restart to current"
					onClicked: root.restartToCurrent()
				}

				Row {
					anchors.right: parent.right
					spacing: Theme.spacingS

					DialogButton {
						text: "Cancel"
						onClicked: root.open = false
					}

					DialogButton {
						text: "Restore…"
						variant: "primary"
						onClicked: root.restore()
					}
				}
			}
		}
	}
}
