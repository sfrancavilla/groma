import QtQuick
import ".."

// The 36px circle in a sheet's header: close on the picker, back on the join
// form. Both are the same disc with a different mark in it, which is what the
// design draws and what makes the two pages read as one sheet.
Rectangle {
	id: button

	// "close" | "back"
	property string glyph: "close"

	signal clicked

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
		width: 12
		height: 12
		visible: button.glyph === "close"

		Repeater {
			model: [45, -45]

			Rectangle {
				required property int modelData

				anchors.centerIn: parent
				width: 2
				height: 12
				radius: 1
				color: Theme.glassTextPrimary
				rotation: modelData
			}
		}
	}

	// A chevron: two sides of a square, turned to point left. Nudged right by
	// a pixel because the mark's visual centre sits left of its bounding box.
	Item {
		anchors.centerIn: parent
		anchors.horizontalCenterOffset: 2
		width: 9
		height: 9
		visible: button.glyph === "back"
		rotation: 45

		Rectangle {
			anchors.left: parent.left
			width: 2
			height: parent.height
			radius: 1
			color: Theme.glassTextPrimary
		}

		Rectangle {
			anchors.bottom: parent.bottom
			width: parent.width
			height: 2
			radius: 1
			color: Theme.glassTextPrimary
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
