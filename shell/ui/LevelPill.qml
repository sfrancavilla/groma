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

	// Between the bead and the track's edge, all round.
	readonly property real inset: (pill.height - bead.height) / 2

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

			// Ends round the bead rather than at the value: its cap is then
			// concentric with the bead, and a low value is never a sliver
			// narrower than its own corners.
			width: bead.x + bead.width + pill.inset
			radius: height / 2
			color: pill.fillColor

			Behavior on width {
				NumberAnimation { duration: 180 }
			}
		}
	}

	// The bead rides the end of the fill, and is the one part allowed outside
	// the clipped track so it reads as sitting on top of it.
	//
	// Its centre travels between the centres of the track's two round ends,
	// so at 0 and 1 it sits in the middle of the curve rather than against it.
	Rectangle {
		id: bead

		width: 10
		height: 10
		radius: 5

		anchors.verticalCenter: parent.verticalCenter
		x: pill.inset + (pill.width - pill.height)
			* Math.max(0, Math.min(1, pill.value))

		color: Theme.glassKnobCore
		border.width: 1
		border.color: Theme.glassKnobEdge

		Behavior on x {
			NumberAnimation { duration: 180 }
		}
	}
}
