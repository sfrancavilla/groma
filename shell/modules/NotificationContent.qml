import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import ".."
import "../ui"

// What one notification says: its artwork, who sent it and when, the summary,
// the body and its buttons. The toast and the notification centre draw it on
// different glass; this is the part they share.
//
// A click on the notification itself is the caller's: it is a MouseArea
// under this, so the buttons in here take their own clicks first.
Row {
	id: content

	required property var notification
	// When it arrived, in ms, or 0 if the shell does not know (it was
	// reloaded since).
	property real arrived: 0
	// For "5 min ago" to move on while it is on screen.
	property real now: Date.now()

	readonly property bool isCritical: content.notification.urgency === NotificationUrgency.Critical

	// Resolved once here rather than branching on Theme.glass at every use.
	readonly property color cardText: Theme.glass ? Theme.glassTextPrimary : Theme.textPrimary
	readonly property color cardTextBody: Theme.glass ? Theme.glassTextSecondary : Theme.textSecondary
	readonly property color cardTextMuted: Theme.glass ? Theme.glassTextMuted : Theme.textMuted

	// Clients supply artwork two different ways: an `image` hint (album art, an
	// avatar) or an `app_icon`, which is usually a themed icon name that has to
	// be looked up rather than a path.
	readonly property string artwork: {
		if (content.notification.image !== "")
			return content.notification.image;

		const icon = content.notification.appIcon;
		if (icon === "")
			return "";
		if (icon.startsWith("/") || icon.startsWith("file:"))
			return icon;

		return Quickshell.iconPath(icon, true);
	}

	// "default" is what clicking the notification does, not a button: it is
	// the caller's click, and drawing it as well would offer it twice.
	readonly property var buttons: content.notification.actions.filter(a => a.identifier !== "default")

	signal closeClicked

	spacing: Theme.spacingM

	// Whatever artwork the client attached, if we could resolve it.
	Image {
		id: thumbnail

		// An icon name can resolve in the theme index while no usable file
		// exists behind it. That failure arrives as a successfully-loaded
		// empty image rather than an error, so the only reliable test is
		// whether anything with a size came back.
		visible: content.artwork !== ""
			&& thumbnail.status === Image.Ready
			&& thumbnail.implicitWidth > 0
		source: content.artwork
		width: visible ? 40 : 0
		height: 40
		fillMode: Image.PreserveAspectCrop
		smooth: true
		asynchronous: true
	}

	Column {
		spacing: Theme.spacingXs
		width: content.width - (thumbnail.visible ? thumbnail.width + content.spacing : 0)

		Item {
			width: parent.width
			height: appLabel.implicitHeight

			Text {
				id: appLabel

				anchors.left: parent.left
				anchors.right: close.left
				anchors.rightMargin: Theme.spacingS
				elide: Text.ElideRight
				text: {
					void content.now;
					return content.notification.appName
						+ (content.arrived > 0 ? " · " + History.ago(content.arrived) : "");
				}
				font.pixelSize: Theme.fontCaption
				style: Theme.glass ? Text.Raised : Text.Normal
				styleColor: Theme.glassTextShadow
				color: content.isCritical ? Theme.danger : content.cardTextMuted
			}

			// The same mark the sheets close with, at a toast's size. It
			// was a text "×", which renders at whatever the font decides.
			DiscButton {
				id: close

				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter

				width: 20
				height: 20
				glyph: "close"
				markColor: content.cardTextMuted

				onClicked: content.closeClicked()
			}
		}

		Text {
			width: parent.width
			text: content.notification.summary
			font.pixelSize: Theme.fontTitle
			font.bold: true
			style: Theme.glass ? Text.Raised : Text.Normal
			styleColor: Theme.glassTextShadow
			elide: Text.ElideRight
			color: content.cardText
		}

		Text {
			width: parent.width
			text: content.notification.body
			visible: text !== ""
			style: Theme.glass ? Text.Raised : Text.Normal
			styleColor: Theme.glassTextShadow
			wrapMode: Text.WordWrap
			maximumLineCount: 4
			elide: Text.ElideRight
			// Clients may send limited markup in the body.
			textFormat: Text.StyledText
			color: content.cardTextBody
		}

		Row {
			spacing: Theme.spacingS
			visible: content.buttons.length > 0

			Repeater {
				model: content.buttons

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
