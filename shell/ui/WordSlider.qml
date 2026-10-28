import QtQuick
import ".."

// A slider between two words - "Slower" and "Faster" - for a setting whose
// number would mean nothing to anyone: a pointer's speed, a key's repeat.
Row {
	id: control

	property string low: ""
	property string high: ""
	property real value: 0
	property real trackWidth: 240

	signal moved(real position)

	spacing: 12

	Text {
		anchors.verticalCenter: parent.verticalCenter
		text: control.low
		font.pixelSize: Theme.fontCaption
		opacity: 0.8
		color: Theme.glassTextPrimary
	}

	Slider {
		anchors.verticalCenter: parent.verticalCenter
		width: control.trackWidth
		value: control.value
		onMoved: v => control.moved(v)
	}

	Text {
		anchors.verticalCenter: parent.verticalCenter
		text: control.high
		font.pixelSize: Theme.fontCaption
		opacity: 0.8
		color: Theme.glassTextPrimary
	}
}
