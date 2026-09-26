import QtQuick
import ".."

// A pill: one option among a few, the chosen one brighter.
Rectangle {
	id: chip

	property alias text: label.text
	property bool active: false

	// A coloured chip, for a state worth a colour: the launcher's track shows
	// the mode it recognised in amber for calculation and green for a command.
	property color accent: "transparent"

	signal clicked

	// A Rectangle is zero-wide until told otherwise, so a Chip with no width
	// set rendered as nothing at all. Callers that lay chips out in a grid
	// still set their own.
	implicitWidth: label.implicitWidth + Theme.spacingM * 2

	height: Theme.chipHeight
	radius: Theme.radiusPill

	color: chip.accent.a > 0 ? Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.38)
		: chip.active ? Theme.glassChipActive
		: mouse.containsMouse ? Theme.glassControlHover
		: Theme.glassChip

	border.width: chip.accent.a > 0 ? 1 : 0
	border.color: Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.6)

	Behavior on color {
		ColorAnimation { duration: 120 }
	}

	Text {
		id: label

		anchors {
			fill: parent
			leftMargin: Theme.spacingS
			rightMargin: Theme.spacingS
		}

		horizontalAlignment: Text.AlignHCenter
		verticalAlignment: Text.AlignVCenter
		elide: Text.ElideRight
		font.pixelSize: Theme.fontCaption
		// The chosen chip is marked by its brighter fill, not by its weight.
		opacity: chip.active ? 1.0 : 0.8
		color: Theme.glassTextPrimary
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: chip.clicked()
	}
}
