import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// The application launcher: type, pick, Enter.
//
// Native rather than a separate program for the reason everything else here
// is: it is a surface in the same shell, drawn with the same glass, driven by
// the same IPC, and it costs nothing when it is closed. The applications come
// from Quickshell's DesktopEntries, which reads the .desktop files and knows
// how to run them - this file only has to decide what to show and in what
// order.
//
// No design turn exists for this one, so it follows the pickers: a wide sheet,
// a search track, rows, a selection, Enter to act. The search track is the
// header - there is nothing to title - with the close disc beside it.
Scope {
	id: root

	property bool open: false

	// Held by id, not by row: the list re-sorts on every keystroke.
	property string picked: ""

	readonly property string query: searchField.text

	function show() {
		root.picked = "";
		searchField.clear();
		root.open = true;
		list.contentY = 0;
		Qt.callLater(() => searchField.focusInput());
	}

	function close() {
		root.open = false;
		root.picked = "";
	}

	function setSearch(term) {
		searchField.text = term;
	}

	// Everything with a menu entry, minus what asks not to be shown.
	readonly property var apps: DesktopEntries.applications.values
		.filter(entry => !entry.noDisplay)

	// A match is worth more the earlier and the tighter it is: the name's
	// start, then a word's start, then anywhere in the name, then the letters
	// in order with gaps, then the description. Ties go alphabetically, so the
	// order is the same every time for the same letters.
	function score(entry, term) {
		const name = entry.name.toLowerCase();

		if (name.startsWith(term))
			return 5;
		if (name.split(/[\s-]+/).some(word => word.startsWith(term)))
			return 4;
		if (name.includes(term))
			return 3;

		let at = 0;
		for (const ch of term) {
			at = name.indexOf(ch, at);
			if (at < 0)
				break;
			at += 1;
		}
		if (at > 0)
			return 2;

		const rest = [entry.genericName, entry.comment,
			...(entry.keywords ?? [])].join(" ").toLowerCase();
		if (rest.includes(term))
			return 1;

		return 0;
	}

	readonly property var matches: {
		const term = root.query.trim().toLowerCase();
		const scored = root.apps
			.map(entry => ({ entry: entry, score: term === "" ? 1 : root.score(entry, term) }))
			.filter(item => item.score > 0)
			.sort((a, b) => b.score - a.score
				|| a.entry.name.localeCompare(b.entry.name));

		return scored.map(item => item.entry);
	}

	// The first match is the one Enter runs, unless something else was
	// picked - and a pick that no longer matches falls back to the first.
	readonly property var current: root.matches.find(
		entry => entry.id === root.picked) ?? root.matches[0] ?? null

	function move(step) {
		const entries = root.matches;
		if (entries.length === 0)
			return;

		const at = entries.findIndex(entry => entry.id === (root.current?.id ?? ""));
		const next = Math.max(0, Math.min(entries.length - 1, at + step));
		root.picked = entries[next].id;

		// Keep the pick on screen.
		const y = next * (root.rowHeight + Theme.spacingS);
		if (y < list.contentY)
			list.contentY = y;
		else if (y + root.rowHeight > list.contentY + list.height)
			list.contentY = y + root.rowHeight - list.height;
	}

	function launch() {
		const entry = root.current;
		if (entry === null)
			return;

		entry.execute();
		root.close();
	}

	readonly property int rowHeight: 48
	readonly property int visibleRows: 8

	IpcHandler {
		target: "launcher"

		function toggle(): void {
			if (root.open)
				root.close();
			else
				root.show();
		}

		function opened(): void {
			root.show();
		}

		function close(): void {
			root.close();
		}

		function search(term: string): void {
			root.setSearch(term);
		}
	}

	PanelWindow {
		id: window

		visible: root.open || dialog.sheet.opacity > 0.01

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:launcher"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			sheetWidth: Theme.dialogWidthWide
			padding: 24
			spacing: Theme.spacingL

			Keys.onEscapePressed: root.close()
			Keys.onReturnPressed: root.launch()
			Keys.onEnterPressed: root.launch()
			Keys.onDownPressed: root.move(1)
			Keys.onUpPressed: root.move(-1)

			// The header is the search track. A launcher has nothing to say
			// about itself; what you type is the title.
			Item {
				width: parent.width
				height: Theme.sliderHeight

				GlassField {
					id: searchField

					anchors {
						left: parent.left
						right: closeDisc.left
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					placeholder: "Search applications"

					leading: SearchIcon {
						color: Theme.glassTextPrimary
						opacity: 0.8
					}

					onAccepted: root.launch()
				}

				DiscButton {
					id: closeDisc

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					glyph: "close"
					onClicked: root.close()
				}
			}

			Item {
				width: parent.width
				height: Math.min(root.visibleRows * (root.rowHeight + Theme.spacingS)
					- Theme.spacingS, list.contentHeight)
				visible: root.matches.length > 0

				Flickable {
					id: list

					anchors.fill: parent
					clip: true
					contentHeight: rows.implicitHeight
					boundsBehavior: Flickable.StopAtBounds

					Column {
						id: rows

						// Room for the selected row's ring, drawn outside it.
						x: 3
						width: list.width - 6
						spacing: Theme.spacingS

						Repeater {
							model: root.matches

							Rectangle {
								id: row

								required property var modelData

								readonly property bool selected:
									root.current?.id === modelData.id
								readonly property string iconFile:
									Quickshell.iconPath(modelData.icon, true)

								width: rows.width
								height: root.rowHeight
								radius: Theme.radiusRow

								color: row.selected ? Theme.glassChipSelected
									: rowMouse.containsMouse ? Theme.glassControlHover
									: Theme.glassControl
								border.width: 1
								border.color: row.selected
									? Theme.glassChipSelectedBorder
									: Theme.glassControlBorder

								Behavior on color {
									ColorAnimation { duration: 120 }
								}

								Rectangle {
									anchors.fill: parent
									anchors.margins: -3
									z: -1
									radius: row.radius + 3
									color: Theme.glassRowRing
									visible: row.selected
								}

								Row {
									anchors {
										left: parent.left
										right: parent.right
										leftMargin: Theme.spacingM
										rightMargin: Theme.spacingM
										verticalCenter: parent.verticalCenter
									}

									spacing: Theme.spacingM

									// The application's own icon where the
									// theme has one; its initial on a disc
									// where it does not, so every row has
									// something to look at in the same place.
									Item {
										anchors.verticalCenter: parent.verticalCenter
										width: 28
										height: 28

										// iconPath answers with an image://icon/ URL from
										// Quickshell's own provider, not a file path.
										Image {
											anchors.fill: parent
											visible: row.iconFile !== ""
											source: row.iconFile
											sourceSize: Qt.size(56, 56)
											fillMode: Image.PreserveAspectFit
											smooth: true
										}

										Lens {
											anchors.fill: parent
											visible: row.iconFile === ""
											plain: !row.selected
											sheen: false

											Text {
												anchors.centerIn: parent
												text: row.modelData.name.slice(0, 1).toUpperCase()
												font.pixelSize: Theme.fontLead
												font.bold: true
												color: row.selected
													? Theme.glassTextOnLens
													: Theme.glassTextPrimary
											}
										}
									}

									Column {
										anchors.verticalCenter: parent.verticalCenter
										width: parent.width - 28 - Theme.spacingM
										spacing: 2

										Text {
											width: parent.width
											elide: Text.ElideRight
											text: row.modelData.name
											font.pixelSize: Theme.fontLead
											font.weight: row.selected ? Font.Bold : Font.DemiBold
											color: Theme.glassTextPrimary
										}

										Text {
											width: parent.width
											elide: Text.ElideRight
											visible: text !== ""
											text: row.modelData.genericName
												|| row.modelData.comment || ""
											font.pixelSize: Theme.fontBody
											opacity: 0.7
											color: Theme.glassTextPrimary
										}
									}
								}

								MouseArea {
									id: rowMouse

									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: {
										root.picked = row.modelData.id;
										root.launch();
									}
								}
							}
						}
					}
				}
			}

			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				visible: root.matches.length === 0
				topPadding: 20
				bottomPadding: 12
				text: `Nothing matches “${root.query.trim()}”`
				font.pixelSize: Theme.fontTitle
				font.weight: Font.DemiBold
				opacity: 0.6
				color: Theme.glassTextPrimary
			}
		}
	}
}
