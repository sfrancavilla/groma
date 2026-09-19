import QtQuick
import ".."

// A text field as a glass track, with a focus ring rather than a thicker
// border - a border that grows on focus nudges everything beside it.
Item {
	id: field

	property alias text: input.text
	property alias echoMode: input.echoMode
	property string placeholder: ""

	signal accepted

	function clear() {
		input.text = "";
	}

	function focusInput() {
		input.forceActiveFocus();
	}

	implicitWidth: 200
	implicitHeight: Theme.sliderHeight

	Rectangle {
		anchors.fill: parent
		anchors.margins: -3
		radius: (parent.height + 6) / 2
		color: Theme.focusRing
		visible: input.activeFocus
	}

	Rectangle {
		anchors.fill: parent
		radius: height / 2
		color: Theme.glassTrack
		border.width: 1
		border.color: input.activeFocus
			? Theme.glassTrackBorderFocus : Theme.glassTrackBorder

		Text {
			anchors {
				left: parent.left
				leftMargin: Theme.spacingL + 2
				verticalCenter: parent.verticalCenter
			}

			text: field.placeholder
			visible: input.text === ""
			font.pixelSize: Theme.fontTitle
			font.weight: Font.DemiBold
			opacity: 0.55
			color: Theme.glassTextPrimary
		}

		TextInput {
			id: input

			anchors {
				fill: parent
				leftMargin: Theme.spacingL + 2
				rightMargin: Theme.spacingL + 2
			}

			verticalAlignment: TextInput.AlignVCenter
			clip: true
			font.pixelSize: Theme.fontTitle
			font.weight: Font.DemiBold
			color: Theme.glassTextPrimary
			selectionColor: Theme.glassControlHover
			selectedTextColor: Theme.glassTextPrimary

			onAccepted: field.accepted()
		}
	}
}
