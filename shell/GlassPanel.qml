import QtQuick

// A pane of glass: gradient rim, inset body, feathered ambient shadow.
//
// The construction is fiddly enough that a second copy would drift from the
// first, and it is wanted in three places - notification cards, the
// authentication dialog and the bar. Falls back to a flat surface when
// Theme.glass is off, so callers never branch on it themselves.
//
// Anything declared inside a GlassPanel lands on top of the glass.
Rectangle {
	id: panel

	// Tints the rim for something urgent, rather than drawing a red outline.
	property bool danger: false

	// Paint the desktop's colour inside the surface, since we cannot sample
	// it. The caller supplies where this panel sits, so the colour lines up
	// with the wallpaper behind it.
	property bool wash: false
	property real washOriginX: 0
	property real washOriginY: 0
	property real washFieldWidth: width
	property real washFieldHeight: height
	// The bar sits against a screen edge and has nowhere to cast into.
	property int shadowLayers: Theme.glassShadowLayers

	radius: Theme.radiusMedium

	default property alias content: contentHolder.data

	// In glass mode this rectangle is only the edge: a gradient fading top to
	// bottom, with the body inset inside it. In flat mode it is the surface.
	color: Theme.glass ? "transparent" : Theme.surface
	border.width: Theme.glass ? 0 : (panel.danger ? 2 : 1)
	border.color: panel.danger ? Theme.danger : Theme.borderSubtle

	gradient: !Theme.glass ? null : panel.danger ? dangerRim : plainRim

	Gradient {
		id: plainRim

		GradientStop { position: 0.0; color: Theme.glassRimTop }
		GradientStop { position: 0.35; color: Theme.glassRimMid }
		GradientStop { position: 1.0; color: Theme.glassRimBottom }
	}

	Gradient {
		id: dangerRim

		GradientStop { position: 0.0; color: Theme.glassRimDangerTop }
		GradientStop { position: 0.35; color: Theme.glassRimDangerMid }
		GradientStop { position: 1.0; color: Theme.glassRimDangerBottom }
	}

	// Concentric rings of decreasing opacity, standing in for a blurred
	// shadow. The curve matters more than the count: a linear fade reads as
	// banding, so opacity falls off as a power of the distance.
	Repeater {
		model: Theme.glass ? panel.shadowLayers : 0

		Rectangle {
			id: ring

			required property int index

			readonly property real spread: ring.index + 1
			readonly property real reach:
				Math.max(1, panel.shadowLayers)
			// Shadows fall downward.
			readonly property real drift:
				ring.spread * Theme.glassShadowDrift

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

	// The body, inset by the rim width so the gradient reads as an edge.
	Rectangle {
		visible: Theme.glass
		anchors.fill: parent
		anchors.margins: Theme.glassRimWidth
		radius: parent.radius - Theme.glassRimWidth

		gradient: Gradient {
			GradientStop { position: 0.0; color: Theme.glassSurfaceTop }
			GradientStop { position: 1.0; color: Theme.glassSurfaceBottom }
		}
	}

	// `inset 0 1px 0` in the design: a lit line along the top inside edge. The
	// rim gradient fades over the whole panel, which is a different thing -
	// this is the hard edge that makes it look like a lit surface.
	Rectangle {
		visible: Theme.glass
		anchors {
			left: parent.left
			right: parent.right
			top: parent.top
			leftMargin: parent.radius * 0.5
			rightMargin: parent.radius * 0.5
			topMargin: Theme.glassRimWidth
		}

		height: 1
		color: Theme.glassInnerHighlight
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

	// Declared last, so caller content sits above the glass.
	Item {
		id: contentHolder

		anchors.fill: parent
	}
}
