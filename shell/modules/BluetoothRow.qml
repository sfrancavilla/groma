import QtQuick
import Quickshell.Bluetooth
import ".."
import "../ui"

// One device in a list: its name, and what it is currently doing.
//
// Bluetooth has no equivalent of signal bars here - the API reports no RSSI -
// so the right-hand side carries state instead of strength.
Rectangle {
	id: row

	property var device: null

	// The tile's row. Off, it is the sheet's: taller, larger type, selectable.
	property bool compact: true
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

		return row.known ? "Paired" : "";
	}

	readonly property string batteryText: (row.device?.batteryAvailable ?? false)
		? `${Math.round((row.device?.battery ?? 0) * 100)}%` : ""

	height: row.compact ? 32 : 42
	radius: row.compact ? 14 : Theme.radiusRow

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

	Text {
		anchors {
			left: parent.left
			right: trailing.left
			leftMargin: row.compact ? Theme.spacingM : Theme.spacingL - 2
			rightMargin: Theme.spacingS
			verticalCenter: parent.verticalCenter
		}

		text: row.label
		elide: Text.ElideRight
		font.pixelSize: row.compact ? Theme.fontCaption : Theme.fontLead
		font.weight: row.selected ? Font.Bold : Font.DemiBold
		color: Theme.glassTextPrimary
	}

	Row {
		id: trailing

		anchors {
			right: parent.right
			rightMargin: row.compact ? Theme.spacingM : Theme.spacingL - 2
			verticalCenter: parent.verticalCenter
		}

		spacing: Theme.spacingS

		Text {
			anchors.verticalCenter: parent.verticalCenter
			text: row.status
			visible: text !== ""
			font.pixelSize: row.compact ? Theme.fontCaption : Theme.fontBody
			font.weight: Font.DemiBold
			opacity: row.selected ? 0.8 : 0.7
			color: Theme.glassTextPrimary
		}

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

		// In the tile a click is the whole interaction. In the sheet it picks
		// the row and the footer commits, for the same reason the network
		// picker does: a list you scroll is a list you can hit the wrong row of.
		onClicked: row.compact ? row.activated() : row.chosen()
		onDoubleClicked: row.activated()
	}
}
