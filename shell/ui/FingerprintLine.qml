import QtQuick
import ".."
import "../icons"

// A fingerprint and a line beside it: what the reader wants, or what went
// wrong with the last touch. The lock screen and the polkit prompt each show
// one under their password field.
Row {
	id: line

	property string text: ""
	property bool isError: false

	readonly property color tone: line.isError ? Theme.warning : Theme.glassTextMuted

	spacing: Theme.spacingS

	FingerprintIcon {
		anchors.verticalCenter: parent.verticalCenter
		width: 13
		height: 14
		color: line.tone
	}

	Text {
		anchors.verticalCenter: parent.verticalCenter
		text: line.text
		font.pixelSize: Theme.fontCaption
		color: line.tone
	}
}
