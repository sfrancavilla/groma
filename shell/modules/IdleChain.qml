import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick
import ".."

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

	// Timeouts are in seconds, chosen in Settings (where the defaults and the
	// reasons for them live). Zero disables a stage.
	readonly property bool onBattery: UPower.onBattery

	readonly property int dimAfter: Settings.idleAfter("dim", root.onBattery)
	readonly property int lockAfter: Settings.idleAfter("lock", root.onBattery)
	readonly property int screenOffAfter: Settings.idleAfter("screenOff", root.onBattery)
	readonly property int suspendAfter: Settings.idleAfter("suspend", root.onBattery)

	// The panel backlight, named explicitly: with no device brightnessctl walks
	// everything it can find, which here includes two keyboard LEDs. Found at
	// start (Backlight.qml); without one there is nothing to dim.
	readonly property string backlight: Backlight.device

	// brightnessctl keeps the pre-dim value itself, so there is no state here
	// to get out of step with the hardware.
	IdleMonitor {
		enabled: root.dimAfter > 0
		timeout: Math.max(1, root.dimAfter)
		respectInhibitors: true

		onIsIdleChanged: {
			if (root.backlight === "")
				return;
			if (isIdle)
				Quickshell.execDetached(["brightnessctl", "-d", root.backlight,
					"-s", "set", "20%"]);
			else
				Quickshell.execDetached(["brightnessctl", "-d", root.backlight,
					"-r"]);
		}
	}

	IdleMonitor {
		enabled: root.lockAfter > 0
		timeout: Math.max(1, root.lockAfter)
		respectInhibitors: true

		// Locking is one-way: coming back from idle must not unlock anything.
		onIsIdleChanged: if (isIdle) root.lock.setLocked(true)
	}

	IdleMonitor {
		enabled: root.screenOffAfter > 0
		timeout: Math.max(1, root.screenOffAfter)
		respectInhibitors: true

		onIsIdleChanged: Quickshell.execDetached(
			["hyprctl", "dispatch", "dpms", isIdle ? "off" : "on"])
	}

	// logind allows the active session to suspend itself without asking, so
	// this needs no privileges. The sleep hook locks on the way down, and this
	// is already past the lock stage anyway.
	IdleMonitor {
		enabled: root.suspendAfter > 0
		timeout: Math.max(1, root.suspendAfter)
		respectInhibitors: true

		onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "suspend"])
	}
}
