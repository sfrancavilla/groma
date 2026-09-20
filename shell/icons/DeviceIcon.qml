import QtQuick
import QtQuick.Shapes

// What kind of thing a Bluetooth device is, from the `icon` bluez reports.
//
// Five shapes rather than the freedesktop icon theme: the theme's names are
// what bluez gives us, but rendering themed PNGs into a glass sheet would look
// like a different application had drawn them.
Item {
	id: icon

	// "headphones" | "speaker" | "input" | "phone" | "unknown"
	property string kind: "unknown"
	property color color: "#ffffff"

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

		// A band over the head with an earcup either side.
		Shape {
			anchors.fill: parent
			visible: icon.kind === "headphones"
			preferredRendererType: Shape.CurveRenderer

			ShapePath {
				strokeColor: icon.color
				strokeWidth: 1.8
				fillColor: "transparent"
				capStyle: ShapePath.RoundCap

				PathAngleArc {
					centerX: 9; centerY: 9
					radiusX: 6.5; radiusY: 6.5
					startAngle: 180; sweepAngle: 180
				}
			}
		}

		Repeater {
			model: icon.kind === "headphones" ? [2.5, 15.5] : []

			Rectangle {
				required property real modelData

				x: modelData - 1.6
				y: 8.5
				width: 3.2
				height: 6.5
				radius: 1.6
				color: icon.color
			}
		}

		// A cabinet with a driver in it.
		Rectangle {
			visible: icon.kind === "speaker"
			x: 4; y: 1.5
			width: 10; height: 15
			radius: 2.5
			color: "transparent"
			border.width: 1.8
			border.color: icon.color

			Rectangle {
				x: 2.1; y: 6.4
				width: 5.8; height: 5.8
				radius: 2.9
				color: "transparent"
				border.width: 1.6
				border.color: icon.color
			}
		}

		// A flat pad, which is as close as a mouse and a keyboard get.
		Rectangle {
			visible: icon.kind === "input"
			x: 1.5; y: 4
			width: 15; height: 10
			radius: 2.5
			color: "transparent"
			border.width: 1.8
			border.color: icon.color
		}

		Rectangle {
			visible: icon.kind === "phone"
			x: 5; y: 1.5
			width: 8; height: 15
			radius: 2
			color: "transparent"
			border.width: 1.8
			border.color: icon.color
		}

		// Something is there and it has not said what.
		Rectangle {
			visible: icon.kind === "unknown"
			x: 4; y: 4
			width: 10; height: 10
			radius: 5
			color: "transparent"
			border.width: 1.8
			border.color: icon.color
		}
	}
}
