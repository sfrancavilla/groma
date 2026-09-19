import QtQuick
import QtQuick.Shapes

// A sun: filled centre, eight rays that lengthen with the level, so the glyph
// reads as bright or dim without a label.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..1, scaling the rays.
	property real level: 1

	readonly property real baseWidth: 18
	readonly property real baseHeight: 18
	readonly property real aspect: 1

	// Geometry, from the centre outward. The longest ray has to stay inside
	// the box: gap + the longest length must not exceed half the width.
	readonly property real centre: icon.baseWidth / 2
	readonly property real discRadius: 3.5
	readonly property real rayGap: 5
	readonly property real rayLength: 1.5 + 1.5 * Math.max(0, Math.min(1, icon.level))

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

			ShapePath {
				strokeWidth: 0
				fillColor: icon.color

				PathAngleArc {
					centerX: icon.centre
					centerY: icon.centre
					radiusX: icon.discRadius
					radiusY: icon.discRadius
					startAngle: 0
					sweepAngle: 360
				}
			}
		}

		Repeater {
			model: 8

			Rectangle {
				id: ray

				required property int index

				width: 1.6
				height: icon.rayLength
				radius: width / 2
				color: icon.color

				// Drawn pointing up from the centre, then rotated into place.
				// Every reference here is qualified: inside the Rotation below,
				// an unqualified `parent` is this rectangle's parent, not the
				// rectangle, which is what scattered the rays the first time.
				x: icon.centre - ray.width / 2
				y: icon.centre - icon.rayGap - ray.height

				transform: Rotation {
					origin.x: ray.width / 2
					origin.y: icon.rayGap + ray.height
					angle: ray.index * 45
				}
			}
		}
	}
}
