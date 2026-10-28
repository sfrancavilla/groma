import QtQuick
import ".."

// Three upright cells side by side, each filled from the bottom by how much
// of something is in use - processor, memory, disk in the bar.
//
// Outlines that fill, as the battery's cell does, on the same 24-unit grid
// and with the same stroke, so it carries the weight of the line glyphs
// beside it. Solid bars read as three white blocks among them.
Item {
	id: icon

	property color color: "#ffffff"
	// 0..1 each, left to right.
	property var values: [0, 0, 0]
	// A cell whose index is true here is drawn in alertColor.
	property var alerts: [false, false, false]
	property color alertColor: Theme.warning

	readonly property real baseWidth: 24
	readonly property real baseHeight: 24
	readonly property real aspect: icon.baseWidth / icon.baseHeight

	// The stroke in pixels as drawn; the cells below are in grid units.
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

		Row {
			x: 2
			y: 3
			spacing: 2.5

			Repeater {
				model: 3

				Item {
					id: cell

					required property int index

					readonly property color tint:
						icon.alerts[cell.index] ? icon.alertColor : icon.color
					readonly property real level:
						Math.max(0, Math.min(1, icon.values[cell.index] ?? 0))

					width: 5
					height: 18

					Rectangle {
						anchors.fill: parent
						radius: 1.5
						color: "transparent"
						border.width: icon.units
						border.color: cell.tint
					}

					// Flush with the outline, so a full cell is one solid bar.
					// Never quite empty: a sliver says "measured, and idle".
					Rectangle {
						anchors.bottom: parent.bottom
						width: parent.width
						height: Math.max(icon.units * 2, parent.height * cell.level)
						radius: 1.5
						color: cell.tint

						Behavior on height {
							NumberAnimation { duration: 180 }
						}
					}
				}
			}
		}
	}
}
