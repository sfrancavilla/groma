import QtQuick
import QtQuick.Shapes

// An eye, for revealing a password. Struck through when the secret is showing,
// because the control says what a click will do next.
Item {
	id: icon

	property color color: "#ffffff"
	property bool crossed: false

	readonly property real baseWidth: 16
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

		Shape {
			anchors.fill: parent
			preferredRendererType: Shape.CurveRenderer

			// Outline.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 1.3
				fillColor: "transparent"

				PathAngleArc {
					centerX: 8; centerY: 5.5
					radiusX: 7.2; radiusY: 4.8
					startAngle: 0; sweepAngle: 360
				}
			}

			// Pupil.
			ShapePath {
				strokeWidth: 0
				fillColor: icon.color

				PathAngleArc {
					centerX: 8; centerY: 5.5
					radiusX: 2.1; radiusY: 2.1
					startAngle: 0; sweepAngle: 360
				}
			}

			ShapePath {
				strokeColor: icon.crossed ? icon.color : "transparent"
				strokeWidth: 1.3
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 1.5; startY: 10
				PathLine { x: 14.5; y: 1 }
			}
		}
	}
}
