import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's network readout, and the tile it opens.
BarPopup {
	id: root

	readonly property var wifi: Networking.devices.values.find(
		device => device.type === DeviceType.Wifi) ?? null

	readonly property var current:
		root.wifi?.networks?.values?.find(network => network.connected) ?? null

	readonly property bool enabled: Networking.wifiEnabled
	readonly property bool online:
		Networking.connectivity === NetworkConnectivity.Full

	// Connected first, then ones we have credentials for, then the rest by
	// name. Capped, because a tile is not a network manager and there are
	// usually more networks in range than anyone wants listed.
	readonly property int listLimit: 5

	readonly property var candidates: {
		const all = root.wifi?.networks?.values ?? [];

		return all.slice().sort((a, b) =>
			(b.connected - a.connected)
			|| (b.known - a.known)
			|| a.name.localeCompare(b.name));
	}

	// Scan only while the tile is open. A wifi scan costs power and airtime,
	// and the list is worthless when nobody is looking at it - with the
	// scanner off the device reports just the network it is already on.
	onOpenChanged: {
		if (root.wifi)
			root.wifi.scannerEnabled = root.open;
	}

	name: "network"
	title: "Network"

	trailing: !root.enabled ? "Wi-Fi off"
		: root.current ? root.current.name
		: "Disconnected"

	trigger: WifiIcon {
		height: Theme.barIconHeight
		width: height * aspect

		crossed: !root.enabled
		// Two arcs when connected, none when not: the arcs are state, since
		// nothing here reports signal strength.
		level: root.enabled && root.current ? 2 : 0

		// Connected but no route out is worth flagging - a captive portal
		// looks exactly like a working connection otherwise.
		color: root.enabled && root.current && !root.online
			? Theme.warning
			: root.enabled ? Theme.glassTextPrimary
			: Theme.glassTextMuted

		opacity: root.active ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}
	}

	IpcHandler {
		target: "network"

		function toggle(): void {
			root.open = !root.open;
		}

		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}

		function wifi(on: string): void {
			Networking.wifiEnabled = on !== "off";
		}
	}

	// The radio itself, above the list: turning it off is a different kind of
	// action from joining a network.
	Item {
		width: parent.width
		height: radioLabel.implicitHeight

		Text {
			id: radioLabel

			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			text: "Wi-Fi"
			font.pixelSize: Theme.fontBody
			color: Theme.glassTextPrimary
		}

		Chip {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			width: 64
			text: root.enabled ? "On" : "Off"
			active: root.enabled
			onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
		}
	}

	Column {
		width: parent.width
		spacing: Theme.spacingXs
		visible: root.enabled && root.candidates.length > 0

		Repeater {
			model: Math.min(root.listLimit, root.candidates.length)

			Rectangle {
				id: row

				required property int index
				readonly property var network: root.candidates[row.index]

				width: parent.width
				height: Theme.chipHeight
				radius: Theme.radiusPill

				color: row.network.connected ? Theme.glassChipActive
					: rowMouse.containsMouse ? Theme.glassControlHover
					: "transparent"

				Behavior on color {
					ColorAnimation { duration: 120 }
				}

				Text {
					anchors {
						left: parent.left
						right: state.left
						leftMargin: Theme.spacingM
						rightMargin: Theme.spacingS
						verticalCenter: parent.verticalCenter
					}

					text: row.network.name
					elide: Text.ElideRight
					font.pixelSize: Theme.fontCaption
					// A network we have credentials for is one click away; the
					// rest would need a password we cannot ask for yet.
					opacity: row.network.known || row.network.connected ? 1.0 : 0.6
					color: Theme.glassTextPrimary
				}

				Text {
					id: state

					anchors {
						right: parent.right
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					text: row.network.connected ? "connected"
						: row.network.stateChanging ? "…"
						: row.network.known ? "saved" : ""

					font.pixelSize: Theme.fontCaption
					opacity: 0.7
					color: Theme.glassTextPrimary
				}

				MouseArea {
					id: rowMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor

					onClicked: {
						if (row.network.connected)
							root.wifi.requestDisconnect();
						else if (row.network.known)
							row.network.requestConnect();
					}
				}
			}
		}
	}

	Text {
		width: parent.width
		visible: root.enabled && root.candidates.length > root.listLimit
		text: (root.candidates.length - root.listLimit) + " more in range"
		font.pixelSize: Theme.fontCaption
		opacity: 0.6
		color: Theme.glassTextPrimary
	}
}
