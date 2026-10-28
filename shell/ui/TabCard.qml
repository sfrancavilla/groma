import Quickshell
import QtQuick
import QtQuick.Shapes
import ".."

// A card that hangs from something in the bar like a tab, and grows down out
// of it - the way Caelestia's popouts grow out of its bar.
//
// One drawn outline: a tab standing round whatever opened the card, meeting
// the card in a curve. Opening, the tab drops from the screen edge and the
// card grows out of it, its contents sliding out from under the join; closing
// runs it back. Pointed at something else in the bar, the tab slides there
// and the card resizes.
//
// It fills a surface laid across the top of the screen, so its coordinates
// are the screen's. The caller owns that surface and hands it `blurRegion`.
// What goes in the card is the caller's, and so is what goes on the tab: the
// glass is dense enough to hide the bar under it, so whatever opened the card
// has to be drawn again, in `tabLayer`.
Item {
	id: card

	// What the tab stands round, in screen coordinates.
	property rect anchorRect: Qt.rect(0, 0, 0, 0)
	property real tabPadding: Theme.tabPadding
	// Things on the right of the bar open leftward, so the card stays on screen.
	property bool alignRight: false
	// The clock, in the middle of the bar, opens a card centred under it: the
	// tab meets the body half way along, with a join on either side.
	property bool centred: false
	property bool open: false
	property real bodyWidth: Theme.tileWidth
	// How tall the card is when all the way out: the height of its contents.
	property real contentHeight: 0

	default property alias content: slide.data
	// Over the tab and cut to it. Its coordinates start at the tab's corner.
	readonly property alias tabLayer: tabLayer
	// The card's body as it stands, for input regions and clicks outside.
	readonly property alias bodyItem: body

	property real tabX: card.anchorRect.x - card.tabPadding
	property real tabWidth: card.anchorRect.width + card.tabPadding * 2
	readonly property real tabY: Theme.tabInset
	readonly property real bodyX: card.centred ? card.tabX + (card.tabWidth - card.bodyWidth) / 2
		: card.alignRight ? card.tabX + card.tabWidth - card.bodyWidth : card.tabX

	// How far the card is out, 0 to 1 - a little past 1 on the way, as the
	// curve overshoots. The first part of it drops the tab from the screen
	// edge; the rest grows the card out of the tab. Closing runs it back: the
	// card goes into the tab, and the tab goes up into the edge.
	//
	// Nothing fades. What the caller draws on the tab sits exactly on the
	// real thing under it, and the bar's glyphs are slightly translucent: a
	// fading tab let the two show through each other, and the glyph dimmed
	// or brightened for a moment every time a card closed. A tab that
	// retracts only ever shows one of them at a time.
	property real reveal: card.open ? 1 : 0
	readonly property real tabShare: 0.15
	readonly property real tabProgress: Math.max(0, Math.min(1, card.reveal / card.tabShare))
	readonly property real bodyProgress: Math.max(0, (card.reveal - card.tabShare) / (1 - card.tabShare))

	readonly property real tabFullHeight: Theme.barHeight - Theme.tabInset * 2
	readonly property real bodyY: card.tabY + card.tabFullHeight * card.tabProgress
	readonly property real tabRadius: Math.min(Theme.radiusMedium, (card.bodyY - card.tabY) / 2)

	// Animated, so a change of contents resizes the card.
	property real fullHeight: card.contentHeight
	readonly property real bodyHeight: Math.max(0, card.bodyProgress * card.fullHeight)
	readonly property real bodyRadius: Math.min(Theme.radiusPanel, card.bodyHeight / 2)

	// With no card out, the outline is the tab alone. Drawn at the card's
	// width, a card of no height is its top and bottom edges on one another:
	// a bright line across the screen while the tab goes up.
	readonly property bool bodyShown: card.bodyHeight >= 0.5
	readonly property real outlineLeft: card.bodyShown ? card.bodyX : card.tabX
	readonly property real outlineRight: card.bodyShown ? card.bodyX + card.bodyWidth : card.tabX + card.tabWidth
	readonly property real joinRadius: card.bodyShown ? Theme.tabJoin * card.tabProgress : 0

	// Out at all: the caller's surface should be up.
	readonly property bool out: card.reveal > 0.001
	// Still on its way out or in.
	readonly property bool moving: revealMotion.running

	readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0
	// How tall the caller's surface has to be.
	readonly property real extent: Theme.barHeight - Theme.tabInset
		+ Math.max(card.contentHeight, card.fullHeight) + card.pad * 2 + Theme.spacingL

	// No region at all while the body is too thin to have one: an empty region
	// makes Hyprland blur the whole surface, a pane of frosted glass across
	// the top of the screen. The tab is left out: it lies over the bar, and
	// blurring there would blur what the bar shows.
	readonly property var blurRegion: card.bodyHeight >= 1 ? region : null

	Behavior on reveal {
		NumberAnimation {
			id: revealMotion

			duration: Theme.motionSpatialDuration
			easing.type: Easing.Bezier
			easing.bezierCurve: Theme.motionSpatial
		}
	}
	// In its tab, it goes straight to where it is wanted; out, it slides.
	Behavior on tabX {
		enabled: card.out

		NumberAnimation {
			duration: Theme.motionSpatialDuration
			easing.type: Easing.Bezier
			easing.bezierCurve: Theme.motionSpatial
		}
	}
	Behavior on tabWidth {
		enabled: card.out

		NumberAnimation {
			duration: Theme.motionSpatialDuration
			easing.type: Easing.Bezier
			easing.bezierCurve: Theme.motionSpatial
		}
	}
	Behavior on fullHeight {
		enabled: card.out

		NumberAnimation {
			duration: Theme.motionSpatialDuration
			easing.type: Easing.Bezier
			easing.bezierCurve: Theme.motionSpatial
		}
	}

	Region {
		id: region

		item: body
		radius: card.bodyRadius

		// The body's corner under the tab is square, where the tab runs into it.
		Region {
			item: corner
		}
	}

	// The body casts the shadow; the tab is on the bar and has nowhere to cast
	// it. Cut at the body's top, so no ring runs under the tab.
	Item {
		x: card.bodyX - card.pad
		y: card.bodyY
		width: card.bodyWidth + card.pad * 2
		height: card.bodyHeight + card.pad * 2
		clip: true
		// Rings round a card of no height are dark lines across the screen.
		visible: card.bodyShown

		GlassShadow {
			x: card.pad
			width: card.bodyWidth
			height: card.bodyHeight
			radius: card.bodyRadius
		}
	}

	// Drawn clockwise from the body's bottom-left. Left-aligned, the tab's
	// left edge runs straight down into the body's; right-aligned, its right
	// edge does, and the join is on the other side.
	Shape {
		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer
		// A tab of no height is a bright line along the screen edge.
		visible: card.bodyY - card.tabY >= 1

		ShapePath {
			id: edge

			readonly property bool right: card.alignRight
			readonly property real r: card.tabRadius
			readonly property real join: card.joinRadius
			readonly property real big: card.bodyRadius
			readonly property real tabLeft: card.tabX
			readonly property real tabRight: card.tabX + card.tabWidth
			readonly property real tabTop: card.tabY
			readonly property real top: card.bodyY
			readonly property real bottom: card.bodyY + card.bodyHeight
			readonly property real left: card.outlineLeft
			readonly property real rightEdge: card.outlineRight

			// Centred, the outline below draws it instead.
			fillColor: card.centred ? "transparent" : Theme.tabCardSurface
			strokeColor: card.centred ? "transparent" : Theme.glassEdge
			strokeWidth: 1

			startX: edge.left
			startY: edge.bottom - edge.big

			// Up the left: into the tab, or round the body's corner.
			PathLine { x: edge.left; y: edge.right ? edge.top + edge.big : edge.tabTop + edge.r }
			PathArc {
				x: edge.right ? edge.left + edge.big : edge.left + edge.r
				y: edge.right ? edge.top : edge.tabTop
				radiusX: edge.right ? edge.big : edge.r
				radiusY: radiusX
			}
			// Right-aligned: along the body's top to the join, and up the tab.
			PathLine { x: edge.right ? edge.tabLeft - edge.join : edge.tabRight - edge.r; y: edge.right ? edge.top : edge.tabTop }
			PathArc {
				x: edge.right ? edge.tabLeft : edge.tabRight
				y: edge.right ? edge.top - edge.join : edge.tabTop + edge.r
				radiusX: edge.right ? edge.join : edge.r
				radiusY: radiusX
				direction: edge.right ? PathArc.Counterclockwise : PathArc.Clockwise
			}
			// Left-aligned: down the tab to the join, and out along the body.
			PathLine { x: edge.right ? edge.tabLeft : edge.tabRight; y: edge.right ? edge.tabTop + edge.r : edge.top - edge.join }
			PathArc {
				x: edge.right ? edge.tabLeft + edge.r : edge.tabRight + edge.join
				y: edge.right ? edge.tabTop : edge.top
				radiusX: edge.right ? edge.r : edge.join
				radiusY: radiusX
				direction: edge.right ? PathArc.Clockwise : PathArc.Counterclockwise
			}
			PathLine { x: edge.right ? edge.tabRight - edge.r : edge.rightEdge - edge.big; y: edge.right ? edge.tabTop : edge.top }
			PathArc {
				x: edge.right ? edge.tabRight : edge.rightEdge
				y: edge.right ? edge.tabTop + edge.r : edge.top + edge.big
				radiusX: edge.right ? edge.r : edge.big
				radiusY: radiusX
			}
			// Down the right and round the bottom.
			PathLine { x: edge.rightEdge; y: edge.bottom - edge.big }
			PathArc { x: edge.rightEdge - edge.big; y: edge.bottom; radiusX: edge.big; radiusY: edge.big }
			PathLine { x: edge.left + edge.big; y: edge.bottom }
			PathArc { x: edge.left; y: edge.bottom - edge.big; radiusX: edge.big; radiusY: edge.big }
		}

		// Centred: along the body's top to a join, up and over the tab, down
		// into a second join, and on along the top. With no body out, the
		// joins have no radius and the outline is the tab alone.
		ShapePath {
			id: middle

			readonly property real r: card.tabRadius
			readonly property real join: card.joinRadius
			readonly property real big: card.bodyRadius
			readonly property real tabLeft: card.tabX
			readonly property real tabRight: card.tabX + card.tabWidth
			readonly property real tabTop: card.tabY
			readonly property real top: card.bodyY
			readonly property real bottom: card.bodyY + card.bodyHeight
			readonly property real left: card.outlineLeft
			readonly property real rightEdge: card.outlineRight

			fillColor: card.centred ? Theme.tabCardSurface : "transparent"
			strokeColor: card.centred ? Theme.glassEdge : "transparent"
			strokeWidth: 1

			startX: middle.left
			startY: middle.bottom - middle.big

			PathLine { x: middle.left; y: middle.top + middle.big }
			PathArc { x: middle.left + middle.big; y: middle.top; radiusX: middle.big; radiusY: middle.big }
			PathLine { x: middle.tabLeft - middle.join; y: middle.top }
			PathArc {
				x: middle.tabLeft; y: middle.top - middle.join
				radiusX: middle.join; radiusY: middle.join
				direction: PathArc.Counterclockwise
			}
			PathLine { x: middle.tabLeft; y: middle.tabTop + middle.r }
			PathArc { x: middle.tabLeft + middle.r; y: middle.tabTop; radiusX: middle.r; radiusY: middle.r }
			PathLine { x: middle.tabRight - middle.r; y: middle.tabTop }
			PathArc { x: middle.tabRight; y: middle.tabTop + middle.r; radiusX: middle.r; radiusY: middle.r }
			PathLine { x: middle.tabRight; y: middle.top - middle.join }
			PathArc {
				x: middle.tabRight + middle.join; y: middle.top
				radiusX: middle.join; radiusY: middle.join
				direction: PathArc.Counterclockwise
			}
			PathLine { x: middle.rightEdge - middle.big; y: middle.top }
			PathArc { x: middle.rightEdge; y: middle.top + middle.big; radiusX: middle.big; radiusY: middle.big }
			PathLine { x: middle.rightEdge; y: middle.bottom - middle.big }
			PathArc { x: middle.rightEdge - middle.big; y: middle.bottom; radiusX: middle.big; radiusY: middle.big }
			PathLine { x: middle.left + middle.big; y: middle.bottom }
			PathArc { x: middle.left; y: middle.bottom - middle.big; radiusX: middle.big; radiusY: middle.big }
		}
	}

	Item {
		id: tabLayer

		x: card.tabX
		y: card.tabY
		width: card.tabWidth
		height: card.bodyY - card.tabY
		clip: true
	}

	// For the blur: the body's square corner under the tab.
	Item {
		id: corner

		x: card.tabX
		y: card.bodyY
		width: card.tabWidth
		height: Math.min(card.bodyHeight, Theme.radiusPanel)
	}

	// The contents come out from under the tab as the body grows, and are cut
	// off where the body ends.
	Item {
		id: body

		x: card.bodyX
		y: card.bodyY
		width: card.bodyWidth
		height: card.bodyHeight
		clip: true

		Item {
			id: slide

			width: card.bodyWidth
			height: card.contentHeight
			y: (card.bodyProgress - 1) * card.contentHeight
		}
	}
}
