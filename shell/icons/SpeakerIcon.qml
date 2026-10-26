import QtQuick
import QtQuick.Shapes

// The speaker glyph, drawn rather than taken from an icon font.
//
// The design builds it from a box, a cone and two arcs. Here the box and cone
// are one outline, so it carries the same weight as the other bar glyphs - all
// drawn on the shared 24-unit grid with a 2-unit stroke.
Item {
	id: icon

	property color color: "#ffffff"
	// 0 = muted (a cross), 1 = one arc lit, 2 = both. An unlit arc stays
	// faintly drawn, as Wi-Fi's do.
	property int waves: 2

	readonly property color unlit: Qt.rgba(icon.color.r, icon.color.g, icon.color.b, icon.color.a * 0.3)

	// The paths below are drawn at this size; setting width or height scales
	// them rather than cropping, which absolute path coordinates would
	// otherwise do.
	readonly property real baseWidth: 24
	readonly property real baseHeight: 24
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

		// Box and cone as a single outline.
		ShapePath {
			strokeColor: icon.color
			strokeWidth: 2
			fillColor: "transparent"
			joinStyle: ShapePath.RoundJoin

			startX: 3; startY: 9.5
			PathLine { x: 7; y: 9.5 }
			PathLine { x: 11.5; y: 5 }
			PathLine { x: 11.5; y: 19 }
			PathLine { x: 7; y: 14.5 }
			PathLine { x: 3; y: 14.5 }
			PathLine { x: 3; y: 9.5 }
		}

		// Inner arc.
		ShapePath {
			strokeColor: icon.waves === 0 ? "transparent" : icon.color
			strokeWidth: 2
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			PathAngleArc {
				centerX: 12.5; centerY: 12
				radiusX: 4; radiusY: 4
				startAngle: -45; sweepAngle: 90
			}
		}

		// Outer arc.
		ShapePath {
			strokeColor: icon.waves === 0 ? "transparent" : icon.waves >= 2 ? icon.color : icon.unlit
			strokeWidth: 2
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			PathAngleArc {
				centerX: 12.5; centerY: 12
				radiusX: 8; radiusY: 8
				startAngle: -50; sweepAngle: 100
			}
		}

		// Muted: a cross where the waves would be.
		ShapePath {
			strokeColor: icon.waves === 0 ? icon.color : "transparent"
			strokeWidth: 2
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			startX: 15.5; startY: 9.5
			PathLine { x: 20.5; y: 14.5 }
		}

		ShapePath {
			strokeColor: icon.waves === 0 ? icon.color : "transparent"
			strokeWidth: 2
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap

			startX: 20.5; startY: 9.5
			PathLine { x: 15.5; y: 14.5 }
		}
	}
}
