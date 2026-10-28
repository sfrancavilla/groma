import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import ".."
import "../ui"

// One notification as it arrives: a card in the corner that goes by itself.
// Going is not the end of it - the notification stays in the centre, under
// the clock, until it is dismissed there or here.
GlassPanel {
	id: toast

	required property var modelData
	property real arrived: 0

	readonly property bool isCritical:
		toast.modelData.urgency === NotificationUrgency.Critical

	// Its time on screen is up: Notifications takes it off the stack.
	signal timedOut

	width: parent.width
	implicitHeight: content.implicitHeight + Theme.spacingM * 2
	height: implicitHeight
	radius: Theme.radiusMedium
	danger: toast.isCritical

	// Notifications carry their own lifetime. A timeout of 0 means "wait for
	// the user", and urgent ones should not disappear on their own either.
	// Paused while pointed at, so a long one can be read to the end.
	Timer {
		running: toast.visible && !toast.isCritical && toast.modelData.expireTimeout !== 0
			&& !click.containsMouse
		interval: toast.modelData.expireTimeout > 0
			? toast.modelData.expireTimeout
			: 5000
		onTriggered: toast.timedOut()
	}

	// A click does what the notification is for - its "default" action, if
	// it has one - and a right-click puts it away.
	MouseArea {
		id: click

		anchors.fill: parent
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.RightButton
		onClicked: mouse => {
			const open = toast.modelData.actions.find(a => a.identifier === "default");
			if (mouse.button === Qt.LeftButton && open)
				open.invoke();
			else if (mouse.button === Qt.RightButton)
				toast.modelData.dismiss();
		}
	}

	NotificationContent {
		id: content

		anchors {
			left: parent.left
			right: parent.right
			verticalCenter: parent.verticalCenter
			leftMargin: Theme.spacingM
			rightMargin: Theme.spacingM
		}

		notification: toast.modelData
		arrived: toast.arrived

		// dismiss() reports that the user closed it, which is not the same
		// as the notification timing out.
		onCloseClicked: toast.modelData.dismiss()
	}
}
