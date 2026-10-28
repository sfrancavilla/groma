import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick

// Unlocking with a finger, beside the password rather than in front of it.
//
// One conversation for the whole lock, not one per monitor: there is one
// reader, and fprintd lets one client hold it at a time. It runs on its own
// PAM stack, fingerprint.pam beside this file, while each lock surface keeps
// its own password conversation on system-auth.
//
// Nothing here knows which reader it is talking to. libfprint drives the chip,
// fprintd puts every reader behind the same D-Bus API, and pam_fprintd speaks
// PAM. A machine without fprintd, without a reader it supports, or without an
// enrolled finger simply never sends the prompt, and the lock screen shows the
// password field alone.
Scope {
	id: root

	// Listen while this is true - the session is locked.
	property bool active: false

	signal authenticated

	// pam_fprintd's own words for this reader: "Place your finger on…" or
	// "Swipe your finger across…". Empty until it is waiting for one.
	property string prompt: ""

	readonly property bool listening: pam.active && root.prompt !== ""

	// A finger that did not match, briefly, or the reason it has stopped.
	property string status: ""

	// No prompt came: no reader, nothing enrolled, no fprintd. Not asked
	// again until the next lock.
	property bool unavailable: false

	// Too many fingers that did not match. Password only until the next lock.
	property bool exhausted: false

	// With the lid shut the reader - often in the power button or beside the
	// keyboard - is out of reach, and a prompt on an external monitor would
	// be a lie.
	property bool lidOpen: true

	readonly property bool wanted: root.active && root.lidOpen
		&& !root.unavailable && !root.exhausted

	// Whether this conversation got as far as asking for a finger.
	property bool prompted: false

	onActiveChanged: {
		if (!root.active)
			return;

		root.unavailable = false;
		root.exhausted = false;
		root.status = "";
	}

	onWantedChanged: {
		if (root.wanted)
			root.listen();
		else if (pam.active)
			pam.abort();
	}

	// A config reload while locked comes back already wanted, with no change
	// to announce it.
	Component.onCompleted: {
		if (root.wanted)
			root.listen();
	}

	function listen() {
		if (pam.active)
			return;

		root.prompt = "";
		root.prompted = false;

		if (!pam.start())
			root.unavailable = true;
	}

	PamContext {
		id: pam

		configDirectory: `${Quickshell.shellDir}/modules`
		config: "fingerprint.pam"

		onPamMessage: {
			if (pam.message === "")
				return;

			if (!pam.messageIsError) {
				root.prompt = pam.message;
				root.prompted = true;
				return;
			}

			root.status = pam.message;
			clearStatus.restart();
		}

		onCompleted: result => {
			root.prompt = "";

			// Aborted on the way out - the password got there first, or the
			// lid closed.
			if (!root.wanted)
				return;

			if (result === PamResult.Success) {
				root.authenticated();
				return;
			}

			if (result === PamResult.MaxTries) {
				clearStatus.stop();
				root.status = "Too many attempts. Use your password.";
				root.exhausted = true;
				return;
			}

			if (!root.prompted) {
				root.unavailable = true;
				return;
			}

			// The reader went away mid-try, or fprintd restarted. Ask again;
			// if it is gone for good, the next try never prompts and stops.
			retry.restart();
		}

		onError: root.unavailable = true
	}

	Timer {
		id: clearStatus

		interval: 2500
		onTriggered: root.status = ""
	}

	Timer {
		id: retry

		interval: 1000
		onTriggered: {
			if (root.wanted)
				root.listen();
		}
	}

	// No event says the lid moved, short of logind over D-Bus, so look while
	// locked. A machine with no lid has no file and counts as open.
	Process {
		id: lid

		command: ["sh", "-c", "cat /proc/acpi/button/lid/*/state 2>/dev/null"]

		stdout: StdioCollector {
			onStreamFinished: root.lidOpen = !text.includes("closed")
		}
	}

	Timer {
		interval: 2000
		repeat: true
		running: root.active
		triggeredOnStart: true
		onTriggered: lid.running = true
	}
}
