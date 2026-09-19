import QtQuick

// A small push button. QtQuick has no button of its own, so a button is a
// rectangle with a label and a MouseArea on top of it.
// `enabled` comes from Item and already disables the MouseArea for us.
Rectangle {
	id: button

	property alias text: label.text
	property bool primary: false

	signal clicked

	implicitWidth: label.implicitWidth + 28
	implicitHeight: 32
	radius: 6

	opacity: button.enabled ? 1.0 : 0.4

	color: button.primary
		? (mouse.containsMouse ? "#222222" : "#444444")
		: (mouse.containsMouse ? "#dddddd" : "#f2f2f2")

	border.width: button.primary ? 0 : 1
	border.color: "#cccccc"

	Text {
		id: label

		anchors.centerIn: parent
		color: button.primary ? "#ffffff" : "#000000"
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: button.clicked()
	}
}
