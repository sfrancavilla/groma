import QtQuick
import QtQuick.Shapes

// A ring with one lit arc, turning. Says the scan is still running, which
// matters here: an empty network list during a scan and an empty network list
// after one mean different things.
Item {
	id: icon

	property color color: "#ffffff"
	// Paused when nothing is being waited for, so an idle dialog is not
	// animating a widget for no reason.
	property bool spinning: true

	readonly property real baseWidth: 12
	readonly property real baseHeight: 12
	readonly property real aspect: 1

	implicitWidth: icon.baseWidth
	implicitHeight: icon.baseHeight

	Item {
		id: dial

		width: icon.baseWidth
		height: icon.baseHeight
		transformOrigin: Item.Center

		transform: Scale {
			origin.x: icon.baseWidth / 2
			origin.y: icon.baseHeight / 2
			xScale: icon.width / icon.baseWidth
			yScale: icon.height / icon.baseHeight
		}

		Shape {
			anchors.fill: parent
			preferredRendererType: Shape.CurveRenderer

			// The unlit track, so the glyph keeps its shape all the way round
			// rather than a lone arc chasing itself.
			ShapePath {
				strokeColor: Qt.rgba(icon.color.r, icon.color.g, icon.color.b,
					0.3)
				strokeWidth: 2
				fillColor: "transparent"

				PathAngleArc {
					centerX: 6; centerY: 6
					radiusX: 5; radiusY: 5
					startAngle: 0; sweepAngle: 360
				}
			}

			ShapePath {
				strokeColor: icon.color
				strokeWidth: 2
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 6; centerY: 6
					radiusX: 5; radiusY: 5
					startAngle: -90; sweepAngle: 90
				}
			}
		}

		RotationAnimation on rotation {
			running: icon.spinning && icon.visible
			from: 0
			to: 360
			duration: 1000
			loops: Animation.Infinite
		}
	}
}
