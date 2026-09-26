pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// What the user has done, as opposed to what the user has decided.
//
// Settings.qml holds choices: a switch flipped, a lookup allowed. This holds
// usage: which applications were launched, how often, and when. They live in
// separate files because they are different kinds of thing - clearing your
// history should not touch your settings, a launch should not rewrite the
// settings file, and usage needs counts and timestamps where a setting needs
// a value. Both sit in Quickshell's state directory for this shell:
// ~/.local/state/quickshell/by-shell/<id>/.
Singleton {
	id: root

	// id -> { count, last } where last is milliseconds since the epoch.
	readonly property var apps: adapter.apps ?? ({})

	function noteLaunch(id) {
		const next = Object.assign({}, adapter.apps ?? {});
		const was = next[id] ?? { count: 0, last: 0 };
		next[id] = { count: was.count + 1, last: Date.now() };
		adapter.apps = next;
	}

	function clear() {
		adapter.apps = ({});
		adapter.commands = ({});
	}

	// Commands run from the launcher, the same shape as apps.
	readonly property var commands: adapter.commands ?? ({})

	function noteCommand(line) {
		const next = Object.assign({}, adapter.commands ?? {});
		const was = next[line] ?? { count: 0, last: 0 };
		next[line] = { count: was.count + 1, last: Date.now() };
		adapter.commands = next;
	}

	function recentCommands(limit) {
		return Object.keys(root.commands)
			.sort((a, b) => root.commands[b].last - root.commands[a].last)
			.slice(0, limit);
	}

	// "just now", "12 min ago", "2 h ago", "Yesterday", "Mon".
	function ago(ms) {
		const d = Date.now() - ms;
		if (d < 60000) return "just now";
		if (d < 3600000) return Math.round(d / 60000) + " min ago";
		if (d < 86400000) return Math.round(d / 3600000) + " h ago";
		if (d < 172800000) return "Yesterday";
		return new Date(ms).toLocaleDateString(Qt.locale(), "ddd");
	}

	// Most recently launched first.
	function recent(limit) {
		return Object.keys(root.apps)
			.sort((a, b) => root.apps[b].last - root.apps[a].last)
			.slice(0, limit);
	}

	// Most often launched first, recency breaking ties.
	function mostUsed(limit) {
		return Object.keys(root.apps)
			.sort((a, b) => root.apps[b].count - root.apps[a].count
				|| root.apps[b].last - root.apps[a].last)
			.slice(0, limit);
	}

	// How much an application has earned a place near the top: its count,
	// worth less the longer ago it was last used, halving every fortnight.
	// Bounded, so it orders within a rank rather than jumping one.
	function weight(id) {
		const entry = root.apps[id];
		if (!entry)
			return 0;

		const fortnights = (Date.now() - entry.last) / (14 * 24 * 3600 * 1000);
		return Math.min(0.9, entry.count * Math.pow(0.5, fortnights) / 10);
	}

	IpcHandler {
		target: "history"

		function clear(): void {
			root.clear();
		}
	}

	FileView {
		id: file

		path: Quickshell.statePath("history.json")
		printErrors: false
		watchChanges: true
		onFileChanged: file.reload()
		onAdapterUpdated: file.writeAdapter()

		JsonAdapter {
			id: adapter

			property var apps: ({})
			property var commands: ({})
		}
	}
}
