import QtQuick
import QtQuick.Shapes

// The speaker glyph, drawn rather than taken from an icon font.
//
// The design builds it from a box, a trapezoid and two arcs. CSS does the
// trapezoid with clip-path and the arcs with one-sided border-radius; here both
// are paths, which is closer to what they actually are.
Item {
	id: icon

	property color color: "#ffffff"
	// 0 = muted (a cross), 1 = one arc, 2 = both arcs.
	property int waves: 2

	// The paths below are drawn at this size; setting width or height scales
	// them rather than cropping, which absolute path coordinates would
	// otherwise do.
	readonly property real baseWidth: 18
	readonly property real baseHeight: 14
	readonly property real aspect: icon.baseWidth / icon.baseHeight

	implicitWidth: icon.baseWidth
	implicitHeight: icon.baseHeight

	Shape {
		width: icon.baseWidth
		height: icon.baseHeight
		preferredRendererType: Shape.CurveRenderer

		transform: Scale {
			xScale: icon.width / icon.baseWidth
			yScale: icon.height / icon.baseHeight
		}

		// Body and cone as a single outline.
		ShapePath {
			fillColor: icon.color
			strokeWidth: 0

			startX: 0; startY: 5
			PathLine { x: 3; y: 5 }
			PathLine { x: 10; y: 0 }
			PathLine { x: 10; y: 14 }
			PathLine { x: 3; y: 9 }
			PathLine { x: 0; y: 9 }
			PathLine { x: 0; y: 5 }
		}

		// Inner arc.
		ShapePath {
			strokeColor: icon.waves >= 1 ? icon.color : "transparent"
			strokeWidth: 1.5
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			PathAngleArc {
				centerX: 11; centerY: 7
				radiusX: 3; radiusY: 4
				startAngle: -60; sweepAngle: 120
			}
		}

		// Outer arc.
		ShapePath {
			strokeColor: icon.waves >= 2 ? icon.color : "transparent"
			strokeWidth: 1.5
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			PathAngleArc {
				centerX: 11; centerY: 7
				radiusX: 6; radiusY: 7
				startAngle: -55; sweepAngle: 110
			}
		}

		// Muted: a cross where the waves would be.
		ShapePath {
			strokeColor: icon.waves === 0 ? icon.color : "transparent"
			strokeWidth: 1.5
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			startX: 12; startY: 4
			PathLine { x: 18; y: 10 }
		}

		ShapePath {
			strokeColor: icon.waves === 0 ? icon.color : "transparent"
			strokeWidth: 1.5
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			startX: 18; startY: 4
			PathLine { x: 12; y: 10 }
		}
	}
}
