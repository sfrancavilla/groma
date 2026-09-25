import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's Bluetooth readout, and the tile it opens.
//
// Built on the same shapes as the Wi-Fi tile: a radio switch, what you are
// connected to given a card of its own, then what else is known.
BarPopup {
	id: root

	// The devices sheet, supplied by whoever built the bar so this does not
	// have to own a window.
	property var dialog: null

	// The Nothing vendor channel, when a pair is connected: left, right and
	// case where bluez has one number for all three.
	property var ear: null

	function budBattery(device) {
		return root.ear?.battery?.[device.address] ?? null;
	}

	readonly property var adapter: Bluetooth.defaultAdapter ?? null
	readonly property bool enabled: root.adapter?.enabled ?? false

	readonly property var devices: Bluetooth.devices?.values ?? []

	readonly property var connected:
		root.devices.filter(device => device.connected)

	// Known but not in use. Sorted so the list does not reorder itself as
	// devices come and go from range.
	readonly property var known: root.devices
		.filter(device => (device.paired || device.bonded) && !device.connected)
		.sort((a, b) => a.name.localeCompare(b.name))

	function label(device) {
		return device.name !== "" ? device.name : device.address;
	}

	// The battery of a connected device, where it reports one. Headphones and
	// mice usually do; a speaker usually does not.
	function batteryText(device) {
		if (!device.batteryAvailable)
			return "";

		return `${Math.round(device.battery * 100)}%`;
	}

	name: "bluetooth"
	title: "Bluetooth"

	trailing: !root.enabled ? "Off"
		: root.connected.length === 1 ? root.label(root.connected[0])
		: root.connected.length > 1 ? `${root.connected.length} connected`
		: root.known.length > 0 ? "Not connected"
		: "No devices"

	trigger: BluetoothIcon {
		height: Theme.barIconHeight
		width: height * aspect

		crossed: !root.enabled

		color: root.enabled ? Theme.glassTextPrimary : Theme.glassTextMuted
		opacity: root.active ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}
	}

	IpcHandler {
		target: "bluetooth"

		function toggle(): void {
			root.open = !root.open;
		}

		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}

		function radio(on: string): void {
			if (root.adapter)
				root.adapter.enabled = on !== "off";
		}

		function devices(): void {
			root.dialog?.show();
			root.open = false;
		}

		// The way out of a sheet that holds the keyboard.
		function close(): void {
			root.dialog?.close();
		}
	}

	// The radio. A switch rather than a chip: two states, no third.
	Item {
		width: parent.width
		height: radioSwitch.height

		Text {
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			text: "Bluetooth radio"
			font.pixelSize: Theme.fontBody
			color: Theme.glassTextPrimary
		}

		Switch {
			id: radioSwitch

			anchors.right: parent.right
			checked: root.enabled
			onToggled: if (root.adapter)
				root.adapter.enabled = !root.adapter.enabled
		}
	}

	Text {
		width: parent.width
		visible: root.enabled && root.connected.length > 0
		text: "CONNECTED"
		font.pixelSize: 10
		font.bold: true
		font.letterSpacing: 0.6
		opacity: 0.6
		color: Theme.glassTextPrimary
	}

	// Whatever is connected, given a card each: it is the answer to the
	// question the tile was opened to ask.
	Column {
		width: parent.width
		spacing: Theme.spacingXs + 2
		visible: root.enabled && root.connected.length > 0

		Repeater {
			model: root.connected

			Rectangle {
				id: card

				required property var modelData

				width: parent.width
				height: 46
				radius: 14

				readonly property bool busy: card.modelData.state
					=== BluetoothDeviceState.Disconnecting

				// Pointing at it is how anyone finds out what it does, so
				// pointing at it is when it says.
				readonly property bool offering:
					cardMouse.containsMouse && !card.busy

				color: card.offering
					? Theme.glassControlStrongHover : Theme.glassChipActive
				border.width: 1
				border.color: Theme.glassTrackBorderFocus

				Behavior on color {
					ColorAnimation { duration: 120 }
				}

				Column {
					anchors {
						left: parent.left
						leftMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					spacing: 2

					Text {
						text: root.label(card.modelData)
						font.pixelSize: Theme.fontBody
						font.bold: true
						color: Theme.glassTextPrimary
					}

					Text {
						text: {
							if (card.busy)
								return "Disconnecting…";

							// The buds' own figures, whichever of them are talking:
							// a docked bud drops out of reports until it is
							// taken out again.
							const buds = root.budBattery(card.modelData);
							const parts = [];
							if (buds) {
								if (buds.left !== undefined) parts.push(`L ${buds.left}%`);
								if (buds.right !== undefined) parts.push(`R ${buds.right}%`);
								if (buds.case !== undefined) parts.push(`Case ${buds.case}%`);
							}
							if (parts.length > 0)
								return parts.join(" · ");

							const battery = root.batteryText(card.modelData);

							return battery !== ""
								? `Connected · ${battery}` : "Connected";
						}

						font.pixelSize: Theme.fontCaption
						opacity: 0.75
						color: Theme.glassTextPrimary
					}
				}

				Row {
					anchors {
						right: parent.right
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					spacing: Theme.spacingS

					Chip {
						anchors.verticalCenter: parent.verticalCenter
						visible: card.offering
						text: "Disconnect"

						// Takes the click itself as well as the card beneath
						// it. Two targets for one action is fine when missing
						// the small one still hits the large one.
						onClicked: card.modelData.connected = false
					}

					// Only for devices that report one. A speaker usually does
					// not, and an empty track would read as a flat battery.
					LevelPill {
						id: pill

						// The lower of the two buds: the one that decides how
						// long the pair lasts.
						readonly property var buds: root.budBattery(card.modelData)
						readonly property real level: {
							const levels = [];
							if (pill.buds?.left !== undefined) levels.push(pill.buds.left);
							if (pill.buds?.right !== undefined) levels.push(pill.buds.right);
							return levels.length > 0
								? Math.min(...levels) / 100 : card.modelData.battery;
						}

						anchors.verticalCenter: parent.verticalCenter
						visible: !card.offering
							&& (pill.buds !== null || card.modelData.batteryAvailable)
						value: pill.level
						fillColor: pill.level <= 0.2
							? Theme.glassFillWarning : Theme.glassTrackFill
					}

					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						visible: !card.offering
						width: 6
						height: 6
						radius: 3
						color: Theme.success
					}
				}

				MouseArea {
					id: cardMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: card.modelData.connected = false
				}
			}
		}
	}

	Text {
		width: parent.width
		visible: root.enabled && root.known.length > 0
		text: "MY DEVICES"
		font.pixelSize: 10
		font.bold: true
		font.letterSpacing: 0.6
		opacity: 0.6
		color: Theme.glassTextPrimary
	}

	Column {
		width: parent.width
		spacing: Theme.spacingXs + 2
		visible: root.enabled && root.known.length > 0

		Repeater {
			model: root.known

			BluetoothRow {
				required property var modelData

				width: parent.width
				device: modelData

				onActivated: modelData.connected = true
			}
		}
	}

	// Nothing paired yet, which is the state a new machine is in. Without this
	// the tile is a switch and a void.
	Text {
		width: parent.width
		visible: root.enabled && root.connected.length === 0
			&& root.known.length === 0
		wrapMode: Text.WordWrap
		text: "No paired devices yet."
		font.pixelSize: Theme.fontCaption
		opacity: 0.6
		color: Theme.glassTextPrimary
	}

	DialogButton {
		width: parent.width
		visible: root.enabled
		text: "Other Devices…"

		onClicked: {
			// Before closing the tile, for the same reason the Wi-Fi tile
			// does: this runs on the tile's own surface.
			root.dialog?.show();
			root.open = false;
		}
	}
}
