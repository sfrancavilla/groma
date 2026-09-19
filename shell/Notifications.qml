import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick

// The notification daemon. Creating a NotificationServer claims
// org.freedesktop.Notifications on the session bus, which is what makes this
// shell *be* the notification daemon - the same role mako or dunst would fill.
Scope {
	id: root

	NotificationServer {
		id: server

		// These advertise our capabilities to clients. An application asks the
		// daemon what it supports before deciding what to send, so claiming
		// something we do not render would produce notifications with missing
		// pieces.
		bodySupported: true
		actionsSupported: true
		imageSupported: true

		// A reload recreates the server, so old toasts would otherwise linger
		// with no way to dismiss them. Set this true once the shell is stable.
		keepOnReload: false

		// A notification is discarded unless we mark it tracked. That is the
		// server asking whether we intend to display it.
		onNotification: notification => {
			notification.tracked = true;
		}
	}

	PanelWindow {
		id: toastWindow

		visible: server.trackedNotifications.values.length > 0

		anchors {
			top: true
			right: true
		}

		// Ignore exclusive zones, then clear the bar by hand. A toast stack
		// must not reserve screen space of its own.
		exclusionMode: ExclusionMode.Ignore
		margins {
			top: 40
			right: 12
		}

		// Cards are 380 wide; the extra room is for the ambient shadow to
		// bleed into, since anything drawn outside the window is clipped.
		readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0

		implicitWidth: 380 + toastWindow.pad * 2
		implicitHeight: Math.max(1, toastColumn.implicitHeight)
			+ toastWindow.pad * 2
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:notifications"
		// Unlike the polkit dialog, toasts must never take keyboard focus.
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		// Ask the compositor to blur what is behind the cards. This is the one
		// part of the glass we cannot draw ourselves - a client never sees its
		// own backdrop. Declaring it here rather than as a Hyprland layer rule
		// keeps Groma self-contained.
		BackgroundEffect.blurRegion: Region {
			item: toastColumn
			radius: Theme.radiusMedium
		}

		Column {
			id: toastColumn

			anchors.fill: parent
			anchors.margins: toastWindow.pad
			spacing: 8

			Repeater {
				model: server.trackedNotifications

				NotificationToast {}
			}
		}
	}
}
