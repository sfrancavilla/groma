import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import ".."
import "../ui"

// One notification card. Repeater hands each delegate its element as
// `modelData`, which `required property` makes explicit.
GlassPanel {
	id: toast

	required property var modelData
	readonly property bool isCritical:
		toast.modelData.urgency === NotificationUrgency.Critical

	// Resolved once here rather than branching on Theme.glass at every use.
	readonly property color cardText:
		Theme.glass ? Theme.glassTextPrimary : Theme.textPrimary
	readonly property color cardTextBody:
		Theme.glass ? Theme.glassTextSecondary : Theme.textSecondary
	readonly property color cardTextMuted:
		Theme.glass ? Theme.glassTextMuted : Theme.textMuted

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
	implicitHeight: layout.implicitHeight + Theme.spacingM * 2
	height: implicitHeight
	radius: Theme.radiusMedium
	danger: toast.isCritical

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
			leftMargin: Theme.spacingM
			rightMargin: Theme.spacingM
		}

		spacing: Theme.spacingM

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
			spacing: Theme.spacingXs
			width: layout.width
				- (thumbnail.visible ? thumbnail.width + layout.spacing : 0)

			Item {
				width: parent.width
				height: appLabel.implicitHeight

				Text {
					id: appLabel

					anchors.left: parent.left
					text: toast.modelData.appName
					font.pixelSize: Theme.fontCaption
					style: Theme.glass ? Text.Raised : Text.Normal
					styleColor: Theme.glassTextShadow
					color: toast.isCritical ? Theme.danger : toast.cardTextMuted
				}

				// The same mark the sheets close with, at a toast's size. It
				// was a text "×", which renders at whatever the font decides.
				DiscButton {
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter

					width: 20
					height: 20
					glyph: "close"
					markColor: toast.cardTextMuted

					// dismiss() reports that the user closed it, which is not
					// the same as the notification timing out.
					onClicked: toast.modelData.dismiss()
				}
			}

			Text {
				width: parent.width
				text: toast.modelData.summary
				font.pixelSize: Theme.fontTitle
				font.bold: true
				style: Theme.glass ? Text.Raised : Text.Normal
				styleColor: Theme.glassTextShadow
				elide: Text.ElideRight
				color: toast.cardText
			}

			Text {
				width: parent.width
				text: toast.modelData.body
				visible: text !== ""
				style: Theme.glass ? Text.Raised : Text.Normal
				styleColor: Theme.glassTextShadow
				wrapMode: Text.WordWrap
				maximumLineCount: 4
				elide: Text.ElideRight
				// Clients may send limited markup in the body.
				textFormat: Text.StyledText
				color: toast.cardTextBody
			}

			Row {
				spacing: Theme.spacingS
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
