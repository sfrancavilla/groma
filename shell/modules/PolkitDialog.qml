import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import ".."
import "../ui"

// A polkit authentication agent: the password prompt that appears when an
// application asks to do something administrative.
//
// Quickshell's PolkitAgent handles the protocol with polkitd. All we supply is
// the interface - built from GlassDialog, so it matches the rest of the shell
// rather than being its own thing.
Scope {
	id: root

	PolkitAgent {
		id: agent
	}

	PanelWindow {
		id: dialogWindow

		// One AuthFlow exists per pending request, and it is null when nothing
		// is pending. Everything the dialog shows comes from it.
		readonly property var flow: agent.flow

		// PAM sends feedback one message at a time, and each new message
		// replaces the previous one. Collect them so an explanation is not
		// lost the instant a follow-up line arrives.
		property var supplementaryLines: []

		// The reader's turn. Where there is one, /etc/pam.d/polkit-1 puts
		// pam_fprintd before the password (system/polkit-1.pam), and it talks
		// in info lines before anything asks for a response. Without a reader
		// the password is asked for at once and this stays empty.
		property string fingerPrompt: ""
		property string fingerError: ""

		readonly property bool readerTurn: dialogWindow.active
			&& !(dialogWindow.flow?.isResponseRequired ?? false)
			&& dialogWindow.fingerPrompt !== ""

		// A password typed while the reader has its turn, sent the moment PAM
		// asks for one - so preferring the password never means waiting.
		property string pendingPassword: ""

		// A new request starts with a clean slate.
		onFlowChanged: {
			dialogWindow.supplementaryLines = [];
			dialogWindow.confirmingCancel = false;
			dialogWindow.fingerPrompt = "";
			dialogWindow.fingerError = "";
			dialogWindow.pendingPassword = "";
		}

		Connections {
			target: dialogWindow.flow

			function onSupplementaryMessageChanged() {
				const flow = dialogWindow.flow;
				const message = flow.supplementaryMessage;
				if (message === "")
					return;

				// Before the password, a line is the reader's: what to do, or
				// a touch that did not match.
				if (!flow.isResponseRequired) {
					if (!flow.supplementaryIsError) {
						dialogWindow.fingerPrompt = message;
						return;
					}
					if (dialogWindow.fingerPrompt !== "") {
						dialogWindow.fingerError = message;
						fingerErrorTimeout.restart();
						return;
					}
				}

				// Keep the last few lines so a long retry sequence cannot grow
				// the dialog without bound.
				dialogWindow.supplementaryLines =
					dialogWindow.supplementaryLines.concat(message).slice(-4);
			}

			function onIsResponseRequiredChanged() {
				const flow = dialogWindow.flow;
				if (!flow.isResponseRequired || dialogWindow.pendingPassword === "")
					return;

				const value = dialogWindow.pendingPassword;
				dialogWindow.pendingPassword = "";
				flow.submit(value);
			}

			// A wrong password: Quickshell starts a new session, and the
			// reader takes its turn again.
			function onAuthenticationFailed() {
				dialogWindow.fingerPrompt = "";
				dialogWindow.fingerError = "";
			}
		}

		Timer {
			id: fingerErrorTimeout

			interval: 2500
			onTriggered: dialogWindow.fingerError = ""
		}

		// Abandoning a polkit prompt makes pam_unix fail, and pam_faillock
		// counts that: three stray Escapes and the account is locked for ten
		// minutes, on TTYs too. Nothing here can stop a cancel reaching PAM -
		// so the first one only arms the second.
		property bool confirmingCancel: false

		function requestCancel() {
			// While the reader has its turn pam_unix has not run, so there is
			// nothing for faillock to count.
			if (dialogWindow.confirmingCancel || dialogWindow.readerTurn) {
				dialogWindow.flow?.cancelAuthenticationRequest();
				return;
			}

			dialogWindow.confirmingCancel = true;
			cancelTimeout.restart();
		}

		Timer {
			id: cancelTimeout

			interval: 5000
			onTriggered: dialogWindow.confirmingCancel = false
		}

		function submitPassword() {
			const flow = dialogWindow.flow;
			if (flow === null || password.text === "")
				return;

			if (flow.isResponseRequired)
				flow.submit(password.text);
			else
				dialogWindow.pendingPassword = password.text;
			password.clear();
		}

		readonly property bool active: dialogWindow.flow !== null
			&& !dialogWindow.flow.isCompleted

		// Stays mapped until the sheet has animated out.
		visible: dialogWindow.active || dialog.sheet.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:polkit"
		// Exclusive focus: while the prompt is up, keystrokes come here and
		// not to whatever was focused before.
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		// Blur the whole desktop, not just behind the sheet: this is modal, and
		// the blur is what lets the scrim stay light.
		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		onVisibleChanged: {
			if (dialogWindow.visible) {
				password.clear();
				password.focusInput();
			}
		}

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: dialogWindow.active

			title: "Authentication Required"
			body: dialogWindow.flow?.message ?? ""

			focus: true
			Keys.onEscapePressed: dialogWindow.requestCancel()

			GlassField {
				id: password

				width: parent.width

				// There from the start, though PAM may not ask yet: while the
				// reader has its turn, what is typed waits for it.
				// polkitd says what to ask for, so the field says it too.
				placeholder: dialogWindow.pendingPassword !== "" ? "Waiting for the reader…"
					: (dialogWindow.flow?.isResponseRequired ?? false)
						? dialogWindow.flow.inputPrompt : "Password"

				echoMode: (dialogWindow.flow?.responseVisible ?? false)
					? TextInput.Normal : TextInput.Password

				onAccepted: dialogWindow.submitPassword()
			}

			FingerprintLine {
				visible: dialogWindow.readerTurn
				isError: dialogWindow.fingerError !== ""
				text: dialogWindow.fingerError !== ""
					? dialogWindow.fingerError : dialogWindow.fingerPrompt
			}

			// Why cancelling is not free.
			Text {
				width: parent.width
				wrapMode: Text.WordWrap
				visible: dialogWindow.confirmingCancel
				text: "Cancelling counts as a failed attempt. "
					+ "Press Cancel again to abandon."
				font.pixelSize: Theme.fontCaption
				lineHeight: 1.4
				color: Theme.warning
			}

			// Retry counts, lockout warnings and other feedback from PAM.
			Text {
				width: parent.width
				wrapMode: Text.WordWrap
				text: dialogWindow.supplementaryLines.join("\n")
				visible: text !== ""
				font.pixelSize: Theme.fontCaption
				lineHeight: 1.4

				color: (dialogWindow.flow?.supplementaryIsError ?? false)
					? Theme.danger : Theme.glassTextMuted
			}

			Row {
				anchors.right: parent.right
				spacing: Theme.spacingS

				DialogButton {
					text: dialogWindow.confirmingCancel ? "Cancel anyway" : "Cancel"
					variant: dialogWindow.confirmingCancel
						? "destructive" : "secondary"
					onClicked: dialogWindow.requestCancel()
				}

				DialogButton {
					text: "Authenticate"
					variant: "primary"
					enabled: (dialogWindow.flow?.isResponseRequired ?? false)
						|| (dialogWindow.readerTurn && password.text !== "")
					onClicked: dialogWindow.submitPassword()
				}
			}
		}
	}
}
