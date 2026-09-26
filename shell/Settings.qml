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

	// The launcher's history, most recent first, by desktop-entry id.
	readonly property alias recentApps: adapter.recentApps

	function noteLaunch(id) {
		const rest = (adapter.recentApps ?? []).filter(entry => entry !== id);
		adapter.recentApps = [id, ...rest].slice(0, 8);
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
			property var recentApps: []
			property bool pauseOnBudRemoved: true
			property bool resumeOnBudReplaced: true
		}
	}
}
