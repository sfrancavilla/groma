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

				color: Theme.glassChipActive
				border.width: 1
				border.color: Theme.glassTrackBorderFocus

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
							if (card.modelData.state
									=== BluetoothDeviceState.Disconnecting)
								return "Disconnecting…";

							const battery = root.batteryText(card.modelData);

							return battery !== ""
								? `Connected · ${battery}` : "Connected";
						}

						font.pixelSize: Theme.fontCaption
						opacity: 0.75
						color: Theme.glassTextPrimary
					}
				}

				Rectangle {
					anchors {
						right: parent.right
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					width: 6
					height: 6
					radius: 3
					color: Theme.success
				}

				MouseArea {
					anchors.fill: parent
					cursorShape: Qt.PointingHandCursor
					onClicked: card.modelData.connected = false
				}
			}
		}
	}

	Text {
		width: parent.width
		visible: root.enabled && root.known.length > 0
		text: "PAIRED DEVICES"
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

			Rectangle {
				id: row

				required property var modelData

				readonly property bool busy: row.modelData.state
					=== BluetoothDeviceState.Connecting

				width: parent.width
				height: 32
				radius: 14

				color: rowMouse.containsMouse
					? Theme.glassControlHover : Theme.glassControl
				border.width: 1
				border.color: Theme.glassControlBorder

				Behavior on color {
					ColorAnimation { duration: 120 }
				}

				Text {
					anchors {
						left: parent.left
						right: state.left
						leftMargin: Theme.spacingM
						rightMargin: Theme.spacingS
						verticalCenter: parent.verticalCenter
					}

					text: root.label(row.modelData)
					elide: Text.ElideRight
					font.pixelSize: Theme.fontCaption
					color: Theme.glassTextPrimary
				}

				Text {
					id: state

					anchors {
						right: parent.right
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					text: row.busy ? "Connecting…" : ""
					font.pixelSize: Theme.fontCaption
					opacity: 0.7
					color: Theme.glassTextPrimary
				}

				MouseArea {
					id: rowMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: row.modelData.connected = true
				}
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
		text: "All Devices…"

		onClicked: {
			// Before closing the tile, for the same reason the Wi-Fi tile
			// does: this runs on the tile's own surface.
			root.dialog?.show();
			root.open = false;
		}
	}
}
