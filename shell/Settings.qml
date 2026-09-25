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
			property bool pauseOnBudRemoved: true
			property bool resumeOnBudReplaced: true
		}
	}
}
