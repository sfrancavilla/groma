import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

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

	WlSessionLock {
		id: sessionLock

		locked: state.locked

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

				// No Escape. There is deliberately no way out of here except
				// authenticating.
				onAuthenticated: state.locked = false

				Component.onCompleted: focusInput()
			}
		}
	}

	IpcHandler {
		target: "lock"

		function lock(): void {
			state.locked = true;
		}

		// Whether the session is currently locked, for scripts and for
		// checking from a TTY.
		function status(): string {
			return state.locked ? "locked" : "unlocked";
		}
	}
}
