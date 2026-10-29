import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes
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

	// There is a bar on every screen. Each shows the workspaces on its own
	// screen, as Waybar does; the one on the screen in use is the one IPC
	// reaches, so SUPER+N names the workspace you are looking at.
	readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""
	readonly property bool lead: root.screenName !== ""
		&& root.screenName === (Hyprland.focusedMonitor?.name ?? "")

	// A moment behind `lead`, as in BarPopup.qml: the bar losing it lets go
	// first, so Quickshell never sees two handlers for one target.
	property bool hasIpc: false
	onLeadChanged: {
		if (!root.lead)
			root.hasIpc = false;
		else
			Qt.callLater(() => root.hasIpc = root.lead);
	}

	// Every workspace Hyprland has on this screen, and every named one it
	// does not have yet - on every screen, since it is not on any. The name
	// is what holds the place: a colour alone is remembered for when the
	// workspace comes back, but does not keep an empty one in the bar.
	readonly property var slots: {
		const all = Hyprland.workspaces.values;
		const live = all.filter(ws => root.screenName === "" || ws.monitor?.name === root.screenName);
		const liveIds = all.map(ws => ws.id);
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

	// Where a workspace's pill is on screen, for whatever opens from it.
	// Asked at the moment something opens, not bound: mapToItem is a call,
	// and a binding on it would keep its first answer.
	function pillFor(id) {
		for (let i = 0; i < pills.count; i++) {
			const pill = pills.itemAt(i);
			if (pill?.workspaceId === id) {
				const at = pill.mapToItem(null, 0, 0);
				return { x: at.x, y: at.y, width: pill.width, height: pill.height };
			}
		}
		const at = root.mapToItem(null, 0, 0);
		return { x: at.x, y: at.y, width: Theme.workspacePillWidth, height: Theme.workspacePillHeight };
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
	// The workspace the card is going to, and the one it is showing. They
	// differ for the moment the card moves between two, while the old
	// contents fade out.
	property int previewId: 0
	property int shownId: 0
	// The pill the card hangs from.
	property var previewPill: ({ x: 0, y: 0, width: 0, height: 0 })
	// Where this row is on screen, for the copy of it drawn on the tab.
	property point rowOrigin: Qt.point(0, 0)
	// The pill the pointer is on, or 0.
	property int pointed: 0
	// The same, for the copies on the tabs to look as the real pills do. Not
	// `pointed`, which a click clears while the pointer is still there.
	property int hoveredId: 0

	// A workspace can go while the pointer is on it: an empty one ends the
	// moment you leave it, by key, and its pill goes from under the pointer.
	// A pill that is gone never says the pointer left, so the card for it
	// would stay until something else was pointed at.
	onSlotsChanged: {
		const ids = root.slots.map(slot => slot.id);
		if (!ids.includes(root.pointed)) {
			root.pointed = 0;
			enterTimer.stop();
		}
		if (!ids.includes(root.hoveredId))
			root.hoveredId = 0;
		if (root.previewOpen && !ids.includes(root.previewId))
			root.previewOpen = false;
	}

	function showPreview(id) {
		const moving = card.shown && id !== root.shownId;
		root.previewId = id;
		root.previewPill = root.pillFor(id);
		root.rowOrigin = root.mapToItem(null, 0, 0);
		// Window positions are in each toplevel's last IPC answer, which
		// Hyprland only sends again when asked.
		Hyprland.refreshToplevels();
		if (moving)
			swap.restart();
		else if (!swap.running)
			root.shownId = id;
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
	// The pill the field hangs from.
	property var editPill: ({ x: 0, y: 0, width: 0, height: 0 })

	function edit(id) {
		root.previewOpen = false;
		enterTimer.stop();
		root.editId = id;
		root.editPill = root.pillFor(id);
		root.rowOrigin = root.mapToItem(null, 0, 0);
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
		enabled: root.hasIpc

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

	Repeater {
		id: pills

		model: root.slots

		WorkspacePill {
			id: pill

			required property var modelData

			workspaceId: modelData.id
			workspace: modelData.workspace
			hovered: mouse.containsMouse

			MouseArea {
				id: mouse

				anchors.fill: parent
				hoverEnabled: true
				cursorShape: Qt.PointingHandCursor
				acceptedButtons: Qt.LeftButton | Qt.RightButton

				onContainsMouseChanged: {
					if (containsMouse) {
						root.hoveredId = pill.workspaceId;
						root.pointAt(pill.workspaceId);
					} else {
						if (root.hoveredId === pill.workspaceId)
							root.hoveredId = 0;
						root.pointAway(pill.workspaceId);
					}
				}

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

	// The card hangs from its workspace like a tab (ui/TabCard.qml). Its own
	// surface across the top of the screen, so moving to the next workspace
	// is the tab sliding along the bar, not the surface jumping. Not the bar's
	// surface: drawn in there, the bar had to grow every time the card came
	// out, and the whole bar visibly redrew.
	PanelWindow {
		id: preview

		readonly property var workspace: root.slotFor(root.shownId)?.workspace ?? null
		readonly property var windows: preview.workspace?.toplevels?.values ?? []

		screen: root.QsWindow.window?.screen ?? null

		// Up while the card is out of its tab at all. Not tied to the body's
		// height: showing the surface lays the card out, which can change
		// that height, and a binding that moves its own trigger loops.
		visible: tabCard.out

		anchors {
			top: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		implicitHeight: tabCard.extent
		color: "transparent"

		// Only to look at. It lies over the bar, and the bar keeps its clicks.
		mask: Region {}

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:workspace-preview"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: tabCard.blurRegion

		TabCard {
			id: tabCard

			anchors.fill: parent
			anchorRect: Qt.rect(root.previewPill.x, root.previewPill.y,
				root.previewPill.width, root.previewPill.height)
			tabPadding: Theme.workspaceTabLip
			open: card.shown
			bodyWidth: Theme.workspacePreviewWidth
			contentHeight: card.implicitHeight

			// The bar's workspaces again, on the tab: its glass is dense enough
			// to hide the real ones underneath. Laid out as the bar lays them
			// out, from the same place, so each lands on its own original
			// wherever the tab is - also while it slides past others.
			Row {
				parent: tabCard.tabLayer
				x: root.rowOrigin.x - tabCard.tabX
				y: root.rowOrigin.y - tabCard.tabY
				spacing: root.spacing

				Repeater {
					model: root.slots

					WorkspacePill {
						required property var modelData

						workspaceId: modelData.id
						workspace: modelData.workspace
						hovered: root.hoveredId === modelData.id
					}
				}
			}

			// The glass is the tab card's; this is only the tile's layout.
			GlassTile {
				id: card

				readonly property bool shown: root.previewOpen && !root.editing

				width: Theme.workspacePreviewWidth
				color: "transparent"
				border.width: 0
				shadowLayers: 0

				title: root.titleFor(root.shownId)
				trailing: preview.windows.length === 0 ? "Empty"
					: preview.windows.length === 1 ? "1 window"
					: `${preview.windows.length} windows`

				contentOpacity: 0

				// The contents come up as the card comes out, and go as it goes.
				onShownChanged: {
					swap.stop();
					fade.to = card.shown ? 1 : 0;
					fade.restart();
				}

				NumberAnimation {
					id: fade

					target: card
					property: "contentOpacity"
					duration: Theme.motionEffectsDuration
					easing.type: Easing.Bezier
					easing.bezierCurve: Theme.motionEffects
				}

				// From one workspace to the next: the tab slides and the
				// card resizes while what it shows fades across.
				SequentialAnimation {
					id: swap

					NumberAnimation {
						target: card
						property: "contentOpacity"
						to: 0
						duration: Theme.motionEffectsFastDuration
						easing.type: Easing.Bezier
						easing.bezierCurve: Theme.motionEffectsFast
					}
					ScriptAction {
						script: root.shownId = root.previewId
					}
					NumberAnimation {
						target: card
						property: "contentOpacity"
						to: 1
						duration: Theme.motionEffectsDuration
						easing.type: Easing.Bezier
						easing.bezierCurve: Theme.motionEffects
					}
				}
				// The screen in miniature. Hyprland gives window positions in the
				// monitor's logical pixels, so one factor maps the lot.
				Rectangle {
					id: miniature

					readonly property var monitor: preview.workspace?.monitor ?? Hyprland.focusedMonitor
					readonly property real screenWidth: monitor ? monitor.width / monitor.scale : 1
					readonly property real screenHeight: monitor ? monitor.height / monitor.scale : 1
					readonly property real factor: width / screenWidth
					readonly property color tint: Theme.tagColor(Settings.workspaceColor(root.shownId))

					width: parent.width
					height: Math.round(screenHeight * factor)
					radius: Theme.radiusMedium
					color: Theme.terminalInset
					border.width: tint.a > 0 ? 1 : 0
					border.color: Qt.rgba(tint.r, tint.g, tint.b, Theme.tagEdge)
					clip: true

					Text {
						anchors.centerIn: parent
						visible: preview.windows.length === 0
						text: "No windows."
						font.pixelSize: Theme.fontBody
						color: Theme.glassTextMuted
					}

					Repeater {
						model: preview.windows

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
							// costs the compositor a render each frame. On the way
							// out it keeps its last frame, or the windows would go
							// grey the moment the card starts to leave.
							ScreencopyView {
								anchors.fill: parent
								captureSource: card.shown || preview.visible
									? thumb.modelData.wayland : null
								live: card.shown
							}
						}
					}
				}

				Column {
					width: parent.width
					spacing: 2
					visible: preview.windows.length > 0

					Repeater {
						model: preview.windows.slice(0, 4)

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
						visible: preview.windows.length > 4
						text: `and ${preview.windows.length - 4} more`
						font.pixelSize: Theme.fontCaption
						color: Theme.glassTextMuted
					}
				}
			}
		}
	}

	// --- the name field ------------------------------------------------------

	// The whole screen, so a click anywhere else is a click this can hear -
	// a client only receives input on its own surfaces.
	PanelWindow {
		visible: root.editing || nameTab.out
		screen: root.QsWindow.window?.screen ?? null

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

		BackgroundEffect.blurRegion: nameTab.blurRegion

		onVisibleChanged: if (visible) field.focusInput()

		MouseArea {
			id: catcher

			anchors.fill: parent

			onClicked: event => {
				const onCard = nameTab.bodyItem.contains(nameTab.bodyItem.mapFromItem(catcher, event.x, event.y));
				const onTab = nameTab.tabLayer.contains(nameTab.tabLayer.mapFromItem(catcher, event.x, event.y));
				if (!onCard && !onTab)
					root.editing = false;
			}
		}

		// Hangs from the workspace being named, as its preview does.
		TabCard {
			id: nameTab

			anchors.fill: parent
			anchorRect: Qt.rect(root.editPill.x, root.editPill.y,
				root.editPill.width, root.editPill.height)
			tabPadding: Theme.workspaceTabLip
			open: root.editing
			contentHeight: nameCard.implicitHeight

			// The bar's workspaces on the tab, as on the preview's.
			Row {
				parent: nameTab.tabLayer
				x: root.rowOrigin.x - nameTab.tabX
				y: root.rowOrigin.y - nameTab.tabY
				spacing: root.spacing

				Repeater {
					model: root.slots

					WorkspacePill {
						required property var modelData

						workspaceId: modelData.id
						workspace: modelData.workspace
						hovered: root.hoveredId === modelData.id
					}
				}
			}

			// The glass is the tab card's; this is only the tile's layout.
			GlassTile {
				id: nameCard

				width: Theme.tileWidth
				color: "transparent"
				border.width: 0
				shadowLayers: 0

				title: `Workspace ${root.editId}`

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
}
