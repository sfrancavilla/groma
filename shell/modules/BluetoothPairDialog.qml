import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import QtQuick
import ".."
import "../icons"
import "../ui"

// The design's 8d: bluez has asked whether a passkey matches the one on the
// device, and this is where that question gets asked of a person.
//
// A prompt, so by the guidelines it carries no X - Cancel is the way out - and
// its answer buttons split the width rather than sitting in a corner, because
// there are only two things to do and they are equally weighted.
Scope {
	id: root

	// The agent that owns the conversation with bluez.
	property var agent: null

	readonly property string passkey: root.agent?.passkey ?? ""
	readonly property bool open: root.passkey !== ""

	readonly property string deviceName: {
		const address = root.agent?.pairingWith ?? "";
		const device = (Bluetooth.devices?.values ?? []).find(
			entry => entry.address === address) ?? null;

		if (device === null || device.name === "")
			return address;

		return device.name;
	}

	PanelWindow {
		id: window

		visible: root.open || dialog.sheet.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:bluetooth-pair"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			// Narrower than the pickers: this is a question, not a list.
			sheetWidth: Theme.dialogWidthPrompt
			padding: 28
			spacing: Theme.spacingL + 2

			Keys.onEscapePressed: root.agent?.respond(false)
			Keys.onReturnPressed: root.agent?.respond(true)
			Keys.onEnterPressed: root.agent?.respond(true)

			// 8d centres everything, which is right for a question with one
			// fact in the middle of it.
			Item {
				width: parent.width
				height: 72

				Lens {
					anchors.horizontalCenter: parent.horizontalCenter
					width: 72
					height: 72

					BluetoothIcon {
						anchors.centerIn: parent
						height: 28
						width: height * aspect
						color: Theme.glassTextOnLens
					}
				}
			}

			Column {
				width: parent.width
				spacing: Theme.spacingS

				Text {
					width: parent.width
					horizontalAlignment: Text.AlignHCenter
					wrapMode: Text.WordWrap
					text: `Pair with “${root.deviceName}”?`
					font.pixelSize: Theme.fontDisplay
					font.bold: true
					font.letterSpacing: -0.2
					color: Theme.glassTextPrimary
				}

				Text {
					width: parent.width
					horizontalAlignment: Text.AlignHCenter
					wrapMode: Text.WordWrap
					text: "Confirm this passkey matches the one shown on the "
						+ "device."
					font.pixelSize: Theme.fontHeading - 1
					lineHeight: 1.5
					opacity: 0.85
					color: Theme.glassTextPrimary
				}
			}

			// The passkey, a digit to a tile. Six tiles because bluez passkeys
			// are six digits, and the leading zeroes matter - which is why
			// this reads the string rather than the number.
			Row {
				anchors.horizontalCenter: parent.horizontalCenter
				spacing: Theme.spacingS

				Repeater {
					model: root.passkey.padStart(6, "0").split("")

					Rectangle {
						required property string modelData

						width: 44
						height: 52
						radius: Theme.radiusRow - 2

						color: Theme.glassChipDigit
						border.width: 1
						border.color: Theme.glassChipSelectedBorder

						Text {
							anchors.centerIn: parent
							text: modelData
							font.pixelSize: 22
							font.bold: true
							font.family: "monospace"
							color: Theme.glassTextPrimary
						}
					}
				}
			}

			Row {
				width: parent.width
				spacing: Theme.spacingS + 2

				DialogButton {
					width: (parent.width - Theme.spacingS - 2) / 2
					text: "Cancel"
					onClicked: root.agent?.respond(false)
				}

				DialogButton {
					width: (parent.width - Theme.spacingS - 2) / 2
					text: "Pair"
					variant: "primary"
					onClicked: root.agent?.respond(true)
				}
			}
		}
	}
}
