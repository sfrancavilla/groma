import QtQuick
import QtQuick.Shapes

// A padlock, marking a network that will want a password.
Item {
	id: icon

	property color color: "#ffffff"

	readonly property real baseWidth: 9
	readonly property real baseHeight: 11
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

		// Shackle.
		Shape {
			anchors.fill: parent
			preferredRendererType: Shape.CurveRenderer

			ShapePath {
				strokeColor: icon.color
				strokeWidth: 1.3
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 4.5; centerY: 4.2
					radiusX: 2.6; radiusY: 2.6
					startAngle: 180; sweepAngle: 180
				}
			}
		}

		// Body.
		Rectangle {
			x: 0.5
			y: 4.4
			width: 8
			height: 6.2
			radius: 1.4
			color: icon.color
		}
	}
}
