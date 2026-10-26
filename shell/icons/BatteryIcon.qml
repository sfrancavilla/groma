import QtQuick
import QtQuick.Shapes

// A battery outline with a nub, drawn as paths, optionally filled to its
// charge level.
//
// Drawn on the shared 24-unit grid with a 2-unit stroke, like the other bar
// glyphs, so at one size they all carry the same weight. It is the one glyph
// wider than it is tall: 28 units, for the nub.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..1. Below zero the cell is left empty, which is how the design shows
	// the outline inside a slider track.
	property real level: -1

	// The paths below are drawn at this size; setting width or height scales
	// them rather than cropping, which absolute path coordinates would
	// otherwise do.
	readonly property real baseWidth: 28
	readonly property real baseHeight: 24
	readonly property real aspect: icon.baseWidth / icon.baseHeight

	// Where the cell sits, so whatever is laid over it - the charging bolt -
	// can be centred on the cell rather than on the cell and nub together.
	readonly property real cellCenterX: 12.5 * icon.width / icon.baseWidth
	readonly property real cellHeight: 12 * icon.height / icon.baseHeight

	implicitWidth: icon.baseWidth
	implicitHeight: icon.baseHeight

	// Outline and fill share one scale, or the charge level drifts out of the
	// cell as the icon is resized.
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

			// Cell.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 2
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin

				startX: 4.5; startY: 7
				PathLine { x: 20.5; y: 7 }
				PathArc { x: 23; y: 9.5; radiusX: 2.5; radiusY: 2.5 }
				PathLine { x: 23; y: 14.5 }
				PathArc { x: 20.5; y: 17; radiusX: 2.5; radiusY: 2.5 }
				PathLine { x: 4.5; y: 17 }
				PathArc { x: 2; y: 14.5; radiusX: 2.5; radiusY: 2.5 }
				PathLine { x: 2; y: 9.5 }
				PathArc { x: 4.5; y: 7; radiusX: 2.5; radiusY: 2.5 }
			}

			// Nub.
			ShapePath {
				strokeColor: icon.color
				strokeWidth: 2
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 26; startY: 10.5
				PathLine { x: 26; y: 13.5 }
			}
		}

		// Charge level, when asked for.
		Rectangle {
			visible: icon.level >= 0
			x: 4.5
			y: 9.5
			width: 16 * Math.min(1, Math.max(0, icon.level))
			height: 5
			radius: 1
			color: icon.color
		}
	}
}
