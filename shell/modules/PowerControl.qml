import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// The power mark at the end of the bar, and what it opens: lock, suspend,
// log out, restart, power off.
//
// The first two lose nothing and act at once - the session locks before any
// suspend, through groma-lock-on-sleep. The last three close every window,
// so they ask first, in a sheet that owns the keyboard: Enter confirms,
// Escape and an IPC call get out.
//
// Everything goes through logind, which lets the active session do these
// without a password - the same route the idle chain suspends by.
BarPopup {
	id: root

	name: "power"
	title: "Power"
	trailing: root.uptime

	// { verb, title, body, run } or null: the question on screen.
	property var asking: null

	property string uptime: ""

	onOpenChanged: if (open) uptimeProbe.running = true

	Process {
		id: uptimeProbe

		command: ["cat", "/proc/uptime"]

		stdout: StdioCollector {
			onStreamFinished: {
				const seconds = parseFloat(text.split(" ")[0]) || 0;
				const h = Math.floor(seconds / 3600);
				const m = Math.floor((seconds % 3600) / 60);
				root.uptime = "Up " + (h > 23 ? Math.floor(h / 24) + " d " + (h % 24) + " h"
					: h > 0 ? h + " h " + m + " m" : m + " m");
			}
		}
	}

	readonly property var actions: [
		{ key: "lock", label: "Lock", hint: "Super L", glyph: "lock", ask: false,
			run: () => Quickshell.execDetached(["qs", "-c", "groma", "ipc", "call", "lock", "lock"]) },
		{ key: "suspend", label: "Suspend", hint: "", glyph: "moon", ask: false,
			run: () => Quickshell.execDetached(["systemctl", "suspend"]) },
		{ key: "logout", label: "Log out…", hint: "", glyph: "leave", ask: true,
			title: "Log out?", verb: "Log out",
			run: () => Quickshell.execDetached(["sh", "-c",
				"command -v hyprshutdown >/dev/null 2>&1 && exec hyprshutdown; exec hyprctl dispatch 'hl.dsp.exit()'"]) },
		{ key: "restart", label: "Restart…", hint: "", glyph: "restart", ask: true,
			title: "Restart the laptop?", verb: "Restart",
			run: () => Quickshell.execDetached(["systemctl", "reboot"]) },
		{ key: "poweroff", label: "Power off…", hint: "", glyph: "power", ask: true,
			title: "Power off the laptop?", verb: "Power off",
			run: () => Quickshell.execDetached(["systemctl", "poweroff"]) }
	]

	function perform(key) {
		const action = root.actions.find(a => a.key === key);
		if (!action)
			return;
		root.open = false;
		if (action.ask)
			root.asking = {
				verb: action.verb,
				title: action.title,
				glyph: action.glyph,
				body: "Every open window closes, and anything unsaved in them is lost.",
				run: action.run
			};
		else
			action.run();
	}

	function confirm() {
		const a = root.asking;
		root.asking = null;
		if (a)
			a.run();
	}

	trigger: PowerIcon {
		// A ring reads larger than the line glyphs beside it at the same
		// height, so it is drawn a little smaller.
		height: Theme.barIconSize - 2
		width: height
		color: Theme.glassTextPrimary
		opacity: root.active ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}
	}

	IpcHandler {
		target: "power"

		function toggle(): void {
			root.open = !root.open;
		}

		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}

		// The path a row takes: lock, suspend, logout, restart, poweroff.
		// The last three only ask; nothing here powers anything off.
		function choose(key: string): void {
			root.perform(key);
		}

		// The sheet's way out, for when the keyboard is not.
		function cancel(): void {
			root.asking = null;
		}
	}

	// The rows.
	Column {
		width: parent.width
		spacing: 2

		Repeater {
			model: root.actions

			Rectangle {
				id: row

				required property var modelData
				required property int index

				// A rule between what is harmless and what closes things.
				readonly property bool firstOfLeaving: index === 2

				width: parent.width
				height: 38 + (firstOfLeaving ? 9 : 0)
				color: "transparent"

				Rectangle {
					visible: row.firstOfLeaving
					y: 4
					x: 8
					width: parent.width - 16
					height: 1
					color: Theme.glassControlBorder
				}

				Rectangle {
					anchors.bottom: parent.bottom
					width: parent.width
					height: 38
					radius: Theme.radiusPill
					color: rowMouse.containsMouse ? Theme.glassControlHover : "transparent"

					Behavior on color {
						ColorAnimation { duration: 120 }
					}

					Row {
						anchors {
							left: parent.left
							right: parent.right
							leftMargin: 6
							rightMargin: 10
							verticalCenter: parent.verticalCenter
						}

						spacing: 10

						Lens {
							id: disc

							anchors.verticalCenter: parent.verticalCenter
							width: 26
							height: 26
							sheen: false

							PowerIcon {
								anchors.centerIn: parent
								width: 16
								height: 16
								kind: row.modelData.glyph
								lineWidth: Theme.markLine
								color: Theme.fileInk
							}
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width - disc.width - 10 - hint.width
							text: row.modelData.label
							font.pixelSize: Theme.fontTitle
							font.weight: Font.DemiBold
							color: Theme.glassTextPrimary
						}

						Text {
							id: hint

							anchors.verticalCenter: parent.verticalCenter
							text: row.modelData.hint
							font.pixelSize: Theme.fontCaption
							font.weight: Font.DemiBold
							opacity: 0.6
							color: Theme.glassTextPrimary
						}
					}

					MouseArea {
						id: rowMouse

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.perform(row.modelData.key)
					}
				}
			}
		}
	}

	// The question, over the whole screen like any sheet.
	PanelWindow {
		id: sheetWindow

		visible: root.asking !== null || dialog.sheet.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:power-confirm"
		WlrLayershell.keyboardFocus: root.asking !== null ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: dialog.sheet
			radius: Theme.radiusPanel
		}

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.asking !== null
			title: root.asking?.title ?? ""
			body: root.asking?.body ?? ""

			icon: Lens {
				width: 44
				height: 44
				sheen: false

				PowerIcon {
					anchors.centerIn: parent
					width: 22
					height: 22
					lineWidth: Theme.markLine * 1.3
					kind: root.asking?.glyph ?? "power"
					color: Theme.calcInk
				}
			}

			Item {
				id: keys

				width: parent.width
				height: buttons.height
				focus: true

				Keys.onPressed: event => {
					if (event.key === Qt.Key_Escape) {
						root.asking = null;
						event.accepted = true;
					} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						root.confirm();
						event.accepted = true;
					}
				}

				Row {
					id: buttons

					anchors.right: parent.right
					spacing: Theme.spacingS

					DialogButton {
						text: "Cancel"
						onClicked: root.asking = null
					}

					DialogButton {
						text: root.asking?.verb ?? ""
						variant: "destructive"
						onClicked: root.confirm()
					}
				}
			}
		}

		// The sheet takes the keyboard the moment it appears.
		onVisibleChanged: if (visible) keys.forceActiveFocus()
	}
}
