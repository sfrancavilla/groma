import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."

// The session lock.
//
// Under ext-session-lock the compositor holds the session shut until this
// client says otherwise, and keeps it shut if the client dies. That is the
// protocol doing its job - a crashed lock screen must not expose the desktop -
// and it is also why a mistake in here is recovered from a TTY rather than
// from the desktop.
//
//   qs -c groma ipc call lock lock
Scope {
	id: root

	// Lock state has to outlive a config reload. Held in a plain property it
	// would be recreated as false every time a QML file is saved, and saving a
	// file would unlock the session.
	PersistentProperties {
		id: state

		reloadableId: "groma-lock"

		property bool locked: false
	}

	// Lock and unlock by assignment, not by binding `locked` to the stored
	// state. Quickshell writes to `locked` itself when it acquires the lock,
	// and an imperative write destroys a binding on the same property - after
	// which changing the stored state has no effect at all, which is exactly
	// what "correct password, still locked" looks like.
	function setLocked(value) {
		state.locked = value;
		sessionLock.locked = value;
	}

	// Restore across a config reload, since the binding is gone.
	Component.onCompleted: sessionLock.locked = state.locked

	// Here, not on each surface: one reader, however many monitors.
	Fingerprint {
		id: reader

		active: state.locked

		onAuthenticated: root.setLocked(false)
	}

	WlSessionLock {
		id: sessionLock

		surface: WlSessionLockSurface {
			color: "transparent"

			// The lock covers everything, so it draws its own desktop rather
			// than revealing the real one behind a scrim.
			DesktopBackdrop {
				anchors.fill: parent
			}

			Rectangle {
				anchors.fill: parent
				color: Theme.scrim
			}

			LockContent {
				anchors.fill: parent
				focus: true
				fingerprint: reader

				// No Escape. There is deliberately no way out of here except
				// authenticating.
				onAuthenticated: root.setLocked(false)

				Component.onCompleted: focusInput()
			}
		}
	}

	IpcHandler {
		target: "lock"

		function lock(): void {
			root.setLocked(true);
		}

		// Whether the session is currently locked, for scripts and for
		// checking from a TTY.
		function status(): string {
			return state.locked ? "locked" : "unlocked"
				+ " (sessionLock=" + sessionLock.locked + ")";
		}

		// An escape hatch that does not need a TTY. Anyone who can run this
		// already has a shell as you, so it gives away nothing that was not
		// already given away.
		function unlock(): void {
			console.log("LOCK: forced unlock over ipc");
			root.setLocked(false);
		}
	}
}
