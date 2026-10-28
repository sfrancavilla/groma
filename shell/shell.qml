import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import "modules"
import "ui"
import "integrations/nothingear"

ShellRoot {
	SystemClock {
		id: clock
		precision: SystemClock.Minutes
	}

	// Settings' Hyprland choices, kept in step with ~/.config/hypr/groma.lua.
	// Named here because a singleton nobody mentions is never made, and the
	// file should follow settings.json from the start, not from the first
	// time Settings is opened.
	readonly property var hyprConfig: HyprConfig

	// The desktop background. Drawn, so the glass has something to tint.
	Wallpaper {}

	// The polkit password prompt, defined in PolkitDialog.qml.
	PolkitDialog {}

	// The notification daemon and its toast stack.
	Notifications {}

	// Not a lock screen yet - a harness for proving the PAM conversation.
	LockScreen { id: lockScreen }

	// Dim, then lock, then turn the screen off.
	IdleChain { lock: lockScreen }

	// Bluez needs an agent to vouch for a pairing, and QML cannot be one.
	BluetoothAgent {
		id: bluetoothAgent
	}

	// Every Bluetooth device in range, and what to do with it.
	BluetoothDialog {
		id: bluetoothDialog

		agent: bluetoothAgent
	}

	// "Does this passkey match the one on the device?"
	BluetoothPairDialog {
		agent: bluetoothAgent
	}

	// Every network in range, and the form for joining one: two pages of the
	// same sheet.
	NetworkDialog {
		id: networkDialog

		controller: networkControl
	}

	// Keeps what passes through the clipboard, for the launcher's ":" mode.
	Clipboard {
		id: clipboard
	}

	// Type, pick, Enter.
	Launcher {
		clipboard: clipboard
	}

	// Booted into a snapshot from the boot menu? A sheet at login, and the
	// chip in the bar below for the rest of the session.
	SnapshotBoot {
		id: snapshotBoot
	}

	// What snapper has kept: system changes to undo, home snapshots to browse.
	SnapshotsDialog {}

	// The fingers that unlock the lock screen, and adding one.
	FingerprintDialog {}

	// The file manager: an ordinary window, opened from SUPER+E.
	FilesWindow { id: files }

	// Groma Store: installing and updating, from the official repositories and the AUR.
	SoftwareWindow {}

	// Settings: keyboard, display, idle, wallpaper and the rest, as a window.
	SettingsWindow {
		earbuds: nothingEar
	}

	// Screenshots and screen recordings: Print, Shift+Print, Alt+Print.
	Capture {
		id: capture

		files: files
	}

	// Feedback for the volume and brightness keys, and for things that
	// happened to the sound.
	Osd { id: osd }

	// --- Device integrations ---------------------------------------------
	// Vendor-specific. Each lives in integrations/<name>/, fills a baseline
	// contract, and costs nothing until its device is present. Remove the
	// instance to remove the integration; nothing else refers to it.

	// Nothing earbuds: per-bud battery, and a pause when a bud comes out.
	NothingEar {
		id: nothingEar

		osd: osd
	}

	PwObjectTracker {
		objects: [Pipewire.defaultAudioSink]
	}

	PanelWindow {
		id: bar

		anchors {
			top: true
			left: true
			right: true
		}

		WlrLayershell.namespace: "groma:bar"

		implicitHeight: Theme.barHeight

		// The bar has no surface of its own: the widgets float directly over
		// the desktop. It still reserves its 32px, so nothing is ever behind
		// it except the background - which is what makes this readable rather
		// than a gamble on whatever window happens to be underneath.
		//
		// No blur either. Blurring behind a surface that draws nothing would
		// just smear a band across the top of the wallpaper.
		color: Theme.glass ? "transparent" : Theme.surface

		readonly property color barText:
			Theme.glass ? Theme.glassTextPrimary : Theme.textPrimary

		// LEFT: workspaces, by number or by what they are for.
		Workspaces {
			anchors {
				left: parent.left
				leftMargin: Theme.spacingM
				verticalCenter: parent.verticalCenter
			}
		}

		// RIGHT: volume and battery
		Row {
			anchors {
				right: parent.right
				rightMargin: Theme.spacingM
				verticalCenter: parent.verticalCenter
			}
			spacing: Theme.spacingL

			// Only while recording the screen: how long, and a click stops it.
			RecordingControl {
				anchors.verticalCenter: parent.verticalCenter
				capture: capture
			}

			// Only while running a snapshot: amber, because nothing done in
			// this session survives a restart.
			Chip {
				anchors.verticalCenter: parent.verticalCenter
				visible: snapshotBoot.active
				text: "Snapshot " + snapshotBoot.number
				accent: Theme.warning
				onClicked: snapshotBoot.open = true
			}

			BluetoothControl {
				anchors.verticalCenter: parent.verticalCenter
				dialog: bluetoothDialog
				batteryDetail: nothingEar
			}

			NetworkControl {
				id: networkControl

				anchors.verticalCenter: parent.verticalCenter
				dialog: networkDialog
			}

			VolumeControl {
				anchors.verticalCenter: parent.verticalCenter
			}

			BatteryControl {
				anchors.verticalCenter: parent.verticalCenter
			}

			// Processor, memory and disk, filled by how much is in use.
			SystemControl {
				anchors.verticalCenter: parent.verticalCenter
			}

			// Lock, suspend, log out, restart, power off.
			PowerControl {
				anchors.verticalCenter: parent.verticalCenter
			}

		}

		// CENTER: clock		
		Text {
			anchors.centerIn: parent
			color: bar.barText
			style: Theme.glass ? Text.Raised : Text.Normal
			styleColor: Theme.glassTextShadow
			// As chosen in Settings: the date or not, 24 hours or 12.
			text: Qt.formatDateTime(clock.date,
				(Settings.clockDate ? "ddd d MMM " : "") + (Settings.clock24 ? "HH:mm" : "h:mm AP"))
		}
 
	}
}
