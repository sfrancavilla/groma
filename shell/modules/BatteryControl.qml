import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's battery readout, and the tile it opens.
//
// Same grammar as the volume tile - title row, glass track, status line - but
// the track is a readout rather than a control: you cannot drag a battery.
BarPopup {
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
	// Only with a battery to be low: without one the level reads 0, and a
	// desktop or a virtual machine would sit in the red forever.
	readonly property bool low: root.ready && !root.onPower && root.level <= 0.20

	// Green means "on mains", not "electrons currently moving". A battery
	// already at 100% goes straight to FullyCharged when you plug in - it
	// never passes through Charging - so keying the colour off charging alone
	// means the state you sit in most of the time looks like being unplugged.
	//
	// UPower's system-level flag rather than the device state, because it also
	// covers the pending-charge cases.
	readonly property bool onPower: root.ready && !UPower.onBattery

	name: "battery"
	title: "Battery"
	trailing: root.summary

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

	trigger: BatteryIcon {
		height: Theme.barIconSize
		width: height * aspect

		// The cell fills with the charge, so the number is not needed to read
		// it at a glance.
		level: root.ready ? root.level : -1

		color: !root.ready ? Theme.glassTextMuted
			: root.low ? Theme.danger
			: root.onPower ? Theme.success
			: Theme.glassTextPrimary

		opacity: root.active ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}

		BoltIcon {
			x: parent.cellCenterX - width / 2
			anchors.verticalCenter: parent.verticalCenter
			height: parent.cellHeight - 1
			width: height * 0.6
			visible: root.charging
			// On top of a filled cell, so it has to hold its own against both.
			color: Theme.glassTextOnLens
		}
	}

	IpcHandler {
		target: "battery"

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
	}

	Slider {
		id: batterySlider

		width: parent.width
		value: root.level
		animateValue: root.settled

		// Shown, not set.
		interactive: false

		// The fill carries the state: green while charging, amber when it is
		// time to worry, plain otherwise.
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

			// At the right end of the track - until the lens would cover it,
			// which a nearly full battery does. "100%" is wider than the lens,
			// so turning it dark under the glass left it half on, half off;
			// it moves ahead of the lens onto the fill instead.
			readonly property real endX: parent.width - Theme.spacingL - width
			x: batterySlider.knobRight + Theme.spacingS > endX
				? batterySlider.knobLeft - Theme.spacingS - width : endX
			anchors.verticalCenter: parent.verticalCenter

			text: Math.round(root.level * 100) + "%"
			font.pixelSize: Theme.fontBody

			color: root.low ? Theme.warning : Theme.glassTextPrimary
		}
	}

	// Status line. The design puts the power adapter and a profile here; there
	// is no power-profiles-daemon on this machine, so the right-hand slot shows
	// battery health instead - real, and the thing actually worth knowing about
	// a laptop battery.
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

