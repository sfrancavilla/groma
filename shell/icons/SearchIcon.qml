import QtQuick
import QtQuick.Shapes

// A magnifier, marking the search track in the network picker.
Item {
	id: icon

	property color color: "#ffffff"

	readonly property real baseWidth: 13
	readonly property real baseHeight: 13
	readonly property real aspect: icon.baseWidth / icon.baseHeight

	implicitWidth: icon.baseWidth
	implicitHeight: icon.baseHeight

	Item {
		width: icon.baseWidth
		height: icon.baseHeight

		transform: Scale {
			xScale: icon.width / icon.baseWidth
			yScale: icon.height / icon.baseHeight
		}

		Shape {
			anchors.fill: parent
			preferredRendererType: Shape.CurveRenderer

			// The lens.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 1.6
				fillColor: "transparent"

				PathAngleArc {
					centerX: 5.4; centerY: 5.4
					radiusX: 4.2; radiusY: 4.2
					startAngle: 0; sweepAngle: 360
				}
			}

			// The handle, leaving the rim at 45 degrees so it reads as one
			// stroke rather than a line touching a circle.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 1.6
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 8.6; startY: 8.6
				PathLine { x: 12; y: 12 }
			}
		}
	}
}
