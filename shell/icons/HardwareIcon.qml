import QtQuick
import QtQuick.Shapes
import ".."

// The parts of the machine the System card reads: processor, graphics,
// memory, disk and swap.
//
// Built like PowerIcon: the shared 24-unit grid, each mark spanning 3..21 so
// it sits in the middle of its square, at markLine. At 24 pixels a pin is
// still under two, so each part is drawn by the one
// feature that names it - a chip's pins, a card's fan, a stick's contacts, a
// drive's light - and nothing finer.
Item {
	id: icon

	property color color: "#ffffff"
	// Which part: cpu, gpu, memory, disk, swap.
	property string kind: "cpu"
	property real lineWidth: Theme.markLine

	readonly property real baseWidth: 24
	readonly property real baseHeight: 24
	readonly property real aspect: 1
	readonly property real units: icon.lineWidth * icon.baseWidth / Math.max(1, icon.width)

	implicitWidth: 16
	implicitHeight: 16

	function ink(kind) {
		return icon.kind === kind ? icon.color : "transparent";
	}

	Item {
		width: icon.baseWidth
		height: icon.baseHeight

		transform: Scale {
			xScale: icon.width / icon.baseWidth
			yScale: icon.height / icon.baseHeight
		}

		Shape {
			anchors.fill: parent
			// As in PowerIcon: the curve renderer draws nothing in a surface
			// created hidden, which every tab card is.
			antialiasing: true
			layer.enabled: true
			layer.samples: 4
			layer.textureSize: Qt.size(icon.width * 3, icon.height * 3)
			layer.smooth: true

			// cpu: a square die with two pins a side, and its core filled.
			ShapePath {
				strokeColor: icon.ink("cpu")
				strokeWidth: icon.units
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin

				startX: 8.5; startY: 6.5
				PathLine { x: 15.5; y: 6.5 }
				PathArc { x: 17.5; y: 8.5; radiusX: 2; radiusY: 2 }
				PathLine { x: 17.5; y: 15.5 }
				PathArc { x: 15.5; y: 17.5; radiusX: 2; radiusY: 2 }
				PathLine { x: 8.5; y: 17.5 }
				PathArc { x: 6.5; y: 15.5; radiusX: 2; radiusY: 2 }
				PathLine { x: 6.5; y: 8.5 }
				PathArc { x: 8.5; y: 6.5; radiusX: 2; radiusY: 2 }
			}

			ShapePath {
				strokeColor: icon.ink("cpu")
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 10; startY: 3.5
				PathLine { x: 10; y: 6.5 }
				PathMove { x: 14; y: 3.5 }
				PathLine { x: 14; y: 6.5 }
				PathMove { x: 10; y: 17.5 }
				PathLine { x: 10; y: 20.5 }
				PathMove { x: 14; y: 17.5 }
				PathLine { x: 14; y: 20.5 }
				PathMove { x: 3.5; y: 10 }
				PathLine { x: 6.5; y: 10 }
				PathMove { x: 3.5; y: 14 }
				PathLine { x: 6.5; y: 14 }
				PathMove { x: 17.5; y: 10 }
				PathLine { x: 20.5; y: 10 }
				PathMove { x: 17.5; y: 14 }
				PathLine { x: 20.5; y: 14 }
			}

			ShapePath {
				strokeColor: "transparent"
				fillColor: icon.ink("cpu")

				startX: 10; startY: 10
				PathLine { x: 14; y: 10 }
				PathLine { x: 14; y: 14 }
				PathLine { x: 10; y: 14 }
				PathLine { x: 10; y: 10 }
			}

			// gpu: a card with a fan on it, standing on its connector.
			ShapePath {
				strokeColor: icon.ink("gpu")
				strokeWidth: icon.units
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 5; startY: 5
				PathLine { x: 19; y: 5 }
				PathArc { x: 21; y: 7; radiusX: 2; radiusY: 2 }
				PathLine { x: 21; y: 15 }
				PathArc { x: 19; y: 17; radiusX: 2; radiusY: 2 }
				PathLine { x: 5; y: 17 }
				PathArc { x: 3; y: 15; radiusX: 2; radiusY: 2 }
				PathLine { x: 3; y: 7 }
				PathArc { x: 5; y: 5; radiusX: 2; radiusY: 2 }
				PathMove { x: 7; y: 17 }
				PathLine { x: 7; y: 20 }
				PathLine { x: 15; y: 20 }
				PathLine { x: 15; y: 17 }
			}

			ShapePath {
				strokeColor: icon.ink("gpu")
				strokeWidth: icon.units
				fillColor: "transparent"

				PathAngleArc {
					centerX: 10.5; centerY: 11
					radiusX: 3.2; radiusY: 3.2
					startAngle: 0; sweepAngle: 360
				}
			}

			ShapePath {
				strokeColor: icon.ink("gpu")
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 16.5; startY: 9
				PathLine { x: 18; y: 9 }
				PathMove { x: 16.5; y: 13 }
				PathLine { x: 18; y: 13 }
			}

			// memory: a stick, its chips, and the contacts along its edge.
			ShapePath {
				strokeColor: icon.ink("memory")
				strokeWidth: icon.units
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 5; startY: 6
				PathLine { x: 19; y: 6 }
				PathArc { x: 21; y: 8; radiusX: 2; radiusY: 2 }
				PathLine { x: 21; y: 15 }
				PathLine { x: 3; y: 15 }
				PathLine { x: 3; y: 8 }
				PathArc { x: 5; y: 6; radiusX: 2; radiusY: 2 }
				PathMove { x: 6.5; y: 15 }
				PathLine { x: 6.5; y: 18.5 }
				PathMove { x: 12; y: 15 }
				PathLine { x: 12; y: 18.5 }
				PathMove { x: 17.5; y: 15 }
				PathLine { x: 17.5; y: 18.5 }
			}

			ShapePath {
				strokeColor: "transparent"
				fillColor: icon.ink("memory")

				startX: 6.5; startY: 9
				PathLine { x: 10; y: 9 }
				PathLine { x: 10; y: 12 }
				PathLine { x: 6.5; y: 12 }
				PathLine { x: 6.5; y: 9 }
				PathMove { x: 14; y: 9 }
				PathLine { x: 17.5; y: 9 }
				PathLine { x: 17.5; y: 12 }
				PathLine { x: 14; y: 12 }
				PathLine { x: 14; y: 9 }
			}

			// disk: a drive seen from the front, its lower bay and its light.
			ShapePath {
				strokeColor: icon.ink("disk")
				strokeWidth: icon.units
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 5.5; startY: 5
				PathLine { x: 18.5; y: 5 }
				PathArc { x: 20.5; y: 7; radiusX: 2; radiusY: 2 }
				PathLine { x: 20.5; y: 17 }
				PathArc { x: 18.5; y: 19; radiusX: 2; radiusY: 2 }
				PathLine { x: 5.5; y: 19 }
				PathArc { x: 3.5; y: 17; radiusX: 2; radiusY: 2 }
				PathLine { x: 3.5; y: 7 }
				PathArc { x: 5.5; y: 5; radiusX: 2; radiusY: 2 }
				PathMove { x: 3.5; y: 13 }
				PathLine { x: 20.5; y: 13 }
			}

			ShapePath {
				strokeColor: "transparent"
				fillColor: icon.ink("disk")

				PathAngleArc {
					centerX: 16.5; centerY: 16
					radiusX: 1.3; radiusY: 1.3
					startAngle: 0; sweepAngle: 360
				}
			}

			// swap: two arrows passing, out of memory and back.
			ShapePath {
				strokeColor: icon.ink("swap")
				strokeWidth: icon.units
				fillColor: "transparent"
				joinStyle: ShapePath.RoundJoin
				capStyle: ShapePath.RoundCap

				startX: 4; startY: 8
				PathLine { x: 19.5; y: 8 }
				PathMove { x: 16; y: 4.5 }
				PathLine { x: 19.5; y: 8 }
				PathLine { x: 16; y: 11.5 }
				PathMove { x: 20; y: 16 }
				PathLine { x: 4.5; y: 16 }
				PathMove { x: 8; y: 12.5 }
				PathLine { x: 4.5; y: 16 }
				PathLine { x: 8; y: 19.5 }
			}
		}
	}
}
