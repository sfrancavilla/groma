import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import ".."
import "../ui"
import "../icons"

// Feedback for the keys that change something you cannot see happening.
//
// The media and brightness keys call in here rather than running brightnessctl
// and wpctl themselves, so the shell makes the change and shows it as one
// action. Watching sysfs to discover what a keybind just did would be guessing
// at our own behaviour.
Scope {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property bool sinkReady: !!(root.sink?.ready && root.sink?.audio)

	PwObjectTracker {
		objects: [Pipewire.defaultAudioSink]
	}

	// Brightness is read from sysfs and written with brightnessctl. Watching
	// the file keeps us right if it changes some other way. The device is
	// found at start (Backlight.qml); with none there is nothing to read.
	readonly property string backlight: Backlight.device

	FileView {
		id: brightnessFile

		path: root.backlight !== "" ? `/sys/class/backlight/${root.backlight}/brightness` : ""
		watchChanges: true
		onFileChanged: reload()
	}

	FileView {
		id: brightnessMax

		path: root.backlight !== "" ? `/sys/class/backlight/${root.backlight}/max_brightness` : ""
	}

	readonly property real brightness: {
		const max = parseInt(brightnessMax.text());
		const now = parseInt(brightnessFile.text());
		return max > 0 && now >= 0 ? now / max : 0;
	}

	// The default sink changing is something that happens to you rather than
	// something you did: a headset connects, a cable goes in, and the sound
	// moves without anything on screen saying so. Worth announcing, unlike a
	// volume step, which you can hear.
	property string lastSink: ""

	onSinkChanged: {
		const name = root.sink?.name ?? "";

		// Nothing to announce on the way up. The first sink after a reload is
		// recorded, not flashed, or every save would fire the OSD.
		if (name === "" || root.lastSink === "") {
			root.lastSink = name;
			return;
		}

		if (name === root.lastSink)
			return;

		root.lastSink = name;
		root.flash("output");
	}

	// Which reading is on screen, and for how long.
	property string kind: ""

	// What the card is drawing. Held through the fade: `kind` is cleared the
	// moment the timer fires, and the card takes another 140ms to go, so
	// keying the contents off it swapped a device name for the volume slider
	// inside a card that was still on screen.
	property string showing: ""

	onKindChanged: if (root.kind !== "") root.showing = root.kind;

	Timer {
		id: hideTimer

		interval: root.textual ? 2400 : 1600
		onTriggered: root.kind = ""
	}

	function flash(what) {
		root.kind = what;
		hideTimer.restart();
	}

	// A line of text with the speaker beside it, for things that happened to
	// the sound rather than levels of it.
	property string message: ""

	function say(text) {
		root.message = text;
		root.flash("message");
	}

	readonly property bool textual:
		root.showing === "output" || root.showing === "message"

	function stepVolume(delta) {
		if (!root.sinkReady)
			return;

		root.sink.audio.volume =
			Math.max(0, Math.min(1, root.sink.audio.volume + delta));
		root.flash("volume");
	}

	function stepBrightness(delta) {
		// No backlight - a desktop, a virtual machine - and the keys do
		// nothing, rather than flash a level nobody can change.
		if (root.backlight === "")
			return;

		// brightnessctl clamps for us, and percentages keep the steps even
		// across the curve.
		Quickshell.execDetached(["brightnessctl", "-d", root.backlight,
			"set", delta > 0 ? "5%+" : "5%-"]);
		root.flash("brightness");
	}

	PanelWindow {
		id: panel

		visible: root.kind !== "" || card.opacity > 0.01

		anchors {
			bottom: true
		}

		exclusionMode: ExclusionMode.Ignore
		margins.bottom: 80

		readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0

		implicitWidth: 280 + panel.pad * 2
		implicitHeight: card.implicitHeight + panel.pad * 2
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:osd"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: card
			radius: Theme.radiusPanel
		}

		GlassPanel {
			id: card

			anchors.fill: parent
			anchors.margins: panel.pad
			radius: Theme.radiusPanel
			implicitHeight: row.implicitHeight + Theme.tilePadding * 2

			opacity: root.kind !== "" ? 1 : 0
			scale: root.kind !== "" ? 1 : 0.96

			Behavior on opacity {
				NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
			}
			Behavior on scale {
				NumberAnimation { duration: 160; easing.type: Easing.OutBack }
			}

			Row {
				id: row

				anchors {
					left: parent.left
					right: parent.right
					verticalCenter: parent.verticalCenter
					leftMargin: Theme.tilePadding
					rightMargin: Theme.tilePadding
				}

				spacing: Theme.spacingM

				SpeakerIcon {
					anchors.verticalCenter: parent.verticalCenter
					visible: root.showing === "volume" || root.textual
					color: Theme.glassTextPrimary

					waves: !root.sinkReady || root.sink.audio.muted
							|| root.sink.audio.volume <= 0 ? 0
						: root.sink.audio.volume > 0.5 ? 2 : 1
				}

				BrightnessIcon {
					anchors.verticalCenter: parent.verticalCenter
					visible: root.showing === "brightness"
					color: Theme.glassTextPrimary
					level: root.brightness
				}

				// Where the sliders go when the OSD is naming a device rather
				// than showing a level.
				Text {
					anchors.verticalCenter: parent.verticalCenter
					visible: root.textual
					width: parent.width - 18 - Theme.spacingM
					elide: Text.ElideRight
					text: root.showing === "message" ? root.message : Audio.sinkLabel(root.sink)
					font.pixelSize: Theme.fontLead
					font.weight: Font.DemiBold
					color: Theme.glassTextPrimary
				}

				Slider {
					anchors.verticalCenter: parent.verticalCenter
					visible: !root.textual
					width: parent.width - 18 - value.width - Theme.spacingM * 2
					interactive: false

					value: root.showing === "brightness"
						? root.brightness
						: root.sinkReady ? root.sink.audio.volume : 0

					active: root.showing === "brightness"
						|| !(root.sinkReady && root.sink.audio.muted)
				}

				Text {
					id: value

					anchors.verticalCenter: parent.verticalCenter
					visible: !root.textual
					width: 34
					horizontalAlignment: Text.AlignRight
					font.pixelSize: Theme.fontBody
					color: Theme.glassTextPrimary

					text: {
						if (root.showing === "brightness")
							return Math.round(root.brightness * 100) + "%";
						if (!root.sinkReady)
							return "--";
						return root.sink.audio.muted
							? "off"
							: Math.round(root.sink.audio.volume * 100) + "%";
					}
				}
			}
		}
	}

	// The keys call these rather than running the tools themselves.
	IpcHandler {
		target: "keys"

		function volumeUp(): void {
			root.stepVolume(0.05);
		}

		function volumeDown(): void {
			root.stepVolume(-0.05);
		}

		function volumeMute(): void {
			if (!root.sinkReady)
				return;

			root.sink.audio.muted = !root.sink.audio.muted;
			root.flash("volume");
		}

		function brightnessUp(): void {
			root.stepBrightness(1);
		}

		function brightnessDown(): void {
			root.stepBrightness(-1);
		}
	}
}
