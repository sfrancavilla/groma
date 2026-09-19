import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick

// What happens when you stop touching the machine.
//
// Three stages rather than one, because locking with no warning is what makes
// automatic locking irritating: the screen dims first, which you notice and can
// cancel by moving, and only then does it lock.
//
// Every stage sets respectInhibitors, so an application holding an idle
// inhibitor - which video players do while playing - suppresses the whole chain.
// Nothing here has to know what is playing.
Scope {
	id: root

	// The lock to drive. Passed in rather than reached for, so this component
	// does not need to know how locking works.
	required property var lock

	// Timeouts are in seconds. Shorter on battery, where the screen is the
	// expensive part.
	readonly property bool onBattery: UPower.onBattery

	readonly property int dimAfter: root.onBattery ? 120 : 300
	readonly property int lockAfter: root.onBattery ? 240 : 600
	readonly property int screenOffAfter: root.onBattery ? 300 : 660

	// The panel backlight, named explicitly: with no device brightnessctl walks
	// everything it can find, which here includes two keyboard LEDs.
	readonly property string backlight: "amdgpu_bl1"

	// brightnessctl keeps the pre-dim value itself, so there is no state here
	// to get out of step with the hardware.
	IdleMonitor {
		timeout: root.dimAfter
		respectInhibitors: true

		onIsIdleChanged: {
			if (isIdle)
				Quickshell.execDetached(["brightnessctl", "-d", root.backlight,
					"-s", "set", "20%"]);
			else
				Quickshell.execDetached(["brightnessctl", "-d", root.backlight,
					"-r"]);
		}
	}

	IdleMonitor {
		timeout: root.lockAfter
		respectInhibitors: true

		// Locking is one-way: coming back from idle must not unlock anything.
		onIsIdleChanged: if (isIdle) root.lock.setLocked(true)
	}

	IdleMonitor {
		timeout: root.screenOffAfter
		respectInhibitors: true

		onIsIdleChanged: Quickshell.execDetached(
			["hyprctl", "dispatch", "dpms", isIdle ? "off" : "on"])
	}
}
