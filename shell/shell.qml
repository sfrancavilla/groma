import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import QtQuick

ShellRoot {
	SystemClock {
		id: clock
		precision: SystemClock.Minutes
	}

	// The polkit password prompt, defined in PolkitDialog.qml.
	PolkitDialog {}

	// The notification daemon and its toast stack.
	Notifications {}

	PwObjectTracker {
		objects: [Pipewire.defaultAudioSink]
	}

	PanelWindow {
		anchors {
			top: true
			left: true
			right: true
		}

		WlrLayershell.namespace: "groma:bar"

		implicitHeight: 32

		// LEFT: workspaces
		Row {
			anchors {
				left: parent.left
				leftMargin: 10
				verticalCenter: parent.verticalCenter	
			}	
	
			spacing: 6

			Repeater {
				model: Hyprland.workspaces
				
				Rectangle {
					id: workspaceButton
					required property var modelData
					readonly property int workspaceId: modelData.id
					readonly property bool isFocused: modelData.focused
					
					width: 26
					height: 22
					radius: 6

					color: workspaceButton.isFocused ? "#444444"
						: workspaceMouse.containsMouse ? "#dddddd" : "#ffffff"

					Text {
						anchors.centerIn: parent
						text: workspaceButton.workspaceId
						color: workspaceButton.isFocused ? "#ffffff" : "#000000"
					}

					MouseArea {
						id: workspaceMouse
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: workspaceButton.modelData.activate()
					}
				}
			}
		}

		// RIGHT: volume and battery
		Row {
			anchors {
				right: parent.right
				rightMargin: 10
				verticalCenter: parent.verticalCenter
			}
			spacing: 16

			Text {
				anchors.verticalCenter: parent.verticalCenter
				text: {
					const sink = Pipewire.defaultAudioSink;
					if (!sink?.ready || !sink.audio)
						return "Vol --";
					return sink.audio.muted ? "Muted"
						: "Vol " + Math.round(sink.audio.volume * 100) + "%";
				}
			}

			Text {
				anchors.verticalCenter: parent.verticalCenter
				color: UPower.displayDevice.ready && UPower.displayDevice.isPresent
					&& UPower.displayDevice.state === UPowerDeviceState.Discharging
					&& UPower.displayDevice.percentage <= 0.20
					? "#cc3333" : "#000000"

				text: UPower.displayDevice.ready && UPower.displayDevice.isPresent
					? (UPower.displayDevice.state === UPowerDeviceState.Charging ? "⚡ " : "")
						+ Math.round(UPower.displayDevice.percentage * 100) + "%"
					: "--%"
			}

		}

		// CENTER: clock		
		Text {
			anchors.centerIn: parent
			text: Qt.formatDateTime(clock.date, "ddd d MMM hh:mm")
		}
 
	}
}
