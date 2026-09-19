import QtQuick

// A pane of glass.
//
// The design's recipe, and nothing more:
//
//   background:  rgba(255,255,255,.14)                 - flat
//   border:      1px solid rgba(255,255,255,.32)       - uniform
//   box-shadow:  0 16px 40px rgba(0,0,0,.30)           - it floats
//
// The design's `inset 0 1px 0 rgba(255,255,255,.45)` is deliberately left out.
// Three attempts at it all read as a stray line on the top edge rather than as
// a lit surface - duplicating the border, hanging outside the corners, or
// simply being visible as a line. The uniform border carries the edge alone.
//
// Earlier versions graded both the fill and the edge from light at the top to
// dark at the bottom, on the theory that real glass catches light unevenly.
// On screen that reads as a white-to-grey panel rather than as one surface,
// which is the opposite of the intent.
//
// Falls back to a flat opaque surface when Theme.glass is off, so callers
// never branch on it themselves. Anything declared inside lands on top.
Rectangle {
	id: panel

	// Tints the edge for something urgent, rather than drawing a red outline.
	property bool danger: false
	// The bar sits against a screen edge and has nowhere to cast into.
	property int shadowLayers: Theme.glassShadowLayers

	default property alias content: contentHolder.data

	radius: Theme.radiusMedium

	color: Theme.glass ? Theme.glassSurface : Theme.surface
	border.width: 1
	border.color: Theme.glass
		? (panel.danger ? Theme.glassEdgeDanger : Theme.glassEdge)
		: (panel.danger ? Theme.danger : Theme.borderSubtle)

	// Concentric rings of decreasing opacity, standing in for a blurred
	// shadow. The curve matters more than the count: a linear fade reads as
	// banding, so opacity falls off as a power of the distance.
	Repeater {
		model: Theme.glass ? panel.shadowLayers : 0

		Rectangle {
			id: ring

			required property int index

			readonly property real spread: ring.index + 1
			readonly property real reach: Math.max(1, panel.shadowLayers)
			// Shadows fall downward.
			readonly property real drift: ring.spread * Theme.glassShadowDrift

			anchors.fill: parent
			anchors.leftMargin: -ring.spread
			anchors.rightMargin: -ring.spread
			anchors.topMargin: -ring.spread + ring.drift
			anchors.bottomMargin: -ring.spread - ring.drift

			radius: parent.radius + ring.spread
			color: "transparent"
			border.width: 1

			border.color: Qt.rgba(0, 0, 0, Theme.glassShadowAlpha
				* Math.pow(1 - ring.index / ring.reach, Theme.glassShadowFalloff))
		}
	}

	// Declared last, so caller content sits above the glass.
	Item {
		id: contentHolder

		anchors.fill: parent
	}
}
