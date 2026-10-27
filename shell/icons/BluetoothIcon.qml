import QtQuick
import QtQuick.Shapes
import ".."

// The Bluetooth rune: a spine with a triangle either side of it, drawn as one
// continuous stroke the way the mark itself is constructed.
//
// Drawn on the shared grid, 24 units high, with one stroke, like the other
// bar glyphs, so at one size they all carry the same weight.
Item {
	id: icon

	property color color: "#ffffff"
	property bool crossed: false

	// Half the grid's width: the rune is narrow, and in a square box it
	// stood with nearly five pixels of nothing either side, so the bar's
	// even spacing left a visibly wider gap beside it than between the rest.
	readonly property real baseWidth: 12
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

				// 17 units tall, not the grid's full 20: the rune is all
				// height, and at 20 its ink stood two pixels above the other
				// bar glyphs', which read as sitting higher than them.
				startX: 1.75; startY: 7.75
				PathLine { x: 10.25; y: 16.25 }
				PathLine { x: 6; y: 20.5 }
				PathLine { x: 6; y: 3.5 }
				PathLine { x: 10.25; y: 7.75 }
				PathLine { x: 1.75; y: 16.25 }
			}

			// Struck through when the radio is off, as the Wi-Fi glyph is.
			ShapePath {
				strokeColor: icon.crossed ? icon.color : "transparent"
				strokeWidth: icon.units
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				// Shorter than the Wi-Fi glyph's, to stay inside the narrow box.
				startX: 0.5; startY: 6.5
				PathLine { x: 11.5; y: 17.5 }
			}
		}
	}
}
