import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import ".."

// The notification daemon. Creating a NotificationServer claims
// org.freedesktop.Notifications on the session bus, which is what makes this
// shell *be* the notification daemon - the same role mako or dunst would fill.
//
// A notification has two lives here. As it arrives it is a toast, for as
// long as it asks to be (five seconds unless it says otherwise); after that
// it stays in the centre under the clock until it is dismissed, or until
// the application that sent it takes it back. Do Not Disturb keeps the
// toasts away - all but critical ones - and nothing else: what arrives
// still waits in the centre.
Scope {
	id: root

	// Newest first: everything the centre lists.
	readonly property var list: Array.from(server.trackedNotifications.values).reverse()
	// Showing as toasts, oldest at the top.
	property var popups: []
	// When each arrived, by id. Unknown for those kept across a reload.
	property var arrived: ({})
	// Arrived while Do Not Disturb kept them quiet, since the centre was
	// last looked at. The clock shows a dot while there are any.
	property int missed: 0

	function retire(n) {
		root.popups = root.popups.filter(p => p !== n);
		// A transient notification asks not to be kept.
		if (n.transient)
			n.expire();
	}

	function clear() {
		// dismiss() takes each out of the list being walked: walk a copy.
		for (const n of root.list.slice())
			n.dismiss();
		root.missed = 0;
	}

	NotificationServer {
		id: server

		// These advertise our capabilities to clients. An application asks the
		// daemon what it supports before deciding what to send, so claiming
		// something we do not render would produce notifications with missing
		// pieces.
		bodySupported: true
		actionsSupported: true
		imageSupported: true

		// The centre keeps what has not been dealt with, and saving a QML
		// file should not throw it away. Toasts are not carried over: what
		// was arriving at the moment of a reload is in the centre.
		keepOnReload: true

		// A notification is discarded unless we mark it tracked. That is the
		// server asking whether we intend to display it.
		onNotification: notification => {
			notification.tracked = true;
			root.arrived = Object.assign({}, root.arrived, { [notification.id]: Date.now() });

			const quiet = Settings.doNotDisturb
				&& notification.urgency !== NotificationUrgency.Critical;
			if (quiet)
				root.missed++;
			else
				root.popups = [...root.popups, notification];

			notification.closed.connect(() => {
				root.popups = root.popups.filter(p => p !== notification);
				const next = Object.assign({}, root.arrived);
				delete next[notification.id];
				root.arrived = next;
			});
		}
	}

	PanelWindow {
		id: toastWindow

		visible: root.popups.length > 0

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
			spacing: Theme.spacingS

			// Over the server's own list, which keeps its delegates, and not
			// over `popups`: a new array is a new model, and every toast on
			// screen would be made again - its timer started again with it -
			// each time one of them left.
			Repeater {
				model: server.trackedNotifications

				NotificationToast {
					visible: root.popups.includes(modelData)
					arrived: root.arrived[modelData.id] ?? 0
					onTimedOut: root.retire(modelData)
				}
			}
		}
	}

	IpcHandler {
		target: "notifications"

		function toggleQuiet(): void {
			Settings.setDoNotDisturb(!Settings.doNotDisturb);
		}

		function clear(): void {
			root.clear();
		}

		function list(): string {
			return JSON.stringify(root.list.map(n => ({ id: n.id, app: n.appName,
				summary: n.summary, popup: root.popups.includes(n) })));
		}
	}
}
