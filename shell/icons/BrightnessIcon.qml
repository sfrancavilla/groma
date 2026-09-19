import QtQuick
import QtQuick.Shapes

// A sun: filled centre, eight rays. The rays shorten as the level drops, so
// the glyph reads as bright or dim on its own.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..1, scaling the rays.
	property real level: 1

	readonly property real baseWidth: 18
	readonly property real baseHeight: 18
	readonly property real aspect: 1

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
					centerX: 9; centerY: 9
					radiusX: 4; radiusY: 4
					startAngle: 0; sweepAngle: 360
				}
			}
		}

		Repeater {
			model: 8

			Rectangle {
				required property int index

				readonly property real len: 2 + 2.5 * Math.max(0.2, icon.level)

				width: 1.6
				height: len
				radius: 0.8
				color: icon.color

				x: 9 - width / 2
				y: 9 - 6 - len
				transformOrigin: Item.Bottom

				transform: Rotation {
					origin.x: 0.8
					origin.y: 6 + parent.len
					angle: index * 45
				}
			}
		}
	}
}
