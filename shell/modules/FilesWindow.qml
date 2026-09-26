import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Effects
import "../ui"
import "../icons"
import ".."

// Files: the design's turn 10, an ordinary window rather than a sheet.
//
// The window never touches the disk itself. QML can read a folder but not
// write one, so browsing lives here and every operation will go through a
// worker. What is here now is the browsing: places, breadcrumbs, a list and a
// grid, a search over the folder on screen, and Enter to open.
//
// Hyprland is told to leave the frame alone - no rounding, border or shadow
// of its own - so the pane can draw the design's 24px corners and cast its
// own shadow into the padding around it.
Scope {
	id: root

	readonly property string home: Quickshell.env("HOME")
	readonly property string trashPath:
		(Quickshell.env("XDG_DATA_HOME") || root.home + "/.local/share") + "/Trash/files"

	property bool open: false
	property string path: root.home
	property bool grid: false
	property bool showHidden: false

	// Where Back and Forward go. Plain arrays, replaced rather than mutated,
	// so the header's discs follow them.
	property var behind: []
	property var ahead: []

	// The path of the highlighted entry, or "" for none.
	property string picked: ""

	readonly property string filter: searchField.text.trim()

	function show(where) {
		if (where && where !== "")
			root.go(where);
		root.open = true;
	}

	function close() {
		root.open = false;
	}

	function go(where) {
		if (where === root.path)
			return;
		root.behind = root.behind.concat([root.path]);
		root.ahead = [];
		root.land(where);
	}

	function goBack() {
		if (root.behind.length === 0)
			return;
		root.ahead = [root.path].concat(root.ahead);
		const where = root.behind[root.behind.length - 1];
		root.behind = root.behind.slice(0, -1);
		root.land(where);
	}

	function goForward() {
		if (root.ahead.length === 0)
			return;
		root.behind = root.behind.concat([root.path]);
		const where = root.ahead[0];
		root.ahead = root.ahead.slice(1);
		root.land(where);
	}

	function up() {
		if (root.path !== "/")
			root.go(root.parentOf(root.path));
	}

	function land(where) {
		root.path = where;
		root.picked = "";
		searchField.clear();
	}

	function parentOf(path) {
		const cut = path.lastIndexOf("/");
		return cut <= 0 ? "/" : path.slice(0, cut);
	}

	function baseName(path) {
		return path === "/" ? "/" : path.slice(path.lastIndexOf("/") + 1);
	}

	function openEntry(entry) {
		if (entry === null)
			return;
		if (entry.folder)
			root.go(entry.path);
		else
			Quickshell.execDetached(["xdg-open", entry.path]);
	}

	// --- places ---------------------------------------------------------

	readonly property var candidates: [
		{ name: "Home", kind: "home", path: root.home },
		{ name: "Documents", kind: "folder", path: root.home + "/Documents" },
		{ name: "Downloads", kind: "downloads", path: root.home + "/Downloads" },
		{ name: "Pictures", kind: "pictures", path: root.home + "/Pictures" },
		{ name: "Trash", kind: "trash", path: root.trashPath }
	]

	// Only the folders that exist. A Pictures entry that opens an error is
	// worse than none.
	property var places: []

	Process {
		id: placesProbe

		command: ["bash", "-c", 'for d in "$@"; do [ -d "$d" ] && printf "%s\\n" "$d"; done; true', "sh"]
			.concat(root.candidates.map(place => place.path))

		stdout: StdioCollector {
			onStreamFinished: {
				const found = text.split("\n");
				root.places = root.candidates.filter(place =>
					place.name === "Trash" || found.includes(place.path));
			}
		}
	}

	onOpenChanged: if (root.open) placesProbe.running = true

	// --- the folder on screen ------------------------------------------

	FolderListModel {
		id: folder

		folder: "file://" + root.path
		showDirsFirst: true
		showDotAndDotDot: false
		showHidden: root.showHidden
		sortField: FolderListModel.Name
		sortCaseSensitive: false
		nameFilters: ["*"]
	}

	// The model, read into plain objects: the search has to cover folders
	// too, which the model's own name filter does not, and the arrow keys
	// want an array to walk.
	property var entries: []

	function rebuild() {
		const term = root.filter.toLowerCase();
		const out = [];
		for (let i = 0; i < folder.count; i++) {
			const name = folder.get(i, "fileName");
			if (term !== "" && !name.toLowerCase().includes(term))
				continue;
			out.push({
				name: name,
				path: folder.get(i, "filePath"),
				folder: folder.get(i, "fileIsDir"),
				size: folder.get(i, "fileSize"),
				modified: folder.get(i, "fileModified"),
				suffix: (folder.get(i, "fileSuffix") || "").toLowerCase()
			});
		}
		root.entries = out;
		if (root.picked !== "" && !out.some(entry => entry.path === root.picked))
			root.picked = "";
	}

	// The model announces changes as rows coming and going; one rebuild per
	// batch is enough, so they are coalesced through callLater.
	Connections {
		target: folder

		function onCountChanged() { Qt.callLater(root.rebuild); }
		function onDataChanged() { Qt.callLater(root.rebuild); }
		function onModelReset() { Qt.callLater(root.rebuild); }
		function onStatusChanged() { if (folder.status === FolderListModel.Ready) Qt.callLater(root.rebuild); }
	}

	onFilterChanged: root.rebuild()

	readonly property int current: root.entries.findIndex(entry => entry.path === root.picked)
	readonly property var currentEntry: root.current >= 0 ? root.entries[root.current] : null

	function move(delta) {
		if (root.entries.length === 0)
			return;
		const next = root.current < 0
			? (delta > 0 ? 0 : root.entries.length - 1)
			: Math.max(0, Math.min(root.entries.length - 1, root.current + delta));
		root.picked = root.entries[next].path;
	}

	// How many things each folder holds, for the design's "14 items". One
	// process per folder shown, not one per row.
	property var counts: ({})

	Process {
		id: counter

		command: ["bash", "-c",
			'cd "$1" 2>/dev/null || exit 0; for d in */ .*/; do [ -d "$d" ] || continue; '
			+ 'case "$d" in ./|../) continue;; esac; '
			+ 'printf "%s\\t%s\\n" "$(ls -1A -- "$d" | wc -l)" "${d%/}"; done',
			"sh", root.path]

		stdout: StdioCollector {
			onStreamFinished: {
				const found = {};
				for (const line of text.split("\n")) {
					const tab = line.indexOf("\t");
					if (tab > 0)
						found[line.slice(tab + 1)] = parseInt(line.slice(0, tab));
				}
				root.counts = found;
			}
		}
	}

	onPathChanged: { root.counts = ({}); recount.restart(); }
	onEntriesChanged: recount.restart()

	Timer {
		id: recount

		interval: 200
		onTriggered: { counter.running = false; counter.running = true; }
	}

	// --- words for things --------------------------------------------------

	function when(date) {
		const now = new Date();
		const then = new Date(date);
		const day = d => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
		const days = Math.round((day(now) - day(then)) / 86400000);
		if (days === 0)
			return "Today, " + Qt.formatTime(then, "h:mm");
		if (days === 1)
			return "Yesterday";
		if (then.getFullYear() === now.getFullYear())
			return Qt.formatDate(then, "MMM d");
		return Qt.formatDate(then, "MMM d, yyyy");
	}

	function size(bytes) {
		if (bytes < 1024)
			return bytes + " B";
		if (bytes < 1024 * 1024)
			return Math.round(bytes / 1024) + " KB";
		if (bytes < 1024 * 1024 * 1024)
			return (bytes / 1024 / 1024).toFixed(1) + " MB";
		return (bytes / 1024 / 1024 / 1024).toFixed(1) + " GB";
	}

	function detail(entry) {
		if (!entry.folder)
			return root.size(entry.size);
		const n = root.counts[entry.name];
		return n === undefined ? "" : n === 1 ? "1 item" : n + " items";
	}

	readonly property var imageTypes: ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg"]

	// The path as chips: Home, then each folder below it. Outside the home
	// directory the first chip is the root. Long paths keep their last four
	// and an ellipsis for the rest.
	readonly property var crumbs: {
		const out = [];
		let rest = root.path;
		if (rest === root.home || rest.startsWith(root.home + "/")) {
			out.push({ name: "Home", path: root.home });
			rest = rest.slice(root.home.length);
		} else {
			out.push({ name: "/", path: "/" });
		}
		let sofar = out[0].path;
		for (const part of rest.split("/").filter(p => p !== "")) {
			sofar = sofar === "/" ? "/" + part : sofar + "/" + part;
			out.push({ name: part, path: sofar });
		}
		if (out.length > 5)
			return [{ name: "…", path: out[out.length - 5].path }].concat(out.slice(-4));
		return out;
	}

	readonly property string placeName: {
		const place = root.places.find(p => p.path === root.path);
		return place ? place.name : root.baseName(root.path);
	}

	readonly property string status: {
		const n = root.entries.length;
		let text = n === 1 ? "1 item" : n + " items";
		if (root.currentEntry !== null) {
			const entry = root.currentEntry;
			const what = entry.folder ? root.detail(entry) : root.size(entry.size);
			text += " · " + entry.name + (what ? ", " + what : "");
		}
		return text;
	}

	IpcHandler {
		target: "files"

		function open(path: string): void {
			root.show(path);
		}

		function toggle(): void {
			if (root.open)
				root.close();
			else
				root.show("");
		}

		function close(): void {
			root.close();
		}

		// "list" or "grid", for scripts and for testing.
		function view(mode: string): void {
			root.grid = mode === "grid";
		}
	}

	// --- the window ---------------------------------------------------------

	FloatingWindow {
		id: window

		visible: root.open
		title: "Files"
		color: "transparent"

		implicitWidth: Theme.filesWidth + Theme.glassShadowPadding * 2
		implicitHeight: Theme.filesHeight + Theme.glassShadowPadding * 2
		minimumSize: Qt.size(640 + Theme.glassShadowPadding * 2, 400 + Theme.glassShadowPadding * 2)

		// Closed by the compositor - SUPER+C - rather than by the disc.
		onVisibleChanged: if (!visible) root.open = false

		GlassPanel {
			id: pane

			anchors.fill: parent
			anchors.margins: Theme.glassShadowPadding
			radius: Theme.radiusPanel

			Item {
				id: body

				anchors.fill: parent
				focus: true

				// Typing anywhere searches the folder, as in the design's
				// search track. The keys that move and open stay here, and
				// still arrive while the track has focus because a
				// single-line field lets Up, Down and Escape through.
				Keys.onPressed: event => {
					const alt = event.modifiers & Qt.AltModifier;
					const ctrl = event.modifiers & Qt.ControlModifier;
					const columns = root.grid ? gridView.columnCount : 1;

					if (event.key === Qt.Key_Escape) {
						if (root.filter !== "" || searchField.activeFocus) {
							searchField.clear();
							body.forceActiveFocus();
						} else {
							root.close();
						}
					} else if (event.key === Qt.Key_Down) {
						root.move(columns);
					} else if (event.key === Qt.Key_Up) {
						root.move(-columns);
					} else if (event.key === Qt.Key_Right && !searchField.activeFocus && !alt) {
						root.move(1);
					} else if (event.key === Qt.Key_Left && !searchField.activeFocus && !alt) {
						root.move(-1);
					} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						root.openEntry(root.currentEntry);
					} else if (event.key === Qt.Key_Backspace && !searchField.activeFocus) {
						root.up();
					} else if (alt && event.key === Qt.Key_Up) {
						root.up();
					} else if (alt && event.key === Qt.Key_Left) {
						root.goBack();
					} else if (alt && event.key === Qt.Key_Right) {
						root.goForward();
					} else if (ctrl && event.key === Qt.Key_H) {
						root.showHidden = !root.showHidden;
					} else if (ctrl && event.key === Qt.Key_F) {
						searchField.focusInput();
					} else if (!ctrl && !alt && event.text.length === 1 && event.text >= " " && !searchField.activeFocus) {
						searchField.focusInput();
						searchField.text += event.text;
					} else {
						return;
					}
					event.accepted = true;
				}

				// Header: back and forward, where you are, then the search,
				// the view and the way out.
				Item {
					id: header

					anchors {
						left: parent.left
						right: parent.right
						top: parent.top
					}

					height: Theme.filesHeaderHeight

					Rectangle {
						anchors.bottom: parent.bottom
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Row {
						id: navigation

						anchors {
							left: parent.left
							leftMargin: 14
							verticalCenter: parent.verticalCenter
						}

						spacing: 10

						// A fixed model: one built from the history would be
						// rebuilt, discs and all, on every step.
						Repeater {
							model: ["back", "forward"]

							Lens {
								id: navDisc

								required property string modelData

								readonly property bool can: modelData === "back"
									? root.behind.length > 0 : root.ahead.length > 0

								width: 34
								height: 34
								sheen: false
								opacity: can ? 1 : 0.5

								FileGlyph {
									anchors.centerIn: parent
									kind: navDisc.modelData
								}

								MouseArea {
									anchors.fill: parent
									enabled: navDisc.can
									cursorShape: Qt.PointingHandCursor
									onClicked: navDisc.modelData === "back" ? root.goBack() : root.goForward()
								}
							}
						}
					}

					// The path as chips. Clipped on its right, where the
					// search begins, and never on the left: a path that
					// does not fit loses its middle instead.
					Item {
						anchors {
							left: navigation.right
							leftMargin: 16
							right: tools.left
							rightMargin: 12
							verticalCenter: parent.verticalCenter
						}

						height: crumbRow.height
						clip: true

						Row {
							id: crumbRow

							spacing: 6

							Repeater {
								model: root.crumbs

								Row {
									id: crumb

									required property var modelData
									required property int index

									readonly property bool last: index === root.crumbs.length - 1

									spacing: 6

									Text {
										anchors.verticalCenter: parent.verticalCenter
										visible: crumb.index > 0
										text: "›"
										font.pixelSize: Theme.fontTitle
										font.bold: true
										opacity: 0.5
										color: Theme.glassTextPrimary
									}

									Rectangle {
										width: crumbLabel.implicitWidth + 24
										height: crumbLabel.implicitHeight + 12
										radius: Theme.radiusPill
										color: crumb.last ? Theme.glassChipActive
											: crumbMouse.containsMouse ? Theme.glassControlHover : Theme.glassChip
										border.width: 1
										border.color: crumb.last ? Theme.glassTrackBorderFocus : Theme.glassControlBorder

										Text {
											id: crumbLabel

											anchors.centerIn: parent
											text: crumb.modelData.name
											font.pixelSize: Theme.fontTitle
											font.weight: crumb.last ? Font.Bold : Font.DemiBold
											color: Theme.glassTextPrimary
										}

										MouseArea {
											id: crumbMouse

											anchors.fill: parent
											hoverEnabled: true
											cursorShape: Qt.PointingHandCursor
											onClicked: root.go(crumb.modelData.path)
										}
									}
								}
							}
						}
					}

					Row {
						id: tools

						anchors {
							right: parent.right
							rightMargin: 14
							verticalCenter: parent.verticalCenter
						}

						spacing: 10

						GlassField {
							id: searchField

							anchors.verticalCenter: parent.verticalCenter
							width: 240
							height: 38
							fontSize: Theme.fontTitle
							placeholder: "Search " + root.placeName

							leading: Lens {
								width: 26
								height: 26
								sheen: false

								FileGlyph {
									anchors.centerIn: parent
									kind: "search"
								}
							}

							onAccepted: {
								root.openEntry(root.currentEntry);
								body.forceActiveFocus();
							}
						}

						// List or grid: one segmented chip, the chosen half
						// brighter.
						Rectangle {
							anchors.verticalCenter: parent.verticalCenter
							width: 32 * 2 + 2 + 6
							height: 28 + 6
							radius: 13
							color: Theme.glassChip
							border.width: 1
							border.color: Theme.glassControlBorder

							Row {
								anchors.centerIn: parent
								spacing: 2

								Repeater {
									model: [false, true]

									Rectangle {
										required property bool modelData

										readonly property bool chosen: root.grid === modelData

										width: 32
										height: 28
										radius: 10
										color: chosen ? Theme.glassChipActive
											: viewMouse.containsMouse ? Theme.glassControlHover : "transparent"
										border.width: chosen ? 1 : 0
										border.color: Theme.glassTrackBorderFocus

										// Three bars for the list.
										Column {
											anchors.centerIn: parent
											visible: !parent.modelData
											spacing: 3

											Repeater {
												model: 3

												Rectangle {
													width: 14
													height: 2
													radius: 1
													color: Theme.glassTextPrimary
												}
											}
										}

										// Four squares for the grid.
										Grid {
											anchors.centerIn: parent
											visible: parent.modelData
											columns: 2
											spacing: 3

											Repeater {
												model: 4

												Rectangle {
													width: 5
													height: 5
													radius: 1.5
													color: "transparent"
													border.width: 1.5
													border.color: Theme.glassTextPrimary
												}
											}
										}

										MouseArea {
											id: viewMouse

											anchors.fill: parent
											hoverEnabled: true
											cursorShape: Qt.PointingHandCursor
											onClicked: root.grid = parent.modelData
										}
									}
								}
							}
						}

						DiscButton {
							anchors.verticalCenter: parent.verticalCenter
							width: 30
							height: 30
							onClicked: root.close()
						}
					}
				}

				// Places.
				Rectangle {
					id: sidebar

					anchors {
						left: parent.left
						top: header.bottom
						bottom: footer.top
					}

					width: Theme.filesSidebarWidth
					color: Qt.rgba(1, 1, 1, 0.04)

					Rectangle {
						anchors.right: parent.right
						width: 1
						height: parent.height
						color: Theme.glassControlBorder
					}

					Column {
						anchors {
							left: parent.left
							right: parent.right
							top: parent.top
							leftMargin: 10
							rightMargin: 10
							topMargin: 6
						}

						spacing: 2

						Text {
							leftPadding: 10
							topPadding: 10
							bottomPadding: 4
							text: "PLACES"
							font.pixelSize: Theme.fontCaption
							font.bold: true
							font.letterSpacing: 0.66
							opacity: 0.6
							color: Theme.glassTextPrimary
						}

						Repeater {
							model: root.places

							Rectangle {
								id: place

								required property var modelData

								readonly property bool here: root.path === modelData.path

								width: parent.width
								height: 38
								radius: Theme.radiusPill
								color: here ? Theme.glassChipActive
									: placeMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: here ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								Row {
									anchors {
										left: parent.left
										right: parent.right
										leftMargin: 8
										rightMargin: 8
										verticalCenter: parent.verticalCenter
									}

									spacing: 10

									Lens {
										anchors.verticalCenter: parent.verticalCenter
										width: 26
										height: 26
										sheen: false

										FileGlyph {
											anchors.centerIn: parent
											kind: place.modelData.kind
										}
									}

									Text {
										anchors.verticalCenter: parent.verticalCenter
										text: place.modelData.name
										font.pixelSize: Theme.fontTitle
										font.weight: place.here ? Font.Bold : Font.DemiBold
										color: Theme.glassTextPrimary
									}
								}

								MouseArea {
									id: placeMouse

									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: root.go(place.modelData.path)
								}
							}
						}
					}
				}

				// What is in the folder, as rows or as tiles.
				Item {
					id: content

					anchors {
						left: sidebar.right
						right: parent.right
						top: header.bottom
						bottom: footer.top
						leftMargin: 12
						rightMargin: 12
						topMargin: 10
						bottomMargin: 10
					}

					// The list's column headings.
					Item {
						id: listHeader

						width: parent.width
						height: 30
						visible: !root.grid

						readonly property int sizeWidth: 90
						readonly property int dateWidth: 160
						readonly property int gap: 12

						Text {
							x: 12
							anchors.verticalCenter: parent.verticalCenter
							text: "NAME ↑"
							font.pixelSize: Theme.fontCaption
							font.bold: true
							font.letterSpacing: 0.66
							opacity: 0.6
							color: Theme.glassTextPrimary
						}

						Text {
							x: parent.width - 12 - listHeader.sizeWidth - listHeader.gap - listHeader.dateWidth
							anchors.verticalCenter: parent.verticalCenter
							text: "MODIFIED"
							font.pixelSize: Theme.fontCaption
							font.bold: true
							font.letterSpacing: 0.66
							opacity: 0.6
							color: Theme.glassTextPrimary
						}

						Text {
							x: parent.width - 12 - listHeader.sizeWidth
							anchors.verticalCenter: parent.verticalCenter
							text: "SIZE"
							font.pixelSize: Theme.fontCaption
							font.bold: true
							font.letterSpacing: 0.66
							opacity: 0.6
							color: Theme.glassTextPrimary
						}
					}

					ListView {
						id: listView

						anchors {
							left: parent.left
							right: parent.right
							top: listHeader.bottom
							bottom: parent.bottom
							topMargin: 4
						}

						visible: !root.grid
						clip: true
						model: root.grid ? [] : root.entries
						spacing: 4
						boundsBehavior: Flickable.StopAtBounds
						currentIndex: root.current
						highlightFollowsCurrentItem: false
						onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

						delegate: Item {
							id: row

							required property var modelData

							readonly property bool selected: root.picked === modelData.path

							width: listView.width
							height: Theme.launcherRowHeight

							Rectangle {
								anchors.fill: parent
								radius: Theme.radiusRow
								color: row.selected ? Theme.glassChipActive
									: rowMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: row.selected ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								Behavior on color {
									ColorAnimation { duration: 120 }
								}
							}

							Lens {
								id: rowDisc

								x: 12
								anchors.verticalCenter: parent.verticalCenter
								width: 30
								height: 30
								sheen: false

								FileGlyph {
									anchors.centerIn: parent
									kind: row.modelData.folder ? "folder" : "file"
								}
							}

							Text {
								anchors {
									left: rowDisc.right
									leftMargin: 12
									right: modifiedText.left
									rightMargin: listHeader.gap
									verticalCenter: parent.verticalCenter
								}

								elide: Text.ElideRight
								text: row.modelData.name
								font.pixelSize: Theme.fontLead
								font.weight: row.selected ? Font.Bold : Font.DemiBold
								color: Theme.glassTextPrimary
							}

							Text {
								id: modifiedText

								x: parent.width - 12 - listHeader.sizeWidth - listHeader.gap - listHeader.dateWidth
								anchors.verticalCenter: parent.verticalCenter
								width: listHeader.dateWidth
								elide: Text.ElideRight
								text: root.when(row.modelData.modified)
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							Text {
								x: parent.width - 12 - listHeader.sizeWidth
								anchors.verticalCenter: parent.verticalCenter
								width: listHeader.sizeWidth
								elide: Text.ElideRight
								text: root.detail(row.modelData)
								font.pixelSize: Theme.fontBody
								font.weight: Font.DemiBold
								opacity: 0.6
								color: Theme.glassTextPrimary
							}

							MouseArea {
								id: rowMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: root.picked = row.modelData.path
								onDoubleClicked: root.openEntry(row.modelData)
							}
						}
					}

					GridView {
						id: gridView

						anchors.fill: parent
						visible: root.grid
						clip: true
						model: root.grid ? root.entries : []
						boundsBehavior: Flickable.StopAtBounds

						// An id elsewhere in the file shadows a property of this name, and
						// the cell width silently became NaN: hence the longer name.
						readonly property int columnCount: Math.max(1, Math.floor(width / 150))

						cellWidth: width / columnCount
						cellHeight: 8 + 104 + 8 + 32 + 8

						currentIndex: root.current
						highlightFollowsCurrentItem: false
						onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)

						delegate: Item {
							id: cell

							required property var modelData

							readonly property bool selected: root.picked === modelData.path
							readonly property bool image: !modelData.folder && root.imageTypes.includes(modelData.suffix)

							width: gridView.cellWidth
							height: gridView.cellHeight

							Rectangle {
								id: tile

								anchors.fill: parent
								anchors.margins: 4
								radius: 18
								color: cell.selected ? Theme.glassChipActive
									: tileMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: cell.selected ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								Behavior on color {
									ColorAnimation { duration: 120 }
								}

								// The picture, or a disc standing in for one.
								Rectangle {
									id: thumb

									anchors {
										left: parent.left
										right: parent.right
										top: parent.top
										margins: 8
									}

									height: 104
									radius: 12
									color: Qt.rgba(1, 1, 1, 0.06)
									border.width: 1
									border.color: cell.image ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.14)

									Lens {
										anchors.centerIn: parent
										width: 56
										height: 56
										sheen: false
										visible: !cell.image

										FileGlyph {
											anchors.centerIn: parent
											kind: cell.modelData.folder ? "folder" : "file"
											zoom: 1.5
										}
									}

									Image {
										id: picture

										anchors.fill: parent
										anchors.margins: 1
										visible: false
										asynchronous: true
										source: cell.image ? "file://" + cell.modelData.path : ""
										sourceSize: Qt.size(260, 260)
										fillMode: Image.PreserveAspectCrop
										smooth: true
									}

									Item {
										id: pictureMask

										anchors.fill: picture
										visible: false
										layer.enabled: true

										Rectangle {
											anchors.fill: parent
											radius: 11
										}
									}

									MultiEffect {
										anchors.fill: picture
										visible: cell.image && picture.status === Image.Ready
										source: picture
										maskEnabled: true
										maskSource: pictureMask
									}
								}

								Column {
									anchors {
										left: parent.left
										right: parent.right
										top: thumb.bottom
										margins: 8
									}

									spacing: 2

									Text {
										width: parent.width
										horizontalAlignment: Text.AlignHCenter
										elide: Text.ElideRight
										text: cell.modelData.name
										font.pixelSize: Theme.fontBody
										font.weight: cell.selected ? Font.Bold : Font.DemiBold
										color: Theme.glassTextPrimary
									}

									Text {
										width: parent.width
										horizontalAlignment: Text.AlignHCenter
										visible: cell.modelData.folder && text !== ""
										text: root.detail(cell.modelData)
										font.pixelSize: Theme.fontCaption
										font.weight: Font.DemiBold
										opacity: 0.6
										color: Theme.glassTextPrimary
									}
								}

								MouseArea {
									id: tileMouse

									anchors.fill: parent
									hoverEnabled: true
									onClicked: root.picked = cell.modelData.path
									onDoubleClicked: root.openEntry(cell.modelData)
								}
							}
						}
					}

					Text {
						anchors.centerIn: parent
						visible: root.entries.length === 0
						text: root.filter !== "" ? `Nothing here matches “${root.filter}”`
							: root.path === root.trashPath ? "Trash is empty"
							: "This folder is empty"
						font.pixelSize: Theme.fontTitle
						font.weight: Font.DemiBold
						opacity: 0.6
						color: Theme.glassTextPrimary
					}
				}

				// Footer: what is here on the left, the keys on the right.
				Item {
					id: footer

					anchors {
						left: parent.left
						right: parent.right
						bottom: parent.bottom
					}

					height: Theme.filesFooterHeight

					Rectangle {
						anchors.top: parent.top
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Text {
						anchors {
							left: parent.left
							leftMargin: 18
							verticalCenter: parent.verticalCenter
						}

						text: root.status
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						opacity: 0.75
						color: Theme.glassTextPrimary
					}

					Row {
						anchors {
							right: parent.right
							rightMargin: 18
							verticalCenter: parent.verticalCenter
						}

						spacing: 14
						opacity: 0.85

						Repeater {
							model: {
								const rows = [[root.grid ? "←↑↓→" : "↑↓", "Move"]];
								if (root.currentEntry !== null)
									rows.push(["↵", root.currentEntry.folder ? "Open" : "Open"]);
								rows.push(["Esc", root.filter !== "" ? "Clear" : "Close"]);
								return rows;
							}

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
									color: Theme.glassTextPrimary
								}
							}
						}
					}
				}
			}
		}
	}
}
