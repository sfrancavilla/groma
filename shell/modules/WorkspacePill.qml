import QtQuick
import ".."

// A workspace as the bar shows it: its number, its name, its colour.
//
// Its own file because it is drawn twice - in the bar, and again on the
// workspace card's tab, whose glass is dense enough to hide the bar under it.
// Behaviour stays with the caller; this is only the look.
Rectangle {
	id: face

	component PillText: Text {
		required property color ink
		required property bool raised

		anchors.verticalCenter: parent.verticalCenter
		color: ink
		style: raised ? Text.Raised : Text.Normal
		styleColor: Theme.glassTextShadow
	}

	required property int workspaceId
	// Hyprland's workspace, or null for a named one it has not made yet.
	required property var workspace
	property bool hovered: false

	readonly property string name: Settings.workspaceNames?.[String(workspaceId)] ?? ""
	readonly property color tint: Theme.tagColor(Settings.workspaceColors?.[String(workspaceId)] ?? "")
	readonly property bool tinted: tint.a > 0
	// The one showing on its screen, focused or not: each screen's bar lights
	// its own. With one screen that is the focused workspace.
	readonly property bool isFocused: workspace?.active ?? false
	// Tagged, but nothing on it and Hyprland has not made it yet.
	readonly property bool waiting: workspace === null
	readonly property bool solid: tinted && !waiting
	readonly property color ink: face.solid ? Theme.tagInk
		: Theme.glass ? Theme.glassTextPrimary
		: face.isFocused ? Theme.textOnStrong
		: Theme.textPrimary

	width: name === "" ? Theme.workspacePillWidth
		: Math.max(Theme.workspacePillWidth, label.implicitWidth + Theme.spacingS * 2)
	height: Theme.workspacePillHeight
	radius: Theme.radiusSmall

	border.width: face.tinted && face.waiting ? 1 : 0
	border.color: Qt.rgba(face.tint.r, face.tint.g, face.tint.b, Theme.tagEdge)

	color: face.solid
		? Qt.rgba(face.tint.r, face.tint.g, face.tint.b,
			face.hovered || face.isFocused ? Theme.tagFillHover : Theme.tagFill)
		: face.tinted ? (face.hovered ? Theme.glassControlHover : "transparent")
		: Theme.glass
		? (face.isFocused ? Theme.glassControlStrong
			: face.hovered ? Theme.glassControlHover
			: "transparent")
		: (face.isFocused ? Theme.surfaceStrong
			: face.hovered ? Theme.surfaceHover
			: Theme.surface)

	// The outline already says "empty" for a coloured one.
	opacity: face.waiting && !face.tinted && !face.hovered ? 0.55 : 1.0

	// Focus on a solid pill: a ring outside it, so nothing moves.
	Rectangle {
		anchors.fill: parent
		anchors.margins: -2
		radius: parent.radius + 2
		color: "transparent"
		border.width: 2
		border.color: Theme.tagRing
		visible: face.solid && face.isFocused
	}

	Row {
		id: label

		anchors.centerIn: parent
		height: parent.height
		spacing: Theme.spacingXs + 1

		// The number stays beside the name: it is still the key.
		PillText {
			ink: face.ink
			raised: Theme.glass && !face.solid
			text: face.workspaceId
			opacity: face.name !== "" ? 0.6 : 1.0
		}

		PillText {
			ink: face.ink
			raised: Theme.glass && !face.solid
			visible: face.name !== ""
			width: Math.min(implicitWidth, Theme.workspaceNameMaxWidth)
			elide: Text.ElideRight
			text: face.name
			font.weight: Font.DemiBold
		}
	}
}
