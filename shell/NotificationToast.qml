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

	// Resolved once here rather than branching on Theme.glass at every use.
	// Only consulted in flat mode - in glass mode the edge is the rim gradient,
	// and border.width is 0.
	readonly property color cardBorder:
		toast.isCritical ? Theme.danger : Theme.borderSubtle
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
	implicitHeight: layout.implicitHeight + 24
	height: implicitHeight
	radius: Theme.radiusMedium

	color: Theme.glass ? "transparent" : Theme.surface

	// In glass mode this outer rectangle *is* the edge: filled with a gradient
	// that fades top to bottom, with the pane inset inside it. No stroke.
	border.width: Theme.glass ? 0 : (toast.isCritical ? 2 : 1)
	border.color: toast.cardBorder
	gradient: !Theme.glass ? null
		: toast.isCritical ? dangerRim : glassRim

	Gradient {
		id: glassRim

		GradientStop { position: 0.0; color: Theme.glassRimTop }
		GradientStop { position: 0.35; color: Theme.glassRimMid }
		GradientStop { position: 1.0; color: Theme.glassRimBottom }
	}

	Gradient {
		id: dangerRim

		GradientStop { position: 0.0; color: Theme.glassRimDangerTop }
		GradientStop { position: 0.35; color: Theme.glassRimDangerMid }
		GradientStop { position: 1.0; color: Theme.glassRimDangerBottom }
	}

	// Ambient shadow: concentric rings fading outward, drawn before the pane so
	// they sit behind it. They deliberately extend past the card, which is why
	// the window reserves padding around the stack.
	Repeater {
		model: Theme.glass ? Theme.glassShadowLayers : 0

		Rectangle {
			required property int index

			anchors.fill: parent
			anchors.margins: -(index + 1)
			radius: parent.radius + index + 1
			color: "transparent"
			border.width: 1
			border.color: Qt.rgba(0, 0, 0,
				Theme.glassShadowAlpha / (index + 1))
		}
	}

	// The pane, inset by the rim width so the gradient shows as an edge.
	Rectangle {
		id: pane

		visible: Theme.glass
		anchors.fill: parent
		anchors.margins: Theme.glassRimWidth
		radius: parent.radius - Theme.glassRimWidth

		// A flat fill reads as "a dark box with some alpha". The vertical sheen
		// is what makes it read as a pane of glass catching the light.
		gradient: Gradient {
			GradientStop { position: 0.0; color: Theme.glassSurfaceTop }
			GradientStop { position: 1.0; color: Theme.glassSurfaceBottom }
		}
	}

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
					style: Theme.glass ? Text.Raised : Text.Normal
					styleColor: Theme.glassTextShadow
					color: toast.isCritical ? Theme.danger : toast.cardTextMuted
				}

				Text {
					anchors.right: parent.right
					text: "×"
					font.pixelSize: 14
					color: closeMouse.containsMouse ? toast.cardText : toast.cardTextMuted

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
