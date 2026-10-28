import Quickshell
import Quickshell.Services.Pam
import QtQuick
import ".."
import "../ui"

// The unlock face: clock, prompt, and the PAM conversation behind it.
//
// Kept separate from the thing that locks the session so it can be run as an
// ordinary window while being built. A lock screen you cannot escape is a poor
// place to discover a typo.
Item {
	id: content

	// Emitted once PAM says yes. The caller decides what that means - unlock
	// the session, or just close a test window.
	signal authenticated

	// The lock's one Fingerprint, shared by every monitor's copy of this.
	// Null in a test window, which then asks for the password alone.
	property Fingerprint fingerprint: null

	readonly property bool busy: pam.active && !pam.responseRequired

	property string status: ""
	property bool statusIsError: false

	function authenticate() {
		if (pam.active || password.text === "")
			return;

		content.status = "";
		content.pendingResponse = password.text;
		password.clear();

		if (!pam.start())
			content.setStatus("Could not start authentication", true);
	}

	function setStatus(text, isError) {
		content.status = text;
		content.statusIsError = isError;
	}

	// Held between start() and PAM asking for it.
	property string pendingResponse: ""

	PamContext {
		id: pam

		// system-auth is the stack everything else on Arch includes. Naming a
		// service with no file in /etc/pam.d falls through to `other`, which
		// is pam_deny - authentication would fail every time, and each failure
		// would count toward faillock.
		config: "system-auth"

		onPamMessage: {
			if (pam.responseRequired) {
				pam.respond(content.pendingResponse);
				content.pendingResponse = "";
				return;
			}

			if (pam.message !== "")
				content.setStatus(pam.message, pam.messageIsError);
		}

		onCompleted: result => {
			content.pendingResponse = "";

			if (result === PamResult.Success) {
				content.setStatus("", false);
				content.authenticated();
				return;
			}

			content.setStatus(result === PamResult.MaxTries
				? "Too many attempts"
				: "Incorrect password", true);
			password.focusInput();
		}

		onError: err => content.setStatus("Authentication error: " + err, true)
	}

	SystemClock {
		id: clock

		precision: SystemClock.Seconds
	}

	Column {
		anchors.centerIn: parent
		spacing: Theme.spacingL

		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			// 12 hours without AM or PM: at this size the hour says enough.
			text: Qt.formatDateTime(clock.date, Settings.clock24 ? "HH:mm" : "h:mm")
			font.pixelSize: 96
			font.weight: Font.Light
			color: Theme.glassTextPrimary
		}

		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			text: Qt.formatDateTime(clock.date, "dddd d MMMM")
			font.pixelSize: Theme.fontLead
			opacity: 0.8
			color: Theme.glassTextPrimary
		}

		Item {
			width: 1
			height: Theme.spacingL
		}

		GlassField {
			id: password

			anchors.horizontalCenter: parent.horizontalCenter
			width: 280
			placeholder: content.busy ? "Checking…" : "Password"
			echoMode: TextInput.Password
			opacity: content.busy ? 0.6 : 1.0

			onAccepted: content.authenticate()

			Behavior on opacity {
				NumberAnimation { duration: 120 }
			}
		}

		// While the reader waits, say so; when a finger fails, say that here
		// too, apart from what the password line says.
		FingerprintLine {
			readonly property Fingerprint fp: content.fingerprint
			readonly property bool hasStatus: fp !== null && fp.status !== ""

			anchors.horizontalCenter: parent.horizontalCenter
			visible: fp !== null && (fp.listening || hasStatus)
			isError: hasStatus
			text: hasStatus ? fp.status : fp?.prompt ?? ""
		}

		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			width: 320
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.WordWrap
			text: content.status
			visible: text !== ""
			font.pixelSize: Theme.fontCaption
			color: content.statusIsError ? Theme.warning : Theme.glassTextMuted
		}
	}

	function focusInput() {
		password.focusInput();
	}
}
