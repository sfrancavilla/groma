import QtQuick
import ".."

// A panel of glass with the shell's standard padding, and an optional header
// naming what it is and what it is acting on.
//
// The volume tile established this shape; everything panel-sized should use it
// rather than re-deciding its own padding and type sizes.
GlassPanel {
	id: tile

	property string title: ""
	property string trailing: ""
	// The trailing text is usually just context, but it is also where a tile
	// says something is wrong.
	property color trailingColor: Theme.glassTextPrimary

	default property alias content: column.data

	radius: Theme.radiusPanel
	implicitWidth: Theme.tileWidth
	implicitHeight: column.implicitHeight + Theme.tilePadding * 2

	Column {
		id: column

		anchors {
			left: parent.left
			right: parent.right
			top: parent.top
			leftMargin: Theme.tilePadding
			rightMargin: Theme.tilePadding
			topMargin: Theme.tilePadding
		}

		spacing: Theme.spacingM

		Item {
			width: parent.width
			height: heading.implicitHeight
			visible: tile.title !== ""

			Text {
				id: heading

				anchors.left: parent.left
				text: tile.title
				font.pixelSize: Theme.fontBody
				font.bold: true
				color: Theme.glassTextPrimary
			}

			Text {
				anchors.right: parent.right
				width: parent.width - heading.width - Theme.spacingM
				horizontalAlignment: Text.AlignRight
				elide: Text.ElideRight
				text: tile.trailing
				font.pixelSize: Theme.fontBody
				opacity: 0.8
				color: tile.trailingColor
			}
		}
	}
}

