import QtQuick
import ".."

// A level as a small glass track with a bead on it - the design's per-device
// battery in the Bluetooth tile.
//
// Not a small Slider: that one is 44 high because it is grabbed and dragged,
// and everything about it is sized for a thumb. This is 14 high and is only
// ever read.
Item {
	id: pill

	// 0..1
	property real value: 0
	property color fillColor: Theme.glassTrackFill

	implicitWidth: 44
	implicitHeight: 14

	Rectangle {
		anchors.fill: parent
		radius: height / 2
		color: Theme.glassTrack
		border.width: 1
		border.color: Theme.glassTrackBorder
		clip: true

		Rectangle {
			anchors {
				left: parent.left
				top: parent.top
				bottom: parent.bottom
			}

			width: parent.width * Math.max(0, Math.min(1, pill.value))
			radius: height / 2
			color: pill.fillColor

			Behavior on width {
				NumberAnimation { duration: 180 }
			}
		}
	}

	// The bead rides the end of the fill, and is the one part allowed outside
	// the clipped track so it reads as sitting on top of it.
	Rectangle {
		width: 10
		height: 10
		radius: 5

		anchors.verticalCenter: parent.verticalCenter
		x: Math.max(1, Math.min(pill.width - width - 1,
			pill.width * Math.max(0, Math.min(1, pill.value)) - width / 2))

		color: Theme.glassKnobCore
		border.width: 1
		border.color: Theme.glassKnobEdge

		Behavior on x {
			NumberAnimation { duration: 180 }
		}
	}
}
