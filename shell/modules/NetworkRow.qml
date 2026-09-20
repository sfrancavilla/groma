import QtQuick
import ".."
import "../icons"
import "../ui"

// One network in a list: name, a lock if it is secured, and its strength.
//
// Wanted in the tile and in the full list, and the two would have drifted.
Rectangle {
	id: row

	// The Quickshell Network object.
	property var network: null
	// What the nmcli scan knows about it, if anything.
	property var detail: null
	property int bars: 0

	signal activated

	readonly property bool known: row.network?.known ?? false
	readonly property bool connected: row.network?.connected ?? false

	height: 32
	radius: 14

	color: row.connected ? Theme.glassChipActive
		: mouse.containsMouse ? Theme.glassControlHover
		: Theme.glassControl

	border.width: 1
	border.color: Theme.glassControlBorder

	Behavior on color {
		ColorAnimation { duration: 120 }
	}

	Row {
		anchors {
			left: parent.left
			right: strength.left
			leftMargin: Theme.spacingM
			rightMargin: Theme.spacingS
			verticalCenter: parent.verticalCenter
		}

		spacing: Theme.spacingS - 2

		Text {
			anchors.verticalCenter: parent.verticalCenter
			text: row.network?.name ?? ""
			elide: Text.ElideRight
			width: Math.min(implicitWidth, parent.width - 16)
			font.pixelSize: Theme.fontCaption
			color: Theme.glassTextPrimary
		}

		LockIcon {
			anchors.verticalCenter: parent.verticalCenter
			visible: row.detail?.secured ?? false
			opacity: 0.6
			color: Theme.glassTextPrimary
		}
	}

	SignalBars {
		id: strength

		anchors {
			right: parent.right
			rightMargin: Theme.spacingM
			verticalCenter: parent.verticalCenter
		}

		level: row.bars
		color: Theme.glassTextPrimary
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: row.activated()
	}
}
