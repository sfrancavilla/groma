import QtQuick
import QtQuick.Shapes

// A fingerprint: ridges as nested arches over a core, open at the foot.
Item {
	id: icon

	property color color: "#ffffff"

	readonly property real baseWidth: 12
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

			// Outermost ridge: the crown of the finger only.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 0.9
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 6; centerY: 6.6
					radiusX: 5.3; radiusY: 5.3
					startAngle: 205; sweepAngle: 130
				}
			}

			// Middle ridge, running down the left side.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 0.9
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 2.2; startY: 10.4

				PathLine { x: 2.2; y: 6.6 }
				PathArc {
					x: 9.8; y: 6.6
					radiusX: 3.8; radiusY: 3.8
				}
				PathLine { x: 9.8; y: 8.4 }
			}

			// Inner ridge, running down the right side.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 0.9
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 3.7; startY: 8.6

				PathLine { x: 3.7; y: 6.6 }
				PathArc {
					x: 8.3; y: 6.6
					radiusX: 2.3; radiusY: 2.3
				}
				PathLine { x: 8.3; y: 12.0 }
			}

			// Core.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 0.9
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 6; startY: 6.0

				PathLine { x: 6; y: 12.2 }
			}
		}
	}
}
