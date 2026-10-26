import QtQuick
import QtQuick.Shapes
import ".."

// The Bluetooth rune: a spine with a triangle either side of it, drawn as one
// continuous stroke the way the mark itself is constructed.
//
// Drawn on the shared 24-unit grid with one stroke, like the other bar
// glyphs, so at one size they all carry the same weight.
Item {
	id: icon

	property color color: "#ffffff"
	property bool crossed: false

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

			ShapePath {
				strokeColor: icon.color
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 7; startY: 7
				PathLine { x: 17; y: 17 }
				PathLine { x: 12; y: 22 }
				PathLine { x: 12; y: 2 }
				PathLine { x: 17; y: 7 }
				PathLine { x: 7; y: 17 }
			}

			// Struck through when the radio is off, as the Wi-Fi glyph is.
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
