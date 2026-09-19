import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick

// The bar's volume readout, and the panel it opens when clicked.
//
// This is the first widget that *writes* to something rather than just
// reporting it, and the first with state of its own - whether it is open.
Item {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property bool ready: root.sink?.ready && root.sink?.audio
	readonly property bool muted: root.ready && root.sink.audio.muted
	readonly property real volume: root.ready ? root.sink.audio.volume : 0

	// The widget's own state. Everything about the panel follows from it.
	property bool open: false

	implicitWidth: label.implicitWidth
	implicitHeight: label.implicitHeight

	Text {
		id: label

		anchors.centerIn: parent
		color: root.muted ? Theme.glassTextMuted : Theme.glassTextPrimary
		style: Theme.glass ? Text.Raised : Text.Normal
		styleColor: Theme.glassTextShadow

		text: !root.ready ? "Vol --"
			: root.muted ? "Muted"
			: "Vol " + Math.round(root.volume * 100) + "%"

		// A readout that opens something should say so before you click it.
		opacity: trigger.containsMouse || root.open ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}
	}

	MouseArea {
		id: trigger

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton

		onEntered: closeTimer.stop()
		onExited: if (root.open) closeTimer.restart()

		onClicked: mouse => {
			if (mouse.button === Qt.MiddleButton)
				root.sink.audio.muted = !root.sink.audio.muted;
			else
				root.open = !root.open;
		}

		// Scrolling over the readout adjusts the volume without opening it.
		onWheel: wheel => {
			if (!root.ready)
				return;

			const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
			root.sink.audio.volume = Math.max(0, Math.min(1, root.volume + step));
		}
	}

	PanelWindow {
		id: panel

		// Stays mapped until the closing animation has finished, otherwise the
		// window would vanish before anything had a chance to animate out.
		visible: root.open || card.opacity > 0.01

		anchors {
			top: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		margins {
			top: 40
			right: 8
		}

		implicitWidth: 260
		implicitHeight: 96
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:volume"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: card
			radius: Theme.radiusLarge
		}

		GlassPanel {
			id: card

			anchors.fill: parent
			anchors.margins: Theme.glassShadowPadding
			radius: Theme.radiusLarge

			// The whole open/close animation. Three properties easing together
			// reads as one movement: it fades in, grows the last few percent,
			// and settles downward from under the bar.
			opacity: root.open ? 1 : 0
			scale: root.open ? 1 : 0.94
			y: root.open ? 0 : -8

			Behavior on opacity {
				NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
			}
			Behavior on scale {
				NumberAnimation { duration: 180; easing.type: Easing.OutBack }
			}
			Behavior on y {
				NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
			}

			// Closes shortly after the pointer leaves, so it does not vanish
			// the instant you overshoot the slider on the way to it.
			MouseArea {
				anchors.fill: parent
				hoverEnabled: true
				onEntered: closeTimer.stop()
				onExited: closeTimer.restart()
			}

			Column {
				anchors {
					left: parent.left
					right: parent.right
					verticalCenter: parent.verticalCenter
					leftMargin: 14
					rightMargin: 14
				}

				spacing: 10

				Text {
					text: root.muted ? "Muted"
						: Math.round(root.volume * 100) + "%"
					font.pixelSize: 15
					font.bold: true
					color: root.muted ? Theme.glassTextMuted : Theme.glassTextPrimary
				}

				// A slider, built from three rectangles and a mouse area.
				Item {
					width: parent.width
					height: 16

					Rectangle {
						id: track

						anchors.verticalCenter: parent.verticalCenter
						width: parent.width
						height: 5
						radius: height / 2
						color: Theme.glassControl
					}

					Rectangle {
						id: fill

						anchors.verticalCenter: parent.verticalCenter
						width: track.width * root.volume
						height: track.height
						radius: track.radius
						color: root.muted ? Theme.glassTextMuted : Theme.glassTextPrimary

						// Animate volume changes from elsewhere - the media
						// keys, or scrolling the bar - but not while dragging,
						// where the handle must track the pointer exactly.
						Behavior on width {
							enabled: !drag.pressed
							NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
						}
					}

					Rectangle {
						id: handle

						x: fill.width - width / 2
						anchors.verticalCenter: parent.verticalCenter
						width: 14
						height: 14
						radius: height / 2
						color: Theme.glassTextPrimary

						scale: drag.pressed ? 1.25 : drag.containsMouse ? 1.12 : 1.0

						Behavior on scale {
							NumberAnimation { duration: 110; easing.type: Easing.OutBack }
						}
						Behavior on x {
							enabled: !drag.pressed
							NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
						}
					}

					MouseArea {
						id: drag

						anchors.fill: parent
						anchors.margins: -6
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor

						function setFromX(x) {
							if (!root.ready)
								return;

							root.sink.audio.volume =
								Math.max(0, Math.min(1, x / track.width));
						}

						onPressed: mouse => drag.setFromX(mouse.x)
						onPositionChanged: mouse => {
							if (drag.pressed)
								drag.setFromX(mouse.x);
						}
					}
				}
			}
		}

		Timer {
			id: closeTimer

			interval: 500
			onTriggered: root.open = false
		}
	}


	// Lets the panel be driven from outside the shell, which makes it bindable
	// to a key and testable without a pointer:
	//
	//   qs -c groma ipc call volume toggle
	IpcHandler {
		target: "volume"

		function toggle(): void {
			root.open = !root.open;
		}

		// Not named show/hide: `show` collides with the `qs ipc show`
		// subcommand, and the call silently lists the functions instead.
		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}

		function set(percent: string): void {
			if (!root.ready)
				return;

			root.sink.audio.volume =
				Math.max(0, Math.min(1, parseFloat(percent) / 100));
		}
	}
}
