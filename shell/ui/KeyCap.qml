import QtQuick
import ".."

// A key, drawn as the small chip the design uses for "↵" and "Esc": a hint
// of what a press will do, next to the word for it.
Rectangle {
	id: cap

	property alias text: label.text

	implicitWidth: label.implicitWidth + 14
	implicitHeight: 20
	radius: 6

	color: Qt.rgba(1, 1, 1, 0.18)
	border.width: 1
	border.color: Qt.rgba(1, 1, 1, 0.32)

	Text {
		id: label

		anchors.centerIn: parent
		font.pixelSize: Theme.fontCaption
		font.weight: Font.DemiBold
		color: Theme.glassTextPrimary
	}
}
