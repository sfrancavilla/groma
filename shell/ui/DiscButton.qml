import QtQuick
import ".."

// The 36px circle in a sheet's header: close on the picker, back on the join
// form. Both are the same disc with a different mark in it, which is what the
// design draws and what makes the two pages read as one sheet.
Rectangle {
	id: button

	// "close" | "back"
	property string glyph: "close"

	// The mark's colour. A toast resolves its own text colours from the
	// notification's urgency, so it cannot take the sheet's.
	property color markColor: Theme.glassTextPrimary

	signal clicked

	// The marks are drawn against a 36px disc and scale with it, so a smaller
	// button is a smaller button rather than a small disc with a full-size
	// cross in it.
	readonly property real scale36: button.width / 36

	implicitWidth: 36
	implicitHeight: 36
	width: implicitWidth
	height: implicitHeight
	radius: width / 2

	color: mouse.containsMouse ? Theme.glassControlHover : Theme.glassControl
	border.width: 1
	border.color: Theme.glassControlBorder

	Behavior on color {
		ColorAnimation { duration: 120 }
	}

	// A cross: two bars through the centre.
	Item {
		anchors.centerIn: parent
		width: 12 * button.scale36
		height: width
		visible: button.glyph === "close"

		Repeater {
			model: [45, -45]

			Rectangle {
				required property int modelData

				anchors.centerIn: parent
				width: 2 * button.scale36
				height: 12 * button.scale36
				radius: width / 2
				color: button.markColor
				rotation: modelData
			}
		}
	}

	// A chevron: two sides of a square, turned to point left. Nudged right by
	// a pixel because the mark's visual centre sits left of its bounding box.
	Item {
		anchors.centerIn: parent
		anchors.horizontalCenterOffset: 2 * button.scale36
		width: 9 * button.scale36
		height: width
		visible: button.glyph === "back"
		rotation: 45

		Rectangle {
			anchors.left: parent.left
			width: 2 * button.scale36
			height: parent.height
			radius: width / 2
			color: button.markColor
		}

		Rectangle {
			anchors.bottom: parent.bottom
			width: parent.width
			height: 2 * button.scale36
			radius: height / 2
			color: button.markColor
		}
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: button.clicked()
	}
}
