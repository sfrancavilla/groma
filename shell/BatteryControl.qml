import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick

// The bar's battery readout, and the tile it opens.
//
// Same grammar as the volume tile - title row, glass track, status line - but
// the track is a readout rather than a control: you cannot drag a battery.
Item {
	id: root

	// displayDevice is a synthetic aggregate: right for percentage, state and
	// time, but it carries no capacity, so health reads 0 off it. Health has
	// to come from the physical battery.
	readonly property var device: UPower.displayDevice
	readonly property var physical:
		UPower.devices.values.find(d => d.isLaptopBattery) ?? null
	readonly property real health: root.physical?.healthPercentage ?? 0
	// !! because both sides are undefined until UPower reports in.
	readonly property bool ready: !!(root.device?.ready && root.device?.isPresent)
	readonly property real level: root.ready ? root.device.percentage : 0
	readonly property int state: root.ready ? root.device.state
		: UPowerDeviceState.Unknown

	readonly property bool charging: root.state === UPowerDeviceState.Charging
	readonly property bool full: root.state === UPowerDeviceState.FullyCharged
	readonly property bool low: !root.onPower && root.level <= 0.20

	// Green means "on mains", not "electrons currently moving". A battery
	// already at 100% goes straight to FullyCharged when you plug in - it
	// never passes through Charging - so keying the colour off charging alone
	// means the state you sit in most of the time looks like being unplugged.
	//
	// UPower's system-level flag rather than the device state, because it also
	// covers the pending-charge cases.
	readonly property bool onPower: root.ready && !UPower.onBattery

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

	// UPower reports seconds; nobody reads a battery in seconds.
	function humanDuration(seconds) {
		if (!seconds || seconds <= 0)
			return "";

		// Time remaining is energy divided by current draw, so a near-idle
		// machine at a high charge produces days - 4700 hours, in one case.
		// Past a couple of days the number is arithmetic, not information.
		if (seconds > 48 * 3600)
			return "";

		const mins = Math.round(seconds / 60);
		const h = Math.floor(mins / 60);
		const m = mins % 60;

		return h > 0 ? h + " h " + m + " m" : m + " m";
	}

	readonly property string summary: {
		if (!root.ready)
			return "No battery";

		// Charging first, so charging at 100% still says how long is left.
		if (root.charging) {
			const t = root.humanDuration(root.device.timeToFull);
			return t ? "Full in " + t : "Charging";
		}

		if (root.full)
			return "Fully charged";

		// On mains but neither charging nor full - a firmware charge limit,
		// or the pending-charge states.
		if (root.onPower)
			return "Plugged in";

		const t = root.humanDuration(root.device.timeToEmpty);
		return t ? t + " remaining" : "On battery";
	}

	BatteryIcon {
		id: label

		anchors.centerIn: parent

		height: Theme.barIconHeight
		width: height * label.aspect

		// The cell fills with the charge, so the number is not needed to read
		// it at a glance.
		level: root.ready ? root.level : -1

		color: root.low ? Theme.danger
			: root.onPower ? Theme.success
			: Theme.glassTextPrimary

		opacity: trigger.containsMouse || root.open ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}

		BoltIcon {
			anchors.centerIn: parent
			width: 7
			height: 11
			visible: root.charging
			// On top of a filled cell, so it has to hold its own against both.
			color: Theme.glassTextOnLens
		}
	}

	MouseArea {
		id: trigger

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: root.open = !root.open
	}

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
		WlrLayershell.namespace: "groma:battery-catcher"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		MouseArea {
			anchors.fill: parent
			onClicked: root.open = false
		}
	}

	PanelWindow {
		id: panel

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
		WlrLayershell.namespace: "groma:battery"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: tile
			radius: Theme.radiusPanel
		}

		GlassTile {
			id: tile

			anchors.fill: parent
			anchors.margins: panel.pad

			title: "Battery"
			trailing: root.summary

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
				id: batterySlider

				width: parent.width
				value: root.level
				animateValue: tile.settled

				// Shown, not set.
				interactive: false

				// The fill carries the state: green while charging, amber when
				// it is time to worry, plain otherwise.
				fillColor: root.onPower ? Theme.glassFillCharging
					: root.low ? Theme.glassFillWarning
					: Theme.glassTrackFill

				// Something is happening, so the fill says so.
				shimmer: root.charging

				knobContent: BoltIcon {
					anchors.centerIn: parent
					visible: root.charging
					color: Theme.glassOnLens
				}

				BatteryIcon {
					id: batteryIcon

					anchors {
						left: parent.left
						leftMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					color: batterySlider.knobLeft < batteryIcon.x + batteryIcon.width
						? Theme.glassTextOnLens : Theme.glassTextPrimary
				}

				Text {
					id: batteryValue

					anchors {
						right: parent.right
						rightMargin: Theme.spacingL
						verticalCenter: parent.verticalCenter
					}

					text: Math.round(root.level * 100) + "%"
					font.pixelSize: Theme.fontBody

					// A full battery puts the lens right under this.
					color: batterySlider.knobRight > batteryValue.x
						? Theme.glassTextOnLens
						: root.low ? Theme.warning
						: Theme.glassTextPrimary
				}
			}

			// Status line. The design puts the power adapter and a profile
			// here; there is no power-profiles-daemon on this machine, so the
			// right-hand slot shows battery health instead - which is real,
			// and the thing worth knowing about a laptop battery anyway.
			Item {
				width: parent.width
				height: source.implicitHeight

				Text {
					id: source

					anchors.left: parent.left
					font.pixelSize: Theme.fontCaption
					opacity: 0.85
					color: Theme.glassTextPrimary

					text: {
						if (!root.ready)
							return "No battery";

						const w = Math.abs(root.device.changeRate);
						const rate = w > 0.1 ? " · " + w.toFixed(1) + " W" : "";

						return (root.onPower ? "Power adapter" : "On battery") + rate;
					}
				}

				Row {
					anchors.right: parent.right
					spacing: Theme.spacingS / 2 + 3
					visible: root.health > 0

					Text {
						anchors.verticalCenter: parent.verticalCenter
						text: "Health " + Math.round(root.health) + "%"
						font.pixelSize: Theme.fontCaption
						opacity: 0.85
						color: Theme.glassTextPrimary
					}

					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						width: 6
						height: 6
						radius: 3

						color: root.health >= 80 ? Theme.success
							: root.health >= 60 ? Theme.warning
							: Theme.danger
					}
				}
			}
		}
	}

	IpcHandler {
		target: "battery"

		function toggle(): void {
			root.open = !root.open;
		}

		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}
	}
}
