import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's volume readout, and the control-center tile it opens.
//
// A BarPopup supplies the window, the click-catcher, the animation and the
// positioning; what is here is the glyph, the tile's contents, and what volume
// means.
BarPopup {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	// !! because both sides are undefined until PipeWire reports in, and
	// undefined is not a bool.
	readonly property bool ready: !!(root.sink?.ready && root.sink?.audio)
	readonly property bool muted: root.ready && root.sink.audio.muted
	readonly property real volume: root.ready ? root.sink.audio.volume : 0
	readonly property bool silent: root.muted || root.volume <= 0

	readonly property var sinks: Pipewire.nodes.values.filter(
		node => node.isSink && !node.isStream)

	name: "volume"
	title: "Sound"
	trailing: root.sink?.description ?? ""

	function setVolume(v) {
		if (root.ready)
			root.sink.audio.volume = Math.max(0, Math.min(1, v));
	}

	trigger: SpeakerIcon {
		height: Theme.barIconSize
		width: height * aspect

		// The glyph is the readout: no waves when silent, one below half, two
		// above. A pack would need three separate icons to say this.
		waves: root.silent ? 0 : root.volume > 0.5 ? 2 : 1
		color: root.silent ? Theme.glassTextMuted : Theme.glassTextPrimary

		opacity: root.active ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}
	}

	onSecondaryClicked: {
		if (root.ready)
			root.sink.audio.muted = !root.sink.audio.muted;
	}

	onScrolled: direction => root.setVolume(root.volume + direction * 0.05)

	IpcHandler {
		target: "volume"
		enabled: root.hasIpc

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

	// Descriptions are only populated for tracked nodes.
	PwObjectTracker {
		objects: root.sinks
	}

	Slider {
		id: volumeSlider

		width: parent.width
		value: root.volume
		active: !root.muted
		animateValue: root.settled
		onMoved: v => root.setVolume(v)

		SpeakerIcon {
			id: speaker

			anchors {
				left: parent.left
				leftMargin: Theme.spacingL
				verticalCenter: parent.verticalCenter
			}

			// Dark once the lens has reached it, since the lens is nearly
			// white and so is this - and dimmed when there is nothing coming
			// out, matching the bar's glyph.
			color: volumeSlider.knobLeft < speaker.x + speaker.width
				? Theme.glassTextOnLens
				: root.silent ? Theme.glassTextMuted : Theme.glassTextPrimary

			waves: root.silent ? 0 : root.volume > 0.5 ? 2 : 1
		}

		Text {
			id: volumeValue

			// At the right end of the track, moving ahead of the lens when it
			// gets there rather than sitting half under it - as the battery's
			// does.
			readonly property real endX: parent.width - Theme.spacingL - width
			x: volumeSlider.knobRight + Theme.spacingS > endX
				? volumeSlider.knobLeft - Theme.spacingS - width : endX
			anchors.verticalCenter: parent.verticalCenter

			text: root.muted ? "Muted" : Math.round(root.volume * 100)
			font.pixelSize: Theme.fontBody

			color: Theme.glassTextPrimary
		}
	}

	// Output devices. Chips wrap rather than shrink, so the tile grows downward
	// instead of squeezing names to nothing.
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

				text: Audio.sinkLabel(modelData)

				onClicked: Pipewire.preferredDefaultAudioSink = modelData
			}
		}
	}
}
