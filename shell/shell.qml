import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import "modules"

ShellRoot {
	SystemClock {
		id: clock
		precision: SystemClock.Minutes
	}

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

		// LEFT: workspaces
		Row {
			anchors {
				left: parent.left
				leftMargin: Theme.spacingM
				verticalCenter: parent.verticalCenter	
			}	
	
			spacing: Theme.spacingS

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
							: "transparent")
						: (workspaceButton.isFocused ? Theme.surfaceStrong
							: workspaceMouse.containsMouse ? Theme.surfaceHover
							: Theme.surface)

					Text {
						anchors.centerIn: parent
						text: workspaceButton.workspaceId
						color: Theme.glass ? Theme.glassTextPrimary
							: workspaceButton.isFocused ? Theme.textOnStrong
							: Theme.textPrimary
						style: Theme.glass ? Text.Raised : Text.Normal
						styleColor: Theme.glassTextShadow
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
				rightMargin: Theme.spacingM
				verticalCenter: parent.verticalCenter
			}
			spacing: Theme.spacingL

			VolumeControl {
				anchors.verticalCenter: parent.verticalCenter
			}

			BatteryControl {
				anchors.verticalCenter: parent.verticalCenter
			}

		}

		// CENTER: clock		
		Text {
			anchors.centerIn: parent
			color: bar.barText
			style: Theme.glass ? Text.Raised : Text.Normal
			styleColor: Theme.glassTextShadow
			text: Qt.formatDateTime(clock.date, "ddd d MMM hh:mm")
		}
 
	}
}
