import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick
import ".."

// The vendor channel of a pair of Nothing earbuds, while one is connected.
//
// Bluez reports one battery figure for the pair. The buds report left, right
// and case, and say so the moment any of them changes - which is what the
// design's tile shows. They also send a "wear changed" event when a bud goes
// in or out. That event carries no direction and nothing the buds answer
// reveals the state (every query came back identical bud-out and bud-in), so
// the one safe thing to do with it is stop the sound: pausing when a bud is
// put *in* costs a press of play, playing into an empty ear costs more.
//
// Recognised by name. Quickshell's device object does not expose service
// UUIDs, which would have been the honest test.
Scope {
	id: root

	// For "Paused" on screen. Silence with no reason given is a bug report.
	property var osd: null

	readonly property var buds: (Bluetooth.devices?.values ?? []).find(
		device => device.connected
			&& /^(Nothing|CMF)\b/.test(device.name)) ?? null

	readonly property string address: root.buds?.address ?? ""

	// address -> { left, right, case, charging: {left, right, case} }, kept
	// for the last pair seen so the tile does not blank between reports.
	property var battery: ({})

	function handle(line) {
		let msg;
		try {
			msg = JSON.parse(line);
		} catch (err) {
			return;
		}

		switch (msg.event) {
		case "battery": {
			// A report carries whatever is talking. The case has no radio, so
			// it appears only while a bud is docked to relay it - and that
			// docked bud then drops out of the next report itself. Measured:
			// left+right, then left+right+case on docking, then right alone.
			// Keep the last figure for anything missing rather than blanking
			// it: the design shows all three, and a value from ten minutes
			// ago is more use than a gap.
			const previous = root.battery[root.address] ?? { charging: {} };
			const entry = { charging: {} };

			for (const part of ["left", "right", "case"]) {
				if (msg[part] !== undefined) {
					entry[part] = msg[part].level;
					entry.charging[part] = msg[part].charging;
				} else if (previous[part] !== undefined) {
					entry[part] = previous[part];
					entry.charging[part] = false;
				}
			}

			const next = Object.assign({}, root.battery);
			next[root.address] = entry;
			root.battery = next;
			return;
		}
		case "wear":
			root.onWear();
			return;
		case "retry":
		case "lost":
			console.log("NothingEar:", msg.event, msg.reason ?? "");
			return;
		}
	}

	// Not `running: root.address !== ""`. Quickshell writes running = false
	// when the process exits, and a write destroys a binding - so a helper
	// that died once (killed, crashed, lost to a shell restart) would never
	// come back. Start and stop it by hand, and bring it back if it goes.
	onAddressChanged: {
		link.running = false;
		if (root.address !== "")
			link.running = true;
	}

	Component.onCompleted: if (root.address !== "") link.running = true

	Timer {
		id: revive

		interval: 2000
		onTriggered: if (root.address !== "" && !link.running) link.running = true
	}

	Process {
		id: link

		command: ["python3", `${Quickshell.shellDir}/helpers/nothing-ear.py`,
			root.address]

		onExited: if (root.address !== "") revive.start()

		stdout: SplitParser {
			onRead: line => root.handle(line)
		}

		stderr: SplitParser {
			onRead: line => console.warn("NothingEar helper:", line)
		}
	}

	// --- pause, and resume ---------------------------------------------
	//
	// The event says a bud moved, not which way. Pausing needs no more than
	// that. Resuming has to be inferred, and the inference is timing:
	//
	//   - the first event while playing pauses, and arms;
	//   - a second event within `otherBudWindow` is read as the other bud
	//     coming out, because two buds leave within a couple of seconds and
	//     one going back in that fast almost never happens;
	//   - the event that brings the count of buds out back to zero resumes;
	//   - pressing play by hand at any point resets everything, and so does
	//     `forgetAfter` of silence - by then it was a decision, not a pause.
	//
	// The failure this cannot exclude: one bud out and straight back in
	// within the window is misread as both out, and playback then waits for
	// two events that are not coming. `forgetAfter` bounds how long.
	readonly property int otherBudWindow: 2500
	readonly property int forgetAfter: 120000

	property bool armed: false
	property int budsOut: 0
	property double pausedAt: 0
	property double lastEventAt: 0
	property double eventGap: 0

	function onWear() {
		const now = Date.now();
		root.eventGap = now - root.lastEventAt;
		root.lastEventAt = now;

		if (root.armed && now - root.pausedAt > root.forgetAfter)
			root.armed = false;

		if (!root.armed && !Settings.pauseOnBudRemoved)
			return;

		status.running = true;
	}

	function decide(state) {
		const playing = state === "Playing";
		const paused = state === "Paused";

		// Playing while armed means someone pressed play themselves. Start
		// over from there.
		if (playing) {
			root.armed = false;

			if (Settings.pauseOnBudRemoved) {
				pause.running = true;
				root.armed = true;
				root.budsOut = 1;
				root.pausedAt = Date.now();
			}

			return;
		}

		if (!root.armed || !paused) {
			root.armed = false;
			return;
		}

		if (root.budsOut === 1 && root.eventGap < root.otherBudWindow) {
			root.budsOut = 2;
			return;
		}

		root.budsOut -= 1;

		if (root.budsOut <= 0) {
			root.armed = false;

			if (Settings.resumeOnBudReplaced)
				play.running = true;
		}
	}

	Process {
		id: status

		command: ["playerctl", "status"]

		stdout: StdioCollector {
			onStreamFinished: root.decide(text.trim())
		}
	}

	Process {
		id: pause

		command: ["playerctl", "-a", "pause"]
		onExited: root.osd?.say("Paused · earbud moved")
	}

	// No card for this one: the sound coming back is its own announcement.
	Process {
		id: play

		command: ["playerctl", "play"]
	}
}
