import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."
import "../ui"

// Every network in range, scrollable.
//
// The tile shows four, because a tile that grows with the airwaves is not a
// tile. This is where the rest live.
Scope {
	id: root

	// The network control, for its scan data and for what a click means. Both
	// are its business, and duplicating either here would let them disagree.
	property var controller: null

	property bool open: false

	function show() {
		root.open = true;
	}

	readonly property var networks: root.controller?.others ?? []

	PanelWindow {
		id: window

		visible: root.open || dialog.sheet.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:network-list"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			Keys.onEscapePressed: root.open = false

			title: "Networks in range"
			body: root.networks.length + " found"

			Item {
				width: parent.width
				// Tall enough to be worth scrolling, short enough to stay a
				// dialog rather than a window.
				height: Math.min(320, Math.max(64, root.networks.length * 36))

				ListView {
					id: list

					anchors.fill: parent
					clip: true
					spacing: Theme.spacingXs
					model: root.networks
					boundsBehavior: Flickable.StopAtBounds

					delegate: NetworkRow {
						required property var modelData

						width: list.width
						network: modelData
						detail: root.controller?.detail[modelData.name] ?? null
						bars: root.controller?.barsFor(modelData.name) ?? 0

						onActivated: {
							root.open = false;
							root.controller?.activate(modelData);
						}
					}
				}

				// Only worth saying when there is more below.
				Text {
					anchors {
						right: parent.right
						bottom: parent.bottom
						bottomMargin: -2
					}

					visible: list.contentHeight > list.height
						&& list.contentY + list.height < list.contentHeight - 4
					text: "scroll for more"
					font.pixelSize: 10
					opacity: 0.5
					color: Theme.glassTextPrimary
				}
			}

			Row {
				anchors.right: parent.right
				spacing: Theme.spacingS

				DialogButton {
					text: "Close"
					onClicked: root.open = false
				}
			}
		}
	}
}

