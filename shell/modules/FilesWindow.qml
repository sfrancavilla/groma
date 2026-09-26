import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Effects
import "../ui"
import "../icons"
import ".."

// Files: the design's turn 10, an ordinary window rather than a sheet.
//
// The window never touches the disk itself. QML can read a folder but not
// write one, so browsing lives here and every operation goes through the
// worker beside this file, files-worker.py: one JSON line each way. Rename,
// new folder, trash, restore and undo are here; copy and move come next.
//
// The window is the pane, edge to edge, and it tiles like any other:
// Hyprland rounds it and casts the shadow, and the layout is anchored so
// whatever size the tiler hands it works. Padding for a shadow of our own
// would be part of the window, and the compositor blurs a window's whole
// rectangle, so it showed as a frosted band around the glass. The design's
// 1040×660 is what it asks for when floated.
Scope {
	id: root

	readonly property string home: Quickshell.env("HOME")
	readonly property string trashPath:
		(Quickshell.env("XDG_DATA_HOME") || root.home + "/.local/share") + "/Trash/files"

	property bool open: false
	property string path: root.home
	property bool grid: false
	property bool showHidden: false

	// Where Back and Forward go. Plain arrays, replaced rather than mutated,
	// so the header's discs follow them.
	property var behind: []
	property var ahead: []

	// The path of the highlighted entry, or "" for none.
	property string picked: ""

	readonly property string filter: searchField.text.trim()

	readonly property bool inTrash: root.path === root.trashPath

	// --- the worker -------------------------------------------------------

	Process {
		id: worker

		command: ["python3", `${Quickshell.shellDir}/modules/files-worker.py`]
		stdinEnabled: true
		onExited: if (root.open) reviveWorker.start()

		stdout: SplitParser {
			onRead: line => root.reply(line)
		}

		stderr: SplitParser {
			onRead: line => console.warn("Files worker:", line)
		}
	}

	Timer {
		id: reviveWorker

		interval: 2000
		onTriggered: if (root.open && !worker.running) worker.running = true
	}

	property int nextId: 1
	property var pending: ({})

	// Sends one request; `then` gets the answer if it was a yes. A no is
	// said in the footer, whoever asked.
	function ask(op, args, then) {
		const id = root.nextId++;
		if (then)
			root.pending[id] = then;
		worker.write(JSON.stringify(Object.assign({ id: id, op: op }, args ?? {})) + "\n");
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

	// A sentence in the footer for a few seconds: what just happened, or
	// why it did not.
	property string notice: ""

	function say(text) {
		root.notice = text;
		noticeTimer.restart();
	}

	Timer {
		id: noticeTimer

		interval: 4000
		onTriggered: root.notice = ""
	}

	// --- the operations ----------------------------------------------------

	// The path being renamed, or "". The editor draws itself in that row or
	// tile and owns the keyboard until it is done.
	property string renaming: ""
	property bool renamingFolder: false
	// A folder just made, to be renamed as soon as the model shows it.
	property string pendingRename: ""

	function startRename(entry) {
		root.picked = entry.path;
		root.renamingFolder = entry.folder;
		root.renaming = entry.path;
	}

	function commitRename(name) {
		const path = root.renaming;
		root.renaming = "";
		if (path === "" || name.trim() === "" || name === root.baseName(path))
			return;
		root.ask("rename", { path: path, name: name.trim() }, msg => { root.picked = msg.path; });
	}

	function cancelRename() {
		root.renaming = "";
		body.forceActiveFocus();
	}

	function newFolder() {
		root.ask("mkdir", { parent: root.path }, msg => { root.pendingRename = msg.path; });
	}

	function trashEntry(entry) {
		root.ask("trash", { paths: [entry.path] }, msg => {
			root.say(`Moved ${entry.name} to Trash · Ctrl+Z undoes`);
		});
	}

	function restoreEntry(entry) {
		root.ask("restore", { names: [entry.name] }, msg => {
			root.say(`Restored ${entry.name} to ${root.tilde(root.parentOf(msg.paths[0]))}`);
		});
	}

	function undo() {
		root.ask("undo", {}, msg => { root.say(`Undid the ${msg.undid}`); });
	}

	// A question with a Cancel: what it asks, the word on the chip that
	// answers yes, and what yes does.
	property var confirm: null

	function askDelete(entry) {
		root.confirm = {
			title: `Delete ${entry.name} forever?`,
			body: "It will not go to the Trash, and there is no undo.",
			verb: "Delete",
			run: () => root.ask("delete", { paths: [entry.path] }, msg => root.say(`Deleted ${entry.name}`))
		};
	}

	function askEmpty() {
		const n = root.entries.length;
		root.confirm = {
			title: "Empty the Trash?",
			body: (n === 1 ? "1 item" : n + " items") + " will be deleted forever. There is no undo.",
			verb: "Empty Trash",
			run: () => root.ask("empty", {}, msg => root.say("The Trash is empty"))
		};
	}

	function runConfirm() {
		const what = root.confirm;
		root.confirm = null;
		if (what)
			what.run();
	}

	// The actions on a thing, or on the folder when nothing is under the
	// pointer. One list for Tab and for the right button, drawn where it
	// was asked for.
	property var menu: null

	function actionsFor(entry) {
		const out = [];
		if (entry === null) {
			if (!root.inTrash)
				out.push({ label: "New folder", run: () => root.newFolder() });
			return out;
		}
		if (root.inTrash) {
			out.push({ label: "Restore", run: () => root.restoreEntry(entry) });
			out.push({ label: "Delete forever…", run: () => root.askDelete(entry) });
			return out;
		}
		out.push({ label: "Open", run: () => root.openEntry(entry) });
		out.push({ label: "Rename", run: () => root.startRename(entry) });
		out.push({ label: "Copy path", run: () => {
			Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", entry.path]);
			root.say(`Copied ${root.tilde(entry.path)}`);
		} });
		out.push({ label: "New folder", run: () => root.newFolder() });
		out.push({ label: "Move to Trash", run: () => root.trashEntry(entry) });
		out.push({ label: "Delete forever…", run: () => root.askDelete(entry) });
		return out;
	}

	readonly property int menuWidth: 200
	readonly property int menuRowHeight: 32
	readonly property int menuGap: 6

	// x and y in the body's coordinates: where the pointer was, or where the
	// menu should start. `anchor` is the row or tile it belongs to, as
	// { top, bottom } in the same coordinates: the menu hangs below it with
	// a gap, or sits above it when the bottom of the window is too close.
	// Without an anchor it opens at the point and flips up or left to fit.
	function openMenu(entry, x, y, anchor) {
		if (entry !== null)
			root.picked = entry.path;
		const items = root.actionsFor(entry);
		if (items.length === 0)
			return;

		const pad = 8;
		const height = items.length * root.menuRowHeight + 12;
		let mx = x;
		let my = y;
		if (anchor) {
			my = anchor.bottom + root.menuGap;
			if (my + height > body.height - pad)
				my = anchor.top - root.menuGap - height;
		} else if (my + height > body.height - pad) {
			my = y - height;
		}
		if (mx + root.menuWidth > body.width - pad)
			mx = anchor ? body.width - pad - root.menuWidth : x - root.menuWidth;
		mx = Math.max(pad, mx);
		my = Math.max(pad, my);

		root.menu = { entry: entry, items: items, x: mx, y: my, index: 0 };
	}

	// The highlighted row or tile, as the menu's anchor.
	function currentAnchor() {
		if (root.current < 0)
			return null;
		const view = root.grid ? gridView : listView;
		const item = view.itemAtIndex(root.current);
		if (!item)
			return null;
		const at = item.mapToItem(body, 0, 0);
		return { left: at.x + (root.grid ? 8 : 54), top: at.y, bottom: at.y + item.height };
	}

	function moveMenu(delta) {
		const m = root.menu;
		root.menu = Object.assign({}, m, { index: (m.index + delta + m.items.length) % m.items.length });
	}

	function runMenu() {
		const m = root.menu;
		root.menu = null;
		if (m)
			m.items[m.index].run();
	}

	// Tab: the menu beside the highlighted thing, or beside the list.
	function toggleMenu() {
		if (root.menu !== null) {
			root.menu = null;
			return;
		}
		const anchor = root.currentAnchor();
		if (anchor)
			root.openMenu(root.currentEntry, anchor.left, 0, anchor);
		else
			root.openMenu(null, content.x + 40, content.y + 40, null);
	}

	// Enter: open a thing, or put it back where it came from.
	function activate() {
		if (root.currentEntry === null)
			return;
		if (root.inTrash)
			root.restoreEntry(root.currentEntry);
		else
			root.openEntry(root.currentEntry);
	}

	// Where each thing in the Trash came from, by name, from the worker.
	property var trashInfo: ({})

	function refreshTrash() {
		if (!root.inTrash)
			return;
		root.ask("trashlist", {}, msg => {
			const map = {};
			for (const item of msg.items)
				map[item.name] = item;
			root.trashInfo = map;
		});
	}

	function show(where) {
		if (where && where !== "")
			root.go(where);
		root.open = true;
	}

	function close() {
		root.open = false;
	}

	function go(where) {
		if (where === root.path)
			return;
		root.behind = root.behind.concat([root.path]);
		root.ahead = [];
		root.land(where);
	}

	function goBack() {
		if (root.behind.length === 0)
			return;
		root.ahead = [root.path].concat(root.ahead);
		const where = root.behind[root.behind.length - 1];
		root.behind = root.behind.slice(0, -1);
		root.land(where);
	}

	function goForward() {
		if (root.ahead.length === 0)
			return;
		root.behind = root.behind.concat([root.path]);
		const where = root.ahead[0];
		root.ahead = root.ahead.slice(1);
		root.land(where);
	}

	function up() {
		if (root.path !== "/")
			root.go(root.parentOf(root.path));
	}

	function land(where) {
		root.renaming = "";
		root.menu = null;
		const trashOrder = root.sortBy === "origin" || root.sortBy === "deleted";
		if ((where === root.trashPath) !== trashOrder && root.sortBy !== "name") {
			root.sortBy = "name";
			root.sortDescending = false;
		}
		root.path = where;
		root.picked = "";
		searchField.clear();
	}

	function parentOf(path) {
		const cut = path.lastIndexOf("/");
		return cut <= 0 ? "/" : path.slice(0, cut);
	}

	function baseName(path) {
		return path === "/" ? "/" : path.slice(path.lastIndexOf("/") + 1);
	}

	// ~ for the home directory, as the design writes it.
	function tilde(path) {
		return path === root.home || path.startsWith(root.home + "/")
			? "~" + path.slice(root.home.length) : path;
	}

	function openEntry(entry) {
		if (entry === null)
			return;
		if (entry.folder)
			root.go(entry.path);
		else
			Quickshell.execDetached(["xdg-open", entry.path]);
	}

	// --- places ---------------------------------------------------------

	readonly property var candidates: [
		{ name: "Home", kind: "home", path: root.home },
		{ name: "Documents", kind: "folder", path: root.home + "/Documents" },
		{ name: "Downloads", kind: "downloads", path: root.home + "/Downloads" },
		{ name: "Pictures", kind: "pictures", path: root.home + "/Pictures" },
		{ name: "Trash", kind: "trash", path: root.trashPath }
	]

	// Only the folders that exist. A Pictures entry that opens an error is
	// worse than none.
	property var places: []

	Process {
		id: placesProbe

		command: ["bash", "-c", 'for d in "$@"; do [ -d "$d" ] && printf "%s\\n" "$d"; done; true', "sh"]
			.concat(root.candidates.map(place => place.path))

		stdout: StdioCollector {
			onStreamFinished: {
				const found = text.split("\n");
				root.places = root.candidates.filter(place =>
					place.name === "Trash" || found.includes(place.path));
			}
		}
	}

	onOpenChanged: {
		if (root.open) {
			placesProbe.running = true;
			worker.running = true;
		} else {
			worker.running = false;
			root.confirm = null;
			root.menu = null;
			root.renaming = "";
		}
	}

	// --- the folder on screen ------------------------------------------

	FolderListModel {
		id: folder

		folder: "file://" + root.path
		showDirsFirst: true
		showDotAndDotDot: false
		showHidden: root.showHidden
		sortField: FolderListModel.Name
		sortCaseSensitive: false
		nameFilters: ["*"]
	}

	// The model, read into plain objects: the search has to cover folders
	// too, which the model's own name filter does not, and the arrow keys
	// want an array to walk.
	property var entries: []

	// Which column orders the list, and which way. Folders stay above
	// files whatever the order, as the model draws them.
	// "name" | "modified" | "size" | "origin" | "deleted"
	property string sortBy: "name"
	property bool sortDescending: false

	// A click on the column already in charge turns it round; on another,
	// it takes over, upward.
	function sortOn(column) {
		if (root.sortBy === column) {
			root.sortDescending = !root.sortDescending;
		} else {
			root.sortBy = column;
			root.sortDescending = false;
		}
		root.entries = root.sorted(root.entries);
	}

	function sorted(list) {
		const by = root.sortBy;
		const sign = root.sortDescending ? -1 : 1;
		const info = name => root.trashInfo[name] ?? {};
		const key = entry => by === "modified" ? new Date(entry.modified).getTime()
			: by === "size" ? (entry.folder ? (root.counts[entry.name] ?? 0) : entry.size)
			: by === "origin" ? (info(entry.name).origin ?? "").toLowerCase()
			: by === "deleted" ? (info(entry.name).deleted ?? "")
			: entry.name.toLowerCase();
		return list.slice().sort((a, b) => {
			if (a.folder !== b.folder)
				return a.folder ? -1 : 1;
			const ka = key(a), kb = key(b);
			const order = ka < kb ? -1 : ka > kb ? 1 : a.name.localeCompare(b.name);
			return order * sign;
		});
	}

	// The list follows what it is sorted on, when that arrives later: item
	// counts for a size order, origins and dates for the Trash's.
	onCountsChanged: if (root.sortBy === "size") root.entries = root.sorted(root.entries)
	onTrashInfoChanged: if (root.sortBy === "origin" || root.sortBy === "deleted") root.entries = root.sorted(root.entries)

	function rebuild() {
		const term = root.filter.toLowerCase();
		const out = [];
		for (let i = 0; i < folder.count; i++) {
			const name = folder.get(i, "fileName");
			if (term !== "" && !name.toLowerCase().includes(term))
				continue;
			out.push({
				name: name,
				path: folder.get(i, "filePath"),
				folder: folder.get(i, "fileIsDir"),
				size: folder.get(i, "fileSize"),
				modified: folder.get(i, "fileModified"),
				suffix: (folder.get(i, "fileSuffix") || "").toLowerCase()
			});
		}
		root.entries = root.sorted(out);
		if (root.picked !== "" && !out.some(entry => entry.path === root.picked))
			root.picked = "";

		const made = out.find(entry => entry.path === root.pendingRename);
		if (made !== undefined) {
			root.pendingRename = "";
			root.startRename(made);
		}
		if (root.inTrash)
			root.refreshTrash();
	}

	// The model announces changes as rows coming and going; one rebuild per
	// batch is enough, so they are coalesced through callLater.
	Connections {
		target: folder

		function onCountChanged() { Qt.callLater(root.rebuild); }
		function onDataChanged() { Qt.callLater(root.rebuild); }
		function onModelReset() { Qt.callLater(root.rebuild); }
		function onStatusChanged() { if (folder.status === FolderListModel.Ready) Qt.callLater(root.rebuild); }
	}

	onFilterChanged: root.rebuild()

	readonly property int current: root.entries.findIndex(entry => entry.path === root.picked)
	readonly property var currentEntry: root.current >= 0 ? root.entries[root.current] : null

	function move(delta) {
		if (root.entries.length === 0)
			return;
		const next = root.current < 0
			? (delta > 0 ? 0 : root.entries.length - 1)
			: Math.max(0, Math.min(root.entries.length - 1, root.current + delta));
		root.picked = root.entries[next].path;
	}

	// How many things each folder holds, for the design's "14 items". One
	// process per folder shown, not one per row.
	property var counts: ({})

	Process {
		id: counter

		command: ["bash", "-c",
			'cd "$1" 2>/dev/null || exit 0; for d in */ .*/; do [ -d "$d" ] || continue; '
			+ 'case "$d" in ./|../) continue;; esac; '
			+ 'printf "%s\\t%s\\n" "$(ls -1A -- "$d" | wc -l)" "${d%/}"; done',
			"sh", root.path]

		stdout: StdioCollector {
			onStreamFinished: {
				const found = {};
				for (const line of text.split("\n")) {
					const tab = line.indexOf("\t");
					if (tab > 0)
						found[line.slice(tab + 1)] = parseInt(line.slice(0, tab));
				}
				root.counts = found;
			}
		}
	}

	onPathChanged: { root.counts = ({}); recount.restart(); }
	onEntriesChanged: recount.restart()

	Timer {
		id: recount

		interval: 200
		onTriggered: { counter.running = false; counter.running = true; }
	}

	// --- words for things --------------------------------------------------

	function when(date, withTime) {
		const now = new Date();
		const then = new Date(date);
		const day = d => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
		const days = Math.round((day(now) - day(then)) / 86400000);
		if (days === 0)
			return withTime ? "Today, " + Qt.formatTime(then, "h:mm") : "Today";
		if (days === 1)
			return "Yesterday";
		if (then.getFullYear() === now.getFullYear())
			return Qt.formatDate(then, "MMM d");
		return Qt.formatDate(then, "MMM d, yyyy");
	}

	function size(bytes) {
		if (bytes < 1024)
			return bytes + " B";
		if (bytes < 1024 * 1024)
			return Math.round(bytes / 1024) + " KB";
		if (bytes < 1024 * 1024 * 1024)
			return (bytes / 1024 / 1024).toFixed(1) + " MB";
		return (bytes / 1024 / 1024 / 1024).toFixed(1) + " GB";
	}

	function detail(entry) {
		if (!entry.folder)
			return root.size(entry.size);
		const n = root.counts[entry.name];
		return n === undefined ? "" : n === 1 ? "1 item" : n + " items";
	}

	readonly property var imageTypes: ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg"]

	// The path as chips: Home, then each folder below it. Outside the home
	// directory the first chip is the root. Long paths keep their last four
	// and an ellipsis for the rest.
	readonly property var crumbs: {
		const out = [];
		let rest = root.path;
		if (rest === root.home || rest.startsWith(root.home + "/")) {
			out.push({ name: "Home", path: root.home });
			rest = rest.slice(root.home.length);
		} else {
			out.push({ name: "/", path: "/" });
		}
		let sofar = out[0].path;
		for (const part of rest.split("/").filter(p => p !== "")) {
			sofar = sofar === "/" ? "/" + part : sofar + "/" + part;
			out.push({ name: part, path: sofar });
		}
		return out;
	}

	// A small dark pane with a sentence in it, for the breadcrumb's "…".
	// { text, x, y } in the body's coordinates, or null.
	property var tip: null

	readonly property string placeName: {
		const place = root.places.find(p => p.path === root.path);
		return place ? place.name : root.baseName(root.path);
	}

	readonly property string status: {
		const n = root.entries.length;
		let text = n === 1 ? "1 item" : n + " items";
		if (root.currentEntry !== null) {
			const entry = root.currentEntry;
			const what = entry.folder ? root.detail(entry) : root.size(entry.size);
			text += " · " + entry.name + (what ? ", " + what : "");
		}
		return text;
	}

	IpcHandler {
		target: "files"

		function open(path: string): void {
			root.show(path);
		}

		function toggle(): void {
			if (root.open)
				root.close();
			else
				root.show("");
		}

		function close(): void {
			root.close();
		}

		// "list" or "grid", for scripts and for testing.
		function view(mode: string): void {
			root.grid = mode === "grid";
		}

		// Highlight a thing in the folder on screen, as a click would.
		function pick(path: string): void {
			root.picked = path;
		}

		// The path Tab takes: the actions for the highlighted thing.
		function actions(): void {
			root.toggleMenu();
		}

		// Order the list by a column: name, modified, size, origin, deleted.
		function sort(column: string): void {
			root.sortOn(column);
		}

		// The path F2 takes on the highlighted thing.
		function rename(): void {
			if (root.currentEntry !== null && !root.inTrash)
				root.startRename(root.currentEntry);
		}
	}

	// --- the window ---------------------------------------------------------

	FloatingWindow {
		id: window

		visible: root.open
		title: "Files"
		color: "transparent"

		implicitWidth: Theme.filesWidth
		implicitHeight: Theme.filesHeight
		minimumSize: Qt.size(640, 400)

		// Closed by the compositor - SUPER+C - rather than by the disc.
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

				// Typing anywhere searches the folder, as in the design's
				// search track. The keys that move and open stay here, and
				// still arrive while the track has focus because a
				// single-line field lets Up, Down and Escape through.
				Keys.onPressed: event => {
					const alt = event.modifiers & Qt.AltModifier;
					const ctrl = event.modifiers & Qt.ControlModifier;
					const shift = event.modifiers & Qt.ShiftModifier;
					const columns = root.grid ? gridView.columnCount : 1;

					// A question on screen takes every key: Escape declines,
					// Return affirms, the rest wait.
					if (root.confirm !== null) {
						if (event.key === Qt.Key_Escape)
							root.confirm = null;
						else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
							root.runConfirm();
						event.accepted = true;
						return;
					}

					// A menu open takes the arrows, Return and Escape; any
					// other key closes it and is then read as usual.
					if (root.menu !== null) {
						if (event.key === Qt.Key_Down) {
							root.moveMenu(1);
						} else if (event.key === Qt.Key_Up) {
							root.moveMenu(-1);
						} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
							root.runMenu();
						} else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab) {
							root.menu = null;
						} else {
							root.menu = null;
							return;
						}
						event.accepted = true;
						return;
					}

					// The rename editor owns the keyboard; what it lets
					// through is not for the list.
					if (root.renaming !== "") {
						event.accepted = true;
						return;
					}

					if (event.key === Qt.Key_Tab) {
						root.toggleMenu();
						event.accepted = true;
						return;
					}

					if (event.key === Qt.Key_Escape) {
						if (root.filter !== "" || searchField.activeFocus) {
							searchField.clear();
							body.forceActiveFocus();
						} else {
							root.close();
						}
					} else if (event.key === Qt.Key_Down) {
						root.move(columns);
					} else if (event.key === Qt.Key_Up) {
						root.move(-columns);
					} else if (event.key === Qt.Key_Right && !searchField.activeFocus && !alt) {
						root.move(1);
					} else if (event.key === Qt.Key_Left && !searchField.activeFocus && !alt) {
						root.move(-1);
					} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						root.activate();
					} else if (event.key === Qt.Key_Delete) {
						if (root.currentEntry !== null) {
							if (root.inTrash || shift)
								root.askDelete(root.currentEntry);
							else
								root.trashEntry(root.currentEntry);
						}
					} else if (event.key === Qt.Key_F2) {
						if (root.currentEntry !== null && !root.inTrash)
							root.startRename(root.currentEntry);
					} else if (ctrl && shift && event.key === Qt.Key_N) {
						if (!root.inTrash)
							root.newFolder();
					} else if (ctrl && event.key === Qt.Key_Z) {
						root.undo();
					} else if (event.key === Qt.Key_Backspace && !searchField.activeFocus) {
						root.up();
					} else if (alt && event.key === Qt.Key_Up) {
						root.up();
					} else if (alt && event.key === Qt.Key_Left) {
						root.goBack();
					} else if (alt && event.key === Qt.Key_Right) {
						root.goForward();
					} else if (ctrl && event.key === Qt.Key_H) {
						root.showHidden = !root.showHidden;
					} else if (ctrl && event.key === Qt.Key_F) {
						searchField.focusInput();
					} else if (!ctrl && !alt && event.text.length === 1 && event.text >= " " && !searchField.activeFocus) {
						searchField.focusInput();
						searchField.text += event.text;
					} else {
						return;
					}
					event.accepted = true;
				}

				// Header: back and forward, where you are, then the search,
				// the view and the way out.
				Item {
					id: header

					anchors {
						left: parent.left
						right: parent.right
						top: parent.top
					}

					height: Theme.filesHeaderHeight

					Rectangle {
						anchors.bottom: parent.bottom
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Row {
						id: navigation

						anchors {
							left: parent.left
							leftMargin: 14
							verticalCenter: parent.verticalCenter
						}

						spacing: 10

						// A fixed model: one built from the history would be
						// rebuilt, discs and all, on every step.
						Repeater {
							model: ["back", "forward"]

							Lens {
								id: navDisc

								required property string modelData

								readonly property bool can: modelData === "back"
									? root.behind.length > 0 : root.ahead.length > 0

								width: 34
								height: 34
								sheen: false
								opacity: can ? 1 : 0.5

								FileGlyph {
									anchors.centerIn: parent
									kind: navDisc.modelData
								}

								MouseArea {
									anchors.fill: parent
									enabled: navDisc.can
									cursorShape: Qt.PointingHandCursor
									onClicked: navDisc.modelData === "back" ? root.goBack() : root.goForward()
								}
							}
						}
					}

					// The path as chips, as many of the last ones as fit. What
					// does not fit folds into a "…" chip on the left, which
					// says the whole path when pointed at and goes up to the
					// first folder it hides when clicked.
					Item {
						id: crumbs

						anchors {
							left: navigation.right
							leftMargin: 16
							right: tools.left
							rightMargin: 12
							verticalCenter: parent.verticalCenter
						}

						height: crumbRow.height

						FontMetrics {
							id: crumbMetrics

							font.pixelSize: Theme.fontTitle
							font.weight: Font.Bold
						}

						// Widths as the chips will draw them: label plus 24
						// of padding, and 6 + separator + 6 between chips.
						function chipWidth(name) { return crumbMetrics.advanceWidth(name) + 24; }
						readonly property real separator: crumbMetrics.advanceWidth("›") + 12

						// From the end backwards, until the next chip would
						// not fit beside the "…". The last chip always shows,
						// elided if it must.
						readonly property var shown: {
							const all = root.crumbs;
							const room = width;
							const ellipsis = crumbs.chipWidth("…") + crumbs.separator;
							let used = 0;
							let first = all.length;
							for (let i = all.length - 1; i >= 0; i--) {
								const w = crumbs.chipWidth(all[i].name) + (i < all.length - 1 ? crumbs.separator : 0);
								const reserve = i > 0 ? ellipsis : 0;
								if (i < all.length - 1 && used + w + reserve > room)
									break;
								used += w;
								first = i;
							}
							const out = all.slice(first);
							if (first > 0)
								out.unshift({ name: "…", path: all[first - 1].path, folded: true });
							return out;
						}

						Row {
							id: crumbRow

							spacing: 6

							Repeater {
								model: crumbs.shown

								Row {
									id: crumb

									required property var modelData
									required property int index

									readonly property bool last: index === crumbs.shown.length - 1
									readonly property bool folded: modelData.folded === true

									spacing: 6

									Text {
										anchors.verticalCenter: parent.verticalCenter
										visible: crumb.index > 0
										text: "›"
										font.pixelSize: Theme.fontTitle
										font.bold: true
										opacity: 0.5
										color: Theme.glassTextPrimary
									}

									Rectangle {
										id: crumbChip

										// The last chip takes what is left rather than
										// spilling under the search.
										width: crumb.last
											? Math.max(40, Math.min(crumbLabel.implicitWidth + 24, crumbs.width - (crumb.x)))
											: crumbLabel.implicitWidth + 24
										height: crumbLabel.implicitHeight + 12
										radius: Theme.radiusPill
										color: crumb.last ? Theme.glassChipActive
											: crumbMouse.containsMouse ? Theme.glassControlHover : Theme.glassChip
										border.width: 1
										border.color: crumb.last ? Theme.glassTrackBorderFocus : Theme.glassControlBorder

										Text {
											id: crumbLabel

											anchors.centerIn: parent
											width: Math.min(implicitWidth, parent.width - 16)
											elide: Text.ElideRight
											text: crumb.modelData.name
											font.pixelSize: Theme.fontTitle
											font.weight: crumb.last ? Font.Bold : Font.DemiBold
											color: Theme.glassTextPrimary
										}

										MouseArea {
											id: crumbMouse

											anchors.fill: parent
											hoverEnabled: true
											cursorShape: Qt.PointingHandCursor
											onClicked: root.go(crumb.modelData.path)

											// The folded chip, and a last chip cut short,
											// say the whole path when pointed at.
											onEntered: {
												if (crumb.folded || (crumb.last && crumbLabel.truncated)) {
													const at = crumbChip.mapToItem(body, 0, crumbChip.height + 6);
													root.tip = { text: root.tilde(root.path), x: at.x, y: at.y };
												}
											}
											onExited: root.tip = null
										}
									}
								}
							}
						}
					}

					Row {
						id: tools

						anchors {
							right: parent.right
							rightMargin: 14
							verticalCenter: parent.verticalCenter
						}

						spacing: 10

						GlassField {
							id: searchField

							anchors.verticalCenter: parent.verticalCenter
							width: 240
							height: 38
							fontSize: Theme.fontTitle
							placeholder: "Search " + root.placeName

							leading: Lens {
								width: 26
								height: 26
								sheen: false

								FileGlyph {
									anchors.centerIn: parent
									kind: "search"
								}
							}

							onAccepted: {
								root.activate();
								body.forceActiveFocus();
							}
							onTabbed: root.toggleMenu()
						}

						// List or grid: one segmented chip, the chosen half
						// brighter.
						Rectangle {
							anchors.verticalCenter: parent.verticalCenter
							width: 32 * 2 + 2 + 6
							height: 28 + 6
							radius: 13
							color: Theme.glassChip
							border.width: 1
							border.color: Theme.glassControlBorder

							Row {
								anchors.centerIn: parent
								spacing: 2

								Repeater {
									model: [false, true]

									Rectangle {
										required property bool modelData

										readonly property bool chosen: root.grid === modelData

										width: 32
										height: 28
										radius: 10
										color: chosen ? Theme.glassChipActive
											: viewMouse.containsMouse ? Theme.glassControlHover : "transparent"
										border.width: chosen ? 1 : 0
										border.color: Theme.glassTrackBorderFocus

										// Three bars for the list.
										Column {
											anchors.centerIn: parent
											visible: !parent.modelData
											spacing: 3

											Repeater {
												model: 3

												Rectangle {
													width: 14
													height: 2
													radius: 1
													color: Theme.glassTextPrimary
												}
											}
										}

										// Four squares for the grid.
										Grid {
											anchors.centerIn: parent
											visible: parent.modelData
											columns: 2
											spacing: 3

											Repeater {
												model: 4

												Rectangle {
													width: 5
													height: 5
													radius: 1.5
													color: "transparent"
													border.width: 1.5
													border.color: Theme.glassTextPrimary
												}
											}
										}

										MouseArea {
											id: viewMouse

											anchors.fill: parent
											hoverEnabled: true
											cursorShape: Qt.PointingHandCursor
											onClicked: root.grid = parent.modelData
										}
									}
								}
							}
						}

						DiscButton {
							anchors.verticalCenter: parent.verticalCenter
							width: 30
							height: 30
							onClicked: root.close()
						}
					}
				}

				// Places.
				Rectangle {
					id: sidebar

					anchors {
						left: parent.left
						top: header.bottom
						bottom: footer.top
					}

					width: Theme.filesSidebarWidth
					color: Qt.rgba(1, 1, 1, 0.04)

					Rectangle {
						anchors.right: parent.right
						width: 1
						height: parent.height
						color: Theme.glassControlBorder
					}

					Column {
						anchors {
							left: parent.left
							right: parent.right
							top: parent.top
							leftMargin: 10
							rightMargin: 10
							topMargin: 6
						}

						spacing: 2

						Text {
							leftPadding: 10
							topPadding: 10
							bottomPadding: 4
							text: "PLACES"
							font.pixelSize: Theme.fontCaption
							font.bold: true
							font.letterSpacing: 0.66
							opacity: 0.6
							color: Theme.glassTextPrimary
						}

						Repeater {
							model: root.places

							Rectangle {
								id: place

								required property var modelData

								readonly property bool here: root.path === modelData.path

								width: parent.width
								height: 38
								radius: Theme.radiusPill
								color: here ? Theme.glassChipActive
									: placeMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: here ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								Row {
									anchors {
										left: parent.left
										right: parent.right
										leftMargin: 8
										rightMargin: 8
										verticalCenter: parent.verticalCenter
									}

									spacing: 10

									Lens {
										anchors.verticalCenter: parent.verticalCenter
										width: 26
										height: 26
										sheen: false

										FileGlyph {
											anchors.centerIn: parent
											kind: place.modelData.kind
										}
									}

									Text {
										anchors.verticalCenter: parent.verticalCenter
										text: place.modelData.name
										font.pixelSize: Theme.fontTitle
										font.weight: place.here ? Font.Bold : Font.DemiBold
										color: Theme.glassTextPrimary
									}
								}

								MouseArea {
									id: placeMouse

									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: root.go(place.modelData.path)
								}
							}
						}
					}
				}

				// What is in the folder, as rows or as tiles.
				Item {
					id: content

					anchors {
						left: sidebar.right
						right: parent.right
						top: header.bottom
						bottom: footer.top
						leftMargin: 12
						rightMargin: 12
						topMargin: 10
						bottomMargin: 10
					}

					// Steps back while a menu is up, so the menu is what is read.
					opacity: root.menu !== null ? Theme.menuBackdropOpacity : 1

					Behavior on opacity {
						NumberAnimation { duration: 120 }
					}

					// In the Trash: what the Trash is, and the way to empty it.
					Rectangle {
						id: banner

						width: parent.width
						height: visible ? 44 : 0
						visible: root.inTrash && root.entries.length > 0
						radius: Theme.radiusRow
						color: Qt.rgba(1, 1, 1, 0.08)
						border.width: 1
						border.color: Qt.rgba(1, 1, 1, 0.16)

						Text {
							anchors {
								left: parent.left
								leftMargin: 14
								verticalCenter: parent.verticalCenter
							}

							text: "Things stay in the Trash until it is emptied."
							font.pixelSize: Theme.fontBody
							font.weight: Font.DemiBold
							opacity: 0.85
							color: Theme.glassTextPrimary
						}

						DialogButton {
							anchors {
								right: parent.right
								rightMargin: 8
								verticalCenter: parent.verticalCenter
							}

							text: "Empty Trash"
							variant: "destructive"
							onClicked: root.askEmpty()
						}
					}

					// The list's column headings. Two layouts: a folder shows
					// when and how big, the Trash shows where from and when.
					Item {
						id: listHeader

						anchors.top: banner.bottom
						anchors.topMargin: banner.visible ? 4 : 0
						width: parent.width
						height: 30
						visible: !root.grid

						readonly property int gap: 12

						// The design's widths at 1040, shrinking with the window
						// so the name always keeps the larger share. Tiled
						// beside an editor the window is two thirds of that.
						readonly property real sizeWidth: Math.min(90, Math.max(60, width * 0.14))
						readonly property real dateWidth: Math.min(160, Math.max(90, width * 0.24))
						readonly property real originWidth: Math.min(200, Math.max(120, width * 0.30))
						readonly property real deletedWidth: Math.min(110, Math.max(72, width * 0.16))
						readonly property int chipWidth: 84

						// Where each column starts, from the right edge in.
						readonly property real lastX: width - 12 - (root.inTrash ? chipWidth : sizeWidth)
						readonly property real midX: root.inTrash
							? lastX - gap - deletedWidth : lastX - gap - dateWidth
						readonly property real firstX: root.inTrash ? midX - gap - originWidth : midX

						// Each heading orders the list when clicked, and the one
						// in charge carries the arrow.
						Repeater {
							model: root.inTrash
								? [["NAME", 12, "name"], ["ORIGINAL LOCATION", listHeader.firstX, "origin"], ["DELETED", listHeader.midX, "deleted"]]
								: [["NAME", 12, "name"], ["MODIFIED", listHeader.midX, "modified"], ["SIZE", listHeader.lastX, "size"]]

							Text {
								id: heading

								required property var modelData

								readonly property bool inCharge: root.sortBy === modelData[2]

								x: modelData[1]
								anchors.verticalCenter: parent.verticalCenter
								text: modelData[0] + (inCharge ? (root.sortDescending ? " ↓" : " ↑") : "")
								font.pixelSize: Theme.fontCaption
								font.bold: true
								font.letterSpacing: 0.66
								opacity: inCharge || headingMouse.containsMouse ? 0.9 : 0.6
								color: Theme.glassTextPrimary

								MouseArea {
									id: headingMouse

									anchors.fill: parent
									anchors.margins: -6
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: root.sortOn(heading.modelData[2])
								}
							}
						}
					}

					ListView {
						id: listView

						anchors {
							left: parent.left
							right: parent.right
							top: listHeader.bottom
							bottom: parent.bottom
							topMargin: 4
						}

						visible: !root.grid
						clip: true
						model: root.grid ? [] : root.entries
						spacing: 4
						boundsBehavior: Flickable.StopAtBounds
						currentIndex: root.current
						highlightFollowsCurrentItem: false
						onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

						delegate: Item {
							id: row

							required property var modelData

							readonly property bool selected: root.picked === modelData.path

							width: listView.width
							height: Theme.launcherRowHeight

							Rectangle {
								anchors.fill: parent
								radius: Theme.radiusRow
								color: row.selected ? Theme.glassChipActive
									: rowMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: row.selected ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								Behavior on color {
									ColorAnimation { duration: 120 }
								}
							}

							Lens {
								id: rowDisc

								x: 12
								anchors.verticalCenter: parent.verticalCenter
								width: 30
								height: 30
								sheen: false

								FileGlyph {
									anchors.centerIn: parent
									kind: row.modelData.folder ? "folder" : "file"
								}
							}

							readonly property bool editing: root.renaming === modelData.path
							readonly property var trashed: root.trashInfo[modelData.name]

							Text {
								anchors {
									left: rowDisc.right
									leftMargin: 12
									right: parent.left
									rightMargin: -(listHeader.firstX - listHeader.gap)
									verticalCenter: parent.verticalCenter
								}

								visible: !row.editing
								elide: Text.ElideRight
								text: row.modelData.name
								font.pixelSize: Theme.fontLead
								font.weight: row.selected ? Font.Bold : Font.DemiBold
								color: Theme.glassTextPrimary
							}

							Loader {
								anchors {
									left: rowDisc.right
									leftMargin: 8
									right: parent.left
									rightMargin: -(listHeader.firstX - listHeader.gap)
									verticalCenter: parent.verticalCenter
								}

								active: row.editing
								sourceComponent: renameBox
							}

							// A folder's row: when it changed, how big it is.
							Text {
								x: listHeader.midX
								anchors.verticalCenter: parent.verticalCenter
								width: listHeader.dateWidth
								visible: !root.inTrash
								elide: Text.ElideRight
								text: root.when(row.modelData.modified, true)
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							Text {
								x: listHeader.lastX
								anchors.verticalCenter: parent.verticalCenter
								width: listHeader.sizeWidth
								visible: !root.inTrash
								elide: Text.ElideRight
								text: root.detail(row.modelData)
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							// The Trash's row: where from, when, and the way back.
							Text {
								x: listHeader.firstX
								anchors.verticalCenter: parent.verticalCenter
								width: listHeader.originWidth
								visible: root.inTrash
								elide: Text.ElideLeft
								text: row.trashed ? root.tilde(root.parentOf(row.trashed.origin)) : ""
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							Text {
								x: listHeader.midX
								anchors.verticalCenter: parent.verticalCenter
								width: listHeader.deletedWidth
								visible: root.inTrash
								elide: Text.ElideRight
								text: row.trashed && row.trashed.deleted ? root.when(row.trashed.deleted, false) : ""
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							Rectangle {
								anchors {
									right: parent.right
									rightMargin: 12
									verticalCenter: parent.verticalCenter
								}

								width: restoreLabel.implicitWidth + 24
								height: 24
								radius: Theme.radiusPill
								visible: root.inTrash && row.selected
								color: Theme.chipRestore
								border.width: 1
								border.color: Theme.chipRestoreBorder

								Text {
									id: restoreLabel

									anchors.centerIn: parent
									text: "Restore"
									font.pixelSize: Theme.fontBody
									font.bold: true
									color: Theme.glassTextPrimary
								}

								MouseArea {
									anchors.fill: parent
									cursorShape: Qt.PointingHandCursor
									onClicked: root.restoreEntry(row.modelData)
								}
							}

							MouseArea {
								id: rowMouse

								// Under the texts, so the Restore chip and the
								// editor get their clicks first.
								anchors.fill: parent
								z: -1
								hoverEnabled: true
								onClicked: root.picked = row.modelData.path
								onDoubleClicked: root.inTrash ? root.restoreEntry(row.modelData) : root.openEntry(row.modelData)
							}
						}
					}

					GridView {
						id: gridView

						anchors {
							left: parent.left
							right: parent.right
							top: banner.bottom
							bottom: parent.bottom
							topMargin: banner.visible ? 4 : 0
						}

						visible: root.grid
						clip: true
						model: root.grid ? root.entries : []
						boundsBehavior: Flickable.StopAtBounds

						// An id elsewhere in the file shadows a property of this name, and
						// the cell width silently became NaN: hence the longer name.
						readonly property int columnCount: Math.max(1, Math.floor(width / 150))

						cellWidth: width / columnCount
						cellHeight: 8 + 104 + 8 + 32 + 8

						currentIndex: root.current
						highlightFollowsCurrentItem: false
						onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)

						delegate: Item {
							id: cell

							required property var modelData

							readonly property bool selected: root.picked === modelData.path
							readonly property bool editing: root.renaming === modelData.path
							readonly property bool image: !modelData.folder && root.imageTypes.includes(modelData.suffix)

							width: gridView.cellWidth
							height: gridView.cellHeight

							Rectangle {
								id: tile

								anchors.fill: parent
								anchors.margins: 4
								radius: 18
								color: cell.editing ? Theme.glassControl
									: cell.selected ? Theme.glassChipActive
									: tileMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: cell.selected || cell.editing ? 1 : 0
								border.color: cell.editing ? Theme.glassEdge : Theme.glassTrackBorderFocus

								Behavior on color {
									ColorAnimation { duration: 120 }
								}

								// The picture, or a disc standing in for one.
								Rectangle {
									id: thumb

									anchors {
										left: parent.left
										right: parent.right
										top: parent.top
										margins: 8
									}

									height: 104
									radius: 12
									color: Qt.rgba(1, 1, 1, 0.06)
									border.width: 1
									border.color: cell.image ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.14)

									Lens {
										anchors.centerIn: parent
										width: 56
										height: 56
										sheen: false
										visible: !cell.image

										FileGlyph {
											anchors.centerIn: parent
											kind: cell.modelData.folder ? "folder" : "file"
											zoom: 1.5
										}
									}

									Image {
										id: picture

										anchors.fill: parent
										anchors.margins: 1
										visible: false
										asynchronous: true
										source: cell.image ? "file://" + cell.modelData.path : ""
										sourceSize: Qt.size(260, 260)
										fillMode: Image.PreserveAspectCrop
										smooth: true
									}

									Item {
										id: pictureMask

										anchors.fill: picture
										visible: false
										layer.enabled: true

										Rectangle {
											anchors.fill: parent
											radius: 11
										}
									}

									MultiEffect {
										anchors.fill: picture
										visible: cell.image && picture.status === Image.Ready
										source: picture
										maskEnabled: true
										maskSource: pictureMask
									}
								}

								Column {
									anchors {
										left: parent.left
										right: parent.right
										top: thumb.bottom
										margins: 8
									}

									spacing: 2

									Text {
										width: parent.width
										visible: !cell.editing
										horizontalAlignment: Text.AlignHCenter
										elide: Text.ElideRight
										text: cell.modelData.name
										font.pixelSize: Theme.fontBody
										font.weight: cell.selected ? Font.Bold : Font.DemiBold
										color: Theme.glassTextPrimary
									}

									// Snug to the name, as 10b draws it, up to the tile's width.
									Loader {
										anchors.horizontalCenter: parent.horizontalCenter
										width: Math.min(parent.width, item ? item.implicitWidth : parent.width)
										active: cell.editing
										sourceComponent: renameBox
										onLoaded: item.fontSize = Theme.fontBody
									}

									Text {
										width: parent.width
										horizontalAlignment: Text.AlignHCenter
										visible: cell.modelData.folder && text !== ""
										text: root.detail(cell.modelData)
										font.pixelSize: Theme.fontCaption
										font.weight: Font.DemiBold
										opacity: 0.6
										color: Theme.glassTextPrimary
									}
								}

								MouseArea {
									id: tileMouse

									anchors.fill: parent
									z: -1
									hoverEnabled: true
									onClicked: root.picked = cell.modelData.path
									onDoubleClicked: root.inTrash ? root.restoreEntry(cell.modelData) : root.openEntry(cell.modelData)
								}
							}
						}
					}

					// The right button, over rows, tiles and the space between:
					// a menu for what is under the pointer. Only that button
					// is taken, so clicks and double-clicks fall through.
					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.RightButton
						onPressed: mouse => {
							const view = root.grid ? gridView : listView;
							const inView = view.mapFromItem(content, mouse.x, mouse.y);
							let entry = null;
							if (inView.x >= 0 && inView.y >= 0 && inView.x < view.width && inView.y < view.height) {
								const index = view.indexAt(inView.x + view.contentX, inView.y + view.contentY);
								if (index >= 0)
									entry = root.entries[index];
							}
							const at = content.mapToItem(body, mouse.x, mouse.y);
							if (entry !== null) {
								root.picked = entry.path;
								root.openMenu(entry, at.x, 0, root.currentAnchor());
							} else {
								root.openMenu(null, at.x, at.y, null);
							}
						}
					}

					Text {
						anchors.centerIn: parent
						visible: root.entries.length === 0
						text: root.filter !== "" ? `Nothing here matches “${root.filter}”`
							: root.path === root.trashPath ? "Trash is empty"
							: "This folder is empty"
						font.pixelSize: Theme.fontTitle
						font.weight: Font.DemiBold
						opacity: 0.6
						color: Theme.glassTextPrimary
					}
				}

				// Footer: what is here on the left, the keys on the right.
				Item {
					id: footer

					anchors {
						left: parent.left
						right: parent.right
						bottom: parent.bottom
					}

					height: Theme.filesFooterHeight

					Rectangle {
						anchors.top: parent.top
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Text {
						anchors {
							left: parent.left
							leftMargin: 18
							right: keys.left
							rightMargin: 18
							verticalCenter: parent.verticalCenter
						}

						elide: Text.ElideRight
						text: root.notice !== "" ? root.notice : root.status
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						opacity: 0.75
						color: Theme.glassTextPrimary
					}

					Row {
						id: keys

						anchors {
							right: parent.right
							rightMargin: 18
							verticalCenter: parent.verticalCenter
						}

						spacing: 14
						opacity: 0.85

						Repeater {
							model: {
								if (root.confirm !== null)
									return [["↵", root.confirm.verb], ["Esc", "Cancel"]];
								if (root.renaming !== "")
									return [["↵", "Rename"], ["Esc", "Cancel"]];
								if (root.menu !== null)
									return [["↑↓", "Move"], ["↵", "Do"], ["Esc", "Close"]];
								const rows = [[root.grid ? "←↑↓→" : "↑↓", "Move"]];
								if (root.currentEntry !== null) {
									rows.push(["↵", root.inTrash ? "Restore" : "Open"]);
									if (!root.inTrash)
										rows.push(["F2", "Rename"]);
									rows.push(["Del", root.inTrash ? "Delete" : "Trash"]);
								}
								rows.push(["Tab", "Actions"]);
								rows.push(["Esc", root.filter !== "" ? "Clear" : "Close"]);
								return rows;
							}

							Row {
								required property var modelData

								spacing: 6

								KeyCap {
									anchors.verticalCenter: parent.verticalCenter
									text: parent.modelData[0]
								}

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

			// The breadcrumb's whole path, when the chips could not say it.
			Rectangle {
				x: Math.max(8, Math.min(body.width - width - 8, root.tip?.x ?? 0))
				y: root.tip?.y ?? 0
				width: tipLabel.implicitWidth + 20
				height: tipLabel.implicitHeight + 12
				radius: 8
				visible: opacity > 0.01
				opacity: root.tip !== null ? 1 : 0
				color: Theme.menuSurface
				border.width: 1
				border.color: Theme.glassEdge

				Behavior on opacity {
					NumberAnimation { duration: 120 }
				}

				Text {
					id: tipLabel

					anchors.centerIn: parent
					text: root.tip?.text ?? ""
					font.pixelSize: Theme.fontBody
					font.weight: Font.DemiBold
					color: Theme.glassTextPrimary
				}
			}

			// Click-away for the menu: anything pressed outside it closes it,
			// and the press goes no further.
			MouseArea {
				anchors.fill: parent
				visible: root.menu !== null
				acceptedButtons: Qt.AllButtons
				onPressed: root.menu = null
			}

			// The menu: a small pane of glass at the pointer, rows for the
			// actions, the keyboard's row brighter.
			GlassPanel {
				id: menuPane

				readonly property var model: root.menu?.items ?? []

				x: root.menu?.x ?? 0
				y: root.menu?.y ?? 0
				width: root.menuWidth
				height: menuColumn.implicitHeight + 12
				radius: 14
				shadowLayers: 8
				color: Theme.menuSurface
				visible: opacity > 0.01
				opacity: root.menu !== null ? 1 : 0
				scale: root.menu !== null ? 1 : 0.96
				transformOrigin: Item.TopLeft

				Behavior on opacity {
					NumberAnimation { duration: 120 }
				}
				Behavior on scale {
					NumberAnimation { duration: 120 }
				}

				Column {
					id: menuColumn

					anchors {
						left: parent.left
						right: parent.right
						top: parent.top
						margins: 6
					}

					Repeater {
						model: menuPane.model

						Rectangle {
							id: menuRow

							required property var modelData
							required property int index

							readonly property bool current: root.menu !== null && root.menu.index === index

							width: parent.width
							height: root.menuRowHeight
							radius: 10
							color: current ? Theme.glassChipActive
								: menuMouse.containsMouse ? Theme.glassControlHover : "transparent"

							Text {
								anchors {
									left: parent.left
									leftMargin: 12
									verticalCenter: parent.verticalCenter
								}

								text: menuRow.modelData.label
								font.pixelSize: Theme.fontTitle
								font.weight: menuRow.current ? Font.Bold : Font.DemiBold
								color: Theme.glassTextPrimary
							}

							MouseArea {
								id: menuMouse

								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onEntered: if (root.menu !== null) root.menu = Object.assign({}, root.menu, { index: menuRow.index })
								onClicked: { root.menu = Object.assign({}, root.menu, { index: menuRow.index }); root.runMenu(); }
							}
						}
					}
				}
			}

			// A question over the window: the 3a sheet, scoped to the pane.
			// Gone entirely when not asked - its scrim swallows every click
			// under it, which with the sheet merely invisible was every
			// click in the window.
			GlassDialog {
				anchors.fill: parent
				open: root.confirm !== null
				visible: open || sheet.opacity > 0.01
				title: root.confirm?.title ?? ""
				body: root.confirm?.body ?? ""

				Row {
					anchors.right: parent.right
					spacing: Theme.spacingS

					DialogButton {
						text: "Cancel"
						onClicked: root.confirm = null
					}

					DialogButton {
						text: root.confirm?.verb ?? ""
						variant: "destructive"
						onClicked: root.runConfirm()
					}
				}
			}
		}
	}

	// The name, editable, as the design draws it in 10b: a small field in
	// the row or under the tile with the stem selected, so typing replaces
	// the name and keeps the extension. Reads what it edits from the window,
	// since only one thing is ever renamed at a time.
	Component {
		id: renameBox

		Rectangle {
			id: editor

			property int fontSize: Theme.fontLead

			implicitWidth: input.contentWidth + 16
			height: input.implicitHeight + 6
			radius: 8
			color: Qt.rgba(1, 1, 1, 0.14)
			border.width: 1
			border.color: Qt.rgba(1, 1, 1, 0.60)

			TextInput {
				id: input

				anchors {
					fill: parent
					leftMargin: 6
					rightMargin: 6
				}

				verticalAlignment: TextInput.AlignVCenter
				clip: true
				text: root.baseName(root.renaming)
				font.pixelSize: editor.fontSize
				font.weight: Font.DemiBold
				color: Theme.glassTextPrimary
				selectionColor: Theme.renameSelection
				selectedTextColor: Theme.glassTextPrimary

				Component.onCompleted: {
					forceActiveFocus();
					const dot = text.lastIndexOf(".");
					select(0, dot > 0 && !root.renamingFolder ? dot : text.length);
				}

				onAccepted: root.commitRename(text)
				Keys.onEscapePressed: root.cancelRename()

				// Clicking away keeps what was typed, as the desktop's other
				// file managers do.
				onActiveFocusChanged: if (!activeFocus && root.renaming !== "") root.commitRename(text)
			}
		}
	}
}
