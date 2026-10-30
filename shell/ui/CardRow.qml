import QtQuick
import ".."

// One line of a bar card: a mark, a title over a detail, and whatever goes on
// the right. The system card's reading, the power card's action and a device
// in the Bluetooth card are all this, so they line up from card to card.
//
// A reading is drawn straight on the card. A row you can click lights a pill
// under itself when pointed at, as the power card's always did.
Item {
	id: row

	property string title: ""
	property string detail: ""
	property color detailColor: Theme.glassTextPrimary

	// The mark, created in the caller's scope so it binds to the caller's
	// state: Theme.rowMark, centred in a 24 square so the titles line up
	// whatever the glyph's own proportions.
	property Component mark
	// Dim, as the system card draws its parts: the title is what is read.
	property real markOpacity: 0.4

	// Above the row: "dashed" between readings, "solid" between groups.
	property string rule: "none"

	property bool interactive: false
	readonly property bool hovered: mouse.containsMouse

	// Anything declared inside goes on the right.
	default property alias trailing: trailingRow.data

	signal clicked

	readonly property real ruleSpace: row.rule !== "none" ? 9 : 0
	// Two lines or one. A list whose details come and go sets it, so its
	// rows do not change height under the pointer.
	property real rowHeight: row.detail !== "" ? 48 : 38

	width: parent?.width ?? 0
	height: row.rowHeight + row.ruleSpace

	Rectangle {
		visible: row.rule === "solid"
		y: 4
		x: 8
		width: parent.width - 16
		height: 1
		color: Theme.glassControlBorder
	}

	// Dashed: it separates readings rather than groups, and a solid rule
	// under every row read as a table's grid.
	Row {
		visible: row.rule === "dashed"
		y: 4
		x: 8
		width: parent.width - 16
		spacing: 3

		Repeater {
			model: row.rule === "dashed" ? Math.max(0, Math.floor((parent.width + 3) / 7)) : 0

			Rectangle {
				width: 4
				height: 1
				color: Theme.glassControlBorder
			}
		}
	}

	Rectangle {
		id: body

		y: row.ruleSpace
		width: parent.width
		height: row.rowHeight
		radius: Theme.radiusPill
		color: row.interactive && mouse.containsMouse
			? Theme.glassControlHover : "transparent"

		Behavior on color {
			ColorAnimation { duration: 120 }
		}

		// Under the trailing controls, so a chip or a switch there still
		// takes its own click.
		MouseArea {
			id: mouse

			anchors.fill: parent
			enabled: row.interactive
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: row.clicked()
		}

		Item {
			id: markBox

			x: 5
			anchors.verticalCenter: parent.verticalCenter
			width: 24
			height: 24
			opacity: row.markOpacity

			Behavior on opacity {
				NumberAnimation { duration: 120 }
			}

			Loader {
				anchors.centerIn: parent
				sourceComponent: row.mark
			}
		}

		Column {
			anchors {
				left: markBox.right
				leftMargin: Theme.spacingM
				right: trailingRow.left
				rightMargin: Theme.spacingS
				verticalCenter: parent.verticalCenter
			}

			spacing: 2

			Text {
				width: parent.width
				elide: Text.ElideRight
				text: row.title
				font.pixelSize: Theme.fontTitle
				font.weight: Font.DemiBold
				color: Theme.glassTextPrimary
			}

			Text {
				width: parent.width
				visible: text !== ""
				elide: Text.ElideRight
				text: row.detail
				font.pixelSize: Theme.fontBody
				opacity: 0.75
				color: row.detailColor
			}
		}

		Row {
			id: trailingRow

			anchors {
				right: parent.right
				rightMargin: row.interactive ? 10 : 4
				verticalCenter: parent.verticalCenter
			}

			spacing: Theme.spacingS
		}
	}
}
