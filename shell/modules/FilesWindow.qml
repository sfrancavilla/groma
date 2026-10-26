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
// new folder, trash, restore, copy, move and undo; a copy reports its
// progress in a card and asks about a name already taken in a sheet.
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

	// A sheet over the window: the folder and the places step back under it.
	readonly property bool sheetUp: root.confirm !== null || root.conflict !== null || root.opener !== null || root.props !== null

	// The path of the highlighted entry, or "" for none: where the keyboard
	// is. The selection is what an action applies to; usually the same one
	// thing, more after Shift or Ctrl.
	property string picked: ""
	property var selection: []
	property bool selectionHeld: false

	onPickedChanged: if (!root.selectionHeld) root.selection = root.picked === "" ? [] : [root.picked]

	// "only" | "toggle" | "range" | "extend"
	function select(entry, mode) {
		if (mode === "toggle") {
			const has = root.selection.includes(entry.path);
			root.selectionHeld = true;
			root.picked = entry.path;
			root.selection = has ? root.selection.filter(p => p !== entry.path) : root.selection.concat([entry.path]);
			root.selectionHeld = false;
		} else if (mode === "range" || mode === "extend") {
			const from = Math.max(0, root.current);
			const to = root.entries.findIndex(e => e.path === entry.path);
			const lo = Math.min(from, to), hi = Math.max(from, to);
			const span = root.entries.slice(lo, hi + 1).map(e => e.path);
			root.selectionHeld = true;
			root.picked = entry.path;
			root.selection = mode === "extend"
				? root.selection.concat(span.filter(p => !root.selection.includes(p))) : span;
			root.selectionHeld = false;
		} else {
			root.picked = entry.path;
			root.selection = [entry.path];
		}
	}

	function selectAll() {
		root.selectionHeld = true;
		root.selection = root.entries.map(e => e.path);
		if (root.picked === "" && root.entries.length > 0)
			root.picked = root.entries[0].path;
		root.selectionHeld = false;
	}

	// What an action is for: the selection when the highlighted thing is
	// part of it, else just the highlighted thing.
	function chosen() {
		if (root.currentEntry === null)
			return [];
		if (root.selection.includes(root.picked))
			return root.entries.filter(e => root.selection.includes(e.path));
		return [root.currentEntry];
	}

	readonly property string filter: searchField.text.trim()

	readonly property bool inTrash: root.path === root.trashPath

	// Inside a snapper snapshot: read-only, and the way back is a copy.
	// The number, and the place the same folder lives today.
	readonly property var snapshotAt: {
		const m = /^(.*)\/\.snapshots\/(\d+)\/snapshot(\/.*)?$/.exec(root.path);
		return m ? { number: parseInt(m[2]), live: (m[1] + (m[3] ?? "")) || "/" } : null;
	}

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

	Process {
		id: copyProbe

		command: ["bash", "-c", "command -v wl-copy && command -v wl-paste"]
		onExited: code => root.hasCopy = code === 0
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
		if (msg.event !== undefined) {
			root.progress(msg);
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

	// One thing at a time: the selection narrows to what is being renamed.
	function startRename(entry) {
		root.select(entry, "only");
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

	// One thing, or several: the words say which.
	function nameThem(entries) {
		return entries.length === 1 ? entries[0].name : root.things(entries.length);
	}

	function trashEntries(entries) {
		if (entries.length === 0)
			return;
		root.ask("trash", { paths: entries.map(e => e.path) }, msg => {
			root.say(`Moved ${root.nameThem(entries)} to Trash · Ctrl+Z undoes`);
		});
	}

	function restoreEntries(entries) {
		if (entries.length === 0)
			return;
		root.ask("restore", { names: entries.map(e => e.name) }, msg => {
			root.say(entries.length === 1
				? `Restored ${entries[0].name} to ${root.tilde(root.parentOf(msg.paths[0]))}`
				: `Restored ${root.things(entries.length)}`);
		});
	}

	function undo() {
		root.ask("undo", {}, msg => { root.say(`Undid the ${msg.undid}`); });
	}

	// A question with a Cancel: what it asks, the word on the chip that
	// answers yes, and what yes does.
	property var confirm: null

	function askDelete(entries) {
		if (entries.length === 0)
			return;
		const what = root.nameThem(entries);
		root.confirm = {
			title: `Delete ${what} forever?`,
			body: (entries.length === 1 ? "It" : "They") + " will not go to the Trash, and there is no undo.",
			verb: "Delete",
			run: () => root.ask("delete", { paths: entries.map(e => e.path) }, msg => root.say(`Deleted ${what}`))
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
			if (!root.inTrash) {
				if (root.held !== null || root.hasCopy)
					out.push({ label: "Paste", run: () => root.paste(undefined) });
				out.push({ label: "New folder", run: () => root.newFolder() });
				out.push({ label: "Open in Terminal", run: () => root.openTerminal(root.path) });
			}
			return out;
		}
		const them = root.chosen();
		const several = them.length > 1;
		if (root.inTrash) {
			out.push({ label: "Restore", run: () => root.restoreEntries(them) });
			out.push({ label: "Delete forever…", run: () => root.askDelete(them) });
			return out;
		}
		if (!several) {
			out.push({ label: "Open", run: () => root.openEntry(entry) });
			out.push({ label: "Open with…", run: () => root.probeOpen(entry, true) });
			if (entry.folder)
				out.push({ label: "Open in Terminal", run: () => root.openTerminal(entry.path) });
			out.push({ label: "Rename", run: () => root.startRename(entry) });
			out.push({ label: "Properties…", run: () => root.showProperties(entry) });
		}
		out.push({ label: "Copy", run: () => root.hold(them, false) });
		out.push({ label: "Cut", run: () => root.hold(them, true) });
		if (!several && entry.folder && (root.held !== null || root.hasCopy))
			out.push({ label: "Paste into " + entry.name, run: () => root.paste(entry.path) });
		out.push({ label: "Copy path", run: () => {
			Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", entry.path]);
			root.say(`Copied ${root.tilde(entry.path)}`);
		} });
		out.push({ label: "New folder", run: () => root.newFolder() });
		out.push({ label: "Move to Trash", run: () => root.trashEntries(them) });
		out.push({ label: "Delete forever…", run: () => root.askDelete(them) });
		return out;
	}

	readonly property int menuWidth: 200
	readonly property int menuRowHeight: 32
	readonly property int menuGap: 6

	// A menu of given items, for the drives, which are not entries.
	function showMenu(items, x, y, anchor) {
		if (items.length === 0)
			return;
		const pad = 8;
		const height = items.length * root.menuRowHeight + 12;
		let my = anchor ? anchor.bottom + root.menuGap : y;
		if (my + height > body.height - pad)
			my = anchor ? anchor.top - root.menuGap - height : y - height;
		let mx = Math.min(x, body.width - pad - root.menuWidth);
		root.menu = { entry: null, items: items, x: Math.max(pad, mx), y: Math.max(pad, my), index: 0 };
	}

	function driveActions(drive) {
		const out = [];
		if (drive.mountpoint === "") {
			out.push({ label: "Mount", run: () => root.openDrive(drive) });
		} else {
			out.push({ label: "Open", run: () => root.go(drive.mountpoint) });
			out.push({ label: "Open in Terminal", run: () => root.openTerminal(drive.mountpoint) });
			out.push({ label: "Unmount", run: () => root.unmountDrive(drive, false) });
			if (drive.removable)
				out.push({ label: "Eject", run: () => root.unmountDrive(drive, true) });
		}
		return out;
	}

	// x and y in the body's coordinates: where the pointer was, or where the
	// menu should start. `anchor` is the row or tile it belongs to, as
	// { top, bottom } in the same coordinates: the menu hangs below it with
	// a gap, or sits above it when the bottom of the window is too close.
	// Without an anchor it opens at the point and flips up or left to fit.
	function openMenu(entry, x, y, anchor) {
		if (entry !== null && !root.selection.includes(entry.path))
			root.select(entry, "only");
		else if (entry !== null)
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
			root.restoreEntries(root.chosen());
		else
			root.openEntry(root.currentEntry);
	}

	// --- copy and move -------------------------------------------------------
	//
	// Ctrl+C and Ctrl+X remember what was picked; Ctrl+V asks the worker to
	// bring it here. The same list goes onto the desktop's clipboard as file
	// URLs, so a paste in another application gets the files too, and a
	// paste here with nothing remembered reads that clipboard back.

	// { paths, cut } or null.
	property var held: null

	function hold(entries, cut) {
		if (entries.length === 0)
			return;
		root.held = { paths: entries.map(e => e.path), cut: cut };
		root.publishHeld();
		root.say((cut ? "Cut " : "Copied ") + root.nameThem(entries) + " · Ctrl+V pastes");
	}

	function publishHeld() {
		if (root.held === null || !root.hasCopy)
			return;
		const urls = root.held.paths.map(path => "file://" + encodeURI(path)).join("\r\n") + "\r\n";
		Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy -t text/uri-list', "sh", urls]);
	}

	// Into the folder on screen, or into `folder` when given.
	function paste(folder) {
		if (root.inTrash)
			return;
		const to = folder ?? root.path;
		if (root.held !== null) {
			root.transferHeld(to);
			return;
		}
		if (root.hasCopy) {
			pasteProbe.target = to;
			pasteProbe.running = true;
		}
	}

	function transferHeld(to) {
		const cut = root.held.cut;
		root.startTransfer(cut ? "move" : "copy", root.held.paths, to);
		if (cut)
			root.held = null;
	}

	// What another application put on the clipboard, as files.
	Process {
		id: pasteProbe

		property string target: ""

		command: ["wl-paste", "-t", "text/uri-list", "-n"]

		stdout: StdioCollector {
			onStreamFinished: {
				const paths = text.split(/\r?\n/)
					.filter(line => line.startsWith("file://"))
					.map(line => decodeURI(line.slice(7)));
				if (paths.length === 0)
					root.say("Nothing to paste");
				else
					root.startTransfer("copy", paths, pasteProbe.target);
			}
		}
	}

	// The copy or move in flight: what the design's card shows.
	// { id, op, count, to, file, index, done, total, started } or null.
	property var transfer: null

	// The question the worker is waiting on, from the design's sheet.
	// { id, name, existing, incoming, remaining } or null.
	property var conflict: null
	property bool applyAll: false

	property bool hasCopy: false

	function startTransfer(op, paths, to) {
		if (root.transfer !== null) {
			root.say("Wait for the current copy to finish");
			return;
		}
		const id = root.nextId;
		root.transfer = { id: id, op: op, count: paths.length, to: to, file: "", index: 0,
			done: 0, total: 0, started: Date.now() };
		root.ask(op, { paths: paths, to: to }, msg => {
			root.transfer = null;
			root.conflict = null;
			if (msg.cancelled)
				root.say((op === "copy" ? "Copy" : "Move") + " cancelled");
			else if (msg.count > 0)
				root.say((op === "copy" ? "Copied " : "Moved ") + root.things(msg.count)
					+ " to " + root.nameOf(to) + " · Ctrl+Z undoes");
			else
				root.say("Nothing " + (op === "copy" ? "copied" : "moved"));
		});
	}

	// The worker's running commentary on a transfer.
	function progress(msg) {
		if (root.transfer === null || msg.id !== root.transfer.id)
			return;
		if (msg.event === "progress") {
			root.transfer = Object.assign({}, root.transfer, {
				file: msg.file, index: msg.index, done: msg.done, total: msg.total });
		} else if (msg.event === "conflict") {
			root.applyAll = false;
			root.conflict = { id: msg.id, name: msg.name, existing: msg.existing,
				incoming: msg.incoming, remaining: msg.remaining };
		}
	}

	function answerConflict(choice) {
		const c = root.conflict;
		root.conflict = null;
		if (c !== null)
			root.ask("answer", { id: c.id, choice: choice, all: root.applyAll });
	}

	function cancelTransfer() {
		if (root.transfer !== null)
			root.ask("cancel", { id: root.transfer.id });
		root.conflict = null;
	}

	function things(n) {
		return n === 1 ? "1 item" : n + " items";
	}

	function nameOf(path) {
		const place = root.places.find(p => p.path === path);
		return place ? place.name : root.baseName(path);
	}

	// "about 12 s left", from how fast it has gone so far.
	readonly property string transferEta: {
		const t = root.transfer;
		if (t === null || t.done === 0 || t.total === 0)
			return "";
		const elapsed = (Date.now() - t.started) / 1000;
		const left = (t.total - t.done) / (t.done / Math.max(elapsed, 0.1));
		if (left < 1)
			return "";
		if (left < 90)
			return "about " + Math.ceil(left) + " s left";
		return "about " + Math.ceil(left / 60) + " min left";
	}

	// --- drag and drop ----------------------------------------------------------
	//
	// Inside the window the drag is ours: a ghost of the rows follows the
	// pointer, a folder or a place lights up as the target, release moves
	// there - or copies, with Ctrl held - and the Trash place trashes. When
	// the pointer leaves the window the same list is handed to the platform
	// as file URLs, so another application can take the drop.
	//
	// { paths, names, folder, count, x, y, target: { path, name } | null,
	//   copy, exported } or null.
	property var drag: null
	property bool dragJustEnded: false

	readonly property int dragThreshold: 8

	function beginDrag(entry, at) {
		if (root.inTrash || root.renaming !== "")
			return;
		const them = root.selection.includes(entry.path) ? root.chosen() : [entry];
		root.drag = { paths: them.map(e => e.path), names: them.map(e => e.name),
			folder: them[0].folder, count: them.length, x: at.x, y: at.y,
			target: null, copy: false, exported: false };
	}

	function dragTo(at, copy) {
		if (root.drag === null || root.drag.exported)
			return;
		if (at.x < 0 || at.y < 0 || at.x > body.width || at.y > body.height) {
			root.exportDrag();
			return;
		}
		root.drag = Object.assign({}, root.drag, { x: at.x, y: at.y, copy: copy, target: root.targetAt(at) });
	}

	function endDrag() {
		const d = root.drag;
		if (d === null)
			return;
		root.drag = null;
		// The click that follows the release must not pick anything - but
		// only when there was a drag. Marking every release ate every click.
		root.dragJustEnded = true;
		Qt.callLater(() => { root.dragJustEnded = false; });
		if (d.exported || d.target === null)
			return;
		if (d.target.path === root.trashPath) {
			root.trashEntries(root.entries.filter(e => d.paths.includes(e.path)));
			return;
		}
		if (!d.copy && d.paths.every(p => root.parentOf(p) === d.target.path))
			return;
		root.startTransfer(d.copy ? "copy" : "move", d.paths, d.target.path);
	}

	function cancelDrag() {
		root.drag = null;
	}

	// A folder row or tile under the point, or a place, that is not one of
	// the things being dragged.
	function targetAt(at) {
		for (const child of placesColumn.children) {
			if (child.modelData === undefined || !child.modelData.path)
				continue;
			const local = child.mapFromItem(body, at.x, at.y);
			if (local.x >= 0 && local.y >= 0 && local.x < child.width && local.y < child.height)
				return { path: child.modelData.path, name: child.modelData.name };
		}
		const view = root.grid ? gridView : listView;
		const inView = view.mapFromItem(body, at.x, at.y);
		if (inView.x >= 0 && inView.y >= 0 && inView.x < view.width && inView.y < view.height) {
			const index = view.indexAt(inView.x + view.contentX, inView.y + view.contentY);
			const entry = index >= 0 ? root.entries[index] : null;
			if (entry !== null && entry.folder && !root.drag.paths.includes(entry.path))
				return { path: entry.path, name: entry.name };
		}
		return null;
	}

	// Over to the platform: the ghost as the drag's picture, the list as
	// file URLs. Qt runs the rest and says when it is over.
	function exportDrag() {
		const d = root.drag;
		root.drag = Object.assign({}, d, { exported: true, target: null });
		dragProxy.Drag.mimeData = {
			"text/uri-list": d.paths.map(path => "file://" + encodeURI(path)).join("\r\n") + "\r\n"
		};
		ghost.grabToImage(result => {
			dragProxy.Drag.imageSource = result.url;
			dragProxy.Drag.active = true;
		});
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
			root.probeOpen(entry, false);
	}

	// A terminal with the folder as its working directory. Foot is what
	// the keybinding opens; a terminal takes no file, so it never appears
	// in "Open with", and gets a line of its own.
	function openTerminal(folder) {
		Quickshell.execDetached(["foot", "--working-directory=" + folder]);
	}

	// --- properties ------------------------------------------------------------
	//
	// What the file system knows about one thing, gathered by a short
	// script: size and dates from stat, the type from the desktop's MIME
	// database, and for a folder the total size and count, which take a
	// moment on a big one and arrive when they do.
	//
	// { entry, type, size, count, modified, accessed, perms, owner, group,
	//   ready } or null.
	property var props: null

	function showProperties(entry) {
		root.props = { entry: entry, type: "", size: entry.size, count: -1, modified: entry.modified,
			accessed: null, perms: "", owner: "", group: "", ready: false };
		propsProbe.running = false;
		propsProbe.running = true;
	}

	Process {
		id: propsProbe

		command: ["bash", "-c",
			'stat -c "%s|%Y|%X|%A|%U|%G" "$1"; xdg-mime query filetype "$1"; '
			+ 'if [ -d "$1" ]; then du -sb "$1" 2>/dev/null | cut -f1; find "$1" -mindepth 1 2>/dev/null | wc -l; fi',
			"sh", root.props?.entry?.path ?? ""]

		stdout: StdioCollector {
			onStreamFinished: {
				if (root.props === null)
					return;
				const lines = text.split("\n");
				const st = (lines[0] ?? "").split("|");
				const folder = root.props.entry.folder;
				root.props = Object.assign({}, root.props, {
					size: folder ? parseInt(lines[2] ?? "0") || 0 : parseInt(st[0]) || 0,
					count: folder ? parseInt(lines[3] ?? "0") || 0 : -1,
					modified: new Date(parseInt(st[1]) * 1000),
					accessed: new Date(parseInt(st[2]) * 1000),
					perms: st[3] ?? "",
					owner: st[4] ?? "",
					group: st[5] ?? "",
					type: (lines[1] ?? "").trim(),
					ready: true
				});
			}
		}
	}

	// --- opening with an application ------------------------------------------
	//
	// The desktop keeps a default per file type; xdg-open follows it. Where
	// there is none, a browser tab is what xdg-open falls back to, so Files
	// asks instead: a sheet of the installed applications, the ones that
	// claim the type first. "Always" writes the default, so Enter opens
	// directly from then on and other programs follow the same choice.
	//
	// { entry, type, defaultId, suggested, always, index } or null.
	property var opener: null

	function probeOpen(entry, ask) {
		typeProbe.entry = entry;
		typeProbe.ask = ask;
		typeProbe.running = false;
		typeProbe.running = true;
	}

	Process {
		id: typeProbe

		property var entry: null
		property bool ask: false

		command: ["bash", "-c",
			't=$(xdg-mime query filetype "$1"); d=$(xdg-mime query default "$t" 2>/dev/null); '
			+ 'printf "%s\\n%s\\n" "$t" "$d"; '
			+ 'case "$t" in text/*) pat="^($t|text/plain)=";; *) pat="^$t=";; esac; '
			+ 'cat /usr/share/applications/mimeinfo.cache "$HOME/.local/share/applications/mimeinfo.cache" '
			+ '/usr/local/share/applications/mimeinfo.cache 2>/dev/null | grep -E "$pat" | cut -d= -f2 | tr ";" "\\n" | grep . | sort -u',
			"sh", typeProbe.entry?.path ?? ""]

		stdout: StdioCollector {
			onStreamFinished: {
				const lines = text.split("\n");
				const type = lines[0] ?? "";
				const defaultId = (lines[1] ?? "").replace(/\.desktop$/, "");
				const suggested = lines.slice(2).filter(l => l !== "").map(l => l.replace(/\.desktop$/, ""));
				if (defaultId !== "" && !typeProbe.ask) {
					Quickshell.execDetached(["xdg-open", typeProbe.entry.path]);
					root.raiseLater(defaultId);
					return;
				}
				root.opener = { entry: typeProbe.entry, type: type, defaultId: defaultId,
					suggested: suggested, always: false, index: 0 };
				// The highlight starts on the current default, when there is one.
				const at = root.openerApps.findIndex(app => app.entry.id === defaultId);
				if (at > 0)
					root.opener = Object.assign({}, root.opener, { index: at });
			}
		}
	}

	// Which desktop categories are a fit for a kind of file, when nothing
	// claims the type outright.
	function fittingCategories(type) {
		if (type === "inode/directory")
			return ["FileManager", "IDE", "TextEditor"];
		if (type.startsWith("text/") || type === "application/json" || type === "application/xml"
				|| type === "application/x-shellscript" || type === "application/javascript")
			return ["TextEditor", "IDE", "Development", "Office", "WordProcessor"];
		if (type.startsWith("image/"))
			return ["Viewer", "Graphics", "Photography", "RasterGraphics", "VectorGraphics"];
		if (type.startsWith("audio/"))
			return ["Audio", "Player", "AudioVideo", "Music"];
		if (type.startsWith("video/"))
			return ["Video", "Player", "AudioVideo"];
		if (type === "application/pdf" || type.startsWith("application/vnd.") || type === "application/msword")
			return ["Office", "Viewer", "WordProcessor", "Spreadsheet", "Presentation"];
		if (type.startsWith("application/") && (type.includes("zip") || type.includes("tar") || type.includes("compress")))
			return ["Archiving", "Compression", "FileManager"];
		return [];
	}

	// Only an entry that takes a file can open one: Exec must carry a %f,
	// %F, %u or %U. Volume Control does not, and has no business in the list.
	function takesFiles(entry) {
		return /%[fFuU]/.test(entry.execString ?? "");
	}

	// The applications on offer: those claiming the type, then those whose
	// categories fit it, both as suggestions; then everything else that can
	// take a file at all.
	readonly property var openerApps: {
		const o = root.opener;
		if (o === null)
			return [];
		const fitting = root.fittingCategories(o.type);
		const claims = e => o.suggested.includes(e.id);
		const fits = e => (e.categories ?? []).some(c => fitting.includes(c));
		const all = DesktopEntries.applications.values.filter(e => !e.noDisplay && root.takesFiles(e));
		const rank = e => claims(e) ? 2 : fits(e) ? 1 : 0;
		return all
			.map(e => ({ entry: e, suggested: rank(e) > 0, rank: rank(e) }))
			.sort((a, b) => b.rank - a.rank || a.entry.name.localeCompare(b.entry.name));
	}

	function moveOpener(delta) {
		const o = root.opener;
		if (o === null || root.openerApps.length === 0)
			return;
		root.opener = Object.assign({}, o, {
			index: Math.max(0, Math.min(root.openerApps.length - 1, o.index + delta)) });
		openerList.positionViewAtIndex(root.opener.index, ListView.Contain);
	}

	function runOpener() {
		const o = root.opener;
		// Read the pick before the sheet goes: the list is derived from it.
		const apps = root.openerApps;
		root.opener = null;
		if (o === null || apps.length === 0)
			return;
		const app = apps[o.index].entry;
		root.launch(app.id, o.entry.path, o.always ? o.type : "");
		root.say(`Opening ${o.entry.name} with ${app.name}` + (o.always ? ` · always, for ${o.type}` : ""));
	}

	// gio launch runs a desktop entry with a file, as a click on it would.
	// With a type, that entry becomes the desktop's default for it first.
	function launch(id, path, alwaysFor) {
		Quickshell.execDetached(["bash", "-c",
			'[ -n "$4" ] && xdg-mime default "$1.desktop" "$4"; '
			+ 'for d in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications; do '
			+ 'f="$d/$1.desktop"; [ -f "$f" ] && exec gio launch "$f" "$2"; done',
			"sh", id, path, "", alwaysFor]);
		root.raiseLater(id);
	}

	// An application already running takes the file as a new tab in a
	// window that stays where it was - on a tiled desktop, possibly on
	// another workspace, so nothing seems to happen. A beat after the
	// launch, its window is brought to the front, as the launcher does.
	// A fresh process gets the focus from the compositor on its own.
	function raiseLater(id) {
		raiser.entryId = id;
		raiser.tries = 0;
		raiseTimer.restart();
	}

	Timer {
		id: raiseTimer

		interval: 500
		onTriggered: { raiser.running = false; raiser.running = true; }
	}

	Process {
		id: raiser

		property string entryId: ""
		property int tries: 0

		command: ["hyprctl", "clients", "-j"]

		stdout: StdioCollector {
			onStreamFinished: {
				const entry = DesktopEntries.byId(raiser.entryId);
				if (entry === null)
					return;
				const exec = String(entry.execString ?? "").trim().split(/\s+/)[0] ?? "";
				const names = [entry.id, entry.startupClass, exec.split("/").pop()]
					.map(name => String(name ?? "").toLowerCase())
					.filter(name => name !== "" && !name.startsWith("@@"));
				let windows = [];
				try {
					windows = JSON.parse(text);
				} catch (err) {
					return;
				}
				const mine = windows
					.filter(win => names.includes(String(win.class ?? "").toLowerCase())
						|| names.includes(String(win.initialClass ?? "").toLowerCase()))
					.sort((a, b) => (a.focusHistoryID ?? 999) - (b.focusHistoryID ?? 999));
				if (mine.length > 0) {
					Quickshell.execDetached(["hyprctl", "dispatch",
						`hl.dsp.focus({ window = "address:${mine[0].address}" })`]);
				} else if (raiser.tries++ < 6) {
					raiseTimer.restart();
				}
			}
		}
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

	// --- drives -----------------------------------------------------------------
	//
	// What lsblk knows, kept to the drives a person plugs in or mounts by
	// hand: removable and hot-plugged filesystems, and anything mounted
	// under /run/media, /media or /mnt. The system's own partitions stay
	// out. udev says when something is plugged or pulled; a slow poll
	// catches a mount made elsewhere. Mounting and ejecting go through
	// udisks, which asks polkit on the user's behalf.
	//
	// [{ dev, disk, name, size, mountpoint, removable }]
	property var drives: []
	property bool hasUdisks: false

	Process {
		id: udisksProbe

		command: ["bash", "-c", "command -v udisksctl"]
		onExited: code => root.hasUdisks = code === 0
	}

	Process {
		id: lsblkProbe

		command: ["lsblk", "-J", "-o", "NAME,PATH,PKNAME,LABEL,SIZE,TYPE,MOUNTPOINT,FSTYPE,RM,HOTPLUG,MODEL,TRAN"]

		stdout: StdioCollector {
			onStreamFinished: root.drives = root.drivesFrom(text)
		}
	}

	function drivesFrom(json) {
		let tree;
		try {
			tree = JSON.parse(json).blockdevices ?? [];
		} catch (err) {
			return [];
		}
		const out = [];
		const walk = (node, disk) => {
			const top = disk ?? node;
			const fs = node.fstype ?? "";
			const mount = node.mountpoint ?? "";
			const plugged = node.rm === true || node.hotplug === true
				|| ["usb", "mmc", "sd"].includes(node.tran ?? "") || top.rm === true || top.hotplug === true;
			const byHand = /^\/(run\/media|media|mnt)(\/|$)/.test(mount);
			const usable = fs !== "" && !["crypto_LUKS", "swap", "LVM2_member", "linux_raid_member"].includes(fs);
			// A hybrid ISO written to a stick shows its filesystem on the whole
			// disk as well as on the first partition: the partitions are what
			// count. And lsblk hangs the encrypted root off whatever it likes;
			// anything mounted at a system path is the system's, not a drive.
			const wholeDiskWithParts = node.type === "disk" && (node.children ?? []).length > 0;
			const system = /^\/(home|boot|var|usr|etc|nix|\.snapshots|efi)?(\/|$)/.test(mount) && mount !== "";
			if (usable && (plugged || byHand) && !wholeDiskWithParts && !system)
				out.push({
					dev: node.path,
					disk: top.path,
					name: node.label || top.model || node.name,
					size: node.size ?? "",
					mountpoint: mount,
					removable: plugged
				});
			for (const child of (node.children ?? []))
				walk(child, top);
		};
		for (const node of tree)
			walk(node, null);
		return out;
	}

	Process {
		id: udevWatch

		command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]

		stdout: SplitParser {
			onRead: line => { if (line.includes("add") || line.includes("remove") || line.includes("change")) relist.restart(); }
		}
	}

	Timer {
		id: relist

		interval: 800
		onTriggered: { lsblkProbe.running = false; lsblkProbe.running = true; }
	}

	Timer {
		id: drivePoll

		interval: 10000
		repeat: true
		running: root.open
		onTriggered: relist.restart()
	}

	function openDrive(drive) {
		if (drive.mountpoint !== "") {
			root.go(drive.mountpoint);
			return;
		}
		if (!root.hasUdisks) {
			root.say("Mounting needs udisks2 installed");
			return;
		}
		mounter.command = ["udisksctl", "mount", "-b", drive.dev];
		mounter.running = true;
	}

	function unmountDrive(drive, eject) {
		if (!root.hasUdisks) {
			root.say("Unmounting needs udisks2 installed");
			return;
		}
		if (drive.mountpoint !== "" && (root.path === drive.mountpoint || root.path.startsWith(drive.mountpoint + "/")))
			root.go(root.home);
		mounter.command = eject
			? ["bash", "-c", 'udisksctl unmount -b "$1" && udisksctl power-off -b "$2"', "sh", drive.dev, drive.disk]
			: ["udisksctl", "unmount", "-b", drive.dev];
		mounter.running = true;
	}

	// udisksctl answers in a sentence: "Mounted /dev/sdb1 at /run/media/…".
	Process {
		id: mounter

		stdout: StdioCollector {
			onStreamFinished: {
				const at = text.indexOf(" at ");
				if (at > 0)
					root.go(text.slice(at + 4).trim().replace(/\.$/, ""));
				else if (text.trim() !== "")
					root.say(text.trim());
				relist.restart();
			}
		}

		stderr: StdioCollector {
			onStreamFinished: if (text.trim() !== "") root.say(text.trim().split("\n")[0])
		}
	}

	onOpenChanged: {
		if (root.open) {
			placesProbe.running = true;
			copyProbe.running = true;
			udisksProbe.running = true;
			worker.running = true;
			relist.restart();
			udevWatch.running = true;
		} else {
			udevWatch.running = false;
			worker.running = false;
			root.confirm = null;
			root.menu = null;
			root.opener = null;
			root.props = null;
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
		if (root.selection.some(p => !out.some(entry => entry.path === p))) {
			root.selectionHeld = true;
			root.selection = root.selection.filter(p => out.some(entry => entry.path === p));
			root.selectionHeld = false;
		}

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

	onFilterChanged: {
		root.rebuild();
		// An empty track has nothing for the keys to do; the list does.
		if (root.filter === "" && searchField.activeFocus && searchField.text === "")
			body.forceActiveFocus();
	}

	readonly property int current: root.entries.findIndex(entry => entry.path === root.picked)
	readonly property var currentEntry: root.current >= 0 ? root.entries[root.current] : null

	function move(delta, extend) {
		if (root.entries.length === 0)
			return;
		const next = root.current < 0
			? (delta > 0 ? 0 : root.entries.length - 1)
			: Math.max(0, Math.min(root.entries.length - 1, root.current + delta));
		root.select(root.entries[next], extend ? "extend" : "only");
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
			return withTime === "exact" ? "Yesterday, " + Qt.formatTime(then, "h:mm") : "Yesterday";
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
		if (root.selection.length > 1)
			return text + " · " + root.selection.length + " selected";
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

		// Highlight a thing in the folder on screen, as a click would; with
		// "add", as a Ctrl-click would.
		function pick(path: string): void {
			const entry = root.entries.find(e => e.path === path);
			if (entry)
				root.select(entry, "only");
		}

		function add(path: string): void {
			const entry = root.entries.find(e => e.path === path);
			if (entry)
				root.select(entry, "toggle");
		}

		// The path Tab takes: the actions for the highlighted thing.
		function actions(): void {
			root.toggleMenu();
		}

		// The paths Ctrl+C, Ctrl+X and Ctrl+V take.
		function copy(): void {
			if (!root.inTrash)
				root.hold(root.chosen(), false);
		}

		function cut(): void {
			if (!root.inTrash)
				root.hold(root.chosen(), true);
		}

		function paste(): void {
			root.paste(undefined);
		}

		// The path Ctrl+I takes on the highlighted thing.
		function properties(): void {
			if (root.currentEntry !== null)
				root.showProperties(root.currentEntry);
		}

		// The path "Open with…" takes on the highlighted thing.
		function openwith(): void {
			if (root.currentEntry !== null)
				root.probeOpen(root.currentEntry, true);
		}

		// The path Open takes in the "Open with" sheet, for a given application.
		function choose(id: string): void {
			const index = root.openerApps.findIndex(app => app.entry.id === id);
			if (index >= 0) {
				root.opener = Object.assign({}, root.opener, { index: index });
				root.runOpener();
			}
		}

		// The path the conflict sheet's chips take: skip, keep or replace.
		function answer(choice: string): void {
			root.answerConflict(choice);
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

					if (root.drag !== null) {
						if (event.key === Qt.Key_Escape)
							root.cancelDrag();
						event.accepted = true;
						return;
					}

					// Properties: nothing to answer, Escape closes it.
					if (root.props !== null) {
						if (event.key === Qt.Key_Escape)
							root.props = null;
						event.accepted = true;
						return;
					}

					// "Open with": walk the applications, Return opens, Escape leaves.
					if (root.opener !== null) {
						if (event.key === Qt.Key_Down)
							root.moveOpener(1);
						else if (event.key === Qt.Key_Up)
							root.moveOpener(-1);
						else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
							root.runOpener();
						else if (event.key === Qt.Key_Escape)
							root.opener = null;
						event.accepted = true;
						return;
					}

					// The conflict sheet: Escape skips, Return keeps both.
					if (root.conflict !== null) {
						if (event.key === Qt.Key_Escape)
							root.answerConflict("skip");
						else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
							root.answerConflict("keep");
						event.accepted = true;
						return;
					}

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
					// other key closes it and then goes on to do what it does.
					if (root.menu !== null) {
						if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
							root.moveMenu(event.key === Qt.Key_Down ? 1 : -1);
							event.accepted = true;
							return;
						}
						if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
							root.runMenu();
							event.accepted = true;
							return;
						}
						root.menu = null;
						if (event.key === Qt.Key_Escape || event.key === Qt.Key_Tab) {
							event.accepted = true;
							return;
						}
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
						root.move(columns, shift);
					} else if (event.key === Qt.Key_Up) {
						root.move(-columns, shift);
					} else if (event.key === Qt.Key_Right && !searchField.activeFocus && !alt) {
						root.move(1, shift);
					} else if (event.key === Qt.Key_Left && !searchField.activeFocus && !alt) {
						root.move(-1, shift);
					} else if (ctrl && event.key === Qt.Key_A) {
						root.selectAll();
					} else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
						root.openTerminal(root.currentEntry?.folder ? root.currentEntry.path : root.path);
					} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						root.activate();
					} else if (event.key === Qt.Key_Delete) {
						if (root.inTrash || shift)
							root.askDelete(root.chosen());
						else
							root.trashEntries(root.chosen());
					} else if (event.key === Qt.Key_F2) {
						if (root.currentEntry !== null && !root.inTrash)
							root.startRename(root.currentEntry);
					} else if (ctrl && shift && event.key === Qt.Key_N) {
						if (!root.inTrash)
							root.newFolder();
					} else if (ctrl && event.key === Qt.Key_Z) {
						root.undo();
					} else if (ctrl && event.key === Qt.Key_I) {
						if (root.currentEntry !== null)
							root.showProperties(root.currentEntry);
					} else if (ctrl && event.key === Qt.Key_C) {
						if (!root.inTrash)
							root.hold(root.chosen(), false);
					} else if (ctrl && event.key === Qt.Key_X) {
						if (!root.inTrash)
							root.hold(root.chosen(), true);
					} else if (ctrl && event.key === Qt.Key_V) {
						root.paste(undefined);
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
					opacity: root.sheetUp ? Theme.menuBackdropOpacity : 1

					Behavior on opacity {
						NumberAnimation { duration: 120 }
					}

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
											onClicked: { body.forceActiveFocus(); root.go(crumb.modelData.path); }

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
											onClicked: { body.forceActiveFocus(); root.grid = parent.modelData; }
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
					opacity: root.sheetUp ? Theme.menuBackdropOpacity : 1

					Behavior on opacity {
						NumberAnimation { duration: 120 }
					}

					Rectangle {
						anchors.right: parent.right
						width: 1
						height: parent.height
						color: Theme.glassControlBorder
					}

					Column {
						id: placesColumn

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
								readonly property bool dropTarget: root.drag !== null && root.drag.target !== null
									&& root.drag.target.path === modelData.path

								width: parent.width
								height: 38
								radius: Theme.radiusPill
								color: dropTarget ? Theme.dropTarget
									: here ? Theme.glassChipActive
									: placeMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: dropTarget ? 1.5 : here ? 1 : 0
								border.color: dropTarget ? Theme.dropTargetEdge : Theme.glassTrackBorderFocus

								Rectangle {
									anchors.fill: parent
									anchors.margins: -4
									radius: parent.radius + 4
									visible: place.dropTarget
									color: "transparent"
									border.width: 4
									border.color: Theme.dropTargetRing
								}

								Row {
									anchors {
										left: parent.left
										right: parent.right
										leftMargin: 8
										rightMargin: 8
										verticalCenter: parent.verticalCenter
									}

									spacing: 10

									FileIcon {
										anchors.verticalCenter: parent.verticalCenter
										width: 26
										height: 26
										iconName: ({ home: "user-home", folder: "folder-documents", downloads: "folder-download",
											pictures: "folder-pictures", trash: "user-trash" })[place.modelData.kind] ?? ""
										glyph: place.modelData.kind
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
									onClicked: { body.forceActiveFocus(); root.go(place.modelData.path); }
								}
							}
						}

						Text {
							leftPadding: 10
							topPadding: 10
							bottomPadding: 4
							visible: root.drives.length > 0
							text: "DRIVES"
							font.pixelSize: Theme.fontCaption
							font.bold: true
							font.letterSpacing: 0.66
							opacity: 0.6
							color: Theme.glassTextPrimary
						}

						// A drive is a place with a mount behind it: the row
						// opens it when mounted and mounts it when not. Its
						// modelData carries the mountpoint as `path`, which
						// is what makes it a drop target like the places.
						Repeater {
							model: root.drives.map(d => Object.assign({}, d, { path: d.mountpoint }))

							Rectangle {
								id: driveRow

								required property var modelData

								readonly property bool here: modelData.path !== "" && root.path === modelData.path
								readonly property bool dropTarget: modelData.path !== "" && root.drag !== null
									&& root.drag.target !== null && root.drag.target.path === modelData.path

								width: parent.width
								height: 38
								radius: Theme.radiusPill
								color: dropTarget ? Theme.dropTarget
									: here ? Theme.glassChipActive
									: driveMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: dropTarget ? 1.5 : here ? 1 : 0
								border.color: dropTarget ? Theme.dropTargetEdge : Theme.glassTrackBorderFocus
								opacity: modelData.path === "" ? 0.7 : 1

								Rectangle {
									anchors.fill: parent
									anchors.margins: -4
									radius: parent.radius + 4
									visible: driveRow.dropTarget
									color: "transparent"
									border.width: 4
									border.color: Theme.dropTargetRing
								}

								Row {
									anchors {
										left: parent.left
										right: parent.right
										leftMargin: 8
										rightMargin: 8
										verticalCenter: parent.verticalCenter
									}

									spacing: 10

									FileIcon {
										id: driveDisc

										anchors.verticalCenter: parent.verticalCenter
										width: 26
										height: 26
										iconName: driveRow.modelData.removable ? "drive-removable-media" : "drive-harddisk"
										glyph: "drive"
									}

									Column {
										anchors.verticalCenter: parent.verticalCenter
										width: parent.width - driveDisc.width - 10
										spacing: 0

										Text {
											width: parent.width
											elide: Text.ElideRight
											text: driveRow.modelData.name
											font.pixelSize: Theme.fontTitle
											font.weight: driveRow.here ? Font.Bold : Font.DemiBold
											color: Theme.glassTextPrimary
										}

										Text {
											width: parent.width
											elide: Text.ElideRight
											text: driveRow.modelData.size + (driveRow.modelData.path === "" ? " · not mounted" : "")
											font.pixelSize: Theme.fontCaption
											font.weight: Font.DemiBold
											opacity: 0.6
											color: Theme.glassTextPrimary
										}
									}
								}

								MouseArea {
									id: driveMouse

									anchors.fill: parent
									hoverEnabled: true
									acceptedButtons: Qt.LeftButton | Qt.RightButton
									cursorShape: Qt.PointingHandCursor
									onClicked: mouse => {
										body.forceActiveFocus();
										if (mouse.button === Qt.RightButton) {
											const at = driveRow.mapToItem(body, 0, 0);
											root.showMenu(root.driveActions(driveRow.modelData), at.x + 8, 0,
												{ top: at.y, bottom: at.y + driveRow.height });
										} else {
											root.openDrive(driveRow.modelData);
										}
									}
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

					// Steps back while a menu or a sheet is up, so that is what
					// is read: nothing inside a window gets the compositor's blur.
					opacity: root.menu !== null || root.sheetUp ? Theme.menuBackdropOpacity : 1

					Behavior on opacity {
						NumberAnimation { duration: 120 }
					}

					// In the Trash: what the Trash is, and the way to empty it.
					Rectangle {
						id: banner

						width: parent.width
						height: visible ? 44 : 0
						visible: (root.inTrash && root.entries.length > 0) || root.snapshotAt !== null
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

							anchors.right: bannerAction.left
							anchors.rightMargin: 12
							elide: Text.ElideRight
							text: root.snapshotAt !== null
								? `Snapshot #${root.snapshotAt.number} · read-only · copy files out to restore`
								: "Things stay in the Trash until it is emptied."
							font.pixelSize: Theme.fontBody
							font.weight: Font.DemiBold
							opacity: 0.85
							color: Theme.glassTextPrimary
						}

						DialogButton {
							id: bannerAction

							anchors {
								right: parent.right
								rightMargin: 8
								verticalCenter: parent.verticalCenter
							}

							// In a snapshot: the same folder as it is today.
							text: root.snapshotAt !== null ? "Open live folder" : "Empty Trash"
							variant: root.snapshotAt !== null ? "secondary" : "destructive"
							onClicked: root.snapshotAt !== null ? root.go(root.snapshotAt.live) : root.askEmpty()
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

							readonly property bool selected: root.selection.includes(modelData.path)
							readonly property bool dragged: root.drag !== null && root.drag.paths.includes(modelData.path)
							readonly property bool dropTarget: root.drag !== null && root.drag.target !== null
								&& root.drag.target.path === modelData.path

							width: listView.width
							height: Theme.launcherRowHeight

							Rectangle {
								anchors.fill: parent
								radius: Theme.radiusRow
								color: row.dropTarget ? Theme.dropTarget
									: row.dragged ? Theme.dragSource
									: row.selected ? Theme.glassChipActive
									: rowMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: row.dropTarget ? 1.5 : row.selected || row.dragged ? 1 : 0
								border.color: row.dropTarget ? Theme.dropTargetEdge
									: row.dragged ? Theme.dragSourceEdge : Theme.glassTrackBorderFocus

								Behavior on color {
									ColorAnimation { duration: 120 }
								}

								Rectangle {
									anchors.fill: parent
									anchors.margins: -4
									radius: parent.radius + 4
									visible: row.dropTarget
									color: "transparent"
									border.width: 4
									border.color: Theme.dropTargetRing
								}
							}

							FileIcon {
								id: rowDisc

								x: 11
								anchors.verticalCenter: parent.verticalCenter
								width: 32
								height: 32
								fileName: row.modelData.name
								folder: row.modelData.folder
								path: row.modelData.path
							}

							readonly property bool editing: root.renaming === modelData.path
							readonly property var trashed: root.trashInfo[modelData.name]
							readonly property bool cutAway: root.held !== null && root.held.cut && root.held.paths.includes(modelData.path)

							opacity: cutAway ? 0.5 : dragged ? 0.55 : 1

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
									onClicked: root.restoreEntries([row.modelData])
								}
							}

							MouseArea {
								id: rowMouse

								property point pressedAt

								// Under the texts, so the Restore chip and the
								// editor get their clicks first. The list would
								// take a vertical drag as a flick without
								// preventStealing.
								anchors.fill: parent
								z: -1
								hoverEnabled: true
								preventStealing: true
								onPressed: mouse => pressedAt = Qt.point(mouse.x, mouse.y)
								onPositionChanged: mouse => {
									if (!pressed)
										return;
									const at = mapToItem(body, mouse.x, mouse.y);
									if (root.drag === null) {
										if (Math.abs(mouse.x - pressedAt.x) + Math.abs(mouse.y - pressedAt.y) > root.dragThreshold)
											root.beginDrag(row.modelData, at);
									} else {
										root.dragTo(at, (mouse.modifiers & Qt.ControlModifier) !== 0);
									}
								}
								onReleased: root.endDrag()
								onCanceled: root.cancelDrag()
								onClicked: mouse => {
									if (root.dragJustEnded)
										return;
									body.forceActiveFocus();
									root.select(row.modelData, mouse.modifiers & Qt.ControlModifier ? "toggle"
										: mouse.modifiers & Qt.ShiftModifier ? "range" : "only");
								}
								onDoubleClicked: root.inTrash ? root.restoreEntries([row.modelData]) : root.openEntry(row.modelData)
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

							readonly property bool selected: root.selection.includes(modelData.path)
							readonly property bool editing: root.renaming === modelData.path
							readonly property bool image: !modelData.folder && root.imageTypes.includes(modelData.suffix)
							readonly property bool cutAway: root.held !== null && root.held.cut && root.held.paths.includes(modelData.path)
							readonly property bool dragged: root.drag !== null && root.drag.paths.includes(modelData.path)
							readonly property bool dropTarget: root.drag !== null && root.drag.target !== null
								&& root.drag.target.path === modelData.path

							opacity: cutAway ? 0.5 : dragged ? 0.55 : 1

							width: gridView.cellWidth
							height: gridView.cellHeight

							Rectangle {
								id: tile

								anchors.fill: parent
								anchors.margins: 4
								radius: 18
								color: cell.dropTarget ? Theme.dropTarget
									: cell.dragged ? Theme.dragSource
									: cell.editing ? Theme.glassControl
									: cell.selected ? Theme.glassChipActive
									: tileMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: cell.dropTarget ? 1.5 : cell.selected || cell.editing || cell.dragged ? 1 : 0
								border.color: cell.dropTarget ? Theme.dropTargetEdge
									: cell.dragged ? Theme.dragSourceEdge
									: cell.editing ? Theme.glassEdge : Theme.glassTrackBorderFocus

								Rectangle {
									anchors.fill: parent
									anchors.margins: -4
									radius: parent.radius + 4
									visible: cell.dropTarget
									color: "transparent"
									border.width: 4
									border.color: Theme.dropTargetRing
								}

								Behavior on color {
									ColorAnimation { duration: 120 }
								}

								// The picture, or the file's icon standing in for one.
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
									border.color: thumb.showsPicture ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.14)

									// An image Qt cannot read - empty, broken, a format it has
									// no plugin for - gets its file-type icon like anything else.
									readonly property bool showsPicture: cell.image && picture.status !== Image.Error

									FileIcon {
										anchors.centerIn: parent
										width: 64
										height: 64
										visible: !thumb.showsPicture
										fileName: cell.modelData.name
										folder: cell.modelData.folder
										path: cell.modelData.path
										zoom: 1.5
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

									property point pressedAt

									anchors.fill: parent
									z: -1
									hoverEnabled: true
									preventStealing: true
									onPressed: mouse => pressedAt = Qt.point(mouse.x, mouse.y)
									onPositionChanged: mouse => {
										if (!pressed)
											return;
										const at = mapToItem(body, mouse.x, mouse.y);
										if (root.drag === null) {
											if (Math.abs(mouse.x - pressedAt.x) + Math.abs(mouse.y - pressedAt.y) > root.dragThreshold)
												root.beginDrag(cell.modelData, at);
										} else {
											root.dragTo(at, (mouse.modifiers & Qt.ControlModifier) !== 0);
										}
									}
									onReleased: root.endDrag()
									onCanceled: root.cancelDrag()
									onClicked: mouse => {
										if (root.dragJustEnded)
											return;
										body.forceActiveFocus();
										root.select(cell.modelData, mouse.modifiers & Qt.ControlModifier ? "toggle"
											: mouse.modifiers & Qt.ShiftModifier ? "range" : "only");
									}
									onDoubleClicked: root.inTrash ? root.restoreEntries([cell.modelData]) : root.openEntry(cell.modelData)
								}
							}
						}
					}

					// Files dropped in from another application: into the folder
					// under the pointer, or into this one.
					DropArea {
						id: incoming

						anchors.fill: parent
						keys: ["text/uri-list"]

						onEntered: drag => { drag.accept(); }
						onPositionChanged: drag => {
							const at = content.mapToItem(body, drag.x, drag.y);
							const state = { paths: [], names: [], folder: false, count: 0, x: at.x, y: at.y,
								target: null, copy: drag.proposedAction === Qt.CopyAction, exported: true };
							root.drag = state;
							root.drag = Object.assign({}, state, { target: root.targetAt(at) });
						}
						onExited: root.drag = null
						onDropped: drop => {
							const target = root.drag?.target?.path ?? root.path;
							root.drag = null;
							const paths = (drop.urls ?? []).map(url => decodeURI(String(url).replace(/^file:\/\//, "")))
								.filter(path => path !== "");
							if (paths.length === 0 || drop.source === dragProxy)
								return;
							if (target === root.trashPath) {
								root.ask("trash", { paths: paths }, msg => root.say(`Moved ${root.things(paths.length)} to Trash`));
								drop.accept(Qt.MoveAction);
								return;
							}
							const copy = drop.proposedAction === Qt.CopyAction || drop.proposedAction === Qt.LinkAction;
							root.startTransfer(copy ? "copy" : "move", paths, target);
							drop.accept(copy ? Qt.CopyAction : Qt.MoveAction);
						}
					}

					// A left click on nothing: the keys come back to the list and
					// the selection lets go. Above the views, because a list takes
					// every press for itself; a press over a row or tile is
					// refused here so it falls through to them.
					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton
						onPressed: mouse => {
							const view = root.grid ? gridView : listView;
							const inView = view.mapFromItem(content, mouse.x, mouse.y);
							// Only the list's own empty space: the banner and the
							// headings above it are buttons, and a row takes its own.
							const inside = inView.x >= 0 && inView.y >= 0 && inView.x < view.width && inView.y < view.height;
							const overRow = inside && view.indexAt(inView.x + view.contentX, inView.y + view.contentY) >= 0;
							mouse.accepted = inside && !overRow;
						}
						onClicked: {
							body.forceActiveFocus();
							root.picked = "";
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
								if (root.props !== null)
									return [["Esc", "Close"]];
								if (root.opener !== null)
									return [["↑↓", "Move"], ["↵", "Open"], ["Esc", "Cancel"]];
								if (root.conflict !== null)
									return [["↵", "Keep both"], ["Esc", "Skip"]];
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

			// The ghost of what is being dragged, from 10d: up to three cards
			// fanned behind the front one, a count on its corner, and a line
			// under it saying what letting go will do.
			Item {
				id: ghost

				readonly property var d: root.drag

				// Beside the pointer, and kept inside the window.
				x: Math.min((d?.x ?? 0) + 14, body.width - width - 12)
				y: Math.min((d?.y ?? 0) + 10, body.height - height - 40)
				width: 260
				height: 44
				visible: d !== null && !d.exported && (d.count ?? 0) > 0
				rotation: -2

				Repeater {
					// A drag from another application has no rows of ours: count 0.
					model: ghost.d === null ? 0 : Math.max(0, Math.min(3, ghost.d.count) - 1)

					Rectangle {
						required property int index

						x: (index + 1) * 5
						y: (index + 1) * 5
						z: -index - 1
						width: 260
						height: 44
						radius: 14
						color: Theme.dragSource
						border.width: 1
						border.color: Theme.glassTrackBorderFocus
					}
				}

				Rectangle {
					anchors.fill: parent
					radius: 14
					color: Theme.glassTrackFill
					border.width: 1
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
							id: ghostDisc

							anchors.verticalCenter: parent.verticalCenter
							width: 28
							height: 28
							sheen: false

							FileGlyph {
								anchors.centerIn: parent
								kind: ghost.d?.folder ? "folder" : "file"
							}
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width - ghostDisc.width - 10
							elide: Text.ElideRight
							text: ghost.d?.names?.[0] ?? ""
							font.pixelSize: Theme.fontTitle
							font.bold: true
							color: Theme.glassTextPrimary
						}
					}
				}

				Rectangle {
					anchors {
						right: parent.right
						top: parent.top
						rightMargin: -8
						topMargin: -9
					}

					width: Math.max(22, badge.implicitWidth + 12)
					height: 22
					radius: 11
					visible: (ghost.d?.count ?? 0) > 1
					color: Theme.glassTextPrimary

					Text {
						id: badge

						anchors.centerIn: parent
						text: ghost.d?.count ?? ""
						font.pixelSize: Theme.fontBody
						font.weight: Font.Black
						color: Theme.dragBadgeInk
					}
				}

				Rectangle {
					anchors {
						left: parent.left
						top: parent.bottom
						leftMargin: 10
						topMargin: 8
					}

					width: caption.implicitWidth + 16
					height: caption.implicitHeight + 6
					radius: 8
					color: Theme.dragCaption

					Text {
						id: caption

						anchors.centerIn: parent
						text: ghost.d === null ? ""
							: ghost.d.target === null ? "Drop on a folder · hold Ctrl to copy"
							: ghost.d.target.path === root.trashPath ? "Move to Trash"
							: (ghost.d.copy ? "Copy to " : "Move to ") + ghost.d.target.name + " · hold Ctrl to copy"
						font.pixelSize: Theme.fontCaption
						font.bold: true
						color: Theme.glassTextPrimary
					}
				}
			}

			// The platform's drag, for drops in other windows.
			Item {
				id: dragProxy

				Drag.dragType: Drag.Automatic
				Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
				Drag.proposedAction: Qt.CopyAction
				Drag.onDragFinished: root.drag = null
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

			// The copy in flight: the design's card, docked bottom right over
			// the list, with the file, the count, a track and Cancel.
			GlassPanel {
				id: transferCard

				anchors {
					right: parent.right
					bottom: parent.bottom
					rightMargin: 16
					bottomMargin: Theme.filesFooterHeight + (root.transfer !== null ? 16 : 8)
				}

				width: Math.min(300, body.width - 32)
				height: transferColumn.implicitHeight + 28
				radius: 20
				shadowLayers: 8
				visible: opacity > 0.01
				opacity: root.transfer !== null ? 1 : 0

				Behavior on opacity {
					NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
				}
				Behavior on anchors.bottomMargin {
					NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
				}

				Column {
					id: transferColumn

					anchors {
						left: parent.left
						right: parent.right
						top: parent.top
						margins: 14
					}

					spacing: 10

					Row {
						width: parent.width
						spacing: 10

						Lens {
							id: transferDisc

							anchors.verticalCenter: parent.verticalCenter
							width: 36
							height: 36
							sheen: false

							FileGlyph {
								anchors.centerIn: parent
								kind: "downloads"
							}
						}

						Column {
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width - transferDisc.width - 10
							spacing: 2

							Text {
								width: parent.width
								elide: Text.ElideRight
								text: root.transfer === null ? ""
									: (root.transfer.op === "copy" ? "Copying " : "Moving ")
										+ root.things(root.transfer.count) + " to " + root.nameOf(root.transfer.to)
								font.pixelSize: Theme.fontTitle
								font.bold: true
								color: Theme.glassTextPrimary
							}

							Text {
								width: parent.width
								elide: Text.ElideRight
								text: root.transfer === null ? ""
									: (root.transfer.file !== "" ? root.transfer.file + " · " : "")
										+ (root.transfer.index + 1) + " of " + root.transfer.count
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.75
								color: Theme.glassTextPrimary
							}
						}
					}

					// The track: 6px, the done part white.
					Rectangle {
						width: parent.width
						height: 6
						radius: 3
						color: Theme.glassControlHover

						Rectangle {
							width: root.transfer !== null && root.transfer.total > 0
								? parent.width * root.transfer.done / root.transfer.total : 0
							height: parent.height
							radius: 3
							color: Theme.glassTextPrimary

							Behavior on width {
								NumberAnimation { duration: 120 }
							}
						}
					}

					Item {
						width: parent.width
						height: cancelChip.height

						Text {
							anchors {
								left: parent.left
								right: cancelChip.left
								rightMargin: 10
								verticalCenter: parent.verticalCenter
							}

							elide: Text.ElideRight
							text: root.transfer === null ? ""
								: root.size(root.transfer.done) + " of " + root.size(root.transfer.total)
									+ (root.transferEta !== "" ? " · " + root.transferEta : "")
							font.pixelSize: Theme.fontCaption
							font.weight: Font.DemiBold
							opacity: 0.75
							color: Theme.glassTextPrimary
						}

						DialogButton {
							id: cancelChip

							anchors.right: parent.right
							text: "Cancel"
							onClicked: root.cancelTransfer()
						}
					}
				}
			}

			// Properties: what the file system knows, as label and value rows.
			// It asks nothing, so no footer; the X in its header is the way out.
			GlassDialog {
				id: propsSheet

				anchors.fill: parent
				dense: true
				open: root.props !== null
				visible: open || sheet.opacity > 0.01
				sheetWidth: Math.min(Theme.dialogWidthPrompt, body.width - 40)

				Item {
					width: parent.width
					height: 44

					Lens {
						id: propsDisc

						anchors.verticalCenter: parent.verticalCenter
						width: 44
						height: 44
						sheen: false

						FileGlyph {
							anchors.centerIn: parent
							kind: root.props?.entry?.folder ? "folder" : "file"
							zoom: 1.3
						}
					}

					Column {
						anchors {
							left: propsDisc.right
							right: propsClose.left
							leftMargin: Theme.spacingM
							rightMargin: Theme.spacingM
							verticalCenter: parent.verticalCenter
						}

						spacing: 2

						Text {
							width: parent.width
							elide: Text.ElideRight
							text: root.props?.entry?.name ?? ""
							font.pixelSize: Theme.fontLead
							font.bold: true
							color: Theme.glassTextPrimary
						}

						Text {
							width: parent.width
							elide: Text.ElideRight
							text: root.props === null ? "" : root.props.entry.folder ? "Folder" : (root.props.type || "File")
							font.pixelSize: Theme.fontBody
							opacity: 0.75
							color: Theme.glassTextPrimary
						}
					}

					DiscButton {
						id: propsClose

						anchors {
							right: parent.right
							verticalCenter: parent.verticalCenter
						}

						onClicked: root.props = null
					}
				}

				Column {
					width: parent.width
					spacing: Theme.spacingS

					Repeater {
						model: {
							const p = root.props;
							if (p === null)
								return [];
							const rows = [];
							rows.push(["Size", !p.ready && p.entry.folder ? "…"
								: root.size(p.size) + (p.entry.folder && p.count >= 0 ? " · " + root.things(p.count) : "")]);
							rows.push(["Where", root.tilde(root.parentOf(p.entry.path))]);
							rows.push(["Modified", root.when(p.modified, "exact")]);
							if (p.accessed)
								rows.push(["Accessed", root.when(p.accessed, "exact")]);
							if (p.perms !== "")
								rows.push(["Permissions", p.perms]);
							if (p.owner !== "")
								rows.push(["Owner", p.owner + (p.group && p.group !== p.owner ? " · " + p.group : "")]);
							return rows;
						}

						Item {
							required property var modelData

							width: parent.width
							height: 24

							Text {
								anchors {
									left: parent.left
									leftMargin: 6
									verticalCenter: parent.verticalCenter
								}

								text: modelData[0]
								font.pixelSize: Theme.fontBody
								font.bold: true
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							Text {
								anchors {
									left: parent.left
									right: parent.right
									leftMargin: 120
									rightMargin: 6
									verticalCenter: parent.verticalCenter
								}

								elide: Text.ElideMiddle
								text: modelData[1]
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								color: Theme.glassTextPrimary
							}
						}
					}
				}
			}

			// "Open with": the installed applications, those that claim the
			// type first, and a switch to make the pick the default.
			GlassDialog {
				id: openerSheet

				anchors.fill: parent
				dense: true
				open: root.opener !== null
				visible: open || sheet.opacity > 0.01
				sheetWidth: Math.min(Theme.dialogWidthPrompt, body.width - 40)
				title: root.opener !== null ? `Open “${root.opener.entry.name}” with` : ""
				body: root.opener === null ? ""
					: root.opener.defaultId !== ""
						? `A ${root.opener.type} file. ${DesktopEntries.byId(root.opener.defaultId)?.name ?? root.opener.defaultId} opens these unless you choose otherwise.`
						: root.openerApps.some(app => app.suggested)
							? `A ${root.opener.type} file. Nothing is set to open these yet; these look like a fit.`
							: `A ${root.opener.type} file. Nothing is set to open these yet.`

				icon: Lens {
					width: 44
					height: 44
					sheen: false

					FileGlyph {
						anchors.centerIn: parent
						kind: root.opener !== null && root.opener.entry.folder ? "folder" : "file"
						zoom: 1.3
					}
				}

				ListView {
					id: openerList

					width: parent.width
					// Up to five rows, plus the headings among them.
					readonly property int shown: Math.min(5, Math.max(1, root.openerApps.length))
					readonly property int headings: root.openerApps.slice(0, shown).some(a => a.suggested)
						&& root.openerApps.slice(0, shown).some(a => !a.suggested) ? 2 : 1

					height: shown * 48 + (shown - 1) * 4 + headings * 20
					clip: true
					spacing: 4
					model: root.openerApps
					boundsBehavior: Flickable.StopAtBounds

					// Nothing installed takes a file at all: say so, rather than
					// showing an empty list with a dead Open.
					Text {
						anchors.centerIn: parent
						width: parent.width - 20
						visible: root.openerApps.length === 0
						horizontalAlignment: Text.AlignHCenter
						wrapMode: Text.WordWrap
						text: "No installed application can open files. Install one and it will be listed here."
						font.pixelSize: Theme.fontTitle
						font.weight: Font.DemiBold
						opacity: 0.6
						color: Theme.glassTextPrimary
					}

					delegate: Item {
						id: appRow

						required property var modelData
						required property int index

						readonly property bool chosen: root.opener !== null && root.opener.index === index
						readonly property bool labelled: index === 0
							|| (!modelData.suggested && root.openerApps[index - 1].suggested)
						readonly property string iconFile: Quickshell.iconPath(modelData.entry.icon, true)
						readonly property bool isDefault: root.opener !== null && root.opener.defaultId === modelData.entry.id

						width: openerList.width
						height: 48 + (labelled ? 20 : 0)

						Text {
							x: 10
							visible: appRow.labelled
							text: appRow.modelData.suggested ? "SUGGESTED" : "ALL APPLICATIONS"
							font.pixelSize: Theme.fontCaption
							font.bold: true
							font.letterSpacing: 0.66
							opacity: 0.6
							color: Theme.glassTextPrimary
						}

						Rectangle {
							anchors.bottom: parent.bottom
							width: parent.width
							height: 48
							radius: Theme.radiusRow
							color: appRow.chosen ? Theme.glassChipActive
								: appMouse.containsMouse ? Theme.glassControlHover : "transparent"
							border.width: appRow.chosen ? 1 : 0
							border.color: Theme.glassTrackBorderFocus

							Row {
								anchors {
									left: parent.left
									right: parent.right
									leftMargin: Theme.spacingM
									rightMargin: Theme.spacingM
									verticalCenter: parent.verticalCenter
								}

								spacing: Theme.spacingM

								Lens {
									id: appDisc

									anchors.verticalCenter: parent.verticalCenter
									width: 30
									height: 30
									sheen: false

									Image {
										anchors.centerIn: parent
										width: parent.width * 0.72
										height: width
										visible: appRow.iconFile !== ""
										source: appRow.iconFile
										sourceSize: Qt.size(64, 64)
										fillMode: Image.PreserveAspectFit
										smooth: true
									}

									Text {
										anchors.centerIn: parent
										visible: appRow.iconFile === ""
										text: appRow.modelData.entry.name.slice(0, 1).toUpperCase()
										font.pixelSize: 12
										font.weight: Font.Black
										color: Theme.fileInk
									}
								}

								Column {
									anchors.verticalCenter: parent.verticalCenter
									width: parent.width - appDisc.width - Theme.spacingM
										- (appRow.isDefault ? defaultChip.width + Theme.spacingM : 0)
									spacing: 2

									Text {
										width: parent.width
										elide: Text.ElideRight
										text: appRow.modelData.entry.name
										font.pixelSize: Theme.fontLead
										font.weight: appRow.chosen ? Font.Bold : Font.DemiBold
										color: Theme.glassTextPrimary
									}

									Text {
										width: parent.width
										elide: Text.ElideRight
										visible: text !== ""
										text: appRow.modelData.entry.genericName || appRow.modelData.entry.comment || ""
										font.pixelSize: Theme.fontBody
										font.weight: Font.DemiBold
										opacity: 0.6
										color: Theme.glassTextPrimary
									}
								}
							}

							// The application the desktop already opens these with.
							Chip {
								id: defaultChip

								anchors {
									right: parent.right
									rightMargin: Theme.spacingM
									verticalCenter: parent.verticalCenter
								}

								visible: appRow.isDefault
								text: "Default"
								active: true
							}

							MouseArea {
								id: appMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: root.opener = Object.assign({}, root.opener, { index: appRow.index })
								onDoubleClicked: { root.opener = Object.assign({}, root.opener, { index: appRow.index }); root.runOpener(); }
							}
						}
					}
				}

				Item {
					width: parent.width
					height: Theme.chipHeight

					Row {
						anchors {
							left: parent.left
							verticalCenter: parent.verticalCenter
						}

						spacing: Theme.spacingS

						Switch {
							anchors.verticalCenter: parent.verticalCenter
							checked: root.opener?.always ?? false
							onToggled: root.opener = Object.assign({}, root.opener, { always: !root.opener.always })
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter
							text: "Always, for this type"
							font.pixelSize: Theme.fontBody
							font.weight: Font.DemiBold
							color: Theme.glassTextPrimary
						}
					}

					Row {
						anchors {
							right: parent.right
							verticalCenter: parent.verticalCenter
						}

						spacing: Theme.spacingS

						DialogButton {
							text: "Cancel"
							onClicked: root.opener = null
						}

						DialogButton {
							text: "Open"
							variant: "primary"
							enabled: root.openerApps.length > 0
							onClicked: root.runOpener()
						}
					}
				}
			}

			// A name already taken: the design's sheet, with the two things
			// side by side and three ways out.
			GlassDialog {
				id: conflictSheet

				anchors.fill: parent
				dense: true
				open: root.conflict !== null
				visible: open || sheet.opacity > 0.01
				sheetWidth: Math.min(360, body.width - 40)
				title: root.conflict !== null ? `“${root.conflict.name}” already exists here` : ""
				body: root.conflict !== null
					? `${root.nameOf(root.transfer?.to ?? root.path)} already has ${root.conflict.existing.folder ? "a folder" : "a file"} with this name. Choose which one to keep.`
					: ""

				icon: Lens {
					width: 44
					height: 44
					sheen: false

					FileGlyph {
						anchors.centerIn: parent
						kind: root.conflict !== null && root.conflict.existing.folder ? "folder" : "file"
						zoom: 1.3
						color: Theme.calcInk
					}
				}

				Column {
					width: parent.width
					spacing: 6

					Repeater {
						model: root.conflict === null ? [] : [
							{ label: "In " + root.nameOf(root.transfer?.to ?? root.path), info: root.conflict.existing, newer: root.conflict.existing.modified >= root.conflict.incoming.modified },
							{ label: "Incoming", info: root.conflict.incoming, newer: root.conflict.incoming.modified > root.conflict.existing.modified }
						]

						Rectangle {
							id: option

							required property var modelData

							width: parent.width
							height: 44
							radius: 14
							color: modelData.newer ? Theme.glassChipActive : Theme.glassChip
							border.width: 1
							border.color: modelData.newer ? Theme.glassTrackBorderFocus : Theme.glassControlBorder

							Row {
								anchors {
									left: parent.left
									right: parent.right
									leftMargin: 10
									rightMargin: 10
									verticalCenter: parent.verticalCenter
								}

								spacing: 10

								Lens {
									anchors.verticalCenter: parent.verticalCenter
									width: 28
									height: 28
									sheen: false

									FileGlyph {
										anchors.centerIn: parent
										kind: option.modelData.info.folder ? "folder" : "file"
									}
								}

								Column {
									anchors.verticalCenter: parent.verticalCenter
									spacing: 1

									Text {
										text: option.modelData.label + (option.modelData.newer ? " · newer" : "")
										font.pixelSize: Theme.fontBody
										font.bold: true
										color: Theme.glassTextPrimary
									}

									Text {
										text: root.size(option.modelData.info.size)
											+ (option.modelData.info.modified ? " · " + root.when(option.modelData.info.modified, "exact") : "")
										font.pixelSize: Theme.fontCaption
										font.weight: Font.DemiBold
										opacity: 0.7
										color: Theme.glassTextPrimary
									}
								}
							}
						}
					}
				}

				Item {
					width: parent.width
					height: 24
					visible: (root.conflict?.remaining ?? 0) > 0

					Text {
						anchors {
							left: parent.left
							leftMargin: 2
							verticalCenter: parent.verticalCenter
						}

						text: `Apply to all remaining (${root.conflict?.remaining ?? 0})`
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						color: Theme.glassTextPrimary
					}

					Switch {
						anchors {
							right: parent.right
							verticalCenter: parent.verticalCenter
						}

						checked: root.applyAll
						onToggled: root.applyAll = !root.applyAll
					}
				}

				Row {
					width: parent.width
					spacing: Theme.spacingS

					Repeater {
						model: [["Skip", "secondary", "skip"], ["Keep both", "primary", "keep"], ["Replace", "destructive", "replace"]]

						DialogButton {
							required property var modelData

							width: (parent.width - Theme.spacingS * 2) / 3
							text: modelData[0]
							variant: modelData[1]
							onClicked: root.answerConflict(modelData[2])
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
				dense: true
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
