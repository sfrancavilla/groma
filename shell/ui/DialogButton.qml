import Quickshell
import QtQuick
import ".."

// A dialog button: the same chip the tiles use, in three weights.
//
// `enabled` comes from Item and already disables the MouseArea for us.
Rectangle {
	id: button

	property alias text: label.text
	// "secondary" | "primary" | "destructive"
	property string variant: "secondary"

	readonly property bool isPrimary: button.variant === "primary"
	readonly property bool isDestructive: button.variant === "destructive"

	signal clicked

	implicitWidth: label.implicitWidth + Theme.spacingL * 2
	implicitHeight: Theme.chipHeight
	radius: Theme.radiusPill

	opacity: button.enabled ? 1.0 : 0.4

	color: button.isPrimary
		? (mouse.containsMouse ? Theme.chipPrimaryHover : Theme.chipPrimary)
		: button.isDestructive
			? (mouse.containsMouse ? Theme.chipDestructiveHover : Theme.chipDestructive)
			: (mouse.containsMouse ? Theme.glassControlHover : Theme.glassControl)

	border.width: 1
	border.color: button.isPrimary ? Theme.chipPrimaryBorder
		: button.isDestructive ? Theme.chipDestructiveBorder
		: Theme.glassControlBorder

	Behavior on color {
		ColorAnimation { duration: 120 }
	}

	Text {
		id: label

		anchors.centerIn: parent

		// Without a width a Text renders at its implicit size wherever it is
		// anchored, so a label too long for its chip spilled out of both ends
		// of it rather than being cut.
		//
		// The clamp is tighter than the padding implicitWidth asks for. A
		// button left to size itself gets a generous inset; one given a width
		// it has to live inside should use that width before eliding, rather
		// than cutting the label to preserve padding nobody asked for.
		width: Math.min(implicitWidth, button.width - Theme.spacingS * 2)
		elide: Text.ElideRight
		horizontalAlignment: Text.AlignHCenter

		font.pixelSize: Theme.fontBody
		font.bold: button.isPrimary || button.isDestructive
		font.weight: button.isPrimary || button.isDestructive
			? Font.Bold : Font.DemiBold

		// The primary chip is bright enough that white on it would not read.
		color: button.isPrimary ? Theme.glassTextOnLens : Theme.glassTextPrimary
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: button.clicked()
	}
}
