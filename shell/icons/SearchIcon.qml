import QtQuick
import QtQuick.Shapes

// A magnifier: the launcher's search disc, Files' and Groma Store's search
// fields, and the network picker.
//
// Drawn on the shared 24-unit grid. Ring and handle together span 3..21 each
// way, so the mark is centred on the grid - and on whatever disc holds it -
// rather than the ring alone.
Item {
	id: icon

	property color color: "#ffffff"
	// The stroke in pixels as drawn. 0 keeps the grid's 2 units, which thins
	// with the glyph; inside a disc it is set, to match the marks beside it.
	property real lineWidth: 0

	readonly property real baseWidth: 24
	readonly property real baseHeight: 24
	readonly property real aspect: icon.baseWidth / icon.baseHeight
	readonly property real units: icon.lineWidth > 0 ? icon.lineWidth * icon.baseWidth / Math.max(1, icon.width) : 2

	implicitWidth: 16
	implicitHeight: 16

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
				strokeWidth: icon.units
				fillColor: "transparent"

				PathAngleArc {
					centerX: 10.5; centerY: 10.5
					radiusX: 6.5; radiusY: 6.5
					startAngle: 0; sweepAngle: 360
				}
			}

			// The handle, leaving the rim on the diagonal through the ring's
			// centre, so it reads as one object rather than a line beside a
			// circle.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 15.1; startY: 15.1
				PathLine { x: 20; y: 20 }
			}
		}
	}
}
