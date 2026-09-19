import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// One notification card. Repeater hands each delegate its element as
// `modelData`, which `required property` makes explicit.
Rectangle {
	id: toast

	required property var modelData
	readonly property bool isCritical:
		toast.modelData.urgency === NotificationUrgency.Critical

	// Clients supply artwork two different ways: an `image` hint (album art, an
	// avatar) or an `app_icon`, which is usually a themed icon name that has to
	// be looked up rather than a path.
	readonly property string artwork: {
		if (toast.modelData.image !== "")
			return toast.modelData.image;

		const icon = toast.modelData.appIcon;
		if (icon === "")
			return "";
		if (icon.startsWith("/") || icon.startsWith("file:"))
			return icon;

		return Quickshell.iconPath(icon, true);
	}

	width: parent.width
	implicitHeight: layout.implicitHeight + 24
	height: implicitHeight
	radius: Theme.radiusMedium

	color: Theme.surface
	border.width: toast.isCritical ? 2 : 1
	border.color: toast.isCritical ? Theme.danger : Theme.borderSubtle

	// Notifications carry their own lifetime. A timeout of 0 means "wait for
	// the user", and urgent ones should not disappear on their own either.
	Timer {
		running: !toast.isCritical && toast.modelData.expireTimeout !== 0
		interval: toast.modelData.expireTimeout > 0
			? toast.modelData.expireTimeout
			: 5000
		onTriggered: toast.modelData.expire()
	}

	Row {
		id: layout

		anchors {
			left: parent.left
			right: parent.right
			verticalCenter: parent.verticalCenter
			leftMargin: 12
			rightMargin: 12
		}

		spacing: 10

		// Whatever artwork the client attached, if we could resolve it.
		Image {
			id: thumbnail

			// An icon name can resolve in the theme index while no usable file
			// exists behind it. That failure arrives as a successfully-loaded
			// empty image rather than an error, so the only reliable test is
			// whether anything with a size came back.
			visible: toast.artwork !== ""
				&& thumbnail.status === Image.Ready
				&& thumbnail.implicitWidth > 0
			source: toast.artwork
			width: visible ? 40 : 0
			height: 40
			fillMode: Image.PreserveAspectCrop
			smooth: true
			asynchronous: true
		}

		Column {
			spacing: 4
			width: layout.width
				- (thumbnail.visible ? thumbnail.width + layout.spacing : 0)

			Item {
				width: parent.width
				height: appLabel.implicitHeight

				Text {
					id: appLabel

					anchors.left: parent.left
					text: toast.modelData.appName
					font.pixelSize: 11
					color: toast.isCritical ? Theme.danger : Theme.textMuted
				}

				Text {
					anchors.right: parent.right
					text: "×"
					font.pixelSize: 14
					color: closeMouse.containsMouse ? Theme.textPrimary : Theme.textMuted

					MouseArea {
						id: closeMouse

						anchors.fill: parent
						anchors.margins: -6
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						// dismiss() reports that the user closed it, which is
						// not the same as the notification timing out.
						onClicked: toast.modelData.dismiss()
					}
				}
			}

			Text {
				width: parent.width
				text: toast.modelData.summary
				font.pixelSize: 13
				font.bold: true
				elide: Text.ElideRight
				color: Theme.textPrimary
			}

			Text {
				width: parent.width
				text: toast.modelData.body
				visible: text !== ""
				wrapMode: Text.WordWrap
				maximumLineCount: 4
				elide: Text.ElideRight
				// Clients may send limited markup in the body.
				textFormat: Text.StyledText
				color: Theme.textSecondary
			}

			Row {
				spacing: 6
				visible: toast.modelData.actions.length > 0

				Repeater {
					model: toast.modelData.actions

					DialogButton {
						required property var modelData

						text: modelData.text
						implicitHeight: 26
						onClicked: modelData.invoke()
					}
				}
			}
		}
	}
}
