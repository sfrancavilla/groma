pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Settings' Hyprland choices, written to ~/.config/hypr/groma.lua for
// hyprland.lua to require - and what Hyprland is actually running with, read
// back for Settings to show.
//
// Hyprland watches the files it has required and reloads when one changes,
// so writing the file is applying it. A reload starts from scratch, so a
// choice dropped from the file goes back to hyprland.lua's default without
// anything here having to know what that was.
//
// A display's scale and refresh rate are the exception, because a wrong one
// can leave a screen nobody can read: previewDisplay() changes the running
// compositor only, and the old setting comes back by itself unless
// keepDisplay() is called in time. Nothing reaches the file until then, so a
// crash mid-preview loses the preview, not the screen.
Singleton {
	id: root

	readonly property string path:
		(Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
		+ "/hypr/groma.lua"

	readonly property string header:
		"-- Written by Groma's Settings window (shell/HyprConfig.qml), and rewritten\n"
		+ "-- whenever something there changes: change it there, not here. Overrides\n"
		+ "-- for this machine alone go in machine.lua, which is loaded after this.\n"

	// --- Writing ---------------------------------------------------------

	// A Lua string literal for any text. A display's description is whatever
	// its maker put in the EDID, so nothing is assumed about it.
	function luaString(text) {
		return '"' + String(text)
			.replace(/[\\"]/g, "\\$&")
			.replace(/[\x00-\x1f\x7f]/g, c => "\\" + String(c.charCodeAt(0)).padStart(3, "0"))
			+ '"';
	}

	// By description rather than connector, as Settings keys it. Position as
	// hyprland.lua's catch-all rule has it, and mode and scale as it has them
	// unless chosen, since a rule names all three or none.
	function monitorRule(description, scale, mode) {
		const scaleValue = scale === null || scale === undefined ? '"auto"' : String(Number(scale));
		const modeValue = root.luaString(mode || "preferred");
		return `hl.monitor({ output = ${root.luaString("desc:" + description)}, `
			+ `mode = ${modeValue}, position = "auto", scale = ${scaleValue} })`;
	}

	readonly property string lua: {
		const input = [];
		const touchpad = [];

		const layouts = Settings.keyboardLayouts ?? [];
		if (layouts.length > 0) {
			input.push(`kb_layout = ${root.luaString(layouts.map(entry => entry.layout).join(","))}`);
			input.push(`kb_variant = ${root.luaString(layouts.map(entry => entry.variant ?? "").join(","))}`);
		}

		// xkb takes its options as one list, so Caps Lock and the layout
		// switch go in together or one would replace the other.
		const options = [];
		// A second layout is no use without a way to reach it. SUPER+SPACE,
		// as GNOME has it; nothing in hyprland.lua is bound there.
		if (layouts.length > 1)
			options.push("grp:win_space_toggle");
		const caps = { escape: "caps:escape", ctrl: "ctrl:nocaps", none: "caps:none" }[Settings.capsLock];
		if (caps)
			options.push(caps);
		if (options.length > 0)
			input.push(`kb_options = ${root.luaString(options.join(","))}`);

		if (Settings.repeatDelay != null)
			input.push(`repeat_delay = ${Math.round(Settings.repeatDelay)}`);
		if (Settings.repeatRate != null)
			input.push(`repeat_rate = ${Math.round(Settings.repeatRate)}`);
		if (Settings.pointerSpeed != null)
			input.push(`sensitivity = ${Number(Settings.pointerSpeed).toFixed(2)}`);
		if (Settings.naturalScroll != null)
			touchpad.push(`natural_scroll = ${Settings.naturalScroll ? "true" : "false"}`);
		// tap_to_click here, though getoption calls it tap-to-click.
		if (Settings.tapToClick != null)
			touchpad.push(`tap_to_click = ${Settings.tapToClick ? "true" : "false"}`);
		if (Settings.disableWhileTyping != null)
			touchpad.push(`disable_while_typing = ${Settings.disableWhileTyping ? "true" : "false"}`);
		if (Settings.scrollFactor != null)
			touchpad.push(`scroll_factor = ${Number(Settings.scrollFactor).toFixed(2)}`);
		if (touchpad.length > 0)
			input.push(`touchpad = { ${touchpad.join(", ")} }`);

		const blocks = [];
		if (input.length > 0)
			blocks.push("hl.config({\n    input = {\n"
				+ input.map(line => `        ${line},\n`).join("")
				+ "    },\n})\n");

		// The swipe is defined in hyprland.lua after this file is loaded, and
		// asks this first: hl.gesture() returns nothing to switch off later.
		if (Settings.workspaceSwipe === false)
			blocks.push("GROMA_WORKSPACE_SWIPE = false\n");

		const scales = Settings.displayScales ?? {};
		const modes = Settings.displayModes ?? {};
		const described = Object.keys(scales).concat(Object.keys(modes))
			.filter((description, i, all) => all.indexOf(description) === i).sort();
		const rules = described
			.map(description => root.monitorRule(description, scales[description], modes[description]) + "\n");
		if (rules.length > 0)
			blocks.push(rules.join(""));

		return [root.header, ...blocks].join("\n");
	}

	// Coalesced, so dragging the pointer-speed slider reloads Hyprland once
	// when it stops rather than at every step.
	onLuaChanged: writeSoon.restart()
	Component.onCompleted: writeSoon.restart()

	Timer {
		id: writeSoon
		interval: 400
		onTriggered: root.write()
	}

	function write() {
		// Every start, and most changes back and forth, would otherwise make
		// Hyprland reload for a file that says what it already said.
		if (file.loaded && file.text() === root.lua)
			return;
		// Nothing chosen, nothing written: most machines never need the file.
		if (!file.loaded && root.lua === root.header)
			return;
		// Hyprland watches only what it found when it last loaded, so the
		// first time the file appears it has to be told.
		const created = !file.loaded;
		file.setText(root.lua);
		if (created)
			reloadOnSave.armed = true;
	}

	Connections {
		id: reloadOnSave

		property bool armed: false

		target: file

		function onSaved() {
			if (!reloadOnSave.armed)
				return;
			reloadOnSave.armed = false;
			Quickshell.execDetached(["hyprctl", "reload"]);
		}
	}

	FileView {
		id: file

		path: root.path
		// write() has to know what is there before it decides, and the file
		// is a few hundred bytes.
		blockLoading: true
		printErrors: false

		// So a file deleted by hand is known to be gone, and comes back with
		// the reload that makes Hyprland see it again.
		watchChanges: true
		onFileChanged: file.reload()

		onSaveFailed: error => console.warn("HyprConfig: could not write", root.path, error)
	}

	// --- Display scale and refresh rate -----------------------------------------

	// What is being tried, or null: { description, kind, scale, mode,
	// previous: { scale, mode, rate } }, kind being "scale" or "mode" - the
	// one that changed. The other is carried, since a rule names both.
	property var preview: null
	// Seconds before it goes back by itself.
	property int previewLeft: 0
	readonly property int previewSeconds: 15

	function previewDisplay(description, kind, value) {
		// One trial at a time: trying a refresh rate while a scale waits for
		// an answer would leave nothing sensible to go back to.
		if (root.preview && (root.preview.description !== description || root.preview.kind !== kind))
			root.revertDisplay();
		const kept = { scale: Settings.displayScale(description), mode: Settings.displayMode(description) };
		// The rate it was running at, so going back can say "120 Hz" when
		// the kept mode is only "preferred".
		const running = root.monitors.find(monitor => monitor.description === description);
		kept.rate = running ? Math.round(running.refreshRate) : null;
		const next = Object.assign({}, kept);
		next[kind] = value;
		root.preview = { description: description, kind: kind, scale: next.scale, mode: next.mode,
			previous: root.preview ? root.preview.previous : kept };
		root.evaluate(root.monitorRule(description, next.scale, next.mode));
		root.previewLeft = root.previewSeconds;
		countdown.restart();
	}

	// Into the file, which Hyprland reloads into what it already has.
	function keepDisplay() {
		if (!root.preview)
			return;
		countdown.stop();
		Settings.setDisplayScale(root.preview.description, root.preview.scale);
		Settings.setDisplayMode(root.preview.description, root.preview.mode);
		root.preview = null;
	}

	function revertDisplay() {
		if (!root.preview)
			return;
		countdown.stop();
		const previous = root.preview.previous;
		root.evaluate(root.monitorRule(root.preview.description, previous.scale, previous.mode));
		root.preview = null;
	}

	Timer {
		id: countdown
		interval: 1000
		repeat: true
		onTriggered: {
			root.previewLeft -= 1;
			if (root.previewLeft <= 0)
				root.revertDisplay();
		}
	}

	// The scales a mode can take without blurring: Wayland's fractional
	// scale moves in 120ths, and Hyprland wants the logical size to come out
	// whole. Down to a logical height of 720, below which apps stop fitting.
	function scalesFor(width, height) {
		const found = [];
		for (let step = 120; height * 120 / step >= 720; step++)
			if ((width * 120) % step === 0 && (height * 120) % step === 0)
				found.push(step / 120);
		return found;
	}

	// One hyprctl eval at a time, in order: a preview and its revert must not
	// arrive the wrong way round.
	property var pending: []

	function evaluate(code) {
		root.pending = [...root.pending, code];
		if (!evaluator.running)
			root.evaluateNext();
	}

	function evaluateNext() {
		if (root.pending.length === 0) {
			reader.running = true;
			return;
		}
		evaluator.command = ["hyprctl", "eval", root.pending[0]];
		root.pending = root.pending.slice(1);
		evaluator.running = true;
	}

	Process {
		id: evaluator

		stdout: StdioCollector { id: evaluatorOut }
		stderr: StdioCollector { id: evaluatorErr }

		onExited: code => {
			if (code !== 0)
				console.warn("HyprConfig: hyprctl eval failed:",
					(evaluatorOut.text + evaluatorErr.text).trim());
			root.evaluateNext();
		}
	}

	// --- Reading -----------------------------------------------------------

	// Every display: { name, description, width, height, scale, scales,
	// refreshRate, rates }, rates being the refresh rates its current size
	// offers, as { rate, mode } with the mode Hyprland would be given.
	property var monitors: []
	// Hyprland's input options as it has them, wherever they came from,
	// by the names below.
	property var input: ({})

	readonly property var inputOptions: ({
		kb_layout: "input:kb_layout",
		kb_variant: "input:kb_variant",
		kb_options: "input:kb_options",
		repeat_delay: "input:repeat_delay",
		repeat_rate: "input:repeat_rate",
		sensitivity: "input:sensitivity",
		natural_scroll: "input:touchpad:natural_scroll",
		tap_to_click: "input:touchpad:tap-to-click",
		disable_while_typing: "input:touchpad:disable_while_typing",
		scroll_factor: "input:touchpad:scroll_factor",
	})

	// "2880x1920@60.00Hz" and the like, at this display's size, highest first.
	function ratesFor(monitor) {
		const size = `${monitor.width}x${monitor.height}@`;
		return (monitor.availableModes ?? [])
			.filter(mode => mode.startsWith(size))
			.map(mode => {
				const rate = parseFloat(mode.slice(size.length));
				return { rate: rate, mode: size + rate.toFixed(2) };
			})
			.filter((entry, i, all) => all.findIndex(other => Math.round(other.rate) === Math.round(entry.rate)) === i)
			.sort((a, b) => b.rate - a.rate);
	}

	Connections {
		target: Hyprland

		function onRawEvent(event) {
			if (event.name === "configreloaded"
					|| event.name.startsWith("monitoradded")
					|| event.name.startsWith("monitorremoved"))
				reader.running = true;
		}
	}

	// One process for all of it, the answers separated by a record separator.
	Process {
		id: reader

		running: true
		command: ["sh", "-c",
			"hyprctl -j monitors; for o in \"$@\"; do printf '\\036'; hyprctl -j getoption \"$o\"; done",
			"sh", ...Object.values(root.inputOptions)]

		stdout: StdioCollector {
			onStreamFinished: {
				const parts = text.split("\x1e");
				try {
					root.monitors = JSON.parse(parts[0]).map(monitor => ({
						name: monitor.name,
						description: monitor.description,
						width: monitor.width,
						height: monitor.height,
						scale: monitor.scale,
						scales: root.scalesFor(monitor.width, monitor.height),
						refreshRate: monitor.refreshRate,
						rates: root.ratesFor(monitor),
					}));
					const keys = Object.keys(root.inputOptions);
					const input = {};
					parts.slice(1).forEach((part, i) => {
						const option = JSON.parse(part);
						input[keys[i]] = option.str ?? option.float ?? option.int ?? option.bool;
					});
					root.input = input;
				} catch (error) {
					console.warn("HyprConfig: could not read Hyprland's state:", error);
				}
			}
		}
	}

	// For scripts and for checking this without the window:
	//   qs -c groma ipc call hyprconfig state
	//   qs -c groma ipc call hyprconfig preview "<description>" 1.6
	//   qs -c groma ipc call hyprconfig previewMode "<description>" 2880x1920@60.00
	IpcHandler {
		target: "hyprconfig"

		function state(): string {
			return JSON.stringify({ input: root.input, monitors: root.monitors,
				preview: root.preview, previewLeft: root.previewLeft }, null, 2);
		}
		function preview(description: string, scale: real): void { root.previewDisplay(description, "scale", scale); }
		function previewMode(description: string, mode: string): void { root.previewDisplay(description, "mode", mode); }
		function keep(): void { root.keepDisplay(); }
		function revert(): void { root.revertDisplay(); }
	}

	// --- Keyboard layouts --------------------------------------------------

	// Every layout xkb knows, by name, for Settings to choose from:
	// [{ layout: "us", name: "English (US)", variants: [{ variant, name }] }]
	property var layoutCatalog: []

	FileView {
		path: "/usr/share/X11/xkb/rules/evdev.lst"

		onLoaded: {
			const layouts = {};
			let section = "";
			for (const line of text().split("\n")) {
				if (line.startsWith("! ")) {
					section = line.slice(2).trim();
					continue;
				}
				const match = line.match(/^\s+(\S+)\s+(.*)$/);
				if (!match)
					continue;
				if (section === "layout") {
					layouts[match[1]] = { layout: match[1], name: match[2], variants: [] };
				} else if (section === "variant") {
					// "  intl            us: English (US, intl., with dead keys)"
					const owner = match[2].match(/^(\S+):\s*(.*)$/);
					if (owner && layouts[owner[1]])
						layouts[owner[1]].variants.push({ variant: match[1], name: owner[2] });
				}
			}
			root.layoutCatalog = Object.values(layouts)
				.sort((a, b) => a.name.localeCompare(b.name));
		}
	}
}
