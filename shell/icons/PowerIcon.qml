import QtQuick
import QtQuick.Shapes
import ".."

// The power mark and its family: the bar's button, the power menu's rows, its
// confirmation sheet, and the restart mark in Snapshots.
//
// Drawn on the shared 24-unit grid, each mark spanning 3..21 both ways so it
// sits in the middle of its disc rather than wherever its shape happens to
// put its weight.
Item {
	id: icon

	property color color: "#ffffff"
	// Which mark: power, lock, moon (suspend), leave (log out), restart.
	property string kind: "power"
	// The stroke in pixels as drawn: the bar's weight unless set - inside a
	// disc it is Theme.markLine, to match the marks beside it.
	property real lineWidth: Theme.barIconLine

	readonly property real baseWidth: 24
	readonly property real baseHeight: 24
	readonly property real aspect: 1
	readonly property real units: icon.lineWidth * icon.baseWidth / Math.max(1, icon.width)

	implicitWidth: 16
	implicitHeight: 16

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
			// Drawn at the size it is shown, not the 24 units it is described
			// in, or the scale transform blurs it; three for the display's two.
			layer.textureSize: Qt.size(icon.width * 3, icon.height * 3)
			layer.smooth: true

			// power: a ring broken at the top, and a stroke through the gap.
			ShapePath {
				strokeColor: icon.kind === "power" ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 12; centerY: 12.5
					radiusX: 8.5; radiusY: 8.5
					startAngle: 310; sweepAngle: 280
				}
			}

			ShapePath {
				strokeColor: icon.kind === "power" ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 12; startY: 3
				PathLine { x: 12; y: 11 }
			}

			// restart: a ring travelling clockwise from three o'clock, nearly
			// all the way round, ending in an arrowhead that points into the
			// gap it leaves.
			ShapePath {
				strokeColor: icon.kind === "restart" ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				PathAngleArc {
					centerX: 12; centerY: 12
					radiusX: 8.5; radiusY: 8.5
					startAngle: 0; sweepAngle: 315
				}
				PathLine { x: 20.5; y: 8 }
				PathMove { x: 20.5; y: 3.5 }
				PathLine { x: 20.5; y: 8 }
				PathLine { x: 16; y: 8 }
			}

			// moon: a crescent, for suspend - a disc with a smaller one bitten
			// out of its top right.
			ShapePath {
				strokeColor: icon.kind === "moon" ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin

				startX: 12; startY: 3
				PathArc { x: 21; y: 12; radiusX: 6.4; radiusY: 6.4; direction: PathArc.Counterclockwise }
				PathArc { x: 12; y: 3; radiusX: 9; radiusY: 9; useLargeArc: true }
			}

			// leave: a door frame and an arrow going out of it, for log out.
			ShapePath {
				strokeColor: icon.kind === "leave" ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 9; startY: 21
				PathLine { x: 5; y: 21 }
				PathArc { x: 3; y: 19; radiusX: 2; radiusY: 2 }
				PathLine { x: 3; y: 5 }
				PathArc { x: 5; y: 3; radiusX: 2; radiusY: 2 }
				PathLine { x: 9; y: 3 }
				PathMove { x: 9; y: 12 }
				PathLine { x: 21; y: 12 }
				PathMove { x: 16; y: 7 }
				PathLine { x: 21; y: 12 }
				PathLine { x: 16; y: 17 }
			}

			// lock: a shackle over a body.
			ShapePath {
				strokeColor: icon.kind === "lock" ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 7.5; startY: 11
				PathLine { x: 7.5; y: 7.5 }
				PathArc { x: 16.5; y: 7.5; radiusX: 4.5; radiusY: 4.5 }
				PathLine { x: 16.5; y: 11 }
				PathMove { x: 6; y: 11 }
				PathLine { x: 18; y: 11 }
				PathArc { x: 20; y: 13; radiusX: 2; radiusY: 2 }
				PathLine { x: 20; y: 19 }
				PathArc { x: 18; y: 21; radiusX: 2; radiusY: 2 }
				PathLine { x: 6; y: 21 }
				PathArc { x: 4; y: 19; radiusX: 2; radiusY: 2 }
				PathLine { x: 4; y: 13 }
				PathArc { x: 6; y: 11; radiusX: 2; radiusY: 2 }
			}
		}
	}
}
