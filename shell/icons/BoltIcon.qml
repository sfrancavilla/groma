import QtQuick
import QtQuick.Shapes

// A charging bolt. Sits inside the lens, so it is drawn dark rather than white.
Item {
	id: icon

	property color color: "#1d6b3f"

	implicitWidth: 10
	implicitHeight: 16

	Shape {
		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer

		// The design's clip-path polygon, in path form.
		ShapePath {
			strokeWidth: 0
			fillColor: icon.color

			startX: icon.width * 0.55; startY: 0
			PathLine { x: icon.width * 0.15; y: icon.height * 0.55 }
			PathLine { x: icon.width * 0.48; y: icon.height * 0.55 }
			PathLine { x: icon.width * 0.40; y: icon.height }
			PathLine { x: icon.width * 0.85; y: icon.height * 0.42 }
			PathLine { x: icon.width * 0.52; y: icon.height * 0.42 }
		}
	}
}
