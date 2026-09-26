import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// The application launcher: type, pick, Enter. The design's turn 9.
//
// Native rather than a separate program for the reason everything else here
// is: it is a surface in the same shell, drawn with the same glass, driven by
// the same IPC, and it costs nothing when it is closed. The applications come
// from Quickshell's DesktopEntries, which reads the .desktop files and knows
// how to run them - this file only has to decide what to show and in what
// order.
//
// The sheet hangs from a fifth of the way down the screen rather than sitting
// in the middle, so a result list that changes length grows downward and the
// sheet never jumps. The search track is the header: a launcher has nothing to
// say about itself, and what you type is the title.
Scope {
	id: root

	property bool open: false

	// Held by id, not by row: the list re-sorts on every keystroke.
	property string picked: ""

	readonly property string query: searchField.text
	readonly property string term: root.query.trim().toLowerCase()

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

	function setSearch(text) {
		searchField.text = text;
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

		// Letters in order with gaps - "chr" finding Chromium - but not for
		// one or two letters, which are in order in almost everything.
		if (term.length >= 3) {
			let at = 0;
			for (const ch of term) {
				at = name.indexOf(ch, at);
				if (at < 0)
					break;
				at += 1;
			}
			if (at > 0)
				return 2;
		}

		// The description, by the starts of its words and never by its
		// filler: "fo" is inside "for", which is inside almost every sentence
		// anyone writes about a program.
		if (term.length >= 3) {
			const words = [entry.genericName, entry.comment,
				...(entry.keywords ?? [])].join(" ").toLowerCase()
				.split(/[^a-z0-9]+/)
				.filter(word => word !== "" && !root.filler.includes(word));
			if (words.some(word => word.startsWith(term)))
				return 1;
		}

		return 0;
	}

	readonly property var filler: ["for", "the", "and", "with", "your", "from",
		"that", "this", "into", "over", "you", "are", "all", "any", "can"]

	readonly property var matches: {
		if (root.term === "")
			return [];

		// The rank decides the order; within a rank, what you launch most
		// rises. The weight is bounded below one so it never crosses a rank.
		return root.apps
			.map(entry => ({ entry: entry,
				score: root.score(entry, root.term) + History.weight(entry.id) }))
			.filter(item => item.score > 0)
			.sort((a, b) => b.score - a.score
				|| a.entry.name.localeCompare(b.entry.name))
			.map(item => item.entry);
	}

	// With nothing typed: what was launched lately as a row of tiles, as the
	// design draws it, then everything else as rows.
	readonly property int recentLimit: 5

	readonly property var recent: History.recent(root.recentLimit)
		.map(id => DesktopEntries.byId(id))
		.filter(entry => entry !== null && !entry.noDisplay)

	readonly property var everything: root.apps.slice()
		.sort((a, b) => a.name.localeCompare(b.name))

	// What the list below the tiles holds.
	readonly property var listed: root.term !== ""
		? root.matches
		: root.everything.filter(
			entry => !root.recent.some(seen => seen.id === entry.id))

	// Everything on screen in the order it is drawn - tiles first - so the
	// arrow keys walk what is there. The field owns left and right for its
	// caret, so the tiles are walked with up and down like the rows.
	readonly property var ordered: root.term !== ""
		? root.matches : root.recent.concat(root.listed)

	// The first row is the one Enter runs, unless something else was picked -
	// and a pick that is no longer on screen falls back to the first.
	readonly property var current: root.ordered.find(
		entry => entry.id === root.picked) ?? root.ordered[0] ?? null

	function move(step) {
		const entries = root.ordered;
		if (entries.length === 0)
			return;

		const at = entries.findIndex(entry => entry.id === (root.current?.id ?? ""));
		const next = Math.max(0, Math.min(entries.length - 1, at + step));
		root.picked = entries[next].id;
	}

	function launch() {
		const entry = root.current;

		if (entry === null) {
			if (root.term !== "")
				root.searchWeb();
			return;
		}

		entry.execute();
		History.noteLaunch(entry.id);
		root.close();
	}

	function searchWeb() {
		Quickshell.execDetached(["xdg-open",
			"https://duckduckgo.com/?q=" + encodeURIComponent(root.query.trim())]);
		root.close();
	}

	// A colour for each application, from its name, so any icon theme - or
	// none - reads as one set. The same name always gets the same hue.
	function hue(name) {
		let h = 0;
		for (const ch of name)
			h = (h * 31 + ch.charCodeAt(0)) % 360;
		return h / 360;
	}

	function tint(name) { return Qt.hsla(root.hue(name), 0.55, 0.62, 1); }
	function ink(name) { return Qt.hsla(root.hue(name), 0.6, 0.30, 1); }

	// What the design puts on the right of a row: the kind of thing it is.
	function kind(entry) {
		const known = ["System", "Settings", "Network", "Utility", "Development",
			"Graphics", "AudioVideo", "Audio", "Video", "Office", "Game", "Education"];
		const found = (entry.categories ?? []).find(cat => known.includes(cat));

		return found === "AudioVideo" ? "Media" : (found ?? entry.genericName ?? "");
	}

	// The name with the matched prefix underlined, as the design draws it -
	// only where the match really is a prefix of the name or of a word.
	function marked(entry) {
		const escape = part => part.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;").replace(/>/g, "&gt;");
		const name = entry.name;
		const lower = name.toLowerCase();
		const term = root.term;

		let at = -1;
		if (term !== "") {
			if (lower.startsWith(term))
				at = 0;
			else {
				const word = lower.search(new RegExp("(^|[\\s-])"
					+ term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
				if (word >= 0)
					at = lower.indexOf(term, word);
			}
		}

		if (at < 0)
			return escape(name);

		return escape(name.slice(0, at)) + "<u>" + escape(name.slice(at, at + term.length))
			+ "</u>" + escape(name.slice(at + term.length));
	}

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

		function search(text: string): void {
			root.setSearch(text);
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

			sheetWidth: Theme.launcherWidth
			padding: Theme.launcherPadding
			spacing: Theme.spacingS + 2
			radius: Theme.launcherRadius
			topFraction: Theme.launcherTop

			Keys.onEscapePressed: root.close()
			Keys.onReturnPressed: root.launch()
			Keys.onEnterPressed: root.launch()
			Keys.onDownPressed: root.move(1)
			Keys.onUpPressed: root.move(-1)

			// The search track. A lens with the magnifier in it on the left,
			// the mode on the right - only "All" exists so far.
			Item {
				width: parent.width
				height: Theme.launcherTrackHeight

				GlassField {
					id: searchField

					anchors.fill: parent
					fontSize: Theme.fontSearch
					placeholder: "Search apps, files, commands…"

					leading: Lens {
						width: 38
						height: 38
						sheen: false

						SearchIcon {
							anchors.centerIn: parent
							width: 15
							height: 15
							color: Theme.glassOnLens
						}
					}

					onAccepted: root.launch()
				}

				Chip {
					anchors {
						right: parent.right
						rightMargin: Theme.spacingM
						verticalCenter: parent.verticalCenter
					}

					text: "All"
					active: true
				}
			}

			// Recent applications as tiles, with the one way to be rid of
			// them beside the label - a secondary action in the header slot.
			Column {
				width: parent.width
				visible: root.term === "" && root.recent.length > 0
				spacing: 6

				Item {
					width: parent.width
					height: recentLabel.height

					Text {
						id: recentLabel

						x: 10
						text: "RECENT"
						font.pixelSize: Theme.fontCaption
						font.bold: true
						font.letterSpacing: 0.66
						opacity: 0.6
						color: Theme.glassTextPrimary
					}

					Text {
						anchors.right: parent.right
						anchors.rightMargin: 10
						text: "Clear"
						font.pixelSize: Theme.fontCaption
						font.weight: Font.DemiBold
						opacity: clearMouse.containsMouse ? 1.0 : 0.6
						color: Theme.glassTextPrimary

						MouseArea {
							id: clearMouse

							anchors.fill: parent
							anchors.margins: -6
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								History.clear();
								root.picked = "";
							}
						}
					}
				}

				Row {
					id: tiles

					readonly property real tileWidth:
						(width - (root.recentLimit - 1) * 6) / root.recentLimit

					width: parent.width
					spacing: 6

					Repeater {
						model: root.recent

						Rectangle {
							id: tile

							required property var modelData

							readonly property bool selected: root.current?.id === modelData.id
							readonly property string iconFile: Quickshell.iconPath(modelData.icon, true)

							width: tiles.tileWidth
							height: 48 + 8 + 16 + 22
							radius: 18

							color: tile.selected ? Theme.glassChipActive
								: tileMouse.containsMouse ? Theme.glassControlHover
								: "transparent"
							border.width: tile.selected ? 1 : 0
							border.color: Theme.glassTrackBorderFocus

							Behavior on color {
								ColorAnimation { duration: 120 }
							}

							Column {
								anchors.centerIn: parent
								width: parent.width
								spacing: 8

								Lens {
									anchors.horizontalCenter: parent.horizontalCenter
									width: 48
									height: 48
									sheen: false
									tint: root.tint(tile.modelData.name)

									Image {
										anchors.centerIn: parent
										width: parent.width * 0.72
										height: width
										visible: tile.iconFile !== ""
										source: tile.iconFile
										sourceSize: Qt.size(96, 96)
										fillMode: Image.PreserveAspectFit
										smooth: true
									}

									Text {
										anchors.centerIn: parent
										visible: tile.iconFile === ""
										text: tile.modelData.name.slice(0, 1).toUpperCase()
										font.pixelSize: 18
										font.weight: Font.Black
										color: root.ink(tile.modelData.name)
									}
								}

								Text {
									width: parent.width - 12
									anchors.horizontalCenter: parent.horizontalCenter
									horizontalAlignment: Text.AlignHCenter
									elide: Text.ElideRight
									text: tile.modelData.name
									font.pixelSize: Theme.fontBody
									font.weight: tile.selected ? Font.Bold : Font.DemiBold
									color: Theme.glassTextPrimary
								}
							}

							MouseArea {
								id: tileMouse

								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: {
									root.picked = tile.modelData.id;
									root.launch();
								}
							}
						}
					}
				}
			}

			// The rows. One list either way; the labels and the top-hit
			// treatment come from what is in it.
			Item {
				width: parent.width
				height: Math.min(8 * (Theme.launcherRowHeight + 4) + 40, list.contentHeight)
				visible: root.listed.length > 0

				Flickable {
					id: list

					anchors.fill: parent
					clip: true
					contentHeight: rows.implicitHeight
					boundsBehavior: Flickable.StopAtBounds

					Column {
						id: rows

						width: list.width
						spacing: 4

						Repeater {
							model: root.listed

							Item {
								id: slot

								required property var modelData
								required property int index

								// The first match gets the design's card; the
								// rest are plain rows. With nothing typed there
								// is no "hit", only what was used lately.
								readonly property bool topHit: root.term !== "" && slot.index === 0
								readonly property bool selected: root.current?.id === modelData.id
								readonly property string iconFile: Quickshell.iconPath(modelData.icon, true)
								readonly property bool firstOther: root.term === ""
									? slot.index === 0
									: slot.index === 1

								width: rows.width
								height: (slot.topHit ? Theme.launcherTopHitHeight : Theme.launcherRowHeight)
									+ (label.visible ? label.height + 8 : 0)

								Text {
									id: label

									x: 10
									visible: slot.topHit || slot.firstOther
									text: slot.topHit ? "TOP HIT" : "APPLICATIONS"
									font.pixelSize: Theme.fontCaption
									font.bold: true
									font.letterSpacing: 0.66
									opacity: 0.6
									color: Theme.glassTextPrimary
								}

								Rectangle {
									id: row

									anchors.bottom: parent.bottom
									width: parent.width
									height: slot.topHit ? Theme.launcherTopHitHeight : Theme.launcherRowHeight
									radius: slot.topHit ? 18 : Theme.radiusRow

									// The top hit is a bright card. Everything
									// else is bare until pointed at or picked.
									color: slot.topHit || slot.selected ? Theme.glassChipActive
										: rowMouse.containsMouse ? Theme.glassControlHover
										: "transparent"
									border.width: slot.topHit || slot.selected ? 1 : 0
									border.color: Theme.glassTrackBorderFocus

									Behavior on color {
										ColorAnimation { duration: 120 }
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

										// Every application on a disc of its own
										// colour. The icon sits on it where the
										// theme has one; the initial where not.
										Lens {
											id: disc

											anchors.verticalCenter: parent.verticalCenter
											width: slot.topHit ? 36 : 30
											height: width
											sheen: false
											tint: root.tint(slot.modelData.name)

											Image {
												anchors.centerIn: parent
												width: parent.width * 0.72
												height: width
												visible: slot.iconFile !== ""
												source: slot.iconFile
												sourceSize: Qt.size(64, 64)
												fillMode: Image.PreserveAspectFit
												smooth: true
											}

											Text {
												anchors.centerIn: parent
												visible: slot.iconFile === ""
												text: slot.modelData.name.slice(0, 1).toUpperCase()
												font.pixelSize: slot.topHit ? 15 : 12
												font.weight: Font.Black
												color: root.ink(slot.modelData.name)
											}
										}

										Column {
											anchors.verticalCenter: parent.verticalCenter
											width: parent.width - disc.width - Theme.spacingM
												- trailing.width - Theme.spacingM
											spacing: 2

											Text {
												width: parent.width
												elide: Text.ElideRight
												textFormat: Text.RichText
												text: root.marked(slot.modelData)
												font.pixelSize: slot.topHit ? 15 : Theme.fontLead
												font.weight: slot.topHit || slot.selected ? Font.Bold : Font.DemiBold
												color: Theme.glassTextPrimary
											}

											Text {
												width: parent.width
												elide: Text.ElideRight
												visible: slot.topHit && text !== ""
												text: ["Application", slot.modelData.genericName]
													.filter(part => part).join(" · ")
												font.pixelSize: Theme.fontBody
												font.weight: Font.DemiBold
												opacity: 0.75
												color: Theme.glassTextPrimary
											}
										}

										// "Open ↵" on the card; the kind of thing
										// it is on a row.
										Row {
											id: trailing

											anchors.verticalCenter: parent.verticalCenter
											spacing: 6

											Text {
												anchors.verticalCenter: parent.verticalCenter
												text: slot.topHit ? "Open" : root.kind(slot.modelData)
												font.pixelSize: Theme.fontBody
												font.weight: Font.DemiBold
												opacity: slot.topHit ? 0.9 : 0.6
												color: Theme.glassTextPrimary
											}

											KeyCap {
												anchors.verticalCenter: parent.verticalCenter
												visible: slot.topHit
												text: "↵"
											}
										}
									}

									MouseArea {
										id: rowMouse

										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.PointingHandCursor
										onClicked: {
											root.picked = slot.modelData.id;
											root.launch();
										}
									}
								}
							}
						}
					}
				}
			}

			// Nothing matched. The web is one Enter away, which is what the
			// footer says.
			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				visible: root.term !== "" && root.ordered.length === 0
				topPadding: 16
				bottomPadding: 8
				text: `Nothing matches “${root.query.trim()}”`
				font.pixelSize: Theme.fontTitle
				font.weight: Font.DemiBold
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			// The footer: the fallback action on the left, the keys on the
			// right. Both are the design's, and both are true.
			Item {
				width: parent.width
				height: 30

				Rectangle {
					anchors.top: parent.top
					width: parent.width
					height: 1
					color: Theme.glassControlBorder
				}

				Text {
					anchors {
						left: parent.left
						leftMargin: 10
						verticalCenter: parent.verticalCenter
						verticalCenterOffset: 4
					}

					visible: root.term !== ""
					text: `Search the web for “${root.query.trim()}”`
					font.pixelSize: Theme.fontBody
					font.weight: Font.DemiBold
					opacity: webMouse.containsMouse ? 1.0 : 0.75
					color: Theme.glassTextPrimary

					MouseArea {
						id: webMouse

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.searchWeb()
					}
				}

				Row {
					anchors {
						right: parent.right
						rightMargin: 10
						verticalCenter: parent.verticalCenter
						verticalCenterOffset: 4
					}

					spacing: 14

					Repeater {
						model: [["↑↓", "Move"], ["↵", "Open"], ["Esc", "Close"]]

						Row {
							required property var modelData

							spacing: 6

							KeyCap {
								anchors.verticalCenter: parent.verticalCenter
								text: parent.modelData[0]
							}

							Text {
								anchors.verticalCenter: parent.verticalCenter
								text: parent.modelData[1]
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.85
								color: Theme.glassTextPrimary
							}
						}
					}
				}
			}
		}
	}
}
