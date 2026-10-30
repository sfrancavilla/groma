import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick
import ".."
import "../icons"
import "../icons/devices.js" as Devices
import "../ui"

// The bar's Bluetooth readout, and the tile it opens.
//
// Built on the same shapes as the Wi-Fi tile: a radio switch, what you are
// connected to first, then what else is known - rows drawn as the system
// card draws its parts.
BarPopup {
	id: root

	// The devices sheet, supplied by whoever built the bar so this does not
	// have to own a window.
	property var dialog: null

	// A contract for integrations: anything with a `battery` map keyed by
	// device address, each entry { left, right, case } in percent, any of
	// them absent. Bluez has one number per device; a maker's own channel may
	// have three. This tile does not know or care whose channel.
	property var batteryDetail: null

	function budBattery(device) {
		return root.batteryDetail?.battery?.[device.address] ?? null;
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

	name: "bluetooth"
	title: "Bluetooth"
	// The system card's width: a connected device carries a figure and a
	// meter.
	cardWidth: Theme.tileWidthWide

	trailing: !root.enabled ? "Off"
		: root.connected.length === 1 ? root.label(root.connected[0])
		: root.connected.length > 1 ? `${root.connected.length} connected`
		: root.known.length > 0 ? "Not connected"
		: "No devices"

	trigger: BluetoothIcon {
		height: Theme.barIconSize
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
		enabled: root.hasIpc

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
			anchors.leftMargin: 8
			anchors.verticalCenter: parent.verticalCenter
			text: "Bluetooth radio"
			font.pixelSize: Theme.fontBody
			color: Theme.glassTextPrimary
		}

		// In line with the figures and switches in the rows below.
		Switch {
			id: radioSwitch

			anchors.right: parent.right
			anchors.rightMargin: 4
			checked: root.enabled
			onToggled: if (root.adapter)
				root.adapter.enabled = !root.adapter.enabled
		}
	}

	// Whatever is connected, first: it is the answer to the question the
	// tile was opened to ask. Its battery reads as the system card's
	// figures do.
	Column {
		width: parent.width
		spacing: 0
		visible: root.enabled && root.connected.length > 0

		Repeater {
			model: root.connected

			CardRow {
				id: card

				required property var modelData
				required property int index

				readonly property bool busy: card.modelData.state
					=== BluetoothDeviceState.Disconnecting

				// Pointing at it is how anyone finds out what it does, so
				// pointing at it is when it says.
				readonly property bool offering: card.hovered && !card.busy

				// The lower of the two buds: the one that decides how long
				// the pair lasts. Otherwise what bluez has, if anything - a
				// speaker usually reports nothing, and an empty track would
				// read as a flat battery.
				readonly property var buds: root.budBattery(card.modelData)
				readonly property real level: {
					const levels = [];
					if (card.buds?.left !== undefined) levels.push(card.buds.left);
					if (card.buds?.right !== undefined) levels.push(card.buds.right);
					return levels.length > 0
						? Math.min(...levels) / 100 : card.modelData.battery;
				}
				readonly property bool hasLevel: card.buds !== null
					|| card.modelData.batteryAvailable

				rule: card.index > 0 ? "dashed" : "none"
				interactive: true
				rowHeight: 48
				markOpacity: 1
				title: root.label(card.modelData)
				detail: {
					if (card.busy)
						return "Disconnecting…";

					// The buds' own figures, whichever of them are talking:
					// a docked bud drops out of reports until it is taken out
					// again.
					const parts = [];
					if (card.buds) {
						if (card.buds.left !== undefined) parts.push(`L ${card.buds.left}%`);
						if (card.buds.right !== undefined) parts.push(`R ${card.buds.right}%`);
						if (card.buds.case !== undefined) parts.push(`Case ${card.buds.case}%`);
					}

					return parts.length > 0 ? parts.join(" · ") : "Connected";
				}

				mark: DeviceIcon {
					width: Theme.rowMark
					height: Theme.rowMark
					kind: Devices.kindFor(card.modelData.icon)
					color: Theme.glassTextPrimary
				}

				onClicked: card.modelData.connected = false

				Chip {
					anchors.verticalCenter: parent.verticalCenter
					visible: card.offering
					text: "Disconnect"

					// Takes the click itself as well as the row beneath it.
					// Two targets for one action is fine when missing the
					// small one still hits the large one.
					onClicked: card.modelData.connected = false
				}

				Text {
					anchors.verticalCenter: parent.verticalCenter
					visible: !card.offering && card.hasLevel
					width: 40
					horizontalAlignment: Text.AlignRight
					text: Math.round(card.level * 100) + "%"
					font.pixelSize: Theme.fontTitle
					font.features: { "tnum": 1 }
					color: card.level <= 0.2 ? Theme.warning : Theme.glassTextPrimary
				}

				LevelPill {
					anchors.verticalCenter: parent.verticalCenter
					visible: !card.offering && card.hasLevel
					width: 104
					value: card.level
					fillColor: card.level <= 0.2
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
		}
	}

	Column {
		width: parent.width
		spacing: 2
		visible: root.enabled && root.known.length > 0

		SectionLabel {
			text: "MY DEVICES"
			bottomPadding: Theme.spacingXs
		}

		Repeater {
			model: root.known

			CardRow {
				id: known

				required property var modelData

				readonly property bool connecting: known.modelData.state
					=== BluetoothDeviceState.Connecting

				interactive: true
				title: root.label(known.modelData)

				mark: DeviceIcon {
					width: Theme.rowMark
					height: Theme.rowMark
					kind: Devices.kindFor(known.modelData.icon)
					color: Theme.glassTextPrimary
				}

				onClicked: known.modelData.connected = true

				Text {
					anchors.verticalCenter: parent.verticalCenter
					text: known.connecting ? "Connecting…" : "Not connected"
					font.pixelSize: Theme.fontCaption
					font.weight: Font.DemiBold
					opacity: 0.6
					color: Theme.glassTextPrimary
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
		text: "Other Devices…"

		onClicked: {
			// Before closing the tile, for the same reason the Wi-Fi tile
			// does: this runs on the tile's own surface.
			root.dialog?.show();
			root.open = false;
		}
	}
}
