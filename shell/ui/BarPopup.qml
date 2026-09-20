import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."

// A readout in the bar, and the tile it opens underneath itself.
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
	property string trailing: ""

	// Names this popup's layer-shell surfaces, so `hyprctl layers` can tell
	// them apart. IPC is deliberately not here: only one handler may claim a
	// target, so a caller that wants its own functions would silently displace
	// one declared in here.
	property string name: ""

	property bool open: false

	// For the caller's trigger: dim it until pointed at.
	readonly property bool active: mouse.containsMouse || root.open

	// Value animations should run while the tile is open and settled, but not
	// while it is opening - mapping the window lays everything out from zero
	// width, and animating that reads as the contents sliding into place every
	// time.
	readonly property bool settled: root.open && tile.opacity > 0.99

	signal secondaryClicked
	signal scrolled(int direction)

	implicitWidth: triggerLoader.implicitWidth
	implicitHeight: triggerLoader.implicitHeight

	// The bar spans the screen, so this item's position inside it is its
	// position on screen.
	//
	// mapToItem is a function call, and QML cannot know when to re-run one -
	// bound naively it evaluates once during early layout, before the row has
	// positioned anything, and keeps that answer forever. Reading the geometry
	// it depends on first registers those as dependencies.
	readonly property real triggerRight: {
		void [root.width, root.x, root.parent?.x, root.parent?.width,
			root.barWidth];

		return root.mapToItem(null, root.width, 0).x;
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

	PanelWindow {
		id: panel

		// Stays mapped until the closing animation has finished, otherwise the
		// window unmaps instantly and there is nothing left to animate.
		visible: root.open || tile.opacity > 0.01

		anchors {
			top: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore

		// Sit under the bar, and line the tile's right edge up with the readout
		// that opened it rather than with the screen edge. The shadow padding
		// is inside the window, so it comes out of both margins.
		margins {
			top: Math.max(0, Theme.barHeight + Theme.barPopupGap - panel.pad)
			right: Math.max(0, root.barWidth - root.triggerRight - panel.pad)
		}

		readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0

		implicitWidth: Theme.tileWidth + panel.pad * 2
		implicitHeight: tile.implicitHeight + panel.pad * 2
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: `groma:${root.name}`
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: tile
			radius: Theme.radiusPanel
		}

		GlassTile {
			id: tile

			anchors.fill: parent
			anchors.margins: panel.pad

			title: root.title
			trailing: root.trailing

			opacity: root.open ? 1 : 0
			scale: root.open ? 1 : 0.96
			y: root.open ? 0 : -6

			Behavior on opacity {
				NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
			}
			Behavior on scale {
				NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
			}
			Behavior on y {
				NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
			}
		}
	}

	// Straight through to the tile's column, so a caller's children are laid
	// out by it rather than stacking inside a wrapper.
	default property alias content: tile.content

}
