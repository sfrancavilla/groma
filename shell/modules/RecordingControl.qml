import QtQuick
import ".."

// The bar while the screen is being recorded: a red dot that breathes, and
// how long it has been. Clicking it stops the recording, as Print does.
Item {
	id: control

	property var capture: null

	readonly property bool recording: control.capture?.recording !== null && control.capture?.recording !== undefined

	visible: control.recording || (control.capture?.starting ?? false)
	implicitWidth: row.implicitWidth
	implicitHeight: Theme.chipHeight - 6

	Rectangle {
		anchors.fill: parent
		anchors.leftMargin: -Theme.spacingS
		anchors.rightMargin: -Theme.spacingS
		radius: height / 2
		color: mouse.containsMouse ? Theme.glassControlHover : "transparent"

		Behavior on color {
			ColorAnimation { duration: 120 }
		}
	}

	Row {
		id: row

		anchors.verticalCenter: parent.verticalCenter
		spacing: 6

		Rectangle {
			id: dot

			anchors.verticalCenter: parent.verticalCenter
			width: 9
			height: 9
			radius: 4.5
			color: Theme.danger

			SequentialAnimation on opacity {
				running: control.recording && !(control.capture?.stopping ?? false)
				loops: Animation.Infinite
				onRunningChanged: if (!running) dot.opacity = 1
				NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
				NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
			}
		}

		Text {
			anchors.verticalCenter: parent.verticalCenter
			text: (control.capture?.stopping ?? false) ? "Saving…"
				: control.recording ? control.capture.elapsed : "Starting…"
			font.pixelSize: Theme.fontBody
			font.features: { "tnum": 1 }
			color: Theme.glassTextPrimary
			style: Theme.glass ? Text.Raised : Text.Normal
			styleColor: Theme.glassTextShadow
		}
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		anchors.margins: -Theme.spacingS
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: control.capture?.stop()
	}
}
