import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick

// A polkit authentication agent: the password prompt that appears when an
// application asks to do something administrative.
//
// Quickshell's PolkitAgent handles the protocol with polkitd. All we supply
// is the interface: show the request, collect a password, submit it.
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

		// PAM sends feedback one message at a time, and each new message replaces
		// the previous one. Collect them so an explanation is not lost the
		// instant a follow-up line arrives.
		property var supplementaryLines: []

		// A new request starts with a clean slate.
		onFlowChanged: dialogWindow.supplementaryLines = []

		Connections {
			target: dialogWindow.flow

			function onSupplementaryMessageChanged() {
				const message = dialogWindow.flow.supplementaryMessage;
				if (message === "")
					return;

				// Keep the last few lines so a long retry sequence cannot grow
				// the dialog without bound.
				dialogWindow.supplementaryLines =
					dialogWindow.supplementaryLines.concat(message).slice(-4);
			}
		}

		function submitPassword() {
			dialogWindow.flow?.submit(passwordInput.text);
			passwordInput.text = "";
		}

		visible: dialogWindow.flow !== null && !dialogWindow.flow.isCompleted

		// Cover the whole screen so we can dim it, but never reserve space
		// the way the bar does.
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

		BackgroundEffect.blurRegion: Region {
			item: card
			radius: Theme.radiusLarge
		}

		onVisibleChanged: {
			if (dialogWindow.visible) {
				passwordInput.text = "";
				passwordInput.forceActiveFocus();
			}
		}

		// Dim the desktop behind the dialog, and swallow stray clicks.
		Rectangle {
			anchors.fill: parent
			color: Theme.scrim

			MouseArea {
				anchors.fill: parent
			}
		}

		GlassPanel {
			id: card

			anchors.centerIn: parent
			width: 420
			height: content.implicitHeight + 40
			radius: Theme.radiusLarge

			// Resolved once rather than branching on Theme.glass at every use.
			readonly property color cardText:
				Theme.glass ? Theme.glassTextPrimary : Theme.textPrimary
			readonly property color cardTextBody:
				Theme.glass ? Theme.glassTextSecondary : Theme.textSecondary
			readonly property color cardTextMuted:
				Theme.glass ? Theme.glassTextMuted : Theme.textMuted

			// Take focus so Escape reaches us even when no password field is shown.
			focus: true
			Keys.onEscapePressed: dialogWindow.flow?.cancelAuthenticationRequest()

			Column {
				id: content

				anchors {
					left: parent.left
					right: parent.right
					verticalCenter: parent.verticalCenter
					leftMargin: 20
					rightMargin: 20
				}

				spacing: 12

				Text {
					text: "Authentication Required"
					font.pixelSize: 16
					font.bold: true
					color: card.cardText
				}

				Text {
					width: parent.width
					wrapMode: Text.WordWrap
					text: dialogWindow.flow?.message ?? ""
					color: card.cardTextBody
				}

				// polkitd tells us what to ask for ("Password: ") and whether
				// the answer should be shown on screen.
				Text {
					text: dialogWindow.flow?.inputPrompt ?? "Password:"
					color: card.cardTextBody
					visible: dialogWindow.flow?.isResponseRequired ?? false
				}

				Rectangle {
					width: parent.width
					height: 34
					radius: Theme.radiusSmall
					color: Theme.glass ? Theme.glassControl : Theme.surfaceSunken
					border.width: passwordInput.activeFocus ? 2 : 1
					border.color: passwordInput.activeFocus
						? (Theme.glass ? Theme.glassTextPrimary : Theme.borderFocus)
						: (Theme.glass ? Theme.glassControlBorder : Theme.border)
					visible: dialogWindow.flow?.isResponseRequired ?? false
					onVisibleChanged: if (visible) passwordInput.forceActiveFocus()

					TextInput {
						id: passwordInput

						anchors {
							fill: parent
							leftMargin: 10
							rightMargin: 10
						}

						verticalAlignment: TextInput.AlignVCenter
						clip: true
						color: card.cardText
						echoMode: (dialogWindow.flow?.responseVisible ?? false)
							? TextInput.Normal : TextInput.Password

						onAccepted: dialogWindow.submitPassword()
					}
				}

				// Retry counts, lockout warnings and other feedback from PAM.
				Text {
					width: parent.width
					wrapMode: Text.WordWrap
					text: dialogWindow.supplementaryLines.join("\n")
					visible: text !== ""
					color: (dialogWindow.flow?.supplementaryIsError ?? false)
						? Theme.danger : card.cardTextMuted
				}

				Row {
					anchors.right: parent.right
					spacing: 8

					DialogButton {
						text: "Cancel"
						onClicked: dialogWindow.flow?.cancelAuthenticationRequest()
					}

					DialogButton {
						text: "Authenticate"
						primary: true
						enabled: dialogWindow.flow?.isResponseRequired ?? false
						onClicked: dialogWindow.submitPassword()
					}
				}
			}
		}
	}
}
