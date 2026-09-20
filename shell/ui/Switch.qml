import QtQuick
import ".."

// An on/off switch: a track with the shell's lens as its knob.
//
// A chip reading "On" states the current value; a switch shows it as a
// position, which is the right affordance for something with exactly two
// states and no third option.
Item {
	id: control

	property bool checked: false

	signal toggled

	implicitWidth: 38
	implicitHeight: 22

	Rectangle {
		anchors.fill: parent
		radius: height / 2

		color: control.checked ? Theme.glassTrackFill
			: mouse.containsMouse ? Theme.glassControlHover
			: Theme.glassControl

		border.width: 1
		border.color: control.checked
			? Theme.glassTrackBorderFocus : Theme.glassControlBorder

		Behavior on color {
			ColorAnimation { duration: 140 }
		}
	}

	Lens {
		id: knob

		// Static: a sweeping highlight on a control this small reads as a
		// fault rather than as glass.
		sheen: false

		width: parent.height - 4
		height: width
		y: 2
		x: control.checked ? control.width - width - 2 : 2

		Behavior on x {
			NumberAnimation { duration: 160; easing.type: Easing.OutBack }
		}
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: control.toggled()
	}
}

