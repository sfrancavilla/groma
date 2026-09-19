import QtQuick

// A pane of glass.
//
// The design's recipe, and nothing more:
//
//   background:  rgba(255,255,255,.14)                 - flat
//   border:      1px solid rgba(255,255,255,.32)       - uniform
//   box-shadow:  inset 0 1px 0 rgba(255,255,255,.45)   - lit top edge
//                0 16px 40px rgba(0,0,0,.30)           - it floats
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

	// Paint the desktop's colour inside the surface, since we cannot sample
	// it. The caller supplies where this panel sits, so the colour lines up
	// with the wallpaper behind it.
	property bool wash: false
	property real washOriginX: 0
	property real washOriginY: 0
	property real washFieldWidth: width
	property real washFieldHeight: height

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

	GlassWash {
		anchors.fill: parent
		visible: Theme.glass && panel.wash
		radius: panel.radius
		originX: panel.washOriginX
		originY: panel.washOriginY
		fieldWidth: panel.washFieldWidth
		fieldHeight: panel.washFieldHeight
	}

	// `inset 0 1px 0`: the top of the edge, lit.
	//
	// It sits *on* the border rather than below it. Drawn one pixel down, it
	// is a second line beside the border - two bright rows, which on a scaled
	// display reads as a doubled edge.
	//
	// And it fades out where the corners begin rather than stopping short of
	// them. A straight line inset by less than the radius has its ends hanging
	// in the space the corner has already curved away from, so they float
	// outside the panel's outline.
	Rectangle {
		id: litEdge

		// How far along the width the straight part of the top edge starts.
		readonly property real corner:
			Math.min(0.45, parent.radius / Math.max(1, parent.width))

		visible: Theme.glass
		anchors {
			left: parent.left
			right: parent.right
			top: parent.top
			leftMargin: 1
			rightMargin: 1
		}

		height: 1

		gradient: Gradient {
			orientation: Gradient.Horizontal

			GradientStop { position: 0.0; color: "#00ffffff" }
			GradientStop { position: litEdge.corner; color: Theme.glassInnerHighlight }
			GradientStop { position: 1.0 - litEdge.corner; color: Theme.glassInnerHighlight }
			GradientStop { position: 1.0; color: "#00ffffff" }
		}
	}

	// Declared last, so caller content sits above the glass.
	Item {
		id: contentHolder

		anchors.fill: parent
	}
}
