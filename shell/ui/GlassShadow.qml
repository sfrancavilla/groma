import QtQuick
import ".."

// The shadow a pane of glass floats on, for the rounded rectangle this item
// fills: concentric rings of decreasing opacity, standing in for a blurred
// shadow. The curve matters more than the count: a linear fade reads as
// banding, so opacity falls off as a power of the distance.
//
// Its own piece because not every pane is a GlassPanel - the workspace card is
// a drawn shape, and still casts the same shadow from its body.
Item {
	id: shadow

	property real radius: Theme.radiusMedium
	property int layers: Theme.glassShadowLayers

	Repeater {
		model: Theme.glass ? shadow.layers : 0

		Rectangle {
			id: ring

			required property int index

			readonly property real spread: ring.index + 1
			readonly property real reach: Math.max(1, shadow.layers)
			// Shadows fall downward.
			readonly property real drift: ring.spread * Theme.glassShadowDrift

			anchors.fill: parent
			anchors.leftMargin: -ring.spread
			anchors.rightMargin: -ring.spread
			anchors.topMargin: -ring.spread + ring.drift
			anchors.bottomMargin: -ring.spread - ring.drift

			radius: shadow.radius + ring.spread
			color: "transparent"
			border.width: 1

			border.color: Qt.rgba(0, 0, 0, Theme.glassShadowAlpha
				* Math.pow(1 - ring.index / ring.reach, Theme.glassShadowFalloff))
		}
	}
}
