import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's network readout, and the tile it opens.
//
// Follows the design's network list: the connected network as a card of its
// own with a subtitle, then the rest as rows with strength and a lock.
BarPopup {
	id: root

	readonly property var wifi: Networking.devices.values.find(
		device => device.type === DeviceType.Wifi) ?? null

	readonly property var current:
		root.wifi?.networks?.values?.find(network => network.connected) ?? null

	readonly property bool enabled: Networking.wifiEnabled
	readonly property bool online:
		Networking.connectivity === NetworkConnectivity.Full

	// Quickshell's Network says whether we are connected and whether we know
	// the network, but not how strong it is, whether it is secured, or which
	// band. NetworkManager knows all three and is already the backend, so the
	// scan fills in what the model does not carry.
	property var detail: ({})

	// The modal that asks for a password, supplied by whoever built the bar so
	// this does not have to own a second window.
	property var joinDialog: null

	function barsFor(name) {
		const signal = root.detail[name]?.signal ?? -1;
		if (signal < 0)
			return 0;

		// Four bars over a 0-100 scale, with the bottom one lit for anything
		// audible at all.
		return signal >= 75 ? 4 : signal >= 50 ? 3 : signal >= 25 ? 2 : 1;
	}

	function parseScan(text) {
		const found = {};

		for (const line of text.split("\n")) {
			if (line.trim() === "")
				continue;

			// nmcli -t escapes colons inside values, so the SSID cannot be
			// found by splitting naively. A lookbehind would express that
			// neatly and Qt's JS engine does not support it - it matches
			// nothing and throws nothing, so the parse silently returns one
			// field. Swap the escaped colons out first instead.
			const parts = line.replace(/\\:/g, "\u0000")
				.split(":")
				.map(part => part.replace(/\u0000/g, ":"));
			if (parts.length < 5)
				continue;

			const inUse = parts[0];
			const freq = parts[parts.length - 1];
			const security = parts[parts.length - 2];
			const signal = parseInt(parts[parts.length - 3]);
			const name = parts.slice(1, parts.length - 3).join(":");

			if (name === "")
				continue;

			// The same network is usually on both bands. Keep the one we are
			// actually joined to when there is one - it is often the weaker
			// of the two, and reporting the stronger would put the wrong band
			// under "Connected".
			const better = !found[name]
				|| (inUse === "*")
				|| (!found[name].inUse && found[name].signal < signal);

			if (better) {
				found[name] = {
					signal: signal,
					secured: security.trim() !== "",
					band: parseInt(freq) >= 5000 ? "5 GHz" : "2.4 GHz",
					inUse: inUse === "*"
				};
			}
		}

		root.detail = found;
	}

	// NetworkDevice.address is the hardware address - aa:bb:cc:dd:ee:ff - not
	// the one anyone means by "the IP". NetworkManager has that too.
	property string ipAddress: ""

	Process {
		id: ipQuery

		command: ["nmcli", "-t", "-f", "IP4.ADDRESS", "device", "show",
			root.wifi?.name ?? ""]

		stdout: StdioCollector {
			onStreamFinished: {
				// IP4.ADDRESS[1]:192.168.1.29/24
				const found = text.match(/IP4\.ADDRESS\[1\]:\s*([0-9.]+)/);
				root.ipAddress = found ? found[1] : "";
			}
		}
	}

	// The address the internet sees. Nothing local knows it - the router
	// translates on the way out - so it has to be asked of something outside,
	// which is the only part of this shell that talks to a third party.
	//
	// Throttled hard: it changes rarely, the tile is the only thing that wants
	// it, and every query tells that service where you are.
	//
	// A DNS query would avoid contacting a web service, and was tried:
	//
	//   dig -t txt +short o-o.myaddr.l.google.com @ns1.google.com  -> 203.0.113.7
	//   curl https://api.ipify.org                                 -> 203.0.113.42
	//
	// Two independent HTTPS services agree on the second, so the first is not
	// this machine's address. The ISP intercepts port 53 and relays the query,
	// so the nameserver sees its resolver rather than us - the DNS method is
	// answering a different question. OpenDNS's equivalent returns no answer
	// at all here.
	property string publicIp: ""
	property double publicIpAt: 0

	readonly property int publicIpMaxAge: 5 * 60 * 1000

	function refreshPublicIp() {
		if (!root.online)
			return;

		if (root.publicIp !== ""
				&& Date.now() - root.publicIpAt < root.publicIpMaxAge)
			return;

		publicIpQuery.running = true;
	}

	Process {
		id: publicIpQuery

		command: ["curl", "--silent", "--ipv4", "--max-time", "4",
			"https://api.ipify.org"]

		stdout: StdioCollector {
			onStreamFinished: {
				const found = text.trim();

				// Anything that is not an address means a captive portal or an
				// error page; keeping the last good answer beats showing HTML.
				if (/^[0-9.]+$/.test(found)) {
					root.publicIp = found;
					root.publicIpAt = Date.now();
				}
			}
		}
	}

	Process {
		id: scan

		command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ",
			"device", "wifi", "list"]

		stdout: StdioCollector {
			onStreamFinished: root.parseScan(text)
		}
	}

	// Only while the tile is open, and only often enough to feel live.
	Timer {
		running: root.open && root.enabled
		interval: 5000
		triggeredOnStart: true
		repeat: true
		onTriggered: {
			scan.running = true;
			ipQuery.running = true;
			root.refreshPublicIp();
		}
	}

	// Scan only while the tile is open. A wifi scan costs power and airtime,
	// and the list is worthless when nobody is looking - with the scanner off
	// the device reports just the network it is already on.
	onOpenChanged: {
		if (root.wifi)
			root.wifi.scannerEnabled = root.open;
	}

	readonly property int listLimit: 4

	// Everything except the one we are on, known first, then by strength.
	readonly property var others: {
		const all = root.wifi?.networks?.values ?? [];

		return all.filter(n => !n.connected).sort((a, b) =>
			(b.known - a.known)
			|| ((root.detail[b.name]?.signal ?? 0)
				- (root.detail[a.name]?.signal ?? 0))
			|| a.name.localeCompare(b.name));
	}

	name: "network"
	title: "Wi-Fi"

	trailing: !root.enabled ? "Off"
		: !root.current ? "Not connected"
		: root.online ? root.detail[root.current.name]?.band ?? "Connected"
		: "No internet connection"

	trailingColor: root.enabled && root.current && !root.online
		? Theme.warning : Theme.glassTextPrimary

	trigger: WifiIcon {
		height: Theme.barIconHeight
		width: height * aspect

		crossed: !root.enabled
		level: !root.enabled || !root.current ? 0
			: root.barsFor(root.current.name) >= 3 ? 2 : 1

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

		// Opens the password dialog for a network by name, without having to
		// find and click its row.
		function join(ssid: string): void {
			root.open = false;
			root.joinDialog?.ask(ssid, root.barsFor(ssid),
				root.detail[ssid]?.secured ?? true);
		}

		// A way out that is not a keypress, for the same reason the lock screen
		// has one: this dialog holds the keyboard.
		function cancelJoin(): void {
			if (root.joinDialog)
				root.joinDialog.open = false;
		}

		function radio(on: string): void {
			Networking.wifiEnabled = on !== "off";
		}
	}

	// The radio itself. A switch rather than a chip: two states, no third.
	Item {
		width: parent.width
		height: radioSwitch.height

		Text {
			anchors.left: parent.left
			anchors.verticalCenter: parent.verticalCenter
			text: "Wi-Fi radio"
			font.pixelSize: Theme.fontBody
			color: Theme.glassTextPrimary
		}

		Switch {
			id: radioSwitch

			anchors.right: parent.right
			checked: root.enabled
			onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
		}
	}

	// The connected network, given a card of its own: it is the answer to the
	// question the tile was opened to ask.
	Rectangle {
		width: parent.width
		height: 46
		radius: 14
		visible: root.enabled && root.current !== null

		color: root.online ? Theme.glassChipActive : Theme.glassFillWarning
		border.width: 1
		border.color: root.online
			? Theme.glassTrackBorderFocus
			: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.5)

		Column {
			anchors {
				left: parent.left
				leftMargin: Theme.spacingM
				verticalCenter: parent.verticalCenter
			}

			spacing: 2

			Text {
				text: root.current?.name ?? ""
				font.pixelSize: Theme.fontBody
				font.bold: true
				color: Theme.glassTextPrimary
			}

			Text {
				text: {
					if (root.current?.stateChanging)
						return "Connecting…";
					if (!root.online)
						return "Connected · no route out";

					// The green dot already says "connected", so the line is
					// better spent on the address and the band.
					const band = root.detail[root.current?.name ?? ""]?.band;
					const parts = [root.ipAddress, band].filter(part => part);

					return parts.length > 0 ? parts.join(" · ") : "Connected";
				}

				font.pixelSize: Theme.fontCaption
				opacity: 0.75
				color: Theme.glassTextPrimary
			}
		}

		Row {
			anchors {
				right: parent.right
				rightMargin: Theme.spacingM
				verticalCenter: parent.verticalCenter
			}

			spacing: Theme.spacingS

			Rectangle {
				anchors.verticalCenter: parent.verticalCenter
				width: 6
				height: 6
				radius: 3
				visible: root.online
				color: Theme.success
			}

			SignalBars {
				anchors.verticalCenter: parent.verticalCenter
				level: root.barsFor(root.current?.name ?? "")
				color: Theme.glassTextPrimary
			}
		}

		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: root.wifi.requestDisconnect()
		}
	}

	Item {
		width: parent.width
		height: publicLabel.implicitHeight
		visible: root.enabled && root.online && root.publicIp !== ""

		Text {
			id: publicLabel

			anchors.left: parent.left
			text: "Public address"
			font.pixelSize: Theme.fontCaption
			opacity: 0.6
			color: Theme.glassTextPrimary
		}

		Text {
			anchors.right: parent.right
			text: root.publicIp
			font.pixelSize: Theme.fontCaption
			opacity: 0.85
			color: Theme.glassTextPrimary
		}
	}

	Text {
		width: parent.width
		visible: root.enabled && root.others.length > 0
		text: "OTHER NETWORKS"
		font.pixelSize: 10
		font.bold: true
		font.letterSpacing: 0.6
		opacity: 0.6
		color: Theme.glassTextPrimary
	}

	Column {
		width: parent.width
		spacing: Theme.spacingXs + 2
		visible: root.enabled && root.others.length > 0

		Repeater {
			model: Math.min(root.listLimit, root.others.length)

			Rectangle {
				id: row

				required property int index
				readonly property var network: root.others[row.index]

				width: parent.width
				height: 32
				radius: 14

				color: rowMouse.containsMouse
					? Theme.glassControlHover : Theme.glassControl
				border.width: 1
				border.color: Theme.glassControlBorder

				Behavior on color {
					ColorAnimation { duration: 120 }
				}

				Row {
					anchors {
						left: parent.left
						leftMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					spacing: Theme.spacingS - 2

					Text {
						anchors.verticalCenter: parent.verticalCenter
						text: row.network.name
						elide: Text.ElideRight
						width: Math.min(implicitWidth, 150)
						font.pixelSize: Theme.fontCaption
						// A saved network is one click away; the rest need a
						// password there is nowhere to type yet.
						opacity: 1.0
						color: Theme.glassTextPrimary
					}

					LockIcon {
						anchors.verticalCenter: parent.verticalCenter
						visible: root.detail[row.network.name]?.secured ?? false
						opacity: 0.6
						color: Theme.glassTextPrimary
					}
				}

				SignalBars {
					anchors {
						right: parent.right
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					level: root.barsFor(row.network.name)
					color: Theme.glassTextPrimary
				}

				MouseArea {
					id: rowMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: {
						if (row.network.known) {
							row.network.requestConnect();
							return;
						}

						// Unknown networks need a password, which means a
						// dialog. Open it *before* closing the tile: this
						// handler lives inside the tile's window, and closing
						// it first tears down the surface the click arrived on
						// while the rest of the handler is still running.
						root.joinDialog?.ask(row.network.name,
							root.barsFor(row.network.name),
							root.detail[row.network.name]?.secured ?? true);

						root.open = false;
					}
				}
			}
		}
	}

	Text {
		width: parent.width
		visible: root.enabled && root.others.length > root.listLimit
		text: (root.others.length - root.listLimit) + " more in range"
		font.pixelSize: Theme.fontCaption
		opacity: 0.6
		color: Theme.glassTextPrimary
	}
}
