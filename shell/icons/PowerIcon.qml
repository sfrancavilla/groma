import QtQuick
import QtQuick.Shapes

// The power mark: a ring broken at the top, and a stroke through the gap.
// Used in the bar, and at other sizes for the power popup's rows.
Item {
	id: icon

	property color color: "#ffffff"
	// Which mark: power, lock, moon (suspend), leave (log out), restart.
	property string kind: "power"
	property real stroke: 1.4

	readonly property real baseWidth: 12
	readonly property real baseHeight: 12
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
			// The curve renderer draws nothing in a window that is created
			// hidden and mapped later - the power sheet's disc stayed empty.
			// The default renderer, with antialiasing, has no such trouble.
			antialiasing: true
			layer.enabled: true
			layer.samples: 4
			// Drawn at the size it is shown, not the 12px it is described in,
			// or the scale transform blurs it; three for the display's two.
			layer.textureSize: Qt.size(icon.width * 3, icon.height * 3)
			layer.smooth: true

			// power: the broken ring and the stroke.
			ShapePath {
				strokeColor: icon.kind === "power" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 6; centerY: 6.6
					radiusX: 4.6; radiusY: 4.6
					startAngle: -55; sweepAngle: 290
				}
			}

			ShapePath {
				strokeColor: icon.kind === "power" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 6; startY: 0.9
				PathLine { x: 6; y: 6 }
			}

			// restart: most of a ring, and an arrowhead where it ends.
			ShapePath {
				strokeColor: icon.kind === "restart" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				PathAngleArc {
					centerX: 6; centerY: 6.4
					radiusX: 4.6; radiusY: 4.6
					startAngle: -80; sweepAngle: 300
				}
			}

			ShapePath {
				strokeColor: icon.kind === "restart" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 4.6; startY: 0.2
				PathLine { x: 6.8; y: 1.8 }
				PathLine { x: 4.9; y: 3.8 }
			}

			// moon: a crescent, for suspend.
			ShapePath {
				strokeColor: icon.kind === "moon" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin

				startX: 7.2; startY: 1.2
				PathArc { x: 10.8; y: 8.4; radiusX: 5; radiusY: 5; direction: PathArc.Counterclockwise; useLargeArc: true }
				PathArc { x: 7.2; y: 1.2; radiusX: 4; radiusY: 4 }
			}

			// leave: a door frame and an arrow going out of it, for log out.
			ShapePath {
				strokeColor: icon.kind === "leave" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 7; startY: 1.5
				PathLine { x: 2; y: 1.5 }
				PathLine { x: 2; y: 10.5 }
				PathLine { x: 7; y: 10.5 }
				PathMove { x: 5; y: 6 }
				PathLine { x: 11; y: 6 }
				PathMove { x: 8.8; y: 3.8 }
				PathLine { x: 11; y: 6 }
				PathLine { x: 8.8; y: 8.2 }
			}

			// lock: a shackle over a body.
			ShapePath {
				strokeColor: icon.kind === "lock" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 6; centerY: 4.6
					radiusX: 2.8; radiusY: 2.8
					startAngle: 180; sweepAngle: 180
				}
			}

			ShapePath {
				strokeColor: icon.kind === "lock" ? icon.color : "transparent"
				strokeWidth: icon.stroke
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 3.2; startY: 4.6
				PathLine { x: 3.2; y: 5.4 }
				PathMove { x: 8.8; y: 4.6 }
				PathLine { x: 8.8; y: 5.4 }
				PathMove { x: 2.2; y: 5.6 }
				PathLine { x: 9.8; y: 5.6 }
				PathLine { x: 9.8; y: 11 }
				PathLine { x: 2.2; y: 11 }
				PathLine { x: 2.2; y: 5.6 }
			}
		}
	}
}
