import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's network readout, and the tile it opens.
//
// The connected network first, with its address and band, then the rest with
// strength and a lock - rows drawn as the system card draws its parts.
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

	// The network sheet - the full list and the join form, which are two pages
	// of one modal. Supplied by whoever built the bar, so this does not have
	// to own a window.
	property var dialog: null

	function barsFor(name) {
		const signal = root.detail[name]?.signal ?? -1;
		if (signal < 0)
			return 0;

		// Four bars over a 0-100 scale, with the bottom one lit for anything
		// audible at all.
		return signal >= 75 ? 4 : signal >= 50 ? 3 : signal >= 25 ? 2 : 1;
	}

	// nmcli reports what the access point advertises - "WPA2", "WPA1 WPA2",
	// "WPA2 802.1X", "" for an open network. The design's rows want one word,
	// and the strongest thing on offer is the honest one to name.
	function securityLabel(security) {
		const raw = security.trim();

		if (raw === "" || raw === "OWE")
			return "Open";
		if (raw.includes("802.1X"))
			return "Enterprise";
		if (raw.includes("WPA3"))
			return "WPA3";
		if (raw.includes("WPA2"))
			return "WPA2";
		if (raw.includes("WPA"))
			return "WPA";
		if (raw.includes("WEP"))
			return "WEP";

		return raw;
	}

	// Fastest first, for picking between a network's two bands.
	function bandRank(band) {
		return band === "6 GHz" ? 3 : band === "5 GHz" ? 2 : 1;
	}

	// FREQ is in MHz. 6 GHz starts at 5955, which is above the 5 GHz band but
	// still begins with a five - so the order of these tests matters.
	function bandFor(freq) {
		const mhz = parseInt(freq);

		return mhz >= 5925 ? "6 GHz" : mhz >= 5000 ? "5 GHz" : "2.4 GHz";
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

			// The same network is usually on both bands, and only one entry
			// survives. Prefer the one we are actually joined to - it is often
			// the weaker of the two, and reporting the stronger would put the
			// wrong band under "Connected".
			//
			// Otherwise prefer the faster band. "Whichever is stronger" was
			// tried and is not stable: the two bands trade places between
			// scans, and in a list grouped by band that makes rows jump from
			// one heading to another while they are being read.
			const band = root.bandFor(freq);
			const previous = found[name];

			const better = !previous
				|| (inUse === "*")
				|| (!previous.inUse
					&& (root.bandRank(band) > root.bandRank(previous.band)
						|| (band === previous.band
							&& previous.signal < signal)));

			if (better) {
				found[name] = {
					signal: signal,
					secured: security.trim() !== "",
					security: root.securityLabel(security),
					band: band,
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

	// Known networks connect; the rest need a password, which means the sheet.
	// Open it before closing the tile: this runs inside the tile's window, and
	// closing first tears down the surface the click arrived on.
	function activate(network) {
		if (network.known) {
			network.requestConnect();
			root.open = false;
			return;
		}

		root.dialog?.askJoin(network.name, root.barsFor(network.name),
			root.detail[network.name]?.secured ?? true);

		root.open = false;
	}

	function refreshPublicIp() {
		if (!Settings.publicAddressLookup || !root.online)
			return;

		if (root.publicIp !== ""
				&& Date.now() - root.publicIpAt < root.publicIpMaxAge)
			return;

		publicIpQuery.running = true;
	}

	Connections {
		target: Settings

		function onPublicAddressLookupChanged() {
			if (Settings.publicAddressLookup)
				root.refreshPublicIp();
			else
				root.publicIp = "";
		}
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
		running: root.scanning
		interval: 5000
		triggeredOnStart: true
		repeat: true
		onTriggered: {
			scan.running = true;
			ipQuery.running = true;
			root.refreshPublicIp();
		}
	}

	// The bar's arcs need the joined network's strength while nothing is
	// open, too, or they show whatever it was when the tile last closed.
	// NetworkManager keeps that reading current for the network it is on, so
	// asking without a rescan costs no airtime - it reads what is cached.
	Process {
		id: signalRead

		command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ",
			"device", "wifi", "list", "--rescan", "no"]

		stdout: StdioCollector {
			onStreamFinished: root.parseScan(text)
		}
	}

	Timer {
		running: root.enabled && !root.scanning && !!root.current
		interval: 30000
		triggeredOnStart: true
		repeat: true
		onTriggered: signalRead.running = true
	}

	// Scan while anything that shows networks is open. A wifi scan costs power
	// and airtime, and the list is worthless when nobody is looking - with the
	// scanner off the device reports only the network it is already on, which
	// is why tying this to the tile alone emptied the full list: the button
	// closes the tile on its way to opening the sheet.
	//
	// The sheet counts even on its join page, which shows no networks. Stopping
	// there empties the model, and the list page is still on screen at the time
	// - sliding out, visibly losing its contents as it goes. It also means a
	// failed join comes back to a list that is already populated.
	//
	// The sheet is one, and the bars are one per screen: only the lead bar
	// scans for it, and it is the one the sheet reads (shell.qml).
	readonly property bool scanning: root.enabled
		&& (root.open || (root.lead && (root.dialog?.open ?? false)))

	Binding {
		target: root.wifi
		property: "scannerEnabled"
		value: root.scanning
		when: root.wifi !== null
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
		height: Theme.barIconSize
		width: height * aspect

		crossed: !root.enabled
		// Four bars of signal onto three arcs: the top two bars share one.
		level: !root.enabled || !root.current ? 0
			: Math.max(1, root.barsFor(root.current.name) - 1)

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
		enabled: root.hasIpc

		function toggle(): void {
			root.open = !root.open;
		}

		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}

		// Buttons in the tile and the sheet do all of these. The IPC is for
		// driving them without a pointer, and for getting out of a sheet that
		// holds the keyboard.
		function list(): void {
			root.dialog?.showList();
			root.open = false;
		}

		// Straight to the join form for a network by name, without having to
		// find and click its row.
		function join(ssid: string): void {
			root.open = false;
			root.dialog?.askJoin(ssid, root.barsFor(ssid),
				root.detail[ssid]?.secured ?? true);
		}

		function hidden(): void {
			root.open = false;
			root.dialog?.askHidden();
		}

		// The way out. Named closeList as well because that is what the
		// keyboard-trap escape hatch has been called since the list was its
		// own window.
		function close(): void {
			root.dialog?.close();
		}

		function closeList(): void {
			root.dialog?.close();
		}

		function search(term: string): void {
			root.dialog?.setSearch(term);
		}

		// The tile has a switch for this; the IPC is for scripting it.
		function publicLookup(on: string): void {
			Settings.setPublicAddressLookup(on !== "off");
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
			anchors.leftMargin: 8
			anchors.verticalCenter: parent.verticalCenter
			text: "Wi-Fi radio"
			font.pixelSize: Theme.fontBody
			color: Theme.glassTextPrimary
		}

		// In line with the switches in the rows below.
		Switch {
			id: radioSwitch

			anchors.right: parent.right
			anchors.rightMargin: 4
			checked: root.enabled
			onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
		}
	}

	// The connected network first: it is the answer to the question the tile
	// was opened to ask. Then what the internet sees of it.
	Column {
		width: parent.width
		spacing: 0
		visible: root.enabled && root.current !== null

		CardRow {
			id: currentRow

			// Pointing at it is how anyone finds out what it does, so
			// pointing at it is when it says.
			readonly property bool offering: currentRow.hovered
				&& !(root.current?.stateChanging ?? false)

			interactive: true
			rowHeight: 48
			markOpacity: 1
			title: root.current?.name ?? ""
			detailColor: root.online ? Theme.glassTextPrimary : Theme.warning
			detail: {
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

			mark: WifiIcon {
				width: Theme.rowMark
				height: Theme.rowMark
				lineWidth: Theme.markLine
				level: Math.max(1, root.barsFor(root.current?.name ?? "") - 1)
				color: root.online ? Theme.glassTextPrimary : Theme.warning
			}

			onClicked: root.wifi.requestDisconnect()

			Chip {
				anchors.verticalCenter: parent.verticalCenter
				visible: currentRow.offering
				text: "Disconnect"

				// Takes the click itself as well as the row beneath it. Two
				// targets for one action is fine when missing the small one
				// still hits the large one.
				onClicked: root.wifi.requestDisconnect()
			}

			Rectangle {
				anchors.verticalCenter: parent.verticalCenter
				visible: root.online && !currentRow.offering
				width: 6
				height: 6
				radius: 3
				color: Theme.success
			}
		}

		// The switch stays visible whether or not the lookup is on, or there
		// would be no way to turn it back on. No mark: it is a fact about the
		// row above, so it sits under that row's name.
		CardRow {
			visible: root.online
			rule: "dashed"
			rowHeight: 48
			title: "Public address"
			detail: Settings.publicAddressLookup
				? (root.publicIp !== "" ? root.publicIp : "Asking…")
				: "Not checked"

			Switch {
				anchors.verticalCenter: parent.verticalCenter
				checked: Settings.publicAddressLookup
				onToggled: Settings.setPublicAddressLookup(
					!Settings.publicAddressLookup)
			}
		}
	}

	Column {
		width: parent.width
		spacing: 2
		visible: root.enabled && root.others.length > 0

		SectionLabel {
			text: "OTHER NETWORKS"
			bottomPadding: Theme.spacingXs
		}

		Repeater {
			model: Math.min(root.listLimit, root.others.length)

			CardRow {
				id: other

				required property int index
				readonly property var entry: root.others[index]

				interactive: true
				title: other.entry?.name ?? ""

				mark: WifiIcon {
					width: Theme.rowMark
					height: Theme.rowMark
					lineWidth: Theme.markLine
					level: Math.max(1, root.barsFor(other.entry?.name ?? "") - 1)
					color: Theme.glassTextPrimary
				}

				onClicked: root.activate(other.entry)

				LockIcon {
					anchors.verticalCenter: parent.verticalCenter
					visible: root.detail[other.entry?.name ?? ""]?.secured ?? false
					opacity: 0.6
					color: Theme.glassTextPrimary
				}
			}
		}
	}

	Row {
		width: parent.width
		spacing: Theme.spacingS
		visible: root.enabled

		DialogButton {
			width: (parent.width - Theme.spacingS) / 2
			text: root.others.length > root.listLimit
				? `All ${root.others.length} networks` : "All networks"

			onClicked: {
				// Before closing the tile, for the same reason as a row.
				root.dialog?.showList();
				root.open = false;
			}
		}

		DialogButton {
			width: (parent.width - Theme.spacingS) / 2

			// The sheet's own button says "Join Hidden Network…", which does
			// not fit half a tile. Dropping the verb is allowed; calling it
			// something else is not.
			text: "Hidden Network…"

			onClicked: {
				root.dialog?.askHidden();
				root.open = false;
			}
		}
	}
}
