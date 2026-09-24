import Quickshell
import Quickshell.Io
import QtQuick

// A pairing agent, which bluez requires and QML cannot provide.
//
// Bluez asks an agent to vouch for a pairing: to show a passkey, confirm one,
// or type a PIN. Quickshell's Bluetooth module exposes no agent type, and
// nothing else on this machine registers one - so BluetoothDevice.pair() has
// nobody to ask and fails on anything beyond "just works".
//
// bluetoothctl registers one. Run with its stdin on a pipe it stays up, takes
// commands a line at a time and prints the agent's questions, which is enough
// to put a real dialog in front of them.
//
// DisplayYesNo rather than NoInputNoOutput on purpose: NoInputNoOutput tells
// bluez we cannot ask anything, so it pairs silently with whatever answers -
// which is convenient and is also how you pair with the wrong device.
Scope {
	id: root

	// The passkey bluez is asking about, "" when it is not asking.
	property string passkey: ""
	property string pairingWith: ""
	property string error: ""
	property bool pairing: false

	signal paired(string address)

	function pair(address) {
		if (root.pairing)
			return;

		root.pairingWith = address;
		root.error = "";
		root.passkey = "";
		root.pairing = true;

		// Trusting it first means the device may reconnect later without
		// asking again, which is what pairing is for.
		root.send(`trust ${address}`);
		root.send(`pair ${address}`);
	}

	function respond(accept) {
		if (root.passkey === "")
			return;

		root.passkey = "";
		root.send(accept ? "yes" : "no");

		if (!accept) {
			root.pairing = false;
			root.send(`cancel-pairing ${root.pairingWith}`);
		}
	}

	function send(line) {
		if (ctl.running)
			ctl.write(line + "\n");
	}

	// The confirm dialog takes the keyboard, so by the guidelines it has to be
	// answerable without one. This is also the way out if the parse ever
	// misses bluez's reply and leaves the question on screen.
	IpcHandler {
		target: "btpair"

		function confirm(): void {
			root.respond(true);
		}

		function cancel(): void {
			root.respond(false);
		}

	}

	Process {
		id: ctl

		command: ["bluetoothctl"]
		running: true
		stdinEnabled: true

		onStarted: {
			// The agent has to be registered before anything asks it to
			// answer, so this goes in the moment the process is up.
			ctl.write("agent DisplayYesNo\n");
			ctl.write("default-agent\n");
		}

		// Restart if it dies: without it the shell has no agent and pairing
		// silently stops working until the next reload.
		onExited: restart.start()

		stdout: SplitParser {
			onRead: line => root.handle(line)
		}
	}

	Timer {
		id: restart

		interval: 2000
		onTriggered: ctl.running = true
	}

	// bluetoothctl writes for a terminal: colour, cursor moves and a prompt in
	// front of whatever it has to say.
	function clean(line) {
		return line
			.replace(/\u001b\[[0-9;?]*[A-Za-z]/g, "")
			.replace(/\r/g, "")
			.replace(/^\s*\[[^\]]*\][>#]?\s*/, "")
			.trim();
	}

	function handle(raw) {
		const line = root.clean(raw);
		if (line === "")
			return;

		// Every line bluez says, at debug level. The patterns below are read
		// off bluetoothctl output rather than any documented contract, so
		// until a real pairing has confirmed them this is how a failure gets
		// diagnosed - and re-adding it later would reload the shell, which
		// restarts the agent underneath whatever pairing went wrong.
		console.log("BT|", line);


		// "Confirm passkey 481903 (yes/no):"
		const confirm = line.match(/Confirm passkey (\d+)/);
		if (confirm) {
			root.passkey = confirm[1];
			return;
		}

		// A device that wants a code typed into it, or into us. Neither is a
		// yes/no, and neither has a dialog yet - so say that rather than
		// leaving the prompt unanswered and the pairing hanging.
		if (/Enter PIN code|Request passkey|Enter passkey/.test(line)) {
			root.send("no");
			root.pairing = false;
			root.error = "This device wants a code typed in, which Groma "
				+ "cannot ask for yet.";
			return;
		}

		if (/Pairing successful/.test(line)) {
			root.pairing = false;
			root.passkey = "";
			root.paired(root.pairingWith);
			return;
		}

		const failed = line.match(/Failed to pair:\s*(.*)$/);
		if (failed) {
			root.pairing = false;
			root.passkey = "";
			root.error = failed[1] !== "" ? failed[1] : "Could not pair";
		}
	}
}
