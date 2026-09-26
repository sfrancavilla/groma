import QtQuick
import "../icons"
import ".."

// A text field as a glass track, with a focus ring rather than a thicker
// border - a border that grows on focus nudges everything beside it.
Item {
	id: field

	property alias text: input.text
	property alias echoMode: input.echoMode
	property string placeholder: ""
	// Offers an eye to show what was typed. A password field you cannot check
	// is a password field you retype.
	property bool revealable: false
	property bool revealed: false

	// An optional glyph inside the track, ahead of the text - the design's
	// magnifier on the network picker's search box.
	property Component leading: null

	property int fontSize: Theme.fontTitle

	signal accepted
	// Return with Shift held. The input owns Return, so the modifier has to
	// be read here, not on whatever contains the field.
	signal acceptedAlternate
	// Tab, which the input would otherwise hand to focus navigation.
	signal tabbed

	function clear() {
		input.text = "";
	}

	function focusInput() {
		input.forceActiveFocus();
	}

	implicitWidth: 200
	implicitHeight: Theme.sliderHeight

	// Where the text starts. The placeholder and the input both read it, so
	// adding a glyph cannot move one without the other.
	readonly property real textInset: field.leading
		? Theme.spacingL + leadingLoader.width + Theme.spacingS + 2
		: Theme.spacingL + 2

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

		Loader {
			id: leadingLoader

			anchors {
				left: parent.left
				leftMargin: Theme.spacingL
				verticalCenter: parent.verticalCenter
			}

			active: field.leading !== null
			sourceComponent: field.leading
		}

		Text {
			anchors {
				left: parent.left
				leftMargin: field.textInset
				verticalCenter: parent.verticalCenter
			}

			text: field.placeholder
			visible: input.text === ""
			font.pixelSize: field.fontSize
			font.weight: Font.DemiBold
			opacity: 0.55
			color: Theme.glassTextPrimary
		}

		EyeIcon {
			anchors {
				right: parent.right
				rightMargin: Theme.spacingL
				verticalCenter: parent.verticalCenter
			}

			visible: field.revealable
			crossed: field.revealed
			opacity: revealMouse.containsMouse ? 1.0 : 0.7
			color: Theme.glassTextPrimary

			MouseArea {
				id: revealMouse

				anchors.fill: parent
				anchors.margins: -6
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				onClicked: field.revealed = !field.revealed
			}
		}

		TextInput {
			id: input

			anchors {
				fill: parent
				leftMargin: field.textInset
				rightMargin: field.revealable
					? Theme.spacingL * 2 + 16 : Theme.spacingL + 2
			}

			verticalAlignment: TextInput.AlignVCenter
			clip: true
			echoMode: field.revealable && field.revealed
				? TextInput.Normal : field.echoMode
			font.pixelSize: field.fontSize
			font.weight: Font.DemiBold
			color: Theme.glassTextPrimary
			selectionColor: Theme.glassControlHover
			selectedTextColor: Theme.glassTextPrimary

			Keys.onPressed: event => {
				if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
						&& (event.modifiers & Qt.ShiftModifier)) {
					event.accepted = true;
					field.acceptedAlternate();
				} else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
					event.accepted = true;
					field.tabbed();
				}
			}

			onAccepted: field.accepted()
		}
	}
}
