import QtQuick
import Quickshell.Bluetooth
import ".."
import "../icons"
import "../icons/devices.js" as Devices
import "../ui"

// One device in a list: its name, and what it is currently doing.
//
// Bluetooth has no equivalent of signal bars here - the API reports no RSSI -
// so the right-hand side carries state instead of strength.
Rectangle {
	id: row

	property var device: null

	property bool selected: false

	signal activated
	signal chosen

	readonly property bool connected: row.device?.connected ?? false
	readonly property bool known:
		(row.device?.paired ?? false) || (row.device?.bonded ?? false)

	readonly property string label: {
		const name = row.device?.name ?? "";
		return name !== "" ? name : (row.device?.address ?? "");
	}

	// One line, because the row has one line to give. Order matters: a device
	// that is connecting is also paired, and "Connecting…" is the useful half.
	readonly property string status: {
		if (row.device?.pairing ?? false)
			return "Pairing…";

		switch (row.device?.state) {
		case BluetoothDeviceState.Connecting:
			return "Connecting…";
		case BluetoothDeviceState.Disconnecting:
			return "Disconnecting…";
		case BluetoothDeviceState.Connected:
			return row.batteryText !== "" ? row.batteryText : "Connected";
		}

		// 8a's wording for a device we know, 8c's for one we do not.
		return row.known ? "Not connected" : "Ready to pair";
	}

	readonly property string kind: Devices.kindFor(row.device?.icon)

	readonly property string kindLabel: {
		switch (row.kind) {
		case "headphones": return "Headphones";
		case "speaker": return "Speaker";
		case "input": return "Input device";
		case "phone": return "Phone";
		}

		// 8c names the address where it cannot name the thing. Three octets
		// is enough to tell two of them apart.
		return (row.device?.address ?? "").split(":").slice(0, 3).join(":");
	}

	readonly property string batteryText: (row.device?.batteryAvailable ?? false)
		? `${Math.round((row.device?.battery ?? 0) * 100)}%` : ""

	height: 60
	radius: Theme.radiusRow

	color: row.selected ? Theme.glassChipSelected
		: row.connected ? Theme.glassChipActive
		: mouse.containsMouse ? Theme.glassControlHover
		: Theme.glassControl

	border.width: 1
	border.color: row.selected
		? Theme.glassChipSelectedBorder : Theme.glassControlBorder

	Behavior on color {
		ColorAnimation { duration: 120 }
	}

	// Drawn outside the row, so whatever holds these must not clip.
	Rectangle {
		anchors.fill: parent
		anchors.margins: -3
		z: -1
		radius: row.radius + 3
		color: Theme.glassRowRing
		visible: row.selected
	}

	// What it is, then its name over what it is and what it
	// is doing.
	Row {
		anchors {
			left: parent.left
			right: trailing.left
			leftMargin: Theme.spacingM
			rightMargin: Theme.spacingS
			verticalCenter: parent.verticalCenter
		}

		spacing: Theme.spacingM

		Lens {
			id: disc

			anchors.verticalCenter: parent.verticalCenter
			width: 36
			height: 36

			// The bright lens is for the picked row; the rest are plain glass,
			// so the disc carries the selection as well as the fill does.
			plain: !row.selected
			sheen: false

			DeviceIcon {
				anchors.centerIn: parent
				width: 18
				height: 18
				kind: row.kind
				color: row.selected
					? Theme.glassTextOnLens : Theme.glassTextPrimary
			}
		}

		Column {
			anchors.verticalCenter: parent.verticalCenter
			spacing: 2

			Text {
				text: row.label
				elide: Text.ElideRight
				width: Math.min(implicitWidth,
					disc.parent.width - disc.width - Theme.spacingM)
				font.pixelSize: Theme.fontLead
				font.weight: row.selected ? Font.Bold : Font.DemiBold
				color: Theme.glassTextPrimary
			}

			Text {
				text: row.status !== ""
					? `${row.kindLabel} · ${row.status}` : row.kindLabel
				font.pixelSize: Theme.fontBody
				font.weight: Font.DemiBold
				opacity: row.selected ? 0.8 : 0.75
				color: Theme.glassTextPrimary
			}
		}
	}

	Row {
		id: trailing

		anchors {
			right: parent.right
			rightMargin: Theme.spacingL - 2
			verticalCenter: parent.verticalCenter
		}

		spacing: Theme.spacingS

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			width: 6
			height: 6
			radius: 3
			visible: row.connected
			color: Theme.success
		}
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor

		// A click picks the row and the footer commits, for the same reason
		// the network picker does: a list you scroll is a list you can hit
		// the wrong row of.
		onClicked: row.chosen()
		onDoubleClicked: row.activated()
	}
}
