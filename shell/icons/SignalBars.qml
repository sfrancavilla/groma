import QtQuick
import ".."

// Four ascending bars, the lit count showing strength.
//
// Unlike the other glyphs these are plain rectangles rather than paths: they
// are four rectangles, and a Shape would be ceremony.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..4 bars lit.
	property int level: 0

	readonly property real baseWidth: 18
	readonly property real baseHeight: 12
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

		Row {
			anchors.bottom: parent.bottom
			spacing: 2

			Repeater {
				model: 4

				Rectangle {
					required property int index

					width: 3
					height: 4 + index * 2.7
					radius: 1
					anchors.bottom: parent.bottom

					color: icon.color
					// Unlit bars stay visible, so the glyph keeps its shape at
					// any strength rather than shrinking.
					opacity: icon.level > index ? 1.0 : 0.35
				}
			}
		}
	}
}
