import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."

// A readout in the bar, and the card it opens: hanging from the readout like
// a tab, and growing down out of it (TabCard.qml).
//
// Volume and battery were half identical before this existed - 155 lines of the
// same window, click-catcher, animation and positioning. What differs between
// them is the glyph, the tile's contents, and what they mean; everything here
// is what did not.
//
// Anything declared inside a BarPopup is the tile's content. The bar glyph goes
// in `trigger`.
Item {
	id: root

	// The glyph shown in the bar. A Component, so it is created in the
	// caller's scope and can bind to the caller's state.
	property Component trigger

	property string title: ""
	// The card's width. A tile's unless what it holds wants more room.
	property real cardWidth: Theme.tileWidth
	property string trailing: ""
	// Hung from the middle of the bar: the card opens centred under it.
	property bool centred: false
	property color trailingColor: Theme.glassTextPrimary

	// Names this popup's layer-shell surfaces, so `hyprctl layers` can tell
	// them apart. IPC is deliberately not here: only one handler may claim a
	// target, so a caller that wants its own functions would silently displace
	// one declared in here.
	property string name: ""

	property bool open: false

	// For the caller's trigger: dim it until pointed at.
	readonly property bool active: mouse.containsMouse || root.open

	// Value animations should run while the tile is open and settled, but not
	// while it is opening - the card grows out of its tab with the contents
	// sliding out of it, and a value animating on top of that reads as the
	// contents moving twice.
	readonly property bool settled: root.open && !tabCard.moving

	signal secondaryClicked
	signal scrolled(int direction)

	implicitWidth: triggerLoader.implicitWidth
	implicitHeight: triggerLoader.implicitHeight

	// Where the trigger is on screen: the bar spans the screen, so its place
	// in the bar is its place on screen.
	//
	// mapToItem is a function call, and QML cannot know when to re-run one -
	// bound naively it evaluates once during early layout, before the row has
	// positioned anything, and keeps that answer forever. Reading the geometry
	// it depends on first registers those as dependencies.
	readonly property rect triggerRect: {
		// The row's y and height as well: it is centred in the bar, and
		// settles there only once every child has its height. On a cold start
		// the first answer came before that, and the trigger drawn on the tab
		// sat too high, cut off at the tab's edge.
		void [root.width, root.height, root.x, root.y, root.parent?.x, root.parent?.width,
			root.parent?.y, root.parent?.height, root.barWidth];

		const at = root.mapToItem(null, 0, 0);
		return Qt.rect(at.x, at.y, root.width, root.height);
	}

	readonly property real barWidth: root.QsWindow?.window?.width ?? 0

	Loader {
		id: triggerLoader

		anchors.centerIn: parent
		sourceComponent: root.trigger
	}

	MouseArea {
		id: mouse

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton

		onClicked: event => {
			if (event.button === Qt.MiddleButton)
				root.secondaryClicked();
			else
				root.open = !root.open;
		}

		onWheel: event => root.scrolled(event.angleDelta.y > 0 ? 1 : -1)
	}

	// A client only receives input on its own surfaces, so "click outside" has
	// to be a surface. This one exists purely to catch that click.
	PanelWindow {
		visible: root.open

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Top
		WlrLayershell.namespace: `groma:${root.name}-catcher`
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		MouseArea {
			anchors.fill: parent
			onClicked: root.open = false
		}
	}

	// The card, hanging from the trigger (TabCard.qml), in a surface across
	// the top of the screen.
	PanelWindow {
		id: panel

		visible: tabCard.out

		anchors {
			top: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		implicitHeight: tabCard.extent
		color: "transparent"

		// The card takes clicks; the rest of this surface is the bar and the
		// desktop, and leaves them to the catcher underneath.
		mask: Region {
			item: tabCard.bodyItem
		}

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: `groma:${root.name}`
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: tabCard.blurRegion

		TabCard {
			id: tabCard

			anchors.fill: parent
			anchorRect: root.triggerRect
			// Opened from the right half of the bar, it opens leftward.
			alignRight: root.triggerRect.x + root.triggerRect.width / 2 > root.barWidth / 2
			centred: root.centred
			open: root.open
			bodyWidth: root.cardWidth
			contentHeight: tile.implicitHeight

			// The trigger again, on the tab: the glass hides the real one.
			// The same Component, so it shows the same state.
			Item {
				parent: tabCard.tabLayer
				x: root.triggerRect.x - tabCard.tabX
				y: root.triggerRect.y - tabCard.tabY
				width: root.triggerRect.width
				height: root.triggerRect.height

				Loader {
					anchors.centerIn: parent
					sourceComponent: root.trigger
				}
			}

			// The glass is the tab card's; this is only the tile's layout.
			GlassTile {
				id: tile

				width: root.cardWidth
				color: "transparent"
				border.width: 0
				shadowLayers: 0

				title: root.title
				trailing: root.trailing
				trailingColor: root.trailingColor
			}
		}
	}

	// Straight through to the tile's column, so a caller's children are laid
	// out by it rather than stacking inside a wrapper.
	default property alias content: tile.content

}
