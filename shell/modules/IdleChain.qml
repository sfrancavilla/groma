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

	// Each stage is a monitor made for one timeout, and a new one is made when
	// the timeout changes. Quickshell 0.3.2's IdleMonitor goes silent for good
	// once its timeout is changed in place - which is what choosing a new time
	// in Settings did - so it is never changed, only replaced.

	// Half of whatever the brightness is, so the dim shows at any level; a fixed
	// level did nothing to a screen already at or below it. brightnessctl keeps
	// the pre-dim value itself, so there is no state here to get out of step
	// with the hardware.
	Variants {
		model: root.dimAfter > 0 ? [root.dimAfter] : []

		IdleMonitor {
			required property int modelData

			timeout: modelData
			respectInhibitors: true

			onIsIdleChanged: {
				if (root.backlight === "")
					return;
				if (isIdle)
					Quickshell.execDetached(["sh", "-c",
						'now=$(brightnessctl -d "$1" g) && brightnessctl -d "$1" -s set $(( now > 1 ? now / 2 : 1 ))',
						"sh", root.backlight]);
				else
					Quickshell.execDetached(["brightnessctl", "-d", root.backlight,
						"-r"]);
			}
		}
	}

	Variants {
		model: root.lockAfter > 0 ? [root.lockAfter] : []

		IdleMonitor {
			required property int modelData

			timeout: modelData
			respectInhibitors: true

			// Locking is one-way: coming back from idle must not unlock anything.
			onIsIdleChanged: if (isIdle) root.lock.setLocked(true)
		}
	}

	Variants {
		model: root.screenOffAfter > 0 ? [root.screenOffAfter] : []

		IdleMonitor {
			required property int modelData

			timeout: modelData
			respectInhibitors: true

			onIsIdleChanged: Quickshell.execDetached(
				["hyprctl", "dispatch", "dpms", isIdle ? "off" : "on"])
		}
	}

	// logind allows the active session to suspend itself without asking, so
	// this needs no privileges. The sleep hook locks on the way down, and this
	// is already past the lock stage anyway.
	Variants {
		model: root.suspendAfter > 0 ? [root.suspendAfter] : []

		IdleMonitor {
			required property int modelData

			timeout: modelData
			respectInhibitors: true

			onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "suspend"])
		}
	}
}
