import QtQuick
import QtQuick.Shapes

// A battery outline with a nub, drawn as paths.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..1. Below zero the cell is left empty, which is how the design shows
	// the outline in the track.
	property real level: -1

	implicitWidth: 26
	implicitHeight: 11

	Shape {
		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer

		// Cell.
		ShapePath {
			strokeColor: icon.color
			strokeWidth: 1.5
			fillColor: "transparent"
			joinStyle: ShapePath.RoundJoin

			startX: 1.5; startY: 0.75
			PathLine { x: 19.5; y: 0.75 }
			PathArc { x: 21.25; y: 2.5; radiusX: 1.75; radiusY: 1.75 }
			PathLine { x: 21.25; y: 8.5 }
			PathArc { x: 19.5; y: 10.25; radiusX: 1.75; radiusY: 1.75 }
			PathLine { x: 1.5; y: 10.25 }
			PathArc { x: -0.25; y: 8.5; radiusX: 1.75; radiusY: 1.75 }
			PathLine { x: -0.25; y: 2.5 }
			PathArc { x: 1.5; y: 0.75; radiusX: 1.75; radiusY: 1.75 }
		}

		// Nub.
		ShapePath {
			strokeWidth: 0
			fillColor: icon.color

			startX: 22.5; startY: 3.5
			PathLine { x: 24.5; y: 3.5 }
			PathLine { x: 24.5; y: 7.5 }
			PathLine { x: 22.5; y: 7.5 }
			PathLine { x: 22.5; y: 3.5 }
		}
	}

	// Charge level, when asked for.
	Rectangle {
		visible: icon.level >= 0
		x: 1.75
		y: 2.5
		width: Math.max(0, (17.5) * Math.min(1, Math.max(0, icon.level)))
		height: 6
		radius: 1
		color: icon.color
	}
}
