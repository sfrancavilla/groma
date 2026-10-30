import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import "modules"
import "ui"
import "integrations/nothingear"

ShellRoot {
	// Settings' Hyprland choices, kept in step with ~/.config/hypr/groma.lua.
	// Named here because a singleton nobody mentions is never made, and the
	// file should follow settings.json from the start, not from the first
	// time Settings is opened.
	readonly property var hyprConfig: HyprConfig

	// The desktop background, on every screen. Drawn, so the glass has
	// something to tint.
	Variants {
		model: Quickshell.screens

		Wallpaper {
			required property var modelData

			screen: modelData
		}
	}

	// The polkit password prompt, defined in PolkitDialog.qml.
	PolkitDialog {}

	// The notification daemon and its toast stack.
	Notifications { id: notificationDaemon }

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
	// same sheet. Its controller is the lead bar's NetworkControl, set from
	// the bar below.
	NetworkDialog {
		id: networkDialog
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
		id: captureService

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

	// The bar, on every screen. Each is whole - its own cards, opening under
	// it - and the one on the screen in use is the one keybinds reach.
	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: bar

			required property var modelData

			screen: modelData

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
					capture: captureService
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

			// CENTER: the clock, and the month it opens.
			ClockControl {
				anchors.centerIn: parent
				notifications: notificationDaemon
			}

			// The network sheet reads the lead bar's list. RestoreNone, so the
			// controller passes from one bar to the next rather than through
			// null on the way.
			Binding {
				target: networkDialog
				property: "controller"
				value: networkControl
				when: networkControl.lead
				restoreMode: Binding.RestoreNone
			}
		}
	}
}
