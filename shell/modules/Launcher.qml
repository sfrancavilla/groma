import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// The application launcher: type, pick, Enter. The design's turn 9.
//
// Native rather than a separate program for the reason everything else here
// is: it is a surface in the same shell, drawn with the same glass, driven by
// the same IPC, and it costs nothing when it is closed. The applications come
// from Quickshell's DesktopEntries, which reads the .desktop files and knows
// how to run them - this file only has to decide what to show and in what
// order.
//
// What you type is recognised rather than declared. Arithmetic gets a result
// card; a word that is a program on PATH gets a Run card; applications are
// searched regardless, and an application that matches by name stays on top
// with the card beneath it - "code" is both. The design's prefixes remain as
// overrides for when recognition would guess wrong: "=" forces a calculation,
// ">" a command. The chip on the track says which was recognised.
//
// The sheet hangs from a fifth of the way down the screen rather than sitting
// in the middle, so a result list that changes length grows downward and the
// sheet never jumps.
Scope {
	id: root

	property bool open: false

	// The clipboard history service, for ":".
	property var clipboard: null

	// The pick is held by key, not by row: the list re-sorts on every
	// keystroke. Keys look like "app:chromium", "run:hyprctl reload", "calc".
	property string picked: ""

	readonly property string query: searchField.text
	readonly property string term: root.query.trim().toLowerCase()

	// --- actions on an application -------------------------------------------
	//
	// Tab on an application opens what can be done with it besides opening
	// it: the actions its .desktop file declares - a private window, an empty
	// window - and then Groma's own. They replace the list; Esc or Tab brings
	// the list back. The sheet stays, because the answer to "what else can I
	// do with this" is not "close".
	property var actionsFor: null

	function toggleActions() {
		if (root.actionsFor !== null) {
			root.actionsFor = null;
			root.picked = "";
			return;
		}

		const item = root.current;
		if (item !== null && (item.kind === "app" || item.kind === "file")) {
			root.actionsFor = item.kind === "app" ? item.entry : item.file;
			root.picked = "";
		}
	}

	readonly property var actionItems: {
		const entry = root.actionsFor;
		if (entry === null)
			return [];

		const out = [];

		// A file: open it, open where it is, or take its path.
		if (entry.path !== undefined) {
			out.push({ kind: "action", key: "act:open", label: entry.folder ? "Open folder" : "Open",
				run: () => { root.openFile(entry.path); } });
			out.push({ kind: "action", key: "act:parent", label: "Open containing folder",
				run: () => { root.openFile(entry.parent); } });
			if (root.hasCopy)
				out.push({ kind: "action", key: "act:copy", label: "Copy path",
					run: () => {
						Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", entry.path]);
						root.close();
					} });
			return out;
		}

		for (const action of (entry.actions ?? []))
			out.push({ kind: "action", key: "act:" + action.id, label: action.name,
				run: () => { action.execute(); History.noteLaunch(entry.id); root.close(); } });

		// Only where the entry declares nothing of its own: Chromium's "New
		// Window" and a Groma "Open a new window" beneath it say one thing twice.
		const open = root.windowsFor(entry);
		if (open.length > 0 && out.length === 0)
			out.push({ kind: "action", key: "act:new", label: "Open a new window",
				run: () => { entry.execute(); History.noteLaunch(entry.id); root.close(); } });

		for (const win of open.slice(0, 5))
			out.push({ kind: "action", key: "act:win:" + win.address,
				label: `Switch to window on workspace ${win.workspace}`,
				run: () => { Quickshell.execDetached(["hyprctl", "dispatch",
					`hl.dsp.focus({ window = "address:${win.address}" })`]); root.close(); } });

		out.push({ kind: "action", key: "act:pin",
			label: Settings.isPinned(entry.id) ? "Unpin from launcher" : "Pin to launcher",
			run: () => { Settings.togglePin(entry.id); root.actionsFor = null; root.picked = ""; } });

		return out;
	}

	function show() {
		root.picked = "";
		root.actionsFor = null;
		root.ranLine = "";
		root.ranOutput = "";
		root.ranExit = -1;
		searchField.clear();
		root.open = true;
		list.contentY = 0;
		clients.running = true;
		executables.running = true;
		tools.running = true;
		Qt.callLater(() => searchField.focusInput());
	}

	function close() {
		root.open = false;
		root.picked = "";
	}

	function setSearch(text) {
		searchField.text = text;
	}

	// --- recognising what was typed --------------------------------------

	readonly property bool forcedCalc: root.query.replace(/^\s+/, "").startsWith("=")
	readonly property bool forcedRun: root.query.replace(/^\s+/, "").startsWith(">")
	readonly property bool forcedClip: root.query.replace(/^\s+/, "").startsWith(":")
	readonly property bool forcedFiles: root.query.replace(/^\s+/, "").startsWith("/")
	readonly property bool forced: root.forcedCalc || root.forcedRun || root.forcedClip || root.forcedFiles

	// The text with any prefix taken off.
	readonly property string body: root.forced
		? root.query.replace(/^\s+/, "").slice(1).trim() : root.query.trim()

	onForcedClipChanged: if (root.forcedClip) root.clipboard?.refresh()

	// Digits and operators and nothing else, with at least one of each.
	readonly property bool looksLikeMath:
		/^[\d\s.,+\-*/%^()]+$/.test(root.body) && /\d/.test(root.body)
			&& /[+\-*/%^]/.test(root.body)

	readonly property string firstWord: root.body.split(/\s+/)[0] ?? ""
	readonly property bool looksLikeCommand:
		root.firstWord !== "" && root.onPath[root.firstWord] === true

	readonly property string mode: root.forcedCalc ? "calc"
		: root.forcedRun ? "run"
		: root.forcedClip ? "clip"
		: root.forcedFiles ? "files"
		: root.looksLikeMath ? "calc"
		: root.looksLikeCommand ? "run"
		: "all"

	// Every program on PATH, gathered when the sheet opens: 1,800 names in
	// under thirty milliseconds, so a word can be checked rather than guessed.
	property var onPath: ({})

	Process {
		id: executables

		command: ["bash", "-c", "compgen -c"]

		stdout: StdioCollector {
			onStreamFinished: {
				const found = {};
				for (const name of text.split("\n"))
					if (name !== "")
						found[name] = true;
				root.onPath = found;
			}
		}
	}

	// Optional helpers: a clipboard to copy into, a calculator that knows
	// units. Neither is required; both are used when present.
	property bool hasCopy: false
	property bool hasQalc: false

	Process {
		id: tools

		command: ["bash", "-c", "command -v wl-copy && echo COPY; command -v qalc && echo QALC; command -v fd && echo FD; true"]

		stdout: StdioCollector {
			onStreamFinished: {
				root.hasCopy = text.includes("COPY");
				root.hasQalc = text.includes("QALC");
				root.hasFd = text.includes("FD");
			}
		}
	}

	// --- files -----------------------------------------------------------
	//
	// fd, asked a beat after the typing stops. Under "all" a few files sit
	// beneath the applications, as in the design; "/" gives them the list.
	// fd leaves hidden and ignored paths out on its own, which is what keeps
	// ~/.cache and node_modules from answering every query.
	property bool hasFd: false
	property var files: []

	readonly property string fileTerm:
		(root.mode === "all" && root.body.length >= 2) || (root.forcedFiles && root.body !== "")
			? root.body : ""
	readonly property int fileLimit: root.forcedFiles ? 12 : 4
	readonly property bool searchingFiles: fileDebounce.running || finder.running

	onFileTermChanged: {
		if (root.fileTerm === "") {
			root.files = [];
			finder.running = false;
		} else {
			fileDebounce.restart();
		}
	}

	Timer {
		id: fileDebounce

		interval: 120
		onTriggered: root.findFiles()
	}

	function findFiles() {
		if (!root.hasFd || root.fileTerm === "")
			return;
		finder.running = false;
		// A slash in the term means a path is being described, so match
		// against the whole path rather than the name.
		const flags = root.fileTerm.includes("/") ? "--full-path" : "--max-depth=12";
		finder.command = ["bash", "-c",
			'fd --fixed-strings --ignore-case --absolute-path --color never --max-results 80 "$2" "$1" "$HOME" '
			+ '| while IFS= read -r p; do if [ -d "$p" ]; then printf "d %s\\n" "$p"; else printf "f %s\\n" "$p"; fi; done',
			"fd", root.fileTerm, flags];
		finder.running = true;
	}

	Process {
		id: finder

		stdout: StdioCollector {
			onStreamFinished: root.files = root.rankFiles(text)
		}
	}

	// fd answers in disk order. What was asked for should come first: a name
	// that is the term, then one starting with it, then one containing it;
	// among equals the shallower path, since ~/Documents/x beats a copy six
	// folders down.
	function rankFiles(text) {
		const term = root.fileTerm.toLowerCase();
		return text.split("\n")
			.filter(line => line.length > 2)
			.map(line => {
				// fd writes a folder with a slash after it.
				const path = line.slice(2).replace(/\/$/, "");
				const cut = path.lastIndexOf("/");
				const name = path.slice(cut + 1);
				const lower = name.toLowerCase();
				return {
					path: path,
					name: name,
					parent: cut === 0 ? "/" : path.slice(0, cut),
					folder: line.startsWith("d "),
					rank: lower === term ? 4 : lower.startsWith(term) ? 3 : lower.includes(term) ? 2 : 1,
					depth: path.split("/").length
				};
			})
			.sort((a, b) => b.rank - a.rank || a.depth - b.depth || a.name.localeCompare(b.name));
	}

	// ~ for the home directory, as the design writes it.
	function tilde(path) {
		const home = Quickshell.env("HOME");
		return home && path.startsWith(home) ? "~" + path.slice(home.length) : path;
	}

	// --- arithmetic --------------------------------------------------------
	//
	// A real parser, not eval(): + - * / % ^, brackets, unary minus, and a
	// comma as a thousands separator. Anything else is not arithmetic and the
	// card does not appear.
	function evaluate(text) {
		const src = text.replace(/,/g, "").replace(/\s+/g, "");
		const tokens = src.match(/\d+(\.\d+)?|[-+*/%^()]/g);
		if (!tokens || tokens.join("") !== src)
			return NaN;

		const out = [], ops = [];
		const prec = { "+": 1, "-": 1, "*": 2, "/": 2, "%": 2, "^": 3, "neg": 4 };
		const rightAssoc = { "^": true, "neg": true };
		let expectOperand = true;

		const apply = op => {
			if (op === "neg") { out.push(-out.pop()); return; }
			const b = out.pop(), a = out.pop();
			switch (op) {
			case "+": out.push(a + b); break;
			case "-": out.push(a - b); break;
			case "*": out.push(a * b); break;
			case "/": out.push(a / b); break;
			case "%": out.push(a % b); break;
			case "^": out.push(Math.pow(a, b)); break;
			}
		};

		for (const tok of tokens) {
			if (/^\d/.test(tok)) {
				out.push(parseFloat(tok)); expectOperand = false;
			} else if (tok === "(") {
				ops.push(tok); expectOperand = true;
			} else if (tok === ")") {
				while (ops.length && ops[ops.length - 1] !== "(") apply(ops.pop());
				if (!ops.length) return NaN;
				ops.pop(); expectOperand = false;
			} else {
				const op = tok === "-" && expectOperand ? "neg" : tok;
				if (op !== "neg" && expectOperand) return NaN;
				while (ops.length) {
					const top = ops[ops.length - 1];
					if (top === "(") break;
					if (prec[top] > prec[op] || (prec[top] === prec[op] && !rightAssoc[op]))
						apply(ops.pop());
					else
						break;
				}
				ops.push(op); expectOperand = true;
			}
		}
		while (ops.length) {
			const op = ops.pop();
			if (op === "(") return NaN;
			apply(op);
		}
		return out.length === 1 && expectOperand === false ? out[0] : NaN;
	}

	readonly property real result: root.mode === "calc" ? root.evaluate(root.body) : NaN
	readonly property bool hasResult: !isNaN(root.result) && isFinite(root.result)

	function pretty(n) {
		const s = Number(n.toPrecision(12)).toString();
		return s.includes("e") ? s : s.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "");
	}

	// --- applications ------------------------------------------------------

	readonly property var apps: DesktopEntries.applications.values
		.filter(entry => !entry.noDisplay)

	// A match is worth more the earlier and the tighter it is: the name's
	// start, then a word's start, then anywhere in the name, then the letters
	// in order with gaps, then the description. Ties go alphabetically, so the
	// order is the same every time for the same letters.
	function score(entry, term) {
		const name = entry.name.toLowerCase();

		if (name.startsWith(term))
			return 5;
		if (name.split(/[\s-]+/).some(word => word.startsWith(term)))
			return 4;
		if (name.includes(term))
			return 3;

		// Letters in order with gaps - "chr" finding Chromium - but not for
		// one or two letters, which are in order in almost everything.
		if (term.length >= 3) {
			let at = 0;
			for (const ch of term) {
				at = name.indexOf(ch, at);
				if (at < 0)
					break;
				at += 1;
			}
			if (at > 0)
				return 2;
		}

		// The description, by the starts of its words and never by its
		// filler: "fo" is inside "for", which is inside almost every sentence
		// anyone writes about a program.
		if (term.length >= 3) {
			const words = [entry.genericName, entry.comment,
				...(entry.keywords ?? [])].join(" ").toLowerCase()
				.split(/[^a-z0-9]+/)
				.filter(word => word !== "" && !root.filler.includes(word));
			if (words.some(word => word.startsWith(term)))
				return 1;
		}

		return 0;
	}

	readonly property var filler: ["for", "the", "and", "with", "your", "from",
		"that", "this", "into", "over", "you", "are", "all", "any", "can"]

	// Forced modes search nothing; recognised ones still do.
	readonly property var matches: {
		if (root.term === "" || root.forced)
			return [];

		const term = root.body.toLowerCase();

		// The rank decides the order; within a rank, what you launch most
		// rises. The weight is bounded below one so it never crosses a rank.
		// The weight only orders what already matched: added to zero it
		// would make anything ever launched match everything.
		return root.apps
			.map(entry => {
				const base = root.score(entry, term);
				return { entry: entry, score: base > 0 ? base + History.weight(entry.id) : 0 };
			})
			.filter(item => item.score > 0)
			.sort((a, b) => b.score - a.score
				|| a.entry.name.localeCompare(b.entry.name))
			.map(item => item.entry);
	}

	// An application matching by its name outranks a card; one matching only
	// by description does not.
	readonly property bool appOnTop: root.matches.length > 0
		&& root.score(root.matches[0], root.body.toLowerCase()) >= 3

	readonly property int recentLimit: 5

	readonly property var pinned: (Settings.pinnedApps ?? [])
		.map(id => DesktopEntries.byId(id))
		.filter(entry => entry !== null && !entry.noDisplay)

	readonly property var recent: History.recent(root.recentLimit + root.pinned.length)
		.map(id => DesktopEntries.byId(id))
		.filter(entry => entry !== null && !entry.noDisplay
			&& !root.pinned.some(pin => pin.id === entry.id))
		.slice(0, root.recentLimit)

	readonly property var everything: root.apps.slice()
		.sort((a, b) => a.name.localeCompare(b.name))

	// --- the list, as items of several kinds -------------------------------
	//
	// { kind: "app", entry }   { kind: "calc" }   { kind: "run", line }
	// { kind: "history", line }   { kind: "clip", id, preview }   { kind: "file", file }
	readonly property var items: {
		const out = [];
		const term = root.term;
		const fileItems = root.files.slice(0, root.fileLimit)
			.map(file => ({ kind: "file", key: "file:" + file.path, file: file }));

		if (root.forcedFiles)
			return fileItems;

		if (root.forcedClip) {
			const needle = root.body.toLowerCase();
			for (const entry of (root.clipboard?.entries ?? []))
				if (needle === "" || entry.preview.toLowerCase().includes(needle))
					out.push({ kind: "clip", key: "clip:" + entry.id, id: entry.id, preview: entry.preview });
			return out;
		}

		if (term === "") {
			for (const entry of root.everything)
				if (!root.recent.some(seen => seen.id === entry.id)
						&& !root.pinned.some(pin => pin.id === entry.id))
					out.push({ kind: "app", entry: entry, key: "app:" + entry.id });
			return out;
		}

		const card = root.mode === "calc" && root.hasResult ? { kind: "calc", key: "calc" }
			: root.mode === "run" && root.body !== "" ? { kind: "run", line: root.body, key: "run:" + root.body }
			: null;

		const appsFirst = root.appOnTop || card === null;
		const appItems = root.matches.map(entry => ({ kind: "app", entry: entry, key: "app:" + entry.id }));

		if (appsFirst) out.push(...appItems);
		if (card) out.push(card);
		if (!appsFirst) out.push(...appItems);

		if (root.mode === "all")
			out.push(...fileItems);

		if (root.mode === "run" && root.ranLine !== "" && root.ranLine === root.body)
			out.push({ kind: "output", key: "output" });

		if (root.mode === "run")
			for (const line of History.recentCommands(6))
				if (line !== root.body)
					out.push({ kind: "history", line: line, key: "hist:" + line });

		return out;
	}

	// Everything on screen in the order it is drawn - tiles first - so the
	// arrow keys walk what is there. The field owns left and right for its
	// caret, so the tiles are walked with up and down like the rows.
	readonly property var ordered: root.actionsFor !== null ? root.actionItems
		: root.term !== "" ? root.items
		: root.pinned.concat(root.recent)
			.map(entry => ({ kind: "app", entry: entry, key: "app:" + entry.id }))
			.concat(root.items)

	readonly property var current: root.ordered.find(item => item.key === root.picked)
		?? root.ordered[0] ?? null

	function move(step) {
		const entries = root.ordered;
		if (entries.length === 0)
			return;

		const at = entries.findIndex(item => item.key === (root.current?.key ?? ""));
		root.picked = entries[Math.max(0, Math.min(entries.length - 1, at + step))].key;
	}

	// --- acting ------------------------------------------------------------

	// What is already running. Opening an application that has a window is,
	// nine times in ten, a request to be taken to that window - so Enter goes
	// there, to the one used most recently, on whichever workspace it is.
	// Shift+Enter opens a fresh one regardless. The match is by the window
	// class against the entry's id, its StartupWMClass and the name of what it
	// runs - all three, because Chromium's .desktop ships a StartupWMClass
	// that is a literal packaging placeholder.
	property var windows: []

	Process {
		id: clients

		command: ["hyprctl", "clients", "-j"]

		stdout: StdioCollector {
			onStreamFinished: {
				try {
					root.windows = JSON.parse(text).map(win => ({
						cls: String(win.class ?? "").toLowerCase(),
						initial: String(win.initialClass ?? "").toLowerCase(),
						address: win.address,
						workspace: win.workspace?.id ?? 0,
						recency: win.focusHistoryID ?? 999
					}));
				} catch (err) {
					root.windows = [];
				}
			}
		}
	}

	function classesOf(entry) {
		const exec = String(entry.execString ?? "").trim().split(/\s+/)[0] ?? "";
		return [entry.id, entry.startupClass, exec.split("/").pop()]
			.map(name => String(name ?? "").toLowerCase())
			.filter(name => name !== "" && !name.startsWith("@@"));
	}

	function windowsFor(entry) {
		if (!entry)
			return [];

		const names = root.classesOf(entry);
		return root.windows
			.filter(win => names.includes(win.cls) || names.includes(win.initial))
			.sort((a, b) => a.recency - b.recency);
	}

	readonly property var currentWindows:
		root.current?.kind === "app" ? root.windowsFor(root.current.entry) : []

	function act(alternate) {
		const item = root.current;

		if (item === null) {
			if (root.term !== "")
				root.searchWeb();
			return;
		}

		switch (item.kind) {
		case "action":
			item.run();
			return;
		case "clip":
			if (alternate) {
				root.clipboard?.remove(item.id);
				root.clipboard?.refresh();
			} else {
				root.clipboard?.copy(item.id);
				root.close();
			}
			return;
		case "app": {
			const open = alternate ? [] : root.windowsFor(item.entry);
			if (open.length > 0) {
				Quickshell.execDetached(["hyprctl", "dispatch",
					`hl.dsp.focus({ window = "address:${open[0].address}" })`]);
			} else {
				item.entry.execute();
			}
			History.noteLaunch(item.entry.id);
			root.close();
			return;
		}
		case "file":
			root.openFile(alternate ? item.file.parent : item.file.path);
			return;
		case "calc":
			if (root.hasCopy) {
				Quickshell.execDetached(["sh", "-c",
					"printf %s \"$1\" | wl-copy", "sh", root.pretty(root.result)]);
				root.close();
			}
			return;
		case "run":
		case "history":
			root.runCommand(item.line, alternate);
			return;
		case "output":
			root.runCommand(root.ranLine, alternate);
			return;
		}
	}

	// Whatever the desktop associates with it: a folder in the file manager,
	// a document in its editor.
	function openFile(path) {
		Quickshell.execDetached(["xdg-open", path]);
		root.close();
	}

	// In the terminal, with the shell kept open afterwards; or detached, with
	// the output written to a file the sheet watches. A command that finishes
	// silently was an action and the sheet closes; one that prints, or fails,
	// is a question and the answer stays on screen. Detached rather than a
	// child of the shell, so a long-running one survives the sheet closing.
	property string ranLine: ""
	property string ranOutput: ""
	property int ranExit: -1
	readonly property bool ranDone: root.ranExit >= 0

	// Each run stamps the file with a token, and only a file carrying the
	// current token is read. Without it the previous run's "exit:0" was still
	// on disk when the sheet next opened, read as a finished silent action,
	// and the sheet closed itself a third of a second after appearing.
	property string ranToken: ""

	readonly property string outputPath:
		(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/groma-launcher-output"

	function runCommand(line, inTerminal) {
		History.noteCommand(line);

		if (inTerminal) {
			Quickshell.execDetached(["foot", "-e", "sh", "-c", line + '; exec "$SHELL"']);
			root.close();
			return;
		}

		root.ranLine = line;
		root.ranOutput = "";
		root.ranExit = -1;
		root.ranToken = String(Date.now());
		Quickshell.execDetached(["sh", "-c",
			'out="$1"; tok="$2"; shift 2; printf "\\036run:%s\\n" "$tok" > "$out"; '
				+ '(eval "$1") >> "$out" 2>&1; printf "\\n\\036exit:%s\\n" "$?" >> "$out"',
			"sh", root.outputPath, root.ranToken, line]);
		settle.start();
	}

	FileView {
		id: outputFile

		path: root.outputPath
		printErrors: false
		watchChanges: true
		onFileChanged: reload()
		onLoaded: root.readOutput()
	}

	function readOutput() {
		if (root.ranLine === "")
			return;

		let raw = outputFile.text() ?? "";
		const head = "\u001erun:" + root.ranToken + "\n";
		if (!raw.startsWith(head))
			return;
		raw = raw.slice(head.length);

		const mark = raw.lastIndexOf("\u001eexit:");
		if (mark >= 0) {
			root.ranExit = parseInt(raw.slice(mark + 6)) || 0;
			root.ranOutput = raw.slice(0, mark).replace(/\n+$/, "");
		} else {
			root.ranOutput = raw;
		}
		settle.restart();
	}

	// A short grace after the file settles: exit 0 with nothing printed was
	// an action, and the sheet goes.
	Timer {
		id: settle

		interval: 350
		onTriggered: {
			outputFile.reload();
			if (root.ranDone && root.ranExit === 0 && root.ranOutput.trim() === "")
				root.close();
		}
	}

	function searchWeb() {
		Quickshell.execDetached(["xdg-open",
			"https://duckduckgo.com/?q=" + encodeURIComponent(root.query.trim())]);
		root.close();
	}

	// A colour for each application, from its name, so any icon theme - or
	// none - reads as one set. The same name always gets the same hue.
	function hue(name) {
		let h = 0;
		for (const ch of name)
			h = (h * 31 + ch.charCodeAt(0)) % 360;
		return h / 360;
	}

	function tint(name) { return Qt.hsla(root.hue(name), 0.55, 0.62, 1); }
	function ink(name) { return Qt.hsla(root.hue(name), 0.6, 0.30, 1); }

	// What the design puts on the right of a row: the kind of thing it is.
	function kind(entry) {
		const known = ["System", "Settings", "Network", "Utility", "Development",
			"Graphics", "AudioVideo", "Audio", "Video", "Office", "Game", "Education"];
		const found = (entry.categories ?? []).find(cat => known.includes(cat));

		return found === "AudioVideo" ? "Media" : (found ?? entry.genericName ?? "");
	}

	// The name with the matched prefix underlined, as the design draws it -
	// only where the match really is a prefix of the name or of a word.
	function marked(entry) {
		const escape = part => part.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;").replace(/>/g, "&gt;");
		const name = entry.name;
		const lower = name.toLowerCase();
		const term = root.body.toLowerCase();

		let at = -1;
		if (term !== "") {
			if (lower.startsWith(term))
				at = 0;
			else {
				const word = lower.search(new RegExp("(^|[\\s-])"
					+ term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
				if (word >= 0)
					at = lower.indexOf(term, word);
			}
		}

		if (at < 0)
			return escape(name);

		return escape(name.slice(0, at)) + "<u>" + escape(name.slice(at, at + term.length))
			+ "</u>" + escape(name.slice(at + term.length));
	}

	IpcHandler {
		target: "launcher"

		function toggle(): void {
			if (root.open)
				root.close();
			else
				root.show();
		}

		function opened(): void {
			root.show();
		}

		function close(): void {
			root.close();
		}

		function search(text: string): void {
			root.setSearch(text);
		}

		function pin(id: string): void {
			Settings.togglePin(id);
		}

		function actions(id: string): void {
			root.show();
			root.actionsFor = DesktopEntries.byId(id);
		}

		// The path Enter (or Shift+Enter) takes on the highlighted item.
		function pick(alternate: bool): void {
			root.act(alternate);
		}

		// The path Enter takes on a command, for scripts and for testing.
		function run(line: string): void {
			root.show();
			root.setSearch(line);
			root.runCommand(line, false);
		}
	}

	PanelWindow {
		id: window

		visible: root.open || dialog.sheet.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:launcher"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			sheetWidth: Theme.launcherWidth
			padding: Theme.launcherPadding
			spacing: Theme.spacingS + 2
			radius: Theme.launcherRadius
			topFraction: Theme.launcherTop

			Keys.onEscapePressed: root.actionsFor !== null ? root.toggleActions() : root.close()
			Keys.onDownPressed: root.move(1)
			Keys.onUpPressed: root.move(-1)

			// The search track. The lens on the left shows what was
			// recognised - the magnifier, "=" or ">_" - and the chip on the
			// right names it, in the design's amber for a calculation and
			// green for a command. Neither is a button.
			Item {
				width: parent.width
				height: Theme.launcherTrackHeight

				GlassField {
					id: searchField

					anchors.fill: parent
					fontSize: Theme.fontSearch
					placeholder: "Search apps, files, commands…"

					leading: Lens {
						width: 38
						height: 38
						sheen: false

						SearchIcon {
							anchors.centerIn: parent
							visible: root.mode === "all"
							width: 15
							height: 15
							color: Theme.glassOnLens
						}

						Text {
							anchors.centerIn: parent
							visible: root.mode !== "all"
							text: root.mode === "calc" ? "=" : root.mode === "clip" ? "⧉"
								: root.mode === "files" ? "/" : ">_"
							font.pixelSize: root.mode === "calc" ? 20 : root.mode === "clip" ? 17
								: root.mode === "files" ? 19 : 14
							font.family: root.mode === "run" ? "monospace" : label.font.family
							font.weight: Font.Black
							color: root.mode === "calc" ? Theme.calcInk
								: root.mode === "clip" ? Theme.glassOnLens
								: root.mode === "files" ? Theme.fileInk : Theme.runInk
						}
					}

					onAccepted: root.act(false)
					onAcceptedAlternate: root.act(true)
					onTabbed: root.toggleActions()
				}

				Chip {
					anchors {
						right: parent.right
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					text: root.mode === "calc" ? "Calc" : root.mode === "run" ? "Run"
						: root.mode === "clip" ? "Clipboard" : root.mode === "files" ? "Files" : "All"
					active: true
					accent: root.mode === "calc" ? Theme.warning
						: root.mode === "run" ? Theme.success
						: root.mode === "clip" ? Theme.desktopWashB : "transparent"
				}
			}

			// Pinned applications as tiles, when there are any.
			Column {
				width: parent.width
				visible: root.term === "" && root.actionsFor === null && root.pinned.length > 0
				spacing: 6

				Text {
					x: 10
					text: "PINNED"
					font.pixelSize: Theme.fontCaption
					font.bold: true
					font.letterSpacing: 0.66
					opacity: 0.6
					color: Theme.glassTextPrimary
				}

				Row {
					width: parent.width
					spacing: 6

					Repeater {
						model: root.pinned
						delegate: tileDelegate
					}
				}
			}

			// Recent applications as tiles, with the one way to be rid of
			// them beside the label - a secondary action in the header slot.
			Column {
				width: parent.width
				visible: root.term === "" && root.actionsFor === null && root.recent.length > 0
				spacing: 6

				Item {
					width: parent.width
					height: recentLabel.height

					Text {
						id: recentLabel

						x: 10
						text: "RECENT"
						font.pixelSize: Theme.fontCaption
						font.bold: true
						font.letterSpacing: 0.66
						opacity: 0.6
						color: Theme.glassTextPrimary
					}

					Text {
						anchors.right: parent.right
						anchors.rightMargin: 10
						text: "Clear"
						font.pixelSize: Theme.fontCaption
						font.weight: Font.DemiBold
						opacity: clearMouse.containsMouse ? 1.0 : 0.6
						color: Theme.glassTextPrimary

						MouseArea {
							id: clearMouse

							anchors.fill: parent
							anchors.margins: -6
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								History.clear();
								root.picked = "";
							}
						}
					}
				}

				Row {
					width: parent.width
					spacing: 6

					Repeater {
						model: root.recent
						delegate: tileDelegate
					}
				}
			}

			// What can be done with the application Tab was pressed on.
			Column {
				width: parent.width
				visible: root.actionsFor !== null
				spacing: 4

				Text {
					x: 10
					text: (root.actionsFor?.name ?? "").toUpperCase()
					font.pixelSize: Theme.fontCaption
					font.bold: true
					font.letterSpacing: 0.66
					opacity: 0.6
					color: Theme.glassTextPrimary
				}

				Repeater {
					model: root.actionItems

					Rectangle {
						id: actionRow

						required property var modelData

						readonly property bool selected: root.current?.key === modelData.key

						width: parent.width
						height: Theme.launcherRowHeight
						radius: Theme.radiusRow
						color: actionRow.selected ? Theme.glassChipActive
							: actionMouse.containsMouse ? Theme.glassControlHover : "transparent"
						border.width: actionRow.selected ? 1 : 0
						border.color: Theme.glassTrackBorderFocus

						Text {
							anchors {
								left: parent.left
								leftMargin: Theme.spacingL
								verticalCenter: parent.verticalCenter
							}

							text: actionRow.modelData.label
							font.pixelSize: Theme.fontLead
							font.weight: actionRow.selected ? Font.Bold : Font.DemiBold
							color: Theme.glassTextPrimary
						}

						MouseArea {
							id: actionMouse

							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: { root.picked = actionRow.modelData.key; root.act(false); }
						}
					}
				}
			}

			// The rows: applications, a calculation, a command, its history.
			Item {
				width: parent.width
				height: Math.min(8 * (Theme.launcherRowHeight + 4) + 60, list.contentHeight)
				visible: root.items.length > 0 && root.actionsFor === null

				Flickable {
					id: list

					anchors.fill: parent
					clip: true
					contentHeight: rows.implicitHeight
					boundsBehavior: Flickable.StopAtBounds

					Column {
						id: rows

						width: list.width
						spacing: 4

						Repeater {
							model: root.items

							Loader {
								required property var modelData
								required property int index

								width: rows.width

								sourceComponent: modelData.kind === "calc" ? calcCard
									: modelData.kind === "clip" ? clipRow
									: modelData.kind === "file" ? fileRow
									: modelData.kind === "run" ? runCard
									: modelData.kind === "output" ? outputCard
									: modelData.kind === "history" ? historyRow
									: appRow
							}
						}
					}
				}
			}

			// Nothing matched. The web is one Enter away, which is what the
			// footer says.
			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				visible: root.term !== "" && root.items.length === 0 && root.actionsFor === null
				topPadding: 16
				bottomPadding: 8
				text: root.mode === "calc" ? "Not a calculation I can do"
					: root.mode === "clip" && !(root.clipboard?.available ?? false)
						? "Clipboard history needs cliphist and wl-clipboard installed"
					: root.mode === "clip" && root.body === "" ? "Nothing copied yet"
					: root.mode === "clip" ? `Nothing on the clipboard matches “${root.body}”`
					: root.mode === "files" && !root.hasFd ? "File search needs fd installed"
					: root.mode === "files" && root.body === "" ? "Type part of a file name"
					: root.searchingFiles ? "Searching…"
					: root.mode === "files" ? `No file matches “${root.body}”`
					: `Nothing matches “${root.query.trim()}”`
				font.pixelSize: Theme.fontTitle
				font.weight: Font.DemiBold
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			// The footer: the fallback action on the left, the keys on the
			// right. Both are the design's, and both are true.
			Item {
				width: parent.width
				height: 30

				Rectangle {
					anchors.top: parent.top
					width: parent.width
					height: 1
					color: Theme.glassControlBorder
				}

				Text {
					anchors {
						left: parent.left
						leftMargin: 10
						verticalCenter: parent.verticalCenter
						verticalCenterOffset: 4
					}

					visible: root.term !== "" && root.mode === "all"
					text: `Search the web for “${root.query.trim()}”`
					font.pixelSize: Theme.fontBody
					font.weight: Font.DemiBold
					opacity: webMouse.containsMouse ? 1.0 : 0.75
					color: Theme.glassTextPrimary

					MouseArea {
						id: webMouse

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.searchWeb()
					}
				}

				Row {
					anchors {
						right: parent.right
						rightMargin: 10
						verticalCenter: parent.verticalCenter
						verticalCenterOffset: 4
					}

					spacing: 14

					Repeater {
						model: {
							// Only promise what Enter can do: without wl-copy a result
							// can be read but not copied.
							// Nothing to act on: only the way out is true.
							if (root.current === null && root.actionsFor === null)
								return [["Esc", "Close"]];

							const kind = root.current?.kind ?? "app";
							const enter = kind === "calc" ? (root.hasCopy ? "Copy" : null)
								: kind === "clip" ? "Copy"
								: kind === "file" ? "Open"
								: kind === "run" || kind === "history" ? "Run"
								: root.currentWindows.length > 0 ? "Switch" : "Open";
							const rows = [["↑↓", "Move"]];
							if (root.actionsFor !== null) {
								rows.push(["↵", "Do"], ["Esc", "Back"]);
								return rows;
							}
							if (enter) rows.push(["↵", enter]);
							if (kind === "run" || kind === "history") rows.push(["⇧↵", "In terminal"]);
							if (kind === "clip") rows.push(["⇧↵", "Delete"]);
							if (kind === "file") rows.push(["⇧↵", "Folder"]);
							if (kind === "app" || kind === "file") rows.push(["Tab", "Actions"]);
							rows.push(["Esc", "Close"]);
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
								opacity: 0.85
								color: Theme.glassTextPrimary
							}
						}
					}
				}
			}
		}
	}

	// A label with the right font for the lens glyph to borrow.
	Text { id: label; visible: false }

	// --- the tile, for the pinned and recent grids ---------------------------

	Component {
		id: tileDelegate

		Rectangle {
			id: tile

			required property var modelData

			readonly property bool selected: root.current?.key === "app:" + modelData.id
			readonly property string iconFile: Quickshell.iconPath(modelData.icon, true)

			width: (parent.width - (root.recentLimit - 1) * 6) / root.recentLimit
			height: 48 + 8 + 16 + 22
			radius: 18

			color: tile.selected ? Theme.glassChipActive
				: tileMouse.containsMouse ? Theme.glassControlHover
				: "transparent"
			border.width: tile.selected ? 1 : 0
			border.color: Theme.glassTrackBorderFocus

			Behavior on color {
				ColorAnimation { duration: 120 }
			}

			Column {
				anchors.centerIn: parent
				width: parent.width
				spacing: 8

				Lens {
					anchors.horizontalCenter: parent.horizontalCenter
					width: 48
					height: 48
					sheen: false
					tint: root.tint(tile.modelData.name)

					Image {
						anchors.centerIn: parent
						width: parent.width * 0.72
						height: width
						visible: tile.iconFile !== ""
						source: tile.iconFile
						sourceSize: Qt.size(96, 96)
						fillMode: Image.PreserveAspectFit
						smooth: true
					}

					Text {
						anchors.centerIn: parent
						visible: tile.iconFile === ""
						text: tile.modelData.name.slice(0, 1).toUpperCase()
						font.pixelSize: 18
						font.weight: Font.Black
						color: root.ink(tile.modelData.name)
					}
				}

				Text {
					width: parent.width - 12
					anchors.horizontalCenter: parent.horizontalCenter
					horizontalAlignment: Text.AlignHCenter
					elide: Text.ElideRight
					text: tile.modelData.name
					font.pixelSize: Theme.fontBody
					font.weight: tile.selected ? Font.Bold : Font.DemiBold
					color: Theme.glassTextPrimary
				}
			}

			MouseArea {
				id: tileMouse

				anchors.fill: parent
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				onClicked: {
					root.picked = "app:" + tile.modelData.id;
					root.act(false);
				}
			}
		}
	}

	// --- the row kinds -------------------------------------------------------

	// An application: the first match gets the design's card, the rest are
	// bare until pointed at or picked. Labels mark the sections.
	Component {
		id: appRow

		Item {
			id: slot

			readonly property var entry: modelData.entry
			readonly property bool topHit: root.term !== "" && index === 0 && root.appOnTop
			readonly property bool selected: root.current?.key === modelData.key
			readonly property string iconFile: Quickshell.iconPath(entry.icon, true)
			readonly property int running: root.windowsFor(entry).length
			readonly property bool labelled: slot.topHit
				|| (root.term === "" ? index === 0
					: index === (root.appOnTop ? 1 : root.items.findIndex(item => item.kind === "app")))

			height: (slot.topHit ? Theme.launcherTopHitHeight : Theme.launcherRowHeight)
				+ (slot.labelled ? sectionLabel.height + 8 : 0)

			Text {
				id: sectionLabel

				x: 10
				visible: slot.labelled
				text: slot.topHit ? "TOP HIT" : "APPLICATIONS"
				font.pixelSize: Theme.fontCaption
				font.bold: true
				font.letterSpacing: 0.66
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			Rectangle {
				anchors.bottom: parent.bottom
				width: parent.width
				height: slot.topHit ? Theme.launcherTopHitHeight : Theme.launcherRowHeight
				radius: slot.topHit ? 18 : Theme.radiusRow

				color: slot.topHit || slot.selected ? Theme.glassChipActive
					: rowMouse.containsMouse ? Theme.glassControlHover
					: "transparent"
				border.width: slot.topHit || slot.selected ? 1 : 0
				border.color: Theme.glassTrackBorderFocus

				Behavior on color {
					ColorAnimation { duration: 120 }
				}

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
						id: disc

						anchors.verticalCenter: parent.verticalCenter
						width: slot.topHit ? 36 : 30
						height: width
						sheen: false
						tint: root.tint(slot.entry.name)

						Image {
							anchors.centerIn: parent
							width: parent.width * 0.72
							height: width
							visible: slot.iconFile !== ""
							source: slot.iconFile
							sourceSize: Qt.size(64, 64)
							fillMode: Image.PreserveAspectFit
							smooth: true
						}

						Text {
							anchors.centerIn: parent
							visible: slot.iconFile === ""
							text: slot.entry.name.slice(0, 1).toUpperCase()
							font.pixelSize: slot.topHit ? 15 : 12
							font.weight: Font.Black
							color: root.ink(slot.entry.name)
						}
					}

					Column {
						anchors.verticalCenter: parent.verticalCenter
						width: parent.width - disc.width - Theme.spacingM - trailing.width - Theme.spacingM
						spacing: 2

						Text {
							width: parent.width
							elide: Text.ElideRight
							textFormat: Text.RichText
							text: root.marked(slot.entry)
							font.pixelSize: slot.topHit ? 15 : Theme.fontLead
							font.weight: slot.topHit || slot.selected ? Font.Bold : Font.DemiBold
							color: Theme.glassTextPrimary
						}

						Text {
							width: parent.width
							elide: Text.ElideRight
							visible: slot.topHit && text !== ""
							text: ["Application", slot.entry.genericName].filter(part => part).join(" · ")
							font.pixelSize: Theme.fontBody
							font.weight: Font.DemiBold
							opacity: 0.75
							color: Theme.glassTextPrimary
						}
					}

					Row {
						id: trailing

						anchors.verticalCenter: parent.verticalCenter
						spacing: 6

						Rectangle {
							anchors.verticalCenter: parent.verticalCenter
							visible: !slot.topHit && slot.running > 0
							width: 6
							height: 6
							radius: 3
							color: Theme.success
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter
							text: slot.topHit ? (slot.running > 0 ? "Switch" : "Open") : root.kind(slot.entry)
							font.pixelSize: Theme.fontBody
							font.weight: Font.DemiBold
							opacity: slot.topHit ? 0.9 : 0.6
							color: Theme.glassTextPrimary
						}

						KeyCap { anchors.verticalCenter: parent.verticalCenter; visible: slot.topHit; text: "↵" }

						Text {
							anchors.verticalCenter: parent.verticalCenter
							visible: slot.topHit && slot.running > 0
							text: "New"
							font.pixelSize: Theme.fontBody
							font.weight: Font.DemiBold
							opacity: 0.7
							color: Theme.glassTextPrimary
						}

						KeyCap { anchors.verticalCenter: parent.verticalCenter; visible: slot.topHit && slot.running > 0; text: "⇧↵" }
					}
				}

				MouseArea {
					id: rowMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: {
						root.picked = modelData.key;
						root.act(false);
					}
				}
			}
		}
	}

	// The design's 9c: the result large, "Copy" on the right, and beneath it
	// the same number in other clothes.
	Component {
		id: calcCard

		Column {
			spacing: 6

			readonly property bool selected: root.current?.key === "calc"

			Text {
				x: 10
				text: "RESULT"
				font.pixelSize: Theme.fontCaption
				font.bold: true
				font.letterSpacing: 0.66
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			Rectangle {
				width: parent.width
				height: 82
				radius: 20
				color: Theme.glassChipActive
				border.width: 1
				border.color: Theme.glassTrackBorderFocus

				Column {
					anchors {
						left: parent.left
						leftMargin: 18
						verticalCenter: parent.verticalCenter
					}

					spacing: 4

					Text {
						text: root.body
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						opacity: 0.75
						color: Theme.glassTextPrimary
					}

					Text {
						text: root.pretty(root.result)
						font.pixelSize: 40
						font.bold: true
						font.letterSpacing: -0.4
						color: Theme.glassTextPrimary
					}
				}

				Row {
					anchors {
						right: parent.right
						rightMargin: 18
						verticalCenter: parent.verticalCenter
					}

					spacing: 6
					visible: root.hasCopy

					Text {
						anchors.verticalCenter: parent.verticalCenter
						text: "Copy"
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						opacity: 0.9
						color: Theme.glassTextPrimary
					}

					KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "↵" }
				}
			}

			Row {
				width: parent.width
				spacing: 6

				Repeater {
					model: {
						const n = root.result, out = [];
						if (Number.isInteger(n) && n >= 0) out.push("Hex 0x" + n.toString(16).toUpperCase());
						out.push(root.pretty(n) + " px → " + root.pretty(n / 16) + " rem");
						if (Number.isInteger(n) && n >= 0) out.push("Binary " + n.toString(2));
						return out;
					}

					Chip {
						required property string modelData

						width: (parent.width - 12) / 3
						text: modelData
					}
				}
			}
		}
	}

	// The design's 9d: the command, monospace, "Run" and "In terminal".
	Component {
		id: runCard

		Column {
			spacing: 6

			Text {
				x: 10
				text: "COMMAND"
				font.pixelSize: Theme.fontCaption
				font.bold: true
				font.letterSpacing: 0.66
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			Rectangle {
				width: parent.width
				height: 52
				radius: 18
				color: root.current?.key === modelData.key ? Theme.glassChipActive : Theme.glassControl
				border.width: 1
				border.color: root.current?.key === modelData.key ? Theme.glassTrackBorderFocus : Theme.glassControlBorder

				Text {
					anchors {
						left: parent.left
						right: runKeys.left
						leftMargin: 14
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					elide: Text.ElideMiddle
					text: modelData.line
					font.pixelSize: Theme.fontLead
					font.family: "monospace"
					font.weight: Font.DemiBold
					color: Theme.glassTextPrimary
				}

				Row {
					id: runKeys

					anchors {
						right: parent.right
						rightMargin: 14
						verticalCenter: parent.verticalCenter
					}

					spacing: 12

					Row {
						spacing: 6
						Text { anchors.verticalCenter: parent.verticalCenter; text: "Run"; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold; opacity: 0.9; color: Theme.glassTextPrimary }
						KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "↵" }
					}

					Row {
						spacing: 6
						Text { anchors.verticalCenter: parent.verticalCenter; text: "In terminal"; font.pixelSize: Theme.fontBody; font.weight: Font.DemiBold; opacity: 0.8; color: Theme.glassTextPrimary }
						KeyCap { anchors.verticalCenter: parent.verticalCenter; text: "⇧↵" }
					}
				}

				MouseArea {
					anchors.fill: parent
					cursorShape: Qt.PointingHandCursor
					onClicked: { root.picked = modelData.key; root.act(false); }
				}
			}
		}
	}

	// What the command printed, and how it ended. Twelve lines, then a count
	// and the way to see the rest.
	Component {
		id: outputCard

		Column {
			spacing: 6

			readonly property var lines: root.ranOutput === "" ? [] : root.ranOutput.split("\n")
			readonly property int shown: Math.min(12, lines.length)

			Item {
				width: parent.width
				height: outputLabel.height

				Text {
					id: outputLabel

					x: 10
					text: "OUTPUT"
					font.pixelSize: Theme.fontCaption
					font.bold: true
					font.letterSpacing: 0.66
					opacity: 0.6
					color: Theme.glassTextPrimary
				}

				Text {
					anchors.right: parent.right
					anchors.rightMargin: 10
					text: !root.ranDone ? "Running…"
						: root.ranExit === 0 ? "Done" : `Exit ${root.ranExit}`
					font.pixelSize: Theme.fontCaption
					font.weight: Font.DemiBold
					opacity: 0.8
					color: root.ranDone && root.ranExit !== 0 ? Theme.warning : Theme.glassTextPrimary
				}
			}

			Rectangle {
				width: parent.width
				height: body.implicitHeight + 24
				radius: 16
				color: Theme.glassControl
				border.width: 1
				border.color: Theme.glassControlBorder

				Text {
					id: body

					anchors {
						left: parent.left
						right: parent.right
						top: parent.top
						margins: 12
						leftMargin: 14
						rightMargin: 14
					}

					text: (lines.slice(0, shown).join("\n") || (root.ranDone ? "(no output)" : ""))
						+ (lines.length > shown
							? `\n… ${lines.length - shown} more lines · ⇧↵ to see them in a terminal` : "")
					wrapMode: Text.NoWrap
					elide: Text.ElideRight
					font.pixelSize: Theme.fontTitle
					font.family: "monospace"
					lineHeight: 1.3
					color: Theme.glassTextPrimary
					opacity: lines.length === 0 ? 0.6 : 1
				}
			}
		}
	}

	// Something copied earlier. One line of it; Enter puts it back, Shift+Enter
	// forgets it. cliphist describes binary entries itself.
	// A file or folder: the design's plain lens with an outline in it, the
	// name, and where it lives.
	Component {
		id: fileRow

		Item {
			id: fileSlot

			readonly property var file: modelData.file
			readonly property bool selected: root.current?.key === modelData.key
			readonly property bool labelled: index === root.items.findIndex(item => item.kind === "file")

			height: Theme.launcherRowHeight + (labelled ? fileLabel.height + 8 : 0)

			Text {
				id: fileLabel

				x: 10
				visible: fileSlot.labelled
				text: "FILES"
				font.pixelSize: Theme.fontCaption
				font.bold: true
				font.letterSpacing: 0.66
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			Rectangle {
				anchors.bottom: parent.bottom
				width: parent.width
				height: Theme.launcherRowHeight
				radius: Theme.radiusRow
				color: fileSlot.selected ? Theme.glassChipActive
					: fileMouse.containsMouse ? Theme.glassControlHover : "transparent"
				border.width: fileSlot.selected ? 1 : 0
				border.color: Theme.glassTrackBorderFocus

				Behavior on color {
					ColorAnimation { duration: 120 }
				}

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
						id: fileDisc

						anchors.verticalCenter: parent.verticalCenter
						width: 30
						height: 30
						sheen: false

						// The design's glyphs: a sheet, or a tray with a rounder base.
						Rectangle {
							anchors.centerIn: parent
							width: fileSlot.file.folder ? 14 : 11
							height: fileSlot.file.folder ? 11 : 14
							radius: 2
							bottomLeftRadius: fileSlot.file.folder ? 3 : 2
							bottomRightRadius: fileSlot.file.folder ? 3 : 2
							color: "transparent"
							border.width: 2
							border.color: Theme.fileInk
						}
					}

					Text {
						anchors.verticalCenter: parent.verticalCenter
						width: parent.width - fileDisc.width - Theme.spacingM - where.width - Theme.spacingM
						elide: Text.ElideRight
						text: fileSlot.file.name
						font.pixelSize: Theme.fontLead
						font.weight: fileSlot.selected ? Font.Bold : Font.DemiBold
						color: Theme.glassTextPrimary
					}

					Text {
						id: where

						anchors.verticalCenter: parent.verticalCenter
						width: Math.min(implicitWidth, fileSlot.width * 0.4)
						elide: Text.ElideLeft
						text: root.tilde(fileSlot.file.parent)
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						opacity: 0.6
						color: Theme.glassTextPrimary
					}
				}

				MouseArea {
					id: fileMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: { root.picked = modelData.key; root.act(false); }
				}
			}
		}
	}

	Component {
		id: clipRow

		Item {
			readonly property bool selected: root.current?.key === modelData.key
			readonly property bool first: index === 0

			height: Theme.launcherRowHeight + (first ? clipLabel.height + 8 : 0)

			Item {
				width: parent.width
				height: clipLabel.height
				visible: first

				Text {
					id: clipLabel

					x: 10
					text: "CLIPBOARD"
					font.pixelSize: Theme.fontCaption
					font.bold: true
					font.letterSpacing: 0.66
					opacity: 0.6
					color: Theme.glassTextPrimary
				}

				Text {
					anchors.right: parent.right
					anchors.rightMargin: 10
					text: "Clear"
					font.pixelSize: Theme.fontCaption
					font.weight: Font.DemiBold
					opacity: wipeMouse.containsMouse ? 1.0 : 0.6
					color: Theme.glassTextPrimary

					MouseArea {
						id: wipeMouse

						anchors.fill: parent
						anchors.margins: -6
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.clipboard?.wipe()
					}
				}
			}

			Rectangle {
				anchors.bottom: parent.bottom
				width: parent.width
				height: Theme.launcherRowHeight
				radius: Theme.radiusRow
				color: selected ? Theme.glassChipActive : clipMouse.containsMouse ? Theme.glassControlHover : "transparent"
				border.width: selected ? 1 : 0
				border.color: Theme.glassTrackBorderFocus

				Text {
					anchors {
						left: parent.left
						right: parent.right
						leftMargin: 14
						rightMargin: 14
						verticalCenter: parent.verticalCenter
					}

					elide: Text.ElideRight
					text: modelData.preview
					font.pixelSize: Theme.fontTitle
					font.family: modelData.preview.startsWith("[[") ? label.font.family : "monospace"
					font.weight: selected ? Font.Bold : Font.DemiBold
					opacity: modelData.preview.startsWith("[[") ? 0.7 : 1
					color: Theme.glassTextPrimary
				}

				MouseArea {
					id: clipMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: { root.picked = modelData.key; root.act(false); }
				}
			}
		}
	}

	// A command run before, with how long ago.
	Component {
		id: historyRow

		Item {
			readonly property bool selected: root.current?.key === modelData.key
			readonly property bool first: index === root.items.findIndex(item => item.kind === "history")

			height: 44 + (first ? historyLabel.height + 8 : 0)

			Text {
				id: historyLabel

				x: 10
				visible: first
				text: "HISTORY"
				font.pixelSize: Theme.fontCaption
				font.bold: true
				font.letterSpacing: 0.66
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			Rectangle {
				anchors.bottom: parent.bottom
				width: parent.width
				height: 44
				radius: 14
				color: selected ? Theme.glassChipActive : histMouse.containsMouse ? Theme.glassControlHover : "transparent"
				border.width: selected ? 1 : 0
				border.color: Theme.glassTrackBorderFocus

				Text {
					anchors {
						left: parent.left
						right: when.left
						leftMargin: 14
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					elide: Text.ElideMiddle
					text: modelData.line
					font.pixelSize: Theme.fontTitle
					font.family: "monospace"
					font.weight: Font.DemiBold
					color: Theme.glassTextPrimary
				}

				Text {
					id: when

					anchors {
						right: parent.right
						rightMargin: 14
						verticalCenter: parent.verticalCenter
					}

					text: History.ago(History.commands[modelData.line]?.last ?? 0)
					font.pixelSize: Theme.fontBody
					font.weight: Font.DemiBold
					opacity: 0.6
					color: Theme.glassTextPrimary
				}

				MouseArea {
					id: histMouse

					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: { root.picked = modelData.key; root.act(false); }
				}
			}
		}
	}
}
