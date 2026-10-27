import Quickshell
import Quickshell.Io
import QtQuick
import "../ui"
import "../icons"
import ".."

// Groma Store: the design's turn 11. Finding, installing, removing and
// updating packages from the official repositories and the AUR.
//
// Knowing is software-worker.py's job - pacman for the repositories, the
// AUR's own API for the rest, one JSON line each way. Doing is a
// terminal's: an install needs a password and prints a lot, so Install,
// Remove and Update open Foot running software-run.sh, which logs every
// line for the card in the corner to tail. The window chooses, shows what
// is installed and what is waiting, and never runs pacman itself.
Scope {
	id: root

	property bool open: false

	// "featured" | a category | "installed" | "updates" | "search"
	property string page: "featured"
	property var behind: []

	readonly property string query: searchField.text.trim()

	function show() {
		root.open = true;
	}

	function close() {
		root.open = false;
	}

	function go(where) {
		if (where === root.page)
			return;
		root.behind = root.behind.concat([root.page]);
		root.page = where;
		root.picked = 0;
		if (where !== "search")
			searchField.clear();
		if (where === "updates" && !root.checking)
			root.checkUpdates();
	}

	function goBack() {
		if (root.behind.length === 0)
			return;
		root.page = root.behind[root.behind.length - 1];
		root.behind = root.behind.slice(0, -1);
		root.picked = 0;
		if (root.page !== "search")
			searchField.clear();
	}

	// --- the catalog ------------------------------------------------------------

	FileView {
		id: catalogFile

		path: `${Quickshell.shellDir}/modules/software-catalog.json`
	}

	readonly property var catalog: {
		try {
			return JSON.parse(catalogFile.text());
		} catch (err) {
			return { featured: [], categories: [], apps: [] };
		}
	}

	// An entry that is neither in a repository nor in the AUR is not shown:
	// the list in the repo may name something a mirror has dropped.
	function available(app) {
		return app.source === "aur" || root.repos[app.pkg] !== undefined;
	}

	readonly property var tiles: {
		const apps = root.catalog.apps ?? [];
		const byPkg = {};
		for (const app of apps)
			byPkg[app.pkg] = app;
		const list = root.page === "featured"
			? (root.catalog.featured ?? []).map(pkg => byPkg[pkg]).filter(app => app !== undefined)
			: apps.filter(app => app.category === root.page);
		return list.filter(app => root.stateLoaded ? root.available(app) : true);
	}

	// --- the worker -------------------------------------------------------------

	Process {
		id: worker

		command: ["python3", `${Quickshell.shellDir}/modules/software-worker.py`]
		stdinEnabled: true
		onStarted: root.wantIcons(root.rows.map(r => r.name))
		onExited: if (root.open) reviveWorker.start()

		stdout: SplitParser {
			onRead: line => root.reply(line)
		}

		stderr: SplitParser {
			onRead: line => console.warn("Software worker:", line)
		}
	}

	Timer {
		id: reviveWorker

		interval: 2000
		onTriggered: if (root.open && !worker.running) { worker.running = true; root.refreshState(); }
	}

	property int nextId: 1
	property var pending: ({})

	function ask(op, args, then) {
		const id = root.nextId++;
		if (then)
			root.pending[id] = then;
		worker.write(JSON.stringify(Object.assign({ id: id, op: op }, args ?? {})) + "\n");
		return id;
	}

	function reply(line) {
		let msg;
		try {
			msg = JSON.parse(line);
		} catch (err) {
			return;
		}
		const then = root.pending[msg.id];
		delete root.pending[msg.id];
		if (!msg.ok) {
			root.say(msg.error);
			return;
		}
		if (then)
			then(msg);
	}

	property string notice: ""

	function say(text) {
		root.notice = text;
		noticeTimer.restart();
	}

	Timer {
		id: noticeTimer

		interval: 5000
		onTriggered: root.notice = ""
	}

	// --- what is installed, what exists ----------------------------------------

	property bool stateLoaded: false
	property var repos: ({})
	property var installedSet: ({})
	property var foreign: ({})
	property var explicit: []
	property string helper: ""
	property bool hasCheck: false
	property real synced: 0

	function refreshState() {
		root.ask("state", {}, msg => {
			root.repos = msg.repos;
			const set = {};
			for (const name of msg.installed)
				set[name] = true;
			root.installedSet = set;
			root.foreign = msg.foreign;
			root.explicit = msg.explicit;
			root.helper = msg.helper;
			root.hasCheck = msg.checkupdates;
			root.synced = msg.synced;
			root.stateLoaded = true;
		});
	}

	function isInstalled(pkg) {
		return root.installedSet[pkg] === true;
	}

	// --- updates ----------------------------------------------------------------

	property var updatesOfficial: []
	property var updatesAur: []
	property bool checking: false
	property real checked: 0
	property string updatesNote: ""
	// Official updates go together - Arch does not support partial
	// upgrades - so they have one switch; AUR ones have one each.
	property bool officialChosen: true
	property var aurChosen: ({})

	readonly property int updateCount: root.updatesOfficial.length + root.updatesAur.length
	readonly property int chosenCount: (root.officialChosen ? root.updatesOfficial.length : 0)
		+ root.updatesAur.filter(u => root.aurChosen[u.name] !== false).length

	function checkUpdates() {
		root.checking = true;
		root.ask("updates", {}, msg => {
			root.checking = false;
			root.updatesOfficial = msg.official;
			root.updatesAur = msg.aur;
			root.checked = msg.checked * 1000;
			root.updatesNote = !msg.hasCheck ? "Install pacman-contrib to check the official repositories"
				: msg.aurError !== "" ? msg.aurError : "";
		});
	}

	function hasUpdate(pkg) {
		return root.updatesOfficial.some(u => u.name === pkg) || root.updatesAur.some(u => u.name === pkg);
	}

	// --- search -----------------------------------------------------------------

	property var resultsOfficial: []
	property var resultsAur: []
	property string resultsFor: ""
	property string aurNote: ""
	property bool searching: false

	onQueryChanged: {
		if (root.query.length >= 2) {
			if (root.page !== "search")
				root.go("search");
			searchDebounce.restart();
		} else if (root.page === "search" && root.query === "") {
			root.goBack();
		}
	}

	Timer {
		id: searchDebounce

		interval: 350
		onTriggered: {
			const term = root.query;
			root.searching = true;
			root.ask("search", { term: term }, msg => {
				if (msg.term !== root.query)
					return;
				root.searching = false;
				root.resultsOfficial = msg.official;
				root.resultsAur = msg.aur;
				root.resultsFor = msg.term;
				root.aurNote = msg.aurError;
				root.picked = 0;
			});
		}
	}

	// --- one list for the keys ----------------------------------------------------

	// What is on the page, in the order drawn, as { name, source }.
	readonly property var rows: root.page === "search"
		? root.resultsOfficial.concat(root.resultsAur)
		: root.page === "installed" ? root.explicit
		: root.page === "updates" ? root.updatesOfficial.concat(root.updatesAur)
		: root.tiles.map(app => ({ name: app.pkg, source: app.source, app: app }))

	property int picked: 0
	readonly property var current: root.rows.length > 0 ? root.rows[Math.min(root.picked, root.rows.length - 1)] : null

	function move(delta) {
		if (root.rows.length === 0)
			return;
		root.picked = Math.max(0, Math.min(root.rows.length - 1, root.picked + delta));
	}

	// --- details ------------------------------------------------------------------

	// { name, source, app, info, loading } or null
	property var details: null

	function showDetails(row) {
		if (row === null)
			return;
		root.details = { name: row.name, source: row.source, app: row.app ?? null, info: null, loading: true };
		root.ask("info", { name: row.name, source: row.source }, msg => {
			if (root.details === null || root.details.name !== row.name)
				return;
			root.details = Object.assign({}, root.details, { info: msg, loading: false });
		});
	}

	// --- doing: the terminal ------------------------------------------------------

	readonly property string logPath:
		(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/groma-software.log"
	readonly property string runner: `${Quickshell.shellDir}/modules/software-run.sh`

	// { verb, what, started, last, pid, exit } or null
	property var job: null

	function runInTerminal(verb, what, argv) {
		if (root.job !== null && root.job.exit === undefined) {
			root.say("Wait for the current " + root.job.verb.toLowerCase() + " to finish");
			return;
		}
		root.job = { verb: verb, what: what, started: Date.now(), last: "", pid: 0 };
		Quickshell.execDetached(["foot", "--app-id=groma-software-run", "--title=Groma Store", "--",
			"bash", root.runner, root.logPath].concat(argv));
		tailTimer.start();
	}

	// An AUR package needs a helper to build it. Without one, the first
	// AUR install builds yay itself, the way its README says to.
	readonly property var bootstrap: ["bash", "-c",
		'set -e; sudo pacman -S --needed --noconfirm git base-devel; d=$(mktemp -d); '
		+ 'git clone https://aur.archlinux.org/yay-bin.git "$d/yay-bin"; cd "$d/yay-bin"; makepkg -si']

	function install(name, source) {
		if (source === "aur" && root.helper === "") {
			root.runInTerminal("Setting up", "AUR support (yay)", root.bootstrap);
			return;
		}
		const argv = source === "aur" ? [root.helper, "-S", "--needed", name] : ["sudo", "pacman", "-S", "--needed", name];
		root.runInTerminal("Installing", name, argv);
	}

	function remove(name) {
		root.runInTerminal("Removing", name, ["sudo", "pacman", "-Rns", name]);
	}

	function updateChosen() {
		const aur = root.updatesAur.filter(u => root.aurChosen[u.name] !== false).map(u => u.name);
		const official = root.officialChosen && root.updatesOfficial.length > 0;
		if (!official && aur.length === 0)
			return;
		if (aur.length > 0 && root.helper === "") {
			root.runInTerminal("Setting up", "AUR support (yay)", root.bootstrap);
			return;
		}
		const parts = [];
		if (official)
			parts.push("sudo pacman -Syu");
		if (aur.length > 0)
			parts.push(root.helper + " -S --needed " + aur.join(" "));
		root.runInTerminal("Updating", root.chosenCount === 1 ? "1 package" : root.chosenCount + " packages",
			["bash", "-c", parts.join(" && ")]);
	}

	function cancelJob() {
		if (root.job !== null && root.job.pid > 0)
			Quickshell.execDetached(["pkill", "-INT", "-P", String(root.job.pid)]);
	}

	function showTerminal() {
		focusProbe.running = true;
	}

	Process {
		id: focusProbe

		command: ["hyprctl", "clients", "-j"]

		stdout: StdioCollector {
			onStreamFinished: {
				let windows = [];
				try {
					windows = JSON.parse(text);
				} catch (err) {
					return;
				}
				const term = windows.find(w => w.class === "groma-software-run");
				if (term)
					Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${term.address}" })`]);
			}
		}
	}

	Timer {
		id: tailTimer

		interval: 500
		repeat: true
		onTriggered: { tail.running = false; tail.running = true; }
	}

	Process {
		id: tail

		command: ["bash", "-c", 'head -n1 "$1" 2>/dev/null; echo ---; tail -n 3 "$1" 2>/dev/null', "sh", root.logPath]

		stdout: StdioCollector {
			onStreamFinished: {
				if (root.job === null)
					return;
				const [head, rest] = text.split("---\n");
				const pid = head.startsWith("pid:") ? parseInt(head.slice(4)) : 0;
				const lines = (rest ?? "").split("\n").filter(l => l.trim() !== "");
				const exitLine = lines.find(l => l.startsWith("exit:"));
				const last = lines.filter(l => !l.startsWith("exit:") && !l.startsWith("pid:")).pop() ?? root.job.last;
				root.job = Object.assign({}, root.job, { pid: pid || root.job.pid, last: last.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\r/g, "").trim() });
				if (exitLine !== undefined) {
					const code = parseInt(exitLine.slice(5));
					tailTimer.stop();
					root.say(code === 0 ? root.job.verb.replace(/ing$/, "ed").replace("Sett", "Set") + " " + root.job.what
						: root.job.verb + " " + root.job.what + " stopped with code " + code);
					root.job = null;
					root.refreshState();
					if (root.page === "updates" || root.updateCount > 0)
						root.checkUpdates();
				}
			}
		}
	}

	// The card's clock.
	property real now: Date.now()

	Timer {
		interval: 1000
		repeat: true
		running: root.job !== null
		onTriggered: root.now = Date.now()
	}

	// --- words ----------------------------------------------------------------------

	function ago(ms) {
		if (!ms)
			return "";
		const minutes = Math.round((Date.now() - ms) / 60000);
		if (minutes < 1)
			return "just now";
		if (minutes < 60)
			return minutes + " min ago";
		const hours = Math.round(minutes / 60);
		if (hours < 24)
			return hours + " h ago";
		const days = Math.round(hours / 24);
		return days === 1 ? "yesterday" : days + " days ago";
	}

	function pageTitle(page) {
		return page === "featured" ? "Featured" : page === "installed" ? "Installed"
			: page === "updates" ? "Updates" : page === "search" ? "Search" : page;
	}

	function hue(name) {
		let h = 0;
		for (const ch of name)
			h = (h * 31 + ch.charCodeAt(0)) % 360;
		return h / 360;
	}

	function tint(name) { return Qt.hsla(root.hue(name), 0.55, 0.62, 1); }
	function ink(name) { return Qt.hsla(root.hue(name), 0.6, 0.30, 1); }

	readonly property string status: {
		if (root.page === "search")
			return root.searching ? `Searching for “${root.query}”…`
				: `${root.resultsOfficial.length + root.resultsAur.length} results for “${root.resultsFor}” · ${root.resultsOfficial.length} official, ${root.resultsAur.length} AUR`;
		if (root.page === "installed")
			return `${root.explicit.length} installed on purpose · ${Object.keys(root.foreign).length} from the AUR`;
		if (root.page === "updates")
			return root.checking ? "Checking for updates…"
				: `${root.chosenCount} of ${root.updateCount} selected`;
		const n = root.tiles.length;
		return `${root.pageTitle(root.page)} · ${n} apps` + (root.synced > 0 ? ` · databases synced ${root.ago(root.synced * 1000)}` : "");
	}

	onOpenChanged: {
		if (root.open) {
			worker.running = true;
			root.refreshState();
			root.checkUpdates();
		} else {
			worker.running = false;
			root.details = null;
		}
	}

	IpcHandler {
		target: "software"

		function open(): void { root.show(); }
		function close(): void { root.close(); }
		function toggle(): void { if (root.open) root.close(); else root.show(); }
		function page(name: string): void { root.go(name); }
		function search(term: string): void { root.show(); searchField.text = term; }
		function pick(index: int): void { root.picked = index; }
		function details(): void { root.showDetails(root.current); }
		function closeDetails(): void { root.details = null; }
	}

	// --- small pieces ---------------------------------------------------------------

	// The design's micro-chip: the source mark, and "out of date".
	component MicroChip: Rectangle {
		property alias text: microLabel.text
		property string kind: "official"

		width: microLabel.implicitWidth + 14
		height: microLabel.implicitHeight + 4
		radius: 7
		color: kind === "aur" ? Theme.chipAur : kind === "stale" ? Theme.chipOutOfDate : Theme.microChip
		border.width: 1
		border.color: kind === "aur" ? Theme.chipAurBorder : kind === "stale" ? Theme.chipOutOfDateBorder : Theme.microChipBorder

		Text {
			id: microLabel

			anchors.centerIn: parent
			font.pixelSize: 10
			font.bold: true
			font.letterSpacing: 0.4
			color: Theme.glassTextPrimary
		}
	}

	// Install · Installed · Update · Remove · Installing…
	component StateChip: Rectangle {
		id: stateChip

		property string state: "install"

		signal clicked

		readonly property string label: state === "installed" ? "Installed" : state === "update" ? "Update"
			: state === "remove" ? "Remove" : state === "busy" ? "Installing…" : "Install"

		width: stateLabel.implicitWidth + 24 + (state === "installed" ? 15 : 0)
		height: 28
		radius: 12
		opacity: state === "installed" ? 0.85 : 1
		color: state === "installed" ? Qt.rgba(1, 1, 1, 0.06)
			: state === "update" ? Theme.chipUpdate
			: state === "remove" ? Theme.chipDestructive
			: state === "busy" ? Theme.glassChip
			: stateMouse.containsMouse ? Theme.chipPrimaryHover : Theme.glassChipSelected
		border.width: 1
		border.color: state === "installed" ? Qt.rgba(1, 1, 1, 0.16)
			: state === "update" ? Theme.chipUpdateBorder
			: state === "remove" ? Theme.chipDestructiveBorder
			: Qt.rgba(1, 1, 1, 0.5)

		Row {
			anchors.centerIn: parent
			spacing: 6

			// The design's tick: two sides of a square, turned.
			Item {
				anchors.verticalCenter: parent.verticalCenter
				visible: stateChip.state === "installed"
				width: 9
				height: 9

				Item {
					anchors.centerIn: parent
					width: 9
					height: 5
					rotation: -45

					Rectangle { width: 2; height: parent.height; color: Theme.glassTextPrimary }
					Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.glassTextPrimary }
				}
			}

			Text {
				id: stateLabel

				anchors.verticalCenter: parent.verticalCenter
				text: stateChip.label
				font.pixelSize: Theme.fontBody
				font.weight: stateChip.state === "installed" ? Font.DemiBold : Font.Bold
				color: Theme.glassTextPrimary
			}
		}

		MouseArea {
			id: stateMouse

			anchors.fill: parent
			hoverEnabled: true
			enabled: stateChip.state !== "installed" && stateChip.state !== "busy"
			cursorShape: Qt.PointingHandCursor
			onClicked: stateChip.clicked()
		}
	}

	// A tinted disc with the application's icon, or its initial.
	// pkgname -> { names, file }, from the worker: the names to try in the
	// icon theme, and a converted catalogue icon for when none of them is.
	property var iconInfo: ({})

	// Only once the worker is running: a request written before it starts
	// is lost, and the packages in it would stay pending for good. It asks
	// again for the whole page when it does start.
	function wantIcons(names) {
		if (!worker.running)
			return;
		const missing = names.filter(n => n && root.iconInfo[n] === undefined);
		if (missing.length === 0)
			return;
		const pending = Object.assign({}, root.iconInfo);
		for (const n of missing)
			pending[n] = null;
		root.iconInfo = pending;
		root.ask("icons", { packages: missing }, msg => {
			root.iconInfo = Object.assign({}, root.iconInfo, msg.icons);
		});
	}

	function iconFor(pkg) {
		const info = root.iconInfo[pkg];
		const names = info ? info.names : [pkg];
		for (const n of names) {
			const themed = Quickshell.iconPath(n, true);
			if (themed !== "")
				return themed;
		}
		return info && info.file ? "file://" + info.file : "";
	}

	onRowsChanged: root.wantIcons(root.rows.map(r => r.name))

	component AppDisc: Lens {
		id: appDisc

		property string name: ""
		property string label: name
		readonly property string iconFile: root.iconFor(name)

		sheen: false
		// Plain pearl behind a real icon; the colour is only for the letter
		// that stands in when there is none.
		tint: appDisc.iconFile !== "" ? "transparent" : root.tint(label)

		Image {
			anchors.centerIn: parent
			width: parent.width * 0.62
			height: width
			visible: appDisc.iconFile !== ""
			source: appDisc.iconFile
			sourceSize: Qt.size(64, 64)
			fillMode: Image.PreserveAspectFit
		}

		Text {
			anchors.centerIn: parent
			visible: appDisc.iconFile === ""
			text: appDisc.label.slice(0, 1).toUpperCase()
			font.pixelSize: appDisc.width * 0.4
			font.weight: Font.Black
			color: root.ink(appDisc.label)
		}
	}

	function stateOf(name) {
		if (root.job !== null && root.job.what === name)
			return "busy";
		if (root.hasUpdate(name))
			return "update";
		return root.isInstalled(name) ? "installed" : "install";
	}

	function act(row) {
		if (row === null)
			return;
		const st = root.stateOf(row.name);
		if (st === "update")
			root.go("updates");
		else if (st === "install" && row.source === "aur")
			root.showDetails(row);
		else if (st === "install")
			root.install(row.name, row.source);
		else
			root.showDetails(row);
	}

	// --- the window ------------------------------------------------------------------

	FloatingWindow {
		id: window

		visible: root.open
		title: "Groma Store"
		color: "transparent"

		implicitWidth: Theme.filesWidth
		implicitHeight: Theme.filesHeight
		minimumSize: Qt.size(640, 400)

		onVisibleChanged: if (!visible) root.open = false

		GlassPanel {
			id: pane

			anchors.fill: parent
			radius: Theme.radiusWindow
			shadowLayers: 0

			Item {
				id: body

				anchors.fill: parent
				focus: true

				Keys.onPressed: event => {
					const ctrl = event.modifiers & Qt.ControlModifier;
					if (root.details !== null) {
						if (event.key === Qt.Key_Escape)
							root.details = null;
						event.accepted = true;
						return;
					}
					const columns = root.page === "featured" || root.catalog.categories.includes(root.page) ? 3 : 1;
					if (event.key === Qt.Key_Escape) {
						if (searchField.text !== "") {
							searchField.clear();
							body.forceActiveFocus();
						} else if (root.behind.length > 0) {
							root.goBack();
						} else {
							root.close();
						}
					} else if (event.key === Qt.Key_Down) {
						root.move(columns);
					} else if (event.key === Qt.Key_Up) {
						root.move(-columns);
					} else if (event.key === Qt.Key_Right && !searchField.activeFocus) {
						root.move(1);
					} else if (event.key === Qt.Key_Left && !searchField.activeFocus) {
						root.move(-1);
					} else if (event.key === Qt.Key_Tab) {
						root.showDetails(root.current);
					} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						if (root.page === "updates")
							root.updateChosen();
						else if (root.page === "search")
							root.act(root.current);
						else
							root.showDetails(root.current);
					} else if (event.key === Qt.Key_Space && root.page === "updates" && root.current !== null) {
						if (root.current.source === "aur")
							root.aurChosen = Object.assign({}, root.aurChosen, { [root.current.name]: root.aurChosen[root.current.name] === false });
						else
							root.officialChosen = !root.officialChosen;
					} else if (event.key === Qt.Key_Slash || (ctrl && event.key === Qt.Key_F)) {
						searchField.focusInput();
					} else if (!ctrl && event.text.length === 1 && event.text > " " && !searchField.activeFocus) {
						searchField.focusInput();
						searchField.text += event.text;
					} else {
						return;
					}
					event.accepted = true;
				}

				// Header.
				Item {
					id: header

					anchors { left: parent.left; right: parent.right; top: parent.top }
					height: Theme.filesHeaderHeight

					Rectangle {
						anchors.bottom: parent.bottom
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Row {
						id: navigation

						anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
						spacing: 16

						Lens {
							width: 34
							height: 34
							sheen: false
							opacity: root.behind.length > 0 ? 1 : 0.5

							FileGlyph { anchors.centerIn: parent; kind: "back" }

							MouseArea {
								anchors.fill: parent
								enabled: root.behind.length > 0
								cursorShape: Qt.PointingHandCursor
								onClicked: root.goBack()
							}
						}

						Rectangle {
							anchors.verticalCenter: parent.verticalCenter
							width: crumbLabel.implicitWidth + 24
							height: crumbLabel.implicitHeight + 12
							radius: Theme.radiusPill
							color: Theme.glassChipActive
							border.width: 1
							border.color: Theme.glassTrackBorderFocus

							Text {
								id: crumbLabel

								anchors.centerIn: parent
								text: root.pageTitle(root.page)
								font.pixelSize: Theme.fontTitle
								font.bold: true
								color: Theme.glassTextPrimary
							}
						}
					}

					Row {
						anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
						spacing: 10

						GlassField {
							id: searchField

							anchors.verticalCenter: parent.verticalCenter
							width: 240
							height: 38
							fontSize: Theme.fontTitle
							placeholder: "Search packages"

							leading: Lens {
								width: 26
								height: 26
								sheen: false

								FileGlyph { anchors.centerIn: parent; kind: "search" }
							}

							onAccepted: { root.act(root.current); body.forceActiveFocus(); }
						}

						DiscButton {
							anchors.verticalCenter: parent.verticalCenter
							width: 30
							height: 30
							onClicked: root.close()
						}
					}
				}

				// Sidebar: discover, categories, library.
				Rectangle {
					id: sidebar

					anchors { left: parent.left; top: header.bottom; bottom: footer.top }
					width: Theme.filesSidebarWidth
					color: Qt.rgba(1, 1, 1, 0.04)

					Rectangle {
						anchors.right: parent.right
						width: 1
						height: parent.height
						color: Theme.glassControlBorder
					}

					Column {
						anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 10; rightMargin: 10; topMargin: 6 }
						spacing: 2

						Repeater {
							model: [["DISCOVER", "", "", ""], ["", "featured", "Featured", "home"]]
								.concat([["CATEGORIES", "", "", ""]])
								.concat((root.catalog.categories ?? []).map(c => ["", c, c, "folder"]))
								.concat([["LIBRARY", "", "", ""], ["", "installed", "Installed", "downloads"], ["", "updates", "Updates", "drive"]])

							Item {
								id: side

								required property var modelData

								readonly property bool heading: modelData[0] !== ""
								readonly property bool here: root.page === modelData[1]

								width: parent.width
								height: heading ? headingLabel.implicitHeight + 14 : 38

								Text {
									id: headingLabel

									visible: side.heading
									leftPadding: 10
									topPadding: 10
									text: side.modelData[0]
									font.pixelSize: Theme.fontCaption
									font.bold: true
									font.letterSpacing: 0.66
									opacity: 0.6
									color: Theme.glassTextPrimary
								}

								Rectangle {
									anchors.fill: parent
									visible: !side.heading
									radius: Theme.radiusPill
									color: side.here ? Theme.glassChipActive
										: sideMouse.containsMouse ? Theme.glassControlHover : "transparent"
									border.width: side.here ? 1 : 0
									border.color: Theme.glassTrackBorderFocus

									Row {
										anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
										spacing: 10

										Lens {
											anchors.verticalCenter: parent.verticalCenter
											width: 26
											height: 26
											sheen: false

											FileGlyph { anchors.centerIn: parent; kind: side.modelData[3] || "folder" }
										}

										Text {
											anchors.verticalCenter: parent.verticalCenter
											width: parent.width - 36 - (countChip.visible ? countChip.width + 10 : 0)
											elide: Text.ElideRight
											text: side.modelData[2]
											font.pixelSize: Theme.fontTitle
											font.weight: side.here ? Font.Bold : Font.DemiBold
											color: Theme.glassTextPrimary
										}

										Rectangle {
											id: countChip

											anchors.verticalCenter: parent.verticalCenter
											visible: side.modelData[1] === "updates" && root.updateCount > 0
											width: Math.max(24, countLabel.implicitWidth + 14)
											height: 18
											radius: 9
											color: Theme.glassChipSelected
											border.width: 1
											border.color: Qt.rgba(1, 1, 1, 0.5)

											Text {
												id: countLabel

												anchors.centerIn: parent
												text: root.updateCount
												font.pixelSize: Theme.fontCaption
												font.bold: true
												color: Theme.glassTextPrimary
											}
										}
									}

									MouseArea {
										id: sideMouse

										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.PointingHandCursor
										onClicked: { body.forceActiveFocus(); root.go(side.modelData[1]); }
									}
								}
							}
						}
					}
				}

				// The page.
				Item {
					id: content

					anchors { left: sidebar.right; right: parent.right; top: header.bottom; bottom: footer.top }
					clip: true
					opacity: root.details !== null ? Theme.menuBackdropOpacity : 1

					Behavior on opacity { NumberAnimation { duration: 120 } }

					// Featured and the categories: a title, then tiles.
					Flickable {
						id: tilesPage

						anchors.fill: parent
						anchors.margins: 18
						anchors.leftMargin: 20
						anchors.rightMargin: 20
						visible: root.page === "featured" || (root.catalog.categories ?? []).includes(root.page)
						contentHeight: tilesColumn.height
						boundsBehavior: Flickable.StopAtBounds
						clip: true

						Column {
							id: tilesColumn

							width: parent.width
							spacing: 14

							Column {
								spacing: 4

								Text {
									text: root.pageTitle(root.page)
									font.pixelSize: Theme.fontSearch
									font.bold: true
									color: Theme.glassTextPrimary
								}

								Text {
									text: root.page === "featured" ? "Picked from the official repositories and the AUR"
										: `${root.page} from the official repositories and the AUR`
									font.pixelSize: Theme.fontBody
									font.weight: Font.DemiBold
									opacity: 0.75
									color: Theme.glassTextPrimary
								}
							}

							Grid {
								id: tileGrid

								readonly property int cols: width >= 600 ? 3 : 2

								width: parent.width
								columns: cols
								spacing: 12

								Repeater {
									model: root.tiles

									Rectangle {
										id: tile

										required property var modelData
										required property int index

										readonly property bool chosen: root.picked === index
										readonly property bool lifted: chosen || tileMouse.containsMouse

										width: (tileGrid.width - tileGrid.spacing * (tileGrid.cols - 1)) / tileGrid.cols
										height: 128
										radius: 20
										color: lifted ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.07)
										border.width: 1
										border.color: lifted ? Qt.rgba(1, 1, 1, 0.42) : Qt.rgba(1, 1, 1, 0.16)
										transform: Translate { y: tile.lifted ? -2 : 0 }

										Behavior on color { ColorAnimation { duration: 120 } }

										Row {
											anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
											spacing: 12

											AppDisc {
												id: tileDisc

												width: 44
												height: 44
												name: tile.modelData.pkg
												label: tile.modelData.name
											}

											Column {
												width: parent.width - tileDisc.width - 12
												spacing: 3

												Text {
													width: parent.width
													elide: Text.ElideRight
													text: tile.modelData.name
													font.pixelSize: 15
													font.bold: true
													color: Theme.glassTextPrimary
												}

												Text {
													width: parent.width
													wrapMode: Text.WordWrap
													maximumLineCount: 2
													elide: Text.ElideRight
													text: tile.modelData.desc
													font.pixelSize: Theme.fontBody
													opacity: 0.82
													lineHeight: 1.1
													color: Theme.glassTextPrimary
												}
											}
										}

										MouseArea {
											id: tileMouse

											anchors.fill: parent
											hoverEnabled: true
											cursorShape: Qt.PointingHandCursor
											onClicked: { body.forceActiveFocus(); root.picked = tile.index; root.showDetails({ name: tile.modelData.pkg, source: tile.modelData.source, app: tile.modelData }); }
										}

										MicroChip {
											anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
											anchors.bottomMargin: 18
											kind: tile.modelData.source
											text: tile.modelData.source === "aur" ? "AUR" : "official"
										}

										StateChip {
											anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
											state: root.stateOf(tile.modelData.pkg)
											onClicked: root.act({ name: tile.modelData.pkg, source: tile.modelData.source, app: tile.modelData })
										}
									}
								}
							}
						}
					}

					// Search, Installed and Updates: lists of rows.
					ListView {
						id: listPage

						anchors.fill: parent
						anchors.margins: 12
						visible: !tilesPage.visible
						clip: true
						spacing: 4
						boundsBehavior: Flickable.StopAtBounds
						model: root.rows
						currentIndex: root.picked
						highlightFollowsCurrentItem: false
						onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
						// A page, or a list that arrived late, opens at its top:
						// the header is part of the page, not something to scroll to.
						onCountChanged: if (root.picked === 0) positionViewAtBeginning()
						Connections {
							target: root
							function onPageChanged() { listPage.positionViewAtBeginning(); }
						}

						header: Item {
							width: listPage.width
							height: root.page === "updates" ? updatesHead.height + 8 : root.page === "installed" ? 60 : 0

							// Updates: the count, when it was checked, and the one action.
							Item {
								id: updatesHead

								visible: root.page === "updates"
								width: parent.width
								height: 56

								Column {
									anchors { left: parent.left; leftMargin: 4; right: updateActions.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
									spacing: 4

									Text {
										width: parent.width
										elide: Text.ElideRight
										// "available" is what goes when a tile is narrow.
										readonly property bool narrow: listPage.width < 760
										text: root.checking ? "Checking…" : root.updateCount === 0 ? "Everything is up to date"
											: root.updateCount === 1 ? "1 update" + (narrow ? "" : " available")
											: `${root.updateCount} updates` + (narrow ? "" : " available")
										font.pixelSize: Theme.fontSearch
										font.bold: true
										color: Theme.glassTextPrimary
									}

									Text {
										width: parent.width
										wrapMode: Text.WordWrap
										maximumLineCount: 2
										elide: Text.ElideRight
										text: (root.updatesNote !== "" ? root.updatesNote + " · " : "")
											+ (root.checked > 0 ? "Checked " + root.ago(root.checked) + " · " : "") + "runs in Terminal"
										font.pixelSize: Theme.fontBody
										font.weight: Font.DemiBold
										opacity: 0.75
										color: Theme.glassTextPrimary
									}
								}

								Row {
									id: updateActions

									anchors { right: parent.right; verticalCenter: parent.verticalCenter }
									spacing: 8
									visible: root.updateCount > 0

									DialogButton {
										text: "Select all"
										onClicked: { root.officialChosen = true; root.aurChosen = ({}); }
									}

									DialogButton {
										text: root.chosenCount === 1 ? "Update 1 package" : `Update ${root.chosenCount} packages`
										variant: "primary"
										enabled: root.chosenCount > 0 && root.job === null
										onClicked: root.updateChosen()
									}
								}
							}

							Column {
								visible: root.page === "installed"
								anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
								spacing: 4

								Text {
									text: "Installed"
									font.pixelSize: Theme.fontSearch
									font.bold: true
									color: Theme.glassTextPrimary
								}

								Text {
									text: "What was installed on purpose, not what came along as a dependency"
									font.pixelSize: Theme.fontBody
									font.weight: Font.DemiBold
									opacity: 0.75
									color: Theme.glassTextPrimary
								}
							}
						}

						delegate: Item {
							id: row

							required property var modelData
							required property int index

							readonly property bool aur: modelData.source === "aur"
							readonly property bool chosen: root.picked === index
							// A heading above the first of each kind.
							readonly property bool headed: index === 0 || root.rows[index - 1].source !== modelData.source
							readonly property bool update: root.page === "updates"
							readonly property bool ticked: row.update && (row.aur ? root.aurChosen[modelData.name] !== false : root.officialChosen)

							width: listPage.width
							height: 48 + (headed && root.page !== "installed" ? 30 : 0)

							Row {
								visible: row.headed && root.page !== "installed"
								x: row.update ? 13 : 13
								height: 30
								spacing: 12

								// Updates: the official group's one checkbox.
								Rectangle {
									anchors.verticalCenter: parent.verticalCenter
									visible: row.update && !row.aur
									width: 22
									height: 22
									radius: 8
									color: root.officialChosen ? Theme.glassChipSelected : Theme.glassChip
									border.width: 1
									border.color: Qt.rgba(1, 1, 1, 0.5)

									FileGlyph { visible: false }

									Item {
										anchors.centerIn: parent
										visible: root.officialChosen
										width: 9
										height: 5
										rotation: -45

										Rectangle { width: 2; height: parent.height; color: Theme.fileInk }
										Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.fileInk }
									}

									MouseArea {
										anchors.fill: parent
										cursorShape: Qt.PointingHandCursor
										onClicked: root.officialChosen = !root.officialChosen
									}
								}

								Text {
									anchors.verticalCenter: parent.verticalCenter
									text: (row.aur ? "AUR · " + (row.update ? root.updatesAur.length : root.resultsAur.length)
										: "OFFICIAL · " + (row.update ? root.updatesOfficial.length : root.resultsOfficial.length))
									font.pixelSize: Theme.fontCaption
									font.bold: true
									font.letterSpacing: 0.66
									opacity: 0.6
									color: Theme.glassTextPrimary
								}

								Text {
									anchors.verticalCenter: parent.verticalCenter
									width: listPage.width - x - 26
									elide: Text.ElideRight
									text: row.update ? (row.aur ? "Rebuilt locally from each PKGBUILD" : "Updated together with pacman -Syu; Arch doesn’t support partial upgrades")
										: row.aur ? "· built from user-submitted PKGBUILDs" : ""
									font.pixelSize: Theme.fontCaption
									font.weight: Font.DemiBold
									opacity: 0.75
									color: Theme.glassTextPrimary
								}
							}

							Rectangle {
								anchors.bottom: parent.bottom
								width: parent.width
								height: 48
								radius: Theme.radiusRow
								color: row.chosen ? Theme.glassChipActive : rowMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: row.chosen ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								MouseArea {
									id: rowMouse

									anchors.fill: parent
									hoverEnabled: true
									onClicked: { body.forceActiveFocus(); root.picked = row.index; }
									onDoubleClicked: root.showDetails(row.modelData)
								}

								Row {
									anchors { left: parent.left; right: rowRight.left; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
									spacing: 12

									// Updates: an AUR row's own checkbox.
									Rectangle {
										anchors.verticalCenter: parent.verticalCenter
										visible: row.update
										width: 22
										height: 22
										radius: 8
										opacity: row.aur ? 1 : 0.5
										color: row.ticked ? Theme.glassChipSelected : Theme.glassChip
										border.width: 1
										border.color: Qt.rgba(1, 1, 1, 0.5)

										Item {
											anchors.centerIn: parent
											visible: row.ticked
											width: 9
											height: 5
											rotation: -45

											Rectangle { width: 2; height: parent.height; color: Theme.fileInk }
											Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.fileInk }
										}

										MouseArea {
											anchors.fill: parent
											enabled: row.aur
											cursorShape: Qt.PointingHandCursor
											onClicked: root.aurChosen = Object.assign({}, root.aurChosen, { [row.modelData.name]: !row.ticked })
										}
									}

									AppDisc {
										id: rowDisc

										anchors.verticalCenter: parent.verticalCenter
										width: 30
										height: 30
										name: row.modelData.name
									}

									Column {
										anchors.verticalCenter: parent.verticalCenter
										width: parent.width - rowDisc.width - 12 - (row.update ? 34 : 0)
										spacing: 2

										Row {
											spacing: 8

											Text {
												text: row.modelData.name
												font.pixelSize: Theme.fontLead
												font.bold: true
												color: Theme.glassTextPrimary
											}

											Text {
												anchors.verticalCenter: parent.verticalCenter
												visible: !row.update
												text: row.modelData.version ?? ""
												font.family: "monospace"
												font.pixelSize: Theme.fontCaption
												font.weight: Font.DemiBold
												opacity: 0.7
												color: Theme.glassTextPrimary
											}

											MicroChip {
												anchors.verticalCenter: parent.verticalCenter
												visible: row.modelData.outOfDate === true
												kind: "stale"
												text: "out of date"
											}
										}

										Text {
											width: parent.width
											elide: Text.ElideRight
											visible: text !== ""
											text: row.update ? `${row.modelData.from}  →  ${row.modelData.to}` : (row.modelData.desc ?? "")
											font.family: row.update ? "monospace" : Qt.application.font.family
											font.pixelSize: Theme.fontBody
											opacity: 0.78
											color: Theme.glassTextPrimary
										}
									}
								}

								// The right-hand columns and the action.
								Row {
									id: rowRight

									anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
									spacing: 14

									Text {
										anchors.verticalCenter: parent.verticalCenter
										visible: root.page === "search" && !row.aur && listPage.width > 620
										width: 52
										text: row.modelData.repo ?? ""
										font.pixelSize: Theme.fontBody
										font.weight: Font.DemiBold
										opacity: 0.75
										color: Theme.glassTextPrimary
									}

									Text {
										anchors.verticalCenter: parent.verticalCenter
										visible: root.page === "search" && !row.aur && listPage.width > 620
										width: 70
										text: (row.modelData.size ?? "").replace("MiB", "MB").replace("KiB", "KB").replace("GiB", "GB")
										font.pixelSize: Theme.fontBody
										font.weight: Font.DemiBold
										opacity: 0.75
										color: Theme.glassTextPrimary
									}

									Repeater {
										model: root.page === "search" && row.aur && listPage.width > 620
											? [[String(row.modelData.votes), 40], [String(row.modelData.popularity), 40], [row.modelData.maintainer, 80]] : []

										Text {
											required property var modelData

											anchors.verticalCenter: parent.verticalCenter
											width: modelData[1]
											elide: Text.ElideRight
											text: modelData[0]
											font.pixelSize: Theme.fontBody
											font.weight: Font.DemiBold
											opacity: 0.75
											color: Theme.glassTextPrimary
										}
									}

									MicroChip {
										anchors.verticalCenter: parent.verticalCenter
										visible: root.page !== "search"
										kind: row.modelData.source
										text: row.aur ? "AUR" : "official"
									}

									Text {
										anchors.verticalCenter: parent.verticalCenter
										visible: row.update && row.aur
										text: "build"
										font.pixelSize: Theme.fontBody
										font.weight: Font.DemiBold
										opacity: 0.75
										color: Theme.glassTextPrimary
									}

									// On Installed, Remove only where the eye already is:
									// forty amber chips down a page read as an alarm.
									StateChip {
										anchors.verticalCenter: parent.verticalCenter
										visible: !row.update && (root.page !== "installed" || row.chosen || rowMouse.containsMouse)
										state: root.page === "installed" ? "remove" : root.stateOf(row.modelData.name)
										onClicked: root.page === "installed" ? root.showDetails(row.modelData) : root.act(row.modelData)
									}
								}
							}
						}

						Text {
							anchors.centerIn: parent
							visible: root.rows.length === 0 && !root.searching && !root.checking && root.page !== "updates"
							width: parent.width - 40
							horizontalAlignment: Text.AlignHCenter
							wrapMode: Text.WordWrap
							text: root.page === "search" ? (root.aurNote !== "" ? root.aurNote : `Nothing matches “${root.query}”`) : "Nothing here yet"
							font.pixelSize: Theme.fontTitle
							font.weight: Font.DemiBold
							opacity: 0.6
							color: Theme.glassTextPrimary
						}
					}
				}

				// Footer.
				Item {
					id: footer

					anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
					height: Theme.filesFooterHeight

					Rectangle { width: parent.width; height: 1; color: Theme.glassControlBorder }

					Text {
						anchors { left: parent.left; leftMargin: 18; right: keys.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
						elide: Text.ElideRight
						text: root.notice !== "" ? root.notice : root.job !== null ? `${root.job.verb} ${root.job.what} in Terminal` : root.status
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						opacity: 0.75
						color: Theme.glassTextPrimary
					}

					Row {
						id: keys

						anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
						spacing: 14
						opacity: 0.85

						Repeater {
							model: root.details !== null ? [["Esc", "Close"]]
								: root.page === "updates" ? [["↑↓", "Move"], ["Space", "Toggle"], ["↵", "Update"], ["Esc", "Back"]]
								: root.page === "search" ? [["↑↓", "Move"], ["↵", root.current?.source === "aur" && root.stateOf(root.current?.name ?? "") === "install" ? "Details" : "Install"], ["Tab", "Details"], ["Esc", "Clear"]]
								: [[root.page === "installed" ? "↑↓" : "←↑↓→", "Move"], ["↵", "Details"], ["/", "Search"], ["Esc", root.behind.length > 0 ? "Back" : "Close"]]

							Row {
								required property var modelData

								spacing: 6

								KeyCap { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[0] }

								Text {
									anchors.verticalCenter: parent.verticalCenter
									text: parent.modelData[1]
									font.pixelSize: Theme.fontBody
									font.weight: Font.DemiBold
									color: Theme.glassTextPrimary
								}
							}
						}
					}
				}
			}

			// The install in flight, docked bottom right: what, since when, the
			// terminal's last line, a sweep for a job with no percentage.
			GlassPanel {
				id: jobCard

				anchors { right: parent.right; bottom: parent.bottom; rightMargin: 16; bottomMargin: Theme.filesFooterHeight + 16 }
				width: Math.min(320, parent.width - 32)
				height: jobColumn.implicitHeight + 28
				radius: 20
				color: Theme.menuSurface
				shadowLayers: 8
				visible: opacity > 0.01
				opacity: root.job !== null ? 1 : 0

				Behavior on opacity { NumberAnimation { duration: 220 } }

				Column {
					id: jobColumn

					anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
					spacing: 10

					Row {
						width: parent.width
						spacing: 10

						Lens {
							width: 36
							height: 36
							sheen: false

							FileGlyph { anchors.centerIn: parent; kind: "downloads" }
						}

						Column {
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width - 46
							spacing: 2

							Text {
								width: parent.width
								elide: Text.ElideRight
								text: root.job ? `${root.job.verb} ${root.job.what}` : ""
								font.pixelSize: Theme.fontTitle
								font.bold: true
								color: Theme.glassTextPrimary
							}

							Text {
								text: {
									if (!root.job)
										return "";
									const s = Math.max(0, Math.floor((root.now - root.job.started) / 1000));
									return `In Terminal · started ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")} ago`;
								}
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.75
								color: Theme.glassTextPrimary
							}
						}
					}

					Rectangle {
						width: parent.width
						height: tailLine.implicitHeight + 14
						radius: 10
						color: Theme.terminalInset
						border.width: 1
						border.color: Qt.rgba(1, 1, 1, 0.14)

						Text {
							id: tailLine

							anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
							elide: Text.ElideRight
							text: root.job?.last || "Waiting for the terminal…"
							font.family: "monospace"
							font.pixelSize: Theme.fontCaption
							font.weight: Font.DemiBold
							opacity: 0.92
							color: Theme.glassTextPrimary
						}
					}

					// The indeterminate track: a band sweeping every 1.4 s.
					Rectangle {
						width: parent.width
						height: 6
						radius: 3
						color: Theme.glassControlHover
						clip: true

						Rectangle {
							id: sweep

							// A fraction, not a position: a range fixed when the
							// animation started would be the zero width the track
							// had before it was laid out.
							property real at: 0

							x: -width + at * (parent.width + width)
							width: parent.width * 0.3
							height: parent.height
							radius: 3

							gradient: Gradient {
								orientation: Gradient.Horizontal
								GradientStop { position: 0.0; color: "#00ffffff" }
								GradientStop { position: 0.5; color: "#ffffffff" }
								GradientStop { position: 1.0; color: "#00ffffff" }
							}

							NumberAnimation on at {
								running: root.job !== null
								loops: Animation.Infinite
								from: 0
								to: 1
								duration: 1400
								easing.type: Easing.Bezier
								easing.bezierCurve: [0.45, 0, 0.25, 1, 1, 1]
							}
						}
					}

					Item {
						width: parent.width
						height: 28

						DialogButton { anchors.left: parent.left; text: "Show terminal"; onClicked: root.showTerminal() }
						DialogButton { anchors.right: parent.right; text: "Cancel"; enabled: (root.job?.pid ?? 0) > 0; onClicked: root.cancelJob() }
					}
				}
			}

			// Details, from 11c: over the window, dense, one action.
			GlassDialog {
				id: detailsSheet

				anchors.fill: parent
				dense: true
				open: root.details !== null
				visible: open || sheet.opacity > 0.01
				sheetWidth: Math.min(460, parent.width - 40)

				readonly property var d: root.details
				readonly property var info: d?.info ?? null
				readonly property bool aur: d?.source === "aur"
				readonly property bool installed: d !== null && root.isInstalled(d.name)

				Item {
					width: parent.width
					height: 48

					AppDisc {
						id: detailDisc

						anchors.verticalCenter: parent.verticalCenter
						width: 48
						height: 48
						name: detailsSheet.d?.name ?? ""
						label: detailsSheet.d?.app?.name ?? detailsSheet.d?.name ?? "?"
					}

					Column {
						anchors { left: detailDisc.right; right: detailClose.left; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
						spacing: 3

						Text {
							width: parent.width
							elide: Text.ElideRight
							text: detailsSheet.d?.app?.name ?? detailsSheet.d?.name ?? ""
							font.pixelSize: Theme.fontLead + 2
							font.bold: true
							color: Theme.glassTextPrimary
						}

						Row {
							spacing: 8

							Text {
								anchors.verticalCenter: parent.verticalCenter
								text: detailsSheet.info?.version ?? ""
								font.family: "monospace"
								font.pixelSize: Theme.fontCaption
								font.weight: Font.DemiBold
								opacity: 0.75
								color: Theme.glassTextPrimary
							}

							MicroChip {
								kind: detailsSheet.aur ? "aur" : "official"
								text: detailsSheet.aur ? "AUR" : "official"
							}

							MicroChip {
								visible: detailsSheet.info?.outOfDate === true
								kind: "stale"
								text: "out of date"
							}
						}
					}

					DiscButton {
						id: detailClose

						anchors { right: parent.right; verticalCenter: parent.verticalCenter }
						onClicked: root.details = null
					}
				}

				Text {
					width: parent.width
					wrapMode: Text.WordWrap
					text: detailsSheet.d === null ? "" : detailsSheet.d.loading ? "Reading the package…"
						: (detailsSheet.info?.desc ?? "") + (detailsSheet.installed && !root.hasUpdate(detailsSheet.d.name) ? " Installed and up to date." : "")
					font.pixelSize: Theme.fontBody
					lineHeight: 1.4
					opacity: 0.85
					color: Theme.glassTextPrimary
				}

				Column {
					width: parent.width
					spacing: 6
					visible: detailsSheet.info !== null

					Repeater {
						model: {
							const i = detailsSheet.info;
							if (i === null)
								return [];
							const rows = [];
							if (detailsSheet.aur) {
								rows.push(["Maintainer", i.maintainer]);
								if (i.modified)
									rows.push(["Last updated", Qt.formatDate(new Date(i.modified * 1000), "MMM d, yyyy") + " · " + root.ago(i.modified * 1000)]);
								rows.push(["Votes · Popularity", `${i.votes} · ${i.popularity}`]);
								rows.push(["Dependencies", `${i.depends} packages` + (i.makedepends ? ` · ${i.makedepends} to build` : "")]);
							} else {
								rows.push(["Repository", i.repo]);
								if (i.built)
									rows.push(["Built", i.built]);
								rows.push(["Dependencies", `${i.depends} packages`]);
								if (i.download)
									rows.push(["Download", i.download]);
								if (i.size)
									rows.push(["Installed size", i.size]);
							}
							return rows;
						}

						Item {
							required property var modelData

							width: parent.width
							height: 22

							Text {
								anchors.verticalCenter: parent.verticalCenter
								x: 4
								text: modelData[0]
								font.pixelSize: Theme.fontBody
								font.bold: true
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							Text {
								anchors { left: parent.left; right: parent.right; leftMargin: 150; verticalCenter: parent.verticalCenter }
								elide: Text.ElideRight
								text: modelData[1] ?? ""
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								color: Theme.glassTextPrimary
							}
						}
					}
				}

				// The package page, as a link chip.
				Rectangle {
					width: parent.width
					height: 34
					radius: 12
					visible: (detailsSheet.info?.url ?? "") !== ""
					color: linkMouse.containsMouse ? Theme.glassControlHover : Theme.glassChip
					border.width: 1
					border.color: Theme.glassControlBorder

					Text {
						anchors { left: parent.left; right: arrow.left; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
						elide: Text.ElideMiddle
						text: (detailsSheet.info?.url ?? "").replace(/^https:\/\//, "")
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						color: Theme.glassTextPrimary
					}

					Text {
						id: arrow

						anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
						text: "↗"
						font.pixelSize: Theme.fontTitle
						font.bold: true
						color: Theme.glassTextPrimary
					}

					MouseArea {
						id: linkMouse

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: Quickshell.execDetached(["xdg-open", detailsSheet.info.url])
					}
				}

				// For the AUR, the caution the design puts above the chips.
				Rectangle {
					width: parent.width
					height: caution.implicitHeight + 16
					radius: 12
					visible: detailsSheet.aur && !detailsSheet.installed
					color: Theme.chipOutOfDate
					border.width: 1
					border.color: Theme.chipOutOfDateBorder

					Text {
						id: caution

						anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
						wrapMode: Text.WordWrap
						text: "AUR packages are built from user-submitted scripts. Check the maintainer and the PKGBUILD."
							+ (root.helper === "" ? " The first AUR install sets up yay to build them." : "")
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						color: Theme.glassTextPrimary
					}
				}

				Row {
					anchors.right: parent.right
					spacing: Theme.spacingS

					DialogButton { text: "Cancel"; onClicked: root.details = null }

					DialogButton {
						readonly property string mode: detailsSheet.d === null ? "" : root.hasUpdate(detailsSheet.d.name) ? "update"
							: detailsSheet.installed ? "remove" : "install"

						text: mode === "update" ? "Update" : mode === "remove" ? "Remove" : "Install"
						variant: mode === "remove" ? "destructive" : "primary"
						enabled: detailsSheet.d !== null && !detailsSheet.d.loading && (detailsSheet.info?.missing !== true) && root.job === null
						onClicked: {
							const d = detailsSheet.d;
							root.details = null;
							if (mode === "update")
								root.go("updates");
							else if (mode === "remove")
								root.remove(d.name);
							else
								root.install(d.name, d.source);
						}
					}
				}
			}
		}
	}
}
