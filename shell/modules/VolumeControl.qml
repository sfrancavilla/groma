import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's volume readout, and the control-center tile it opens.
//
// Built from the shell's shared pieces - GlassTile, Slider, Chip - rather than
// its own. This is the tile the rest of the setup is modelled on.
Item {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	// !! because both sides are undefined until PipeWire reports in, and
	// undefined is not a bool.
	readonly property bool ready: !!(root.sink?.ready && root.sink?.audio)
	readonly property bool muted: root.ready && root.sink.audio.muted
	readonly property real volume: root.ready ? root.sink.audio.volume : 0

	readonly property var sinks: Pipewire.nodes.values.filter(
		node => node.isSink && !node.isStream)

	property bool open: false

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

	implicitWidth: label.implicitWidth
	implicitHeight: label.implicitHeight


	function setVolume(v) {
		if (root.ready)
			root.sink.audio.volume = Math.max(0, Math.min(1, v));
	}

	// Descriptions are only populated for tracked nodes.
	PwObjectTracker {
		objects: root.sinks
	}

	SpeakerIcon {
		id: label

		anchors.centerIn: parent

		height: Theme.barIconHeight
		width: height * label.aspect

		// The glyph is the readout: no waves when muted, one below half, two
		// above. A pack would need three separate icons to say this.
		//
		// Silent is silent, so zero gets the same crossed glyph as mute - it
		// previously fell through to "one wave", which says the opposite.
		waves: root.muted || root.volume <= 0 ? 0
			: root.volume > 0.5 ? 2 : 1
		color: root.muted || root.volume <= 0
			? Theme.glassTextMuted : Theme.glassTextPrimary

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

		onClicked: mouse => {
			if (mouse.button === Qt.MiddleButton)
				root.sink.audio.muted = !root.sink.audio.muted;
			else
				root.open = !root.open;
		}

		onWheel: wheel => {
			if (wheel.angleDelta.y > 0)
				root.setVolume(root.volume + 0.05);
			else
				root.setVolume(root.volume - 0.05);
		}
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
		WlrLayershell.namespace: "groma:volume-catcher"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		MouseArea {
			anchors.fill: parent
			onClicked: root.open = false
		}
	}

	PanelWindow {
		id: panel

		// Stays mapped until the closing animation has finished.
		visible: root.open || tile.opacity > 0.01

		anchors {
			top: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore

		// Sit under the bar, and line the panel's right edge up with the
		// readout that opened it rather than with the screen edge.
		//
		// The shadow padding is inside the window, so it has to come out of
		// both margins or the panel appears that much further from the bar.
		margins {
			top: Math.max(0, Theme.barHeight + Theme.barPopupGap - panel.pad)
			right: Math.max(0, root.barWidth - root.triggerRight - panel.pad)
		}

		readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0

		implicitWidth: Theme.tileWidth + panel.pad * 2
		implicitHeight: tile.implicitHeight + panel.pad * 2
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:volume"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: tile
			radius: Theme.radiusPanel
		}

		GlassTile {
			id: tile

			anchors.fill: parent
			anchors.margins: panel.pad

			title: "Sound"
			trailing: root.sink?.description ?? ""

			// Value changes should animate while you are looking at the panel,
			// but not while it is opening: mapping the window lays the track
			// out from zero width, and animating that reads as the slider
			// sliding up to the current volume every time you open it.
			readonly property bool settled: root.open && tile.opacity > 0.99

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

			Slider {
				id: volumeSlider

				width: parent.width
				value: root.volume
				active: !root.muted
				animateValue: tile.settled
				onMoved: v => root.setVolume(v)

				SpeakerIcon {
					id: speaker

					anchors {
						left: parent.left
						leftMargin: Theme.spacingL
						verticalCenter: parent.verticalCenter
					}

					// Dark once the lens has reached it, since the lens is
					// nearly white and so is this - and dimmed when there is
					// nothing coming out, matching the bar's glyph.
					color: volumeSlider.knobLeft < speaker.x + speaker.width
						? Theme.glassTextOnLens
						: root.muted || root.volume <= 0
							? Theme.glassTextMuted
							: Theme.glassTextPrimary
					// Silent is silent: zero gets the crossed glyph too.
					waves: root.muted || root.volume <= 0 ? 0
						: root.volume > 0.5 ? 2 : 1
				}

				Text {
					id: volumeValue

					anchors {
						right: parent.right
						rightMargin: Theme.spacingL
						verticalCenter: parent.verticalCenter
					}

					text: root.muted ? "Muted" : Math.round(root.volume * 100)
					font.pixelSize: Theme.fontBody

					color: volumeSlider.knobRight > volumeValue.x
						? Theme.glassTextOnLens : Theme.glassTextPrimary
				}
			}

			// Output devices. Chips wrap rather than shrink, so the tile grows
			// downward instead of squeezing names to nothing.
			Flow {
				id: chips

				readonly property int perRow: Math.min(2, root.sinks.length)
				readonly property real chipWidth:
					(width - (chips.perRow - 1) * Theme.spacingS)
					/ Math.max(1, chips.perRow)

				width: parent.width
				spacing: Theme.spacingS
				visible: root.sinks.length > 0

				Repeater {
					model: root.sinks

					Chip {
						required property var modelData

						width: chips.chipWidth
						active: modelData === Pipewire.defaultAudioSink

						// PipeWire offers three names for a sink and only one
						// is any use on a chip: nickname is the codec
						// ("ALC285 Analog"), description is device plus profile,
						// and the profile description is what it actually is.
						text: (modelData.properties
								|| {})["device.profile.description"]
							|| modelData.description
							|| modelData.nickname
							|| "Output"

						onClicked: Pipewire.preferredDefaultAudioSink = modelData
					}
				}
			}
		}
	}

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
			root.setVolume(parseFloat(percent) / 100);
		}
	}
}
