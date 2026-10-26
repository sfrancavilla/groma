import QtQuick
import QtQuick.Shapes
import ".."

// Wi-Fi: a dot with three arcs fanning out above it. `level` is how many arcs
// are lit; the rest stay faintly drawn, so the glyph keeps its shape at any
// strength instead of shrinking to a dot. `crossed` strikes it through when
// the radio is off.
//
// Drawn on the shared 24-unit grid with one stroke, like the other bar
// glyphs, so at one size they all carry the same weight.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..3 arcs lit above the dot.
	property int level: 3
	property bool crossed: false

	readonly property color unlit: Qt.rgba(icon.color.r, icon.color.g, icon.color.b, icon.color.a * 0.3)

	readonly property real baseWidth: 24
	readonly property real baseHeight: 24
	readonly property real aspect: icon.baseWidth / icon.baseHeight

	// The stroke in pixels as drawn; the paths below are in grid units.
	property real lineWidth: Theme.barIconLine
	readonly property real units: icon.lineWidth * icon.baseHeight / Math.max(1, icon.height)

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

			// The dot, always lit: the radio exists even when nothing is
			// connected.
			ShapePath {
				strokeWidth: 0
				fillColor: icon.color

				PathAngleArc {
					centerX: 12; centerY: 18.5
					radiusX: 1.6; radiusY: 1.6
					startAngle: 0; sweepAngle: 360
				}
			}

			ShapePath {
				strokeColor: icon.level >= 1 ? icon.color : icon.unlit
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 12; centerY: 18.5
					radiusX: 4.5; radiusY: 4.5
					startAngle: 225; sweepAngle: 90
				}
			}

			ShapePath {
				strokeColor: icon.level >= 2 ? icon.color : icon.unlit
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 12; centerY: 18.5
					radiusX: 8.5; radiusY: 8.5
					startAngle: 225; sweepAngle: 90
				}
			}

			ShapePath {
				strokeColor: icon.level >= 3 ? icon.color : icon.unlit
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 12; centerY: 18.5
					radiusX: 12.5; radiusY: 12.5
					startAngle: 225; sweepAngle: 90
				}
			}

			// Struck through when the radio is off.
			ShapePath {
				strokeColor: icon.crossed ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 4; startY: 4
				PathLine { x: 20; y: 20 }
			}
		}
	}
}
