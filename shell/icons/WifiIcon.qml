import QtQuick
import QtQuick.Shapes

// Wi-Fi: a dot with arcs above it. `level` is how many arcs are lit, and
// `crossed` strikes it through when the radio is off.
//
// The arcs are state, not strength: Quickshell's Network exposes whether a
// network is connected but not how strong it is, so claiming bars would be
// inventing a reading.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..2 arcs above the dot.
	property int level: 2
	property bool crossed: false

	readonly property real baseWidth: 18
	readonly property real baseHeight: 14
	readonly property real aspect: icon.baseWidth / icon.baseHeight

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

			// The dot, always present: the radio exists even when nothing is
			// connected.
			ShapePath {
				strokeWidth: 0
				fillColor: icon.color

				PathAngleArc {
					centerX: 9; centerY: 11.5
					radiusX: 1.6; radiusY: 1.6
					startAngle: 0; sweepAngle: 360
				}
			}

			ShapePath {
				strokeColor: icon.level >= 1 ? icon.color : "transparent"
				strokeWidth: 1.6
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 9; centerY: 11.5
					radiusX: 4.5; radiusY: 4.5
					startAngle: 200; sweepAngle: 140
				}
			}

			ShapePath {
				strokeColor: icon.level >= 2 ? icon.color : "transparent"
				strokeWidth: 1.6
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 9; centerY: 11.5
					radiusX: 8; radiusY: 8
					startAngle: 205; sweepAngle: 130
				}
			}

			// Struck through when the radio is off.
			ShapePath {
				strokeColor: icon.crossed ? icon.color : "transparent"
				strokeWidth: 1.6
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 2.5; startY: 2
				PathLine { x: 15.5; y: 13 }
			}
		}
	}
}

