import QtQuick
import QtQuick.Shapes
import ".."

// A checkbox and its label, clickable as one thing.
Item {
	id: control

	property bool checked: false
	property alias text: label.text

	signal toggled

	implicitWidth: box.width + Theme.spacingS + label.implicitWidth
	implicitHeight: Math.max(box.height, label.implicitHeight)

	Rectangle {
		id: box

		anchors.verticalCenter: parent.verticalCenter
		width: 16
		height: 16
		radius: 5

		color: control.checked ? Theme.chipPrimary
			: mouse.containsMouse ? Theme.glassControlHover
			: Theme.glassControl

		border.width: 1
		border.color: control.checked
			? Theme.chipPrimaryBorder : Theme.glassControlBorder

		Behavior on color {
			ColorAnimation { duration: 120 }
		}

		// The tick is dark: the box is bright when checked.
		Shape {
			anchors.fill: parent
			visible: control.checked
			preferredRendererType: Shape.CurveRenderer

			ShapePath {
				strokeColor: Theme.glassTextOnLens
				strokeWidth: 2
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 4; startY: 8.5
				PathLine { x: 6.8; y: 11.2 }
				PathLine { x: 12; y: 5 }
			}
		}
	}

	Text {
		id: label

		anchors {
			left: box.right
			leftMargin: Theme.spacingS
			verticalCenter: parent.verticalCenter
		}

		font.pixelSize: Theme.fontCaption
		opacity: 0.85
		color: Theme.glassTextPrimary
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: control.toggled()
	}
}
