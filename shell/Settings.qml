pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Choices that have to outlive a restart.
//
// Theme.qml holds what the shell looks like, which is part of the source.
// This holds what the user decided, which is not - so it lives in a file and
// is written back whenever it changes.
Singleton {
	id: root

	// Whether the network tile may ask a web service for the public address.
	// Off by default: a shell that contacts a third party before anyone has
	// agreed to it has asked the question too late.
	readonly property alias publicAddressLookup: adapter.publicAddressLookup

	function setPublicAddressLookup(value) {
		adapter.publicAddressLookup = value;
	}

	// Applications pinned to the launcher, by desktop-entry id, in order.
	readonly property alias pinnedApps: adapter.pinnedApps

	function isPinned(id) {
		return (adapter.pinnedApps ?? []).includes(id);
	}

	function togglePin(id) {
		const now = adapter.pinnedApps ?? [];
		adapter.pinnedApps = now.includes(id)
			? now.filter(entry => entry !== id)
			: [...now, id].slice(0, 5);
	}

	// What each workspace is for - "Terminals", "Groma", "YouTube" - by
	// number. Kept by number rather than handed to Hyprland, because Hyprland
	// forgets a workspace the moment its last window closes, and a name is
	// worth more than the windows that happen to be on it today.
	readonly property alias workspaceNames: adapter.workspaceNames

	function workspaceName(id) {
		return (adapter.workspaceNames ?? {})[String(id)] ?? "";
	}

	function setWorkspaceName(id, name) {
		const next = Object.assign({}, adapter.workspaceNames ?? {});
		const clean = String(name ?? "").trim();
		if (clean === "")
			delete next[String(id)];
		else
			next[String(id)] = clean;
		adapter.workspaceNames = next;
	}

	// And a colour for each, as a key into Theme.tagPalette - "blue", not a
	// hex value, so a new theme moves everyone's blue along with it.
	readonly property alias workspaceColors: adapter.workspaceColors

	function workspaceColor(id) {
		return (adapter.workspaceColors ?? {})[String(id)] ?? "";
	}

	function setWorkspaceColor(id, key) {
		const next = Object.assign({}, adapter.workspaceColors ?? {});
		if (!key)
			delete next[String(id)];
		else
			next[String(id)] = key;
		adapter.workspaceColors = next;
	}

	// --- Integration: Nothing earbuds (integrations/nothingear) ----------
	// One settings file for everything, so these keep the baseline's store;
	// the prefix in the comment is the only namespacing there is.

	// Stop the sound when an earbud is taken out - or put in, since the buds
	// do not say which. On by default: the failure mode of "off" is playing
	// into an empty ear.
	readonly property alias pauseOnBudRemoved: adapter.pauseOnBudRemoved

	function setPauseOnBudRemoved(value) {
		adapter.pauseOnBudRemoved = value;
	}

	// And start it again when the bud comes back. Inferred from timing, since
	// the buds report a change and not a direction - see NothingEar.qml.
	readonly property alias resumeOnBudReplaced: adapter.resumeOnBudReplaced

	function setResumeOnBudReplaced(value) {
		adapter.resumeOnBudReplaced = value;
	}

	FileView {
		id: file

		// Quickshell makes this directory; a path under ~/.config would have
		// to be created before the first write.
		path: Quickshell.statePath("settings.json")

		// The file does not exist until something is changed, and complaining
		// about that on every first run is noise.
		printErrors: false
		watchChanges: true
		onFileChanged: file.reload()
		onAdapterUpdated: file.writeAdapter()

		JsonAdapter {
			id: adapter

			property bool publicAddressLookup: false
			property var pinnedApps: []
			property var workspaceNames: ({})
			property var workspaceColors: ({})
			property bool pauseOnBudRemoved: true
			property bool resumeOnBudReplaced: true
		}
	}
}
