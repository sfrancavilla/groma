import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's battery readout, and the tile it opens.
//
// Same grammar as the volume tile - title row, glass track, then rows - but
// the track is a readout rather than a control: you cannot drag a battery.
// The rows under it are readings, drawn as the system card draws its parts.
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
	// The system card's width: its rows carry a figure and a meter.
	cardWidth: Theme.tileWidthWide

	// --- power mode ----------------------------------------------------------
	//
	// power-profiles-daemon's three modes, through Quickshell's PowerProfiles.
	// A choice is remembered for the source it was made on - plugged in or on
	// battery - and put back when the machine next changes to that source, as
	// Omarchy does: Performance at the desk, Power saver on the train, without
	// choosing again each time.

	// Whether the daemon is there to ask. PowerProfiles reads Balanced
	// without one, which would be a control that does nothing.
	property bool profilesAvailable: false

	readonly property var profileNames: ["power-saver", "balanced", "performance"]
	readonly property string source: UPower.onBattery ? "battery" : "ac"

	function profileName(profile) {
		return profile === PowerProfile.PowerSaver ? "power-saver"
			: profile === PowerProfile.Performance ? "performance" : "balanced";
	}

	function profileValue(name) {
		return name === "power-saver" ? PowerProfile.PowerSaver
			: name === "performance" ? PowerProfile.Performance : PowerProfile.Balanced;
	}

	function chooseProfile(name) {
		PowerProfiles.profile = root.profileValue(name);
		Settings.setPowerProfile(root.source, name);
	}

	// What was chosen on this source, if anything was.
	function restoreProfile() {
		const name = Settings.powerProfile(root.source);
		if (!root.profilesAvailable || name === "")
			return;
		if (name === "performance" && !PowerProfiles.hasPerformanceProfile)
			return;
		if (root.profileName(PowerProfiles.profile) !== name)
			PowerProfiles.profile = root.profileValue(name);
	}

	// Once, by the lead bar, not once per screen.
	onSourceChanged: if (root.lead) root.restoreProfile()
	onProfilesAvailableChanged: if (root.lead) root.restoreProfile()
	onOpenChanged: if (root.open) profileProbe.running = true

	Process {
		id: profileProbe

		running: true
		// Over D-Bus, not powerprofilesctl: that is Python, and needs
		// python-gobject, which the daemon does not bring with it.
		command: ["busctl", "--system", "get-property", "org.freedesktop.UPower.PowerProfiles",
			"/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"]
		onExited: code => root.profilesAvailable = code === 0
	}

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

		// "power-saver" | "balanced" | "performance", as the chips choose it.
		function profile(name: string): void {
			root.chooseProfile(name);
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

	// Where the power comes from, and how fast it moves, then what the cell
	// is still worth: readings, drawn as the system card draws its parts.
	// The design puts the adapter and a profile on one caption line; the
	// profile became a control of its own, below, so health took its slot.
	Column {
		width: parent.width
		spacing: 0
		visible: root.ready

		CardRow {
			id: sourceRow

			// Watts either way; the sign is in the words.
			readonly property real watts: Math.abs(root.device?.changeRate ?? 0)

			rowHeight: 48
			title: root.onPower ? "Power adapter" : "On battery"
			detail: root.charging ? "Charging"
				: root.onPower ? "Not charging"
				: "Discharging"

			mark: BoltIcon {
				width: 8
				height: 13
				color: Theme.glassTextPrimary
			}

			Text {
				anchors.verticalCenter: parent.verticalCenter
				visible: sourceRow.watts > 0.1
				text: sourceRow.watts.toFixed(1) + " W"
				font.pixelSize: Theme.fontTitle
				font.features: { "tnum": 1 }
				color: Theme.glassTextPrimary
			}
		}

		// What a full charge holds now against what it held new. The firmware
		// can report a little over 100 on a young battery; the meter stops
		// at full, the figure says what was reported.
		CardRow {
			id: healthRow

			readonly property bool worn: root.health < 80

			visible: root.health > 0
			rule: "dashed"
			rowHeight: 48
			title: "Health"
			detail: (root.physical?.energyCapacity ?? 0) > 0
				? root.physical.energyCapacity.toFixed(1) + " Wh when full" : ""

			// Its size is the width: the cell is wider than it is tall.
			mark: BatteryIcon {
				width: Theme.rowMark + 2
				height: width / aspect
				level: Math.min(1, root.health / 100)
				lineWidth: Theme.markLine
				color: Theme.glassTextPrimary
			}

			Text {
				anchors.verticalCenter: parent.verticalCenter
				width: 40
				horizontalAlignment: Text.AlignRight
				text: Math.round(root.health) + "%"
				font.pixelSize: Theme.fontTitle
				font.features: { "tnum": 1 }
				color: healthRow.worn ? Theme.warning : Theme.glassTextPrimary
			}

			LevelPill {
				anchors.verticalCenter: parent.verticalCenter
				width: 104
				value: Math.min(1, root.health / 100)
				fillColor: healthRow.worn
					? Theme.glassFillWarning : Theme.glassTrackFill
			}
		}
	}

	// The power mode, while power-profiles-daemon is there to set it.
	Column {
		width: parent.width
		spacing: Theme.spacingS
		visible: root.profilesAvailable

		SectionLabel {
			text: "POWER MODE"
		}

		Row {
			id: modes

			readonly property var shown: root.profileNames
				.filter(name => name !== "performance" || PowerProfiles.hasPerformanceProfile)

			width: parent.width
			spacing: Theme.spacingXs

			Repeater {
				model: modes.shown

				Chip {
					required property string modelData

					width: (modes.width - modes.spacing * (modes.shown.length - 1)) / modes.shown.length
					text: modelData === "power-saver" ? "Power saver"
						: modelData === "performance" ? "Performance" : "Balanced"
					active: root.profileName(PowerProfiles.profile) === modelData
					onClicked: root.chooseProfile(modelData)
				}
			}
		}

		// Why Performance is not all it says, when the firmware holds it back.
		Text {
			width: parent.width
			visible: PowerProfiles.profile === PowerProfile.Performance
				&& PowerProfiles.degradationReason !== PerformanceDegradationReason.None
			text: PowerProfiles.degradationReason === PerformanceDegradationReason.HighTemperature
				? "Held back while the processor is hot"
				: "Held back while the laptop is on a lap"
			leftPadding: 8
			wrapMode: Text.WordWrap
			font.pixelSize: Theme.fontCaption
			color: Theme.warning
		}

		// Kept for this source: say so, once there is something kept.
		Text {
			width: parent.width
			visible: Settings.powerProfile(root.source) !== ""
			text: UPower.onBattery ? "Kept for when on battery" : "Kept for when plugged in"
			leftPadding: 8
			font.pixelSize: Theme.fontCaption
			opacity: 0.7
			color: Theme.glassTextPrimary
		}
	}
}
