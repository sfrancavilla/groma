import QtQuick
import QtQuick.Shapes

// The Bluetooth rune: a spine with a triangle either side of it, drawn as one
// continuous stroke the way the mark itself is constructed.
Item {
	id: icon

	property color color: "#ffffff"
	property bool crossed: false

	readonly property real baseWidth: 12
	readonly property real baseHeight: 18
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

			ShapePath {
				strokeColor: icon.color
				strokeWidth: 1.6
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap
				joinStyle: ShapePath.RoundJoin

				startX: 2.5; startY: 5
				PathLine { x: 9.5; y: 13 }
				PathLine { x: 6; y: 16.5 }
				PathLine { x: 6; y: 1.5 }
				PathLine { x: 9.5; y: 5 }
				PathLine { x: 2.5; y: 13 }
			}

			// Struck through when the radio is off, as the Wi-Fi glyph is.
			ShapePath {
				strokeColor: icon.crossed ? icon.color : "transparent"
				strokeWidth: 1.6
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				startX: 1.5; startY: 2
				PathLine { x: 10.5; y: 16 }
			}
		}
	}
}
