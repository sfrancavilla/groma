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
		id: bar

		anchors {
			top: true
			left: true
			right: true
		}

		WlrLayershell.namespace: "groma:bar"

		implicitHeight: 32

		// In glass mode the window itself draws nothing; the panel below is
		// the surface. In flat mode the window is the surface.
		color: Theme.glass ? "transparent" : Theme.surface

		readonly property color barText:
			Theme.glass ? Theme.glassTextPrimary : Theme.textPrimary

		// Blur behind the bar, for the same reason as the toasts: without it
		// the translucency just shows a sharp desktop through a dark film.
		BackgroundEffect.blurRegion: Region { item: barGlass }

		// Declared first so everything else sits on top of it. No radius - it
		// spans the screen edge - and one shadow ring to separate it from the
		// desktop rather than four to feather it.
		GlassPanel {
			id: barGlass

			visible: Theme.glass
			anchors.fill: parent
			radius: 0
			shadowLayers: 1
		}

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
					radius: Theme.radiusSmall

					color: Theme.glass
						? (workspaceButton.isFocused ? Theme.glassControlStrong
							: workspaceMouse.containsMouse ? Theme.glassControlHover
							: Theme.glassControl)
						: (workspaceButton.isFocused ? Theme.surfaceStrong
							: workspaceMouse.containsMouse ? Theme.surfaceHover
							: Theme.surface)

					Text {
						anchors.centerIn: parent
						text: workspaceButton.workspaceId
						color: Theme.glass ? Theme.glassTextPrimary
							: workspaceButton.isFocused ? Theme.textOnStrong
							: Theme.textPrimary
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
				color: bar.barText
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
					? Theme.danger : bar.barText

				text: UPower.displayDevice.ready && UPower.displayDevice.isPresent
					? (UPower.displayDevice.state === UPowerDeviceState.Charging ? "⚡ " : "")
						+ Math.round(UPower.displayDevice.percentage * 100) + "%"
					: "--%"
			}

		}

		// CENTER: clock		
		Text {
			anchors.centerIn: parent
			color: bar.barText
			text: Qt.formatDateTime(clock.date, "ddd d MMM hh:mm")
		}
 
	}
}
