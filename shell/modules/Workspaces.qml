import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../ui"
import ".."

// The workspaces in the bar, by number or by what they are for.
//
// A workspace can carry a name - "Terminals", "Groma", "YouTube" - the way a
// tab group in Chrome does. Right-click it, or SUPER+N for the one you are on.
// A named workspace keeps its place in the bar after its last window closes,
// dimmed, so the name is somewhere to go back to rather than a label that
// disappears with the windows.
//
// Pointing at a workspace for a moment shows what is on it: a miniature of the
// screen with each window drawn live where it sits.
Row {
	id: root

	spacing: Theme.spacingS

	// Every workspace Hyprland has, and every named one it does not have yet.
	// The name is what holds the place: a colour alone is remembered for when
	// the workspace comes back, but does not keep an empty one in the bar.
	readonly property var slots: {
		const live = Hyprland.workspaces.values;
		const liveIds = live.map(ws => ws.id);
		const waiting = Object.keys(Settings.workspaceNames ?? {}).map(Number)
			.filter(id => id > 0 && !liveIds.includes(id));

		return [...live.map(ws => ({ id: ws.id, workspace: ws })),
				...waiting.map(id => ({ id: id, workspace: null }))]
			.sort((a, b) => a.id - b.id);
	}

	function slotFor(id) {
		return root.slots.find(slot => slot.id === id) ?? null;
	}

	function titleFor(id) {
		return Settings.workspaceName(id) || `Workspace ${id}`;
	}

	// Where a workspace's pill starts on screen, for whatever opens under it.
	// Asked at the moment something opens, not bound: mapToItem is a call,
	// and a binding on it would keep its first answer.
	function anchorFor(id) {
		for (let i = 0; i < pills.count; i++) {
			const pill = pills.itemAt(i);
			if (pill?.workspaceId === id)
				return pill.mapToItem(null, 0, 0).x;
		}
		return root.mapToItem(null, 0, 0).x;
	}

	// A workspace with no windows does not exist until something asks for it,
	// so a named one waiting in the bar is reached by number.
	function go(id) {
		const workspace = root.slotFor(id)?.workspace;
		if (workspace)
			workspace.activate();
		else
			Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = ${id} })`]);
	}

	// --- the preview ---------------------------------------------------------

	property bool previewOpen: false
	property int previewId: 0
	property real previewX: 0
	// The pill the pointer is on, or 0.
	property int pointed: 0

	function showPreview(id) {
		root.previewId = id;
		root.previewX = root.anchorFor(id);
		// Window positions are in each toplevel's last IPC answer, which
		// Hyprland only sends again when asked.
		Hyprland.refreshToplevels();
		root.previewOpen = true;
	}

	function pointAt(id) {
		leaveTimer.stop();
		root.pointed = id;
		// Once one card is up, the next follows the pointer without the wait,
		// as hovering along Chrome's tabs does.
		if (root.previewOpen)
			root.showPreview(id);
		else
			enterTimer.restart();
	}

	function pointAway(id) {
		if (root.pointed !== id)
			return;
		root.pointed = 0;
		enterTimer.stop();
		leaveTimer.restart();
	}

	Timer {
		id: enterTimer

		interval: 450
		onTriggered: if (root.pointed !== 0) root.showPreview(root.pointed)
	}

	// Long enough to cross the gap between two pills without the card
	// dropping and coming back.
	Timer {
		id: leaveTimer

		interval: 150
		onTriggered: root.previewOpen = false
	}

	// --- naming --------------------------------------------------------------

	property bool editing: false
	property int editId: 0
	property real editX: 0

	function edit(id) {
		root.previewOpen = false;
		enterTimer.stop();
		root.editId = id;
		root.editX = root.anchorFor(id);
		field.text = Settings.workspaceName(id);
		root.editing = true;
		field.focusInput();
	}

	function commitEdit() {
		Settings.setWorkspaceName(root.editId, field.text);
		root.editing = false;
	}

	IpcHandler {
		target: "workspaces"

		// Name the workspace you are on: what SUPER+N does.
		function edit(): void {
			root.edit(Hyprland.focusedWorkspace?.id ?? 1);
		}

		// Straight to a name, without the field. Empty clears it.
		function rename(id: int, name: string): void {
			Settings.setWorkspaceName(id, name);
		}

		// A key from Theme.tagPalette - "blue" - or empty for none.
		function recolor(id: int, key: string): void {
			Settings.setWorkspaceColor(id, key);
		}

		function preview(id: int): void {
			root.showPreview(id);
		}

		// The field's way out, for when the keyboard is not.
		function close(): void {
			root.editing = false;
			root.previewOpen = false;
		}

		function names(): string {
			return JSON.stringify({ names: Settings.workspaceNames ?? {},
				colors: Settings.workspaceColors ?? {} });
		}
	}

	component PillText: Text {
		required property color ink
		required property bool raised

		anchors.verticalCenter: parent.verticalCenter
		color: ink
		style: raised ? Text.Raised : Text.Normal
		styleColor: Theme.glassTextShadow
	}

	Repeater {
		id: pills

		model: root.slots

		Rectangle {
			id: pill

			required property var modelData
			readonly property int workspaceId: modelData.id
			readonly property string name: Settings.workspaceNames?.[String(workspaceId)] ?? ""
			readonly property color tint: Theme.tagColor(Settings.workspaceColors?.[String(workspaceId)] ?? "")
			readonly property bool tinted: tint.a > 0
			readonly property bool isFocused: modelData.workspace?.focused ?? false
			// Tagged, but nothing on it and Hyprland has not made it yet.
			readonly property bool waiting: modelData.workspace === null
			readonly property bool solid: tinted && !waiting
			readonly property color ink: pill.solid ? Theme.tagInk
				: Theme.glass ? Theme.glassTextPrimary
				: pill.isFocused ? Theme.textOnStrong
				: Theme.textPrimary

			width: name === "" ? Theme.workspacePillWidth
				: Math.max(Theme.workspacePillWidth, label.implicitWidth + Theme.spacingS * 2)
			height: Theme.workspacePillHeight
			radius: Theme.radiusSmall

			border.width: pill.tinted && pill.waiting ? 1 : 0
			border.color: Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, Theme.tagEdge)

			color: pill.solid
				? Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b,
					mouse.containsMouse || pill.isFocused ? Theme.tagFillHover : Theme.tagFill)
				: pill.tinted ? (mouse.containsMouse ? Theme.glassControlHover : "transparent")
				: Theme.glass
				? (pill.isFocused ? Theme.glassControlStrong
					: mouse.containsMouse ? Theme.glassControlHover
					: "transparent")
				: (pill.isFocused ? Theme.surfaceStrong
					: mouse.containsMouse ? Theme.surfaceHover
					: Theme.surface)

			// The outline already says "empty" for a coloured one.
			opacity: pill.waiting && !pill.tinted && !mouse.containsMouse ? 0.55 : 1.0

			// Focus on a solid pill: a ring outside it, so nothing moves.
			Rectangle {
				anchors.fill: parent
				anchors.margins: -2
				radius: parent.radius + 2
				color: "transparent"
				border.width: 2
				border.color: Theme.tagRing
				visible: pill.solid && pill.isFocused
			}

			Row {
				id: label

				anchors.centerIn: parent
				height: parent.height
				spacing: Theme.spacingXs + 1

				// The number stays beside the name: it is still the key.
				PillText {
					ink: pill.ink
					raised: Theme.glass && !pill.solid
					text: pill.workspaceId
					opacity: pill.name !== "" ? 0.6 : 1.0
				}

				PillText {
					ink: pill.ink
					raised: Theme.glass && !pill.solid
					visible: pill.name !== ""
					width: Math.min(implicitWidth, Theme.workspaceNameMaxWidth)
					elide: Text.ElideRight
					text: pill.name
					font.weight: Font.DemiBold
				}
			}

			MouseArea {
				id: mouse

				anchors.fill: parent
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				acceptedButtons: Qt.LeftButton | Qt.RightButton

				onContainsMouseChanged: containsMouse
					? root.pointAt(pill.workspaceId)
					: root.pointAway(pill.workspaceId)

				onClicked: event => {
					if (event.button === Qt.RightButton) {
						root.edit(pill.workspaceId);
						return;
					}
					// Going there makes the card a picture of the screen
					// underneath it. It comes back after the pointer leaves.
					enterTimer.stop();
					root.pointed = 0;
					root.previewOpen = false;
					root.go(pill.workspaceId);
				}
			}
		}
	}

	// --- the preview card ----------------------------------------------------

	PanelWindow {
		id: previewWindow

		readonly property var workspace: root.slotFor(root.previewId)?.workspace ?? null
		readonly property var windows: previewWindow.workspace?.toplevels?.values ?? []
		readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0

		visible: (root.previewOpen && !root.editing) || card.opacity > 0.01

		anchors {
			top: true
			left: true
		}

		exclusionMode: ExclusionMode.Ignore

		margins {
			top: Math.max(0, Theme.barHeight + Theme.barPopupGap - previewWindow.pad)
			left: Math.max(0, root.previewX - previewWindow.pad)
		}

		implicitWidth: Theme.workspacePreviewWidth + previewWindow.pad * 2
		implicitHeight: card.implicitHeight + previewWindow.pad * 2
		color: "transparent"

		// Only to look at. A card that took clicks would catch the one meant
		// for whatever is underneath it while it fades.
		mask: Region {}

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:workspace-preview"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: card
			radius: Theme.radiusPanel
		}

		GlassTile {
			id: card

			readonly property bool shown: root.previewOpen && !root.editing

			anchors.fill: parent
			anchors.margins: previewWindow.pad
			implicitWidth: Theme.workspacePreviewWidth

			title: root.titleFor(root.previewId)
			trailing: previewWindow.windows.length === 0 ? "Empty"
				: previewWindow.windows.length === 1 ? "1 window"
				: `${previewWindow.windows.length} windows`

			opacity: card.shown ? 1 : 0
			y: card.shown ? 0 : -6

			Behavior on opacity {
				NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
			}
			Behavior on y {
				NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
			}

			// The screen in miniature. Hyprland gives window positions in the
			// monitor's logical pixels, so one factor maps the lot.
			Rectangle {
				id: miniature

				readonly property var monitor: previewWindow.workspace?.monitor ?? Hyprland.focusedMonitor
				readonly property real screenWidth: monitor ? monitor.width / monitor.scale : 1
				readonly property real screenHeight: monitor ? monitor.height / monitor.scale : 1
				readonly property real factor: width / screenWidth
				readonly property color tint: Theme.tagColor(Settings.workspaceColor(root.previewId))

				width: parent.width
				height: Math.round(screenHeight * factor)
				radius: Theme.radiusMedium
				color: Theme.terminalInset
				border.width: tint.a > 0 ? 1 : 0
				border.color: Qt.rgba(tint.r, tint.g, tint.b, Theme.tagEdge)
				clip: true

				Text {
					anchors.centerIn: parent
					visible: previewWindow.windows.length === 0
					text: "No windows."
					font.pixelSize: Theme.fontBody
					color: Theme.glassTextMuted
				}

				Repeater {
					model: previewWindow.windows

					Rectangle {
						id: thumb

						required property var modelData
						readonly property var at: modelData.lastIpcObject?.at ?? [0, 0]
						readonly property var size: modelData.lastIpcObject?.size ?? [0, 0]

						x: (at[0] - (miniature.monitor?.x ?? 0)) * miniature.factor
						y: (at[1] - (miniature.monitor?.y ?? 0)) * miniature.factor
						width: size[0] * miniature.factor
						height: size[1] * miniature.factor
						radius: Theme.spacingXs
						// Under the picture, for the moment before the first
						// frame arrives, and for a window that will not give one.
						color: Theme.glassControl
						border.width: 1
						border.color: Theme.glassControlBorder

						// Live only while the card is up: a capture per window
						// costs the compositor a render each frame.
						ScreencopyView {
							anchors.fill: parent
							captureSource: card.shown ? thumb.modelData.wayland : null
							live: card.shown
						}
					}
				}
			}

			Column {
				width: parent.width
				spacing: 2
				visible: previewWindow.windows.length > 0

				Repeater {
					model: previewWindow.windows.slice(0, 4)

					Text {
						required property var modelData

						width: parent.width
						elide: Text.ElideRight
						text: modelData.title || modelData.lastIpcObject?.class || "Untitled window"
						font.pixelSize: Theme.fontCaption
						color: Theme.glassTextSecondary
					}
				}

				Text {
					visible: previewWindow.windows.length > 4
					text: `and ${previewWindow.windows.length - 4} more`
					font.pixelSize: Theme.fontCaption
					color: Theme.glassTextMuted
				}
			}
		}
	}

	// --- the name field ------------------------------------------------------

	// The whole screen, so a click anywhere else is a click this can hear -
	// a client only receives input on its own surfaces.
	PanelWindow {
		visible: root.editing || nameCard.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:workspace-name"
		WlrLayershell.keyboardFocus: root.editing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: nameCard
			radius: Theme.radiusPanel
		}

		onVisibleChanged: if (visible) field.focusInput()

		MouseArea {
			id: catcher

			anchors.fill: parent

			onClicked: event => {
				const inside = nameCard.mapFromItem(catcher, event.x, event.y);
				if (!nameCard.contains(inside))
					root.editing = false;
			}
		}

		GlassTile {
			id: nameCard

			x: Math.max(Theme.spacingS, Math.min(root.editX, parent.width - width - Theme.spacingS))
			y: (root.editing ? 0 : -6) + Theme.barHeight + Theme.barPopupGap

			title: `Workspace ${root.editId}`

			opacity: root.editing ? 1 : 0

			Behavior on opacity {
				NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
			}
			Behavior on y {
				NumberAnimation { duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
			}

			GlassField {
				id: field

				width: parent.width
				placeholder: "Terminals, a repo, YouTube"

				onAccepted: root.commitEdit()
				Keys.onEscapePressed: root.editing = false
			}

			// A colour takes effect on the click, as in Chrome: the pill
			// behind the card is the preview. The name still waits for Enter.
			Item {
				id: swatches

				readonly property string chosen: Settings.workspaceColors?.[String(root.editId)] ?? ""
				readonly property var keys: ["", ...Theme.tagPalette.map(tag => tag.key)]

				width: parent.width
				// Room for the ring, which is drawn outside the disc.
				height: Theme.tagSwatchSize + 6

				Repeater {
					model: swatches.keys

					Item {
						id: swatch

						required property string modelData
						required property int index
						readonly property color tint: Theme.tagColor(modelData)
						readonly property bool chosen: swatches.chosen === modelData

						x: index * (swatches.width - Theme.tagSwatchSize) / (swatches.keys.length - 1)
						anchors.verticalCenter: parent.verticalCenter
						width: Theme.tagSwatchSize
						height: Theme.tagSwatchSize

						// The selection ring, outside, so choosing moves nothing.
						Rectangle {
							anchors.fill: parent
							anchors.margins: -3
							radius: width / 2
							color: "transparent"
							border.width: 2
							border.color: Theme.glassChipSelectedBorder
							visible: swatch.chosen
						}

						Rectangle {
							anchors.fill: parent
							radius: width / 2
							// "None" is the empty disc: a track, not a colour.
							color: swatch.modelData === "" ? Theme.glassTrack : swatch.tint
							border.width: 1
							border.color: swatch.modelData === "" ? Theme.glassTrackBorder : Theme.glassEdge
							opacity: swatchMouse.containsMouse || swatch.chosen ? 1.0 : 0.85
						}

						MouseArea {
							id: swatchMouse

							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								Settings.setWorkspaceColor(root.editId, swatch.modelData);
								field.focusInput();
							}
						}
					}
				}
			}

			Text {
				width: parent.width
				wrapMode: Text.WordWrap
				text: "Leave it empty to show just the number."
				font.pixelSize: Theme.fontCaption
				color: Theme.glassTextMuted
			}
		}
	}
}
