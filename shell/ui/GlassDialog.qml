import QtQuick
import ".."

// A modal sheet: dimmed, blurred desktop with a pane of glass centred on it.
//
// Fills the caller's window; the caller owns the window because a dialog that
// takes keyboard focus and one that does not are different things.
// Anything declared inside follows the title and body.
Item {
	id: dialog

	property bool open: false
	property string title: ""
	property string body: ""
	// An optional disc beside the text, as in the design's 3b and 5c.
	property Component icon: null

	default property alias content: column.data

	// For the caller's blur region: the sheet, not the whole screen.
	readonly property alias sheet: sheet

	// Less dimming than a plain scrim needs, because the desktop behind it is
	// blurred as well.
	Rectangle {
		anchors.fill: parent
		color: Theme.scrim
		opacity: dialog.open ? 1 : 0

		Behavior on opacity {
			NumberAnimation { duration: 180 }
		}

		// Clicks outside the sheet go nowhere rather than through.
		MouseArea {
			anchors.fill: parent
		}
	}

	GlassPanel {
		id: sheet

		anchors.centerIn: parent
		width: Theme.dialogWidth
		height: column.implicitHeight + Theme.dialogPadding * 2
		radius: Theme.radiusPanel

		opacity: dialog.open ? 1 : 0
		scale: dialog.open ? 1 : 0.96
		y: dialog.open ? 0 : -6

		Behavior on opacity {
			NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
		}
		Behavior on scale {
			NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
		}
		Behavior on y {
			NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
		}

		Column {
			id: column

			anchors {
				left: parent.left
				right: parent.right
				top: parent.top
				leftMargin: Theme.dialogPadding
				rightMargin: Theme.dialogPadding
				topMargin: Theme.dialogPadding
			}

			spacing: Theme.spacingM

			Row {
				width: parent.width
				spacing: Theme.spacingM
				visible: dialog.title !== "" || dialog.body !== ""

				Loader {
					width: 44
					height: 44
					visible: dialog.icon !== null
					sourceComponent: dialog.icon
				}

			Column {
				width: parent.width - (dialog.icon ? 44 + Theme.spacingM : 0)
				spacing: Theme.spacingXs

				Text {
					width: parent.width
					wrapMode: Text.WordWrap
					text: dialog.title
					visible: text !== ""
					font.pixelSize: Theme.fontLead
					font.bold: true
					color: Theme.glassTextPrimary
				}

				Text {
					width: parent.width
					wrapMode: Text.WordWrap
					text: dialog.body
					visible: text !== ""
					font.pixelSize: Theme.fontBody
					lineHeight: 1.45
					opacity: 0.82
					color: Theme.glassTextPrimary
				}
			}
			}
		}
	}
}
