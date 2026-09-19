import QtQuick
import QtQuick.Shapes

// The desktop's colour, painted inside a glass surface.
//
// A Wayland client cannot sample what is behind its own surface, so glass here
// can be blurred but never tinted by the desktop. This paints the same washes
// the wallpaper draws, offset by where the surface sits on screen, so the
// colour lines up with the real thing behind it. Not refraction - but the
// surface stops looking like a grey panel and starts looking transparent.
//
// Rounded-rect paths rather than Rectangles, because a Rectangle gradient is
// linear only, and children are not clipped to a parent's rounded corners.
Item {
	id: wash

	// Corner radius to clip to - match the surface this sits in.
	property real radius: 0
	// Where this surface sits within the wash field, and how big that field
	// is. For a fullscreen window, the item's own x/y and the screen size.
	property real originX: 0
	property real originY: 0
	property real fieldWidth: width
	property real fieldHeight: height
	// How much of the desktop's colour shows through the glass.
	property real strength: 0.38

	opacity: wash.strength

	Shape {
		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer
		asynchronous: true

		ShapePath {
			strokeWidth: 0

			fillGradient: RadialGradient {
				centerX: wash.fieldWidth * 0.15 - wash.originX
				centerY: wash.fieldHeight * 0.15 - wash.originY
				centerRadius: wash.fieldWidth * 0.75
				focalX: wash.fieldWidth * 0.15 - wash.originX
				focalY: wash.fieldHeight * 0.15 - wash.originY

				GradientStop { position: 0.0; color: Theme.desktopWashA }
				GradientStop { position: 0.55; color: "#00000000" }
			}

			startX: wash.radius; startY: 0
			PathLine { x: wash.width - wash.radius; y: 0 }
			PathArc { x: wash.width; y: wash.radius; radiusX: wash.radius; radiusY: wash.radius }
			PathLine { x: wash.width; y: wash.height - wash.radius }
			PathArc { x: wash.width - wash.radius; y: wash.height; radiusX: wash.radius; radiusY: wash.radius }
			PathLine { x: wash.radius; y: wash.height }
			PathArc { x: 0; y: wash.height - wash.radius; radiusX: wash.radius; radiusY: wash.radius }
			PathLine { x: 0; y: wash.radius }
			PathArc { x: wash.radius; y: 0; radiusX: wash.radius; radiusY: wash.radius }
		}

		ShapePath {
			strokeWidth: 0

			fillGradient: RadialGradient {
				centerX: wash.fieldWidth * 0.85 - wash.originX
				centerY: wash.fieldHeight * 0.78 - wash.originY
				centerRadius: wash.fieldWidth * 0.70
				focalX: wash.fieldWidth * 0.85 - wash.originX
				focalY: wash.fieldHeight * 0.78 - wash.originY

				GradientStop { position: 0.0; color: Theme.desktopWashB }
				GradientStop { position: 0.6; color: "#00000000" }
			}

			startX: wash.radius; startY: 0
			PathLine { x: wash.width - wash.radius; y: 0 }
			PathArc { x: wash.width; y: wash.radius; radiusX: wash.radius; radiusY: wash.radius }
			PathLine { x: wash.width; y: wash.height - wash.radius }
			PathArc { x: wash.width - wash.radius; y: wash.height; radiusX: wash.radius; radiusY: wash.radius }
			PathLine { x: wash.radius; y: wash.height }
			PathArc { x: 0; y: wash.height - wash.radius; radiusX: wash.radius; radiusY: wash.radius }
			PathLine { x: 0; y: wash.radius }
			PathArc { x: wash.radius; y: 0; radiusX: wash.radius; radiusY: wash.radius }
		}
	}
}
