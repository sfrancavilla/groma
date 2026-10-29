import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import "../ui"
import "../icons"
import ".."

// Settings: the Settings design's A, an ordinary window like Files and the
// Store, with its sections down the side.
//
// Every choice takes effect as it is made. Settings.qml keeps it and
// HyprConfig.qml hands Hyprland its share, so there is no Apply, and - since
// the window asks nothing - no footer. The one choice that waits is a display
// scale, which a wrong value can make unreadable: it is tried, and goes back
// by itself unless it is kept.
Scope {
	id: root

	property bool open: false
	property string section: "keyboard"
	// "" | "layouts" | "pictures"
	property string sheet: ""

	// The earbuds integration (integrations/nothingear), passed in by
	// shell.qml. Its section shows while it knows a pair of buds.
	property var earbuds: null
	readonly property var buds: root.earbuds?.buds ?? null

	readonly property var sections: [
		{ id: "keyboard", title: "Keyboard & Touchpad",
			words: "keyboard layout language typing caps lock escape ctrl repeat delay touchpad trackpad scroll natural tap click swipe gesture palm pointer mouse speed" },
		{ id: "display", title: "Display",
			words: "display screen monitor scale size resolution hidpi zoom refresh rate hz battery" },
		{ id: "idle", title: "Idle & Sleep",
			words: "idle sleep suspend lock dim screen off timeout battery power" },
		{ id: "datetime", title: "Date & Time",
			words: "date time clock 24-hour 12-hour hours am pm bar time zone timezone calendar week monday sunday" },
		{ id: "wallpaper", title: "Wallpaper",
			words: "wallpaper background picture desktop image photo" },
		{ id: "earbuds", title: "Earbuds",
			words: "earbuds headphones nothing buds pause play resume bluetooth" },
		{ id: "privacy", title: "Privacy",
			words: "privacy public address ip network web service" },
		{ id: "about", title: "About",
			words: "about version groma hyprland quickshell kernel linux" },
	]

	readonly property string query: searchField.text.trim().toLowerCase()

	// The sections the side lists: all of them, less Earbuds without buds,
	// narrowed to what the search names.
	readonly property var shown: root.sections.filter(entry =>
		(entry.id !== "earbuds" || root.buds !== null)
		&& (root.query === "" || (entry.title + " " + entry.words).toLowerCase().includes(root.query)))

	function show(section) {
		if (root.sections.some(entry => entry.id === section))
			root.section = section;
		root.open = true;
	}

	function close() {
		root.open = false;
	}

	function go(section) {
		root.section = section;
		root.menu = null;
		content.contentY = 0;
	}

	function move(step) {
		const ids = root.shown.map(entry => entry.id);
		const at = ids.indexOf(root.section);
		const next = ids[Math.max(0, Math.min(ids.length - 1, at + step))];
		if (next !== undefined)
			root.go(next);
	}

	// A window closed mid-trial keeps nothing it was only trying.
	onOpenChanged: {
		if (root.open) {
			about.running = true;
			return;
		}
		HyprConfig.revertDisplay();
		root.sheet = "";
		root.menu = null;
		searchField.clear();
	}

	IpcHandler {
		target: "settings"

		// Without a section, for the launcher: a desktop entry's empty ""
		// argument is dropped on the way, and open() then refuses the call.
		function opened(): void { root.show(""); }
		function open(section: string): void { root.show(section); }
		function close(): void { root.close(); }
		function toggle(): void { if (root.open) root.close(); else root.show(""); }
		function search(term: string): void { root.show(""); searchField.text = term; }
		// "layouts" | "pictures" | "", for scripts and for testing.
		function sheet(name: string): void { root.show(""); root.openSheet(name); }
	}

	// --- Keyboard ------------------------------------------------------------

	// The layouts Hyprland is using, as { layout, variant } pairs: the ones
	// chosen here, else whatever hyprland.lua - or machine.lua - gave it.
	readonly property var layouts: {
		const chosen = Settings.keyboardLayouts ?? [];
		if (chosen.length > 0)
			return chosen;
		const names = String(HyprConfig.input.kb_layout ?? "us").split(",");
		const variants = String(HyprConfig.input.kb_variant ?? "").split(",");
		return names.map((layout, i) => ({ layout: layout.trim(), variant: (variants[i] ?? "").trim() }))
			.filter(entry => entry.layout !== "");
	}

	// Every layout and variant xkb knows, flat, as the picker lists them.
	// Loops, because Qt's JavaScript has no flatMap.
	readonly property var layoutChoices: {
		const flat = [];
		for (const known of HyprConfig.layoutCatalog) {
			// xkb's slot for a hand-written layout, which nobody has.
			if (known.layout === "custom")
				continue;
			flat.push({ layout: known.layout, variant: "", name: known.name });
			for (const v of known.variants)
				flat.push({ layout: known.layout, variant: v.variant, name: v.name });
		}
		return flat;
	}

	readonly property var layoutMatches: {
		const term = layoutSearch.text.trim().toLowerCase();
		const have = root.layouts.map(entry => entry.layout + ":" + entry.variant);
		return root.layoutChoices.filter(choice =>
			!have.includes(choice.layout + ":" + choice.variant)
			&& (term === "" || choice.name.toLowerCase().includes(term) || choice.layout === term));
	}

	property int layoutPicked: 0
	readonly property var layoutCurrent: root.layoutMatches[root.layoutPicked] ?? null

	function layoutName(entry) {
		const known = HyprConfig.layoutCatalog.find(l => l.layout === entry.layout);
		if (!known)
			return entry.variant ? `${entry.layout} (${entry.variant})` : entry.layout;
		if (!entry.variant)
			return known.name;
		return known.variants.find(v => v.variant === entry.variant)?.name
			?? `${known.name} (${entry.variant})`;
	}

	function addLayout(entry) {
		if (!entry)
			return;
		Settings.setKeyboardLayouts(root.layouts.concat([{ layout: entry.layout, variant: entry.variant }]));
		root.sheet = "";
	}

	function removeLayout(index) {
		Settings.setKeyboardLayouts(root.layouts.filter((_, i) => i !== index));
	}

	function makeFirst(index) {
		const list = root.layouts.slice();
		const [entry] = list.splice(index, 1);
		Settings.setKeyboardLayouts([entry].concat(list));
	}

	onLayoutMatchesChanged: root.layoutPicked = 0

	// --- Display -------------------------------------------------------------

	// Of the scales a display can take sharply, the ones a person would pick:
	// steps of a fortieth, which keeps 1.875 - the nearest a 3:2 panel gets to
	// 1.8 - and drops 1.0667 and 1.3333, which are sharp and no use to anyone.
	function niceScales(monitor) {
		return (monitor.scales ?? []).filter(s => Math.abs(s * 40 - Math.round(s * 40)) < 1e-6);
	}

	// Three places, so 1.875 is not shown as 1.88.
	function scaleLabel(scale) {
		return scale === null || scale === undefined ? "Auto" : String(Number(Number(scale).toFixed(3)));
	}

	// What the chips show as chosen: the scale being tried, else the kept one,
	// null being Auto.
	function chosenScale(monitor) {
		const trying = HyprConfig.preview;
		if (trying && trying.description === monitor.description)
			return trying.scale;
		return Settings.displayScale(monitor.description);
	}

	function tryScale(monitor, scale) {
		if (root.scaleLabel(scale) === root.scaleLabel(root.chosenScale(monitor)))
			return;
		HyprConfig.previewDisplay(monitor.description, "scale", scale);
	}

	// The mode the rate chips show as chosen: the one being tried, else the
	// kept one, else whatever the display is running at.
	function chosenRate(monitor) {
		const trying = HyprConfig.preview;
		const mode = trying && trying.description === monitor.description
			? trying.mode : Settings.displayMode(monitor.description);
		return mode ? Math.round(parseFloat(mode.split("@")[1])) : Math.round(monitor.refreshRate);
	}

	function tryRate(monitor, entry) {
		if (Math.round(entry.rate) === root.chosenRate(monitor))
			return;
		HyprConfig.previewDisplay(monitor.description, "mode", entry.mode);
	}

	// A mode's rate; without one, the rate it was running at, if known.
	function rateLabel(mode, rate) {
		if (mode)
			return `${Math.round(parseFloat(mode.split("@")[1]))} Hz`;
		return rate ? `${rate} Hz` : "its usual rate";
	}

	// --- Idle ------------------------------------------------------------------

	readonly property var stages: [
		{ id: "dim", title: "Dim the screen" },
		{ id: "lock", title: "Lock" },
		{ id: "screenOff", title: "Turn the screen off" },
		{ id: "suspend", title: "Suspend" },
	]

	readonly property var durations: [60, 120, 180, 300, 600, 900, 1200, 1800, 2700, 3600, 0]

	function duration(seconds) {
		if (seconds <= 0)
			return "Never";
		if (seconds < 60)
			return `${seconds} s`;
		if (seconds % 3600 === 0)
			return seconds === 3600 ? "1 hour" : `${seconds / 3600} hours`;
		return `${Math.round(seconds / 60)} min`;
	}

	// Each stage comes after the one above it: a lock before the dim would
	// lock a bright screen with no warning, which is the whole point of
	// dimming first. Never fits anywhere, since it leaves the order alone.
	function fits(stage, onBattery, seconds) {
		if (seconds === 0)
			return true;
		const order = root.stages.map(entry => entry.id);
		const at = order.indexOf(stage);
		return order.every((other, i) => {
			const value = Settings.idleAfter(other, onBattery);
			return i === at || value === 0 || (i < at ? value < seconds : value > seconds);
		});
	}

	// Here rather than in the option's click: saving can rebuild the menu's
	// list, which destroys the option mid-handler, and nothing after it would run.
	function chooseDuration(seconds) {
		const menu = root.menu;
		root.menu = null;
		Settings.setIdleAfter(menu.stage, menu.battery, seconds);
	}

	function idleCustomised() {
		return Object.keys(Settings.idleTimes ?? {}).length > 0;
	}

	function resetIdle() {
		for (const stage of root.stages) {
			Settings.setIdleAfter(stage.id, false, null);
			Settings.setIdleAfter(stage.id, true, null);
		}
	}

	// The open duration menu: { stage, battery, x, y }, or null.
	property var menu: null

	// --- Wallpaper -------------------------------------------------------------

	property var pictures: []
	property string picturesDir: ""
	property bool picturesLoaded: false
	property int picturePicked: -1

	function fileName(path) {
		return String(path).split("/").pop();
	}

	function openSheet(name) {
		root.menu = null;
		if (name === "layouts") {
			layoutSearch.clear();
			root.layoutPicked = 0;
			root.sheet = "layouts";
			layoutSearch.focusInput();
		} else if (name === "pictures") {
			root.picturePicked = -1;
			root.picturesLoaded = false;
			pictureFinder.running = true;
			root.sheet = "pictures";
			body.forceActiveFocus();
		} else {
			root.sheet = "";
			body.forceActiveFocus();
		}
	}

	// The newest pictures first, from the pictures folder and a few levels
	// under it. Two hundred is more than anyone scrolls through to find one.
	Process {
		id: pictureFinder

		command: ["sh", "-c",
			"f=\"${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs\"; [ -f \"$f\" ] && . \"$f\"; "
			+ "dir=\"${XDG_PICTURES_DIR:-$HOME/Pictures}\"; echo \"$dir\"; "
			+ "[ -d \"$dir\" ] && find \"$dir\" -maxdepth 4 -type f "
			+ "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) "
			+ "-printf '%T@ %p\\n' | sort -rn | head -200 | cut -d' ' -f2-"]

		stdout: StdioCollector {
			onStreamFinished: {
				const lines = text.split("\n").filter(line => line !== "");
				root.picturesDir = lines[0] ?? "";
				root.pictures = lines.slice(1);
				root.picturesLoaded = true;
			}
		}
	}

	// --- About -----------------------------------------------------------------

	property var versions: []

	// The sliders' width: as wide as a row leaves room for, within reason.
	readonly property real trackWidth: Math.max(160, Math.min(360, page.width - 380))
	property string timeZone: ""

	Process {
		id: about

		command: ["sh", "-c",
			"git -C \"$1\" describe --tags --always 2>/dev/null || echo unknown; "
			+ "hyprctl -j version 2>/dev/null | sed -n 's/.*\"tag\": *\"v\\{0,1\\}\\([^\"]*\\)\".*/\\1/p' | head -1; "
			+ "qs --version 2>/dev/null | head -1 | cut -d' ' -f2; "
			+ "uname -r; "
			+ "timedatectl show -p Timezone --value 2>/dev/null",
			"sh", Quickshell.shellDir]

		stdout: StdioCollector {
			onStreamFinished: {
				const lines = text.split("\n");
				root.versions = [
					{ title: "Groma", value: lines[0] ?? "" },
					{ title: "Hyprland", value: lines[1] ?? "" },
					{ title: "Quickshell", value: lines[2] ?? "" },
					{ title: "Linux", value: lines[3] ?? "" },
				];
				root.timeZone = lines[4] ?? "";
			}
		}
	}

	// --- Pieces --------------------------------------------------------------------

	// A label over the group of rows below it: GUIDELINES' uppercase.
	component Heading: Text {
		width: parent?.width ?? 0
		leftPadding: 4
		topPadding: 10
		bottomPadding: 2
		font.pixelSize: Theme.fontCaption
		font.bold: true
		font.letterSpacing: 0.66
		opacity: 0.6
		color: Theme.glassTextPrimary
	}

	// Rows on one rounded plate.
	component Group: Rectangle {
		default property alias rows: rowsColumn.data

		width: parent?.width ?? 0
		height: rowsColumn.implicitHeight
		radius: Theme.radiusRow
		color: Qt.rgba(1, 1, 1, 0.06)
		border.width: 1
		border.color: Theme.glassControlBorder

		Column {
			id: rowsColumn

			width: parent.width
		}
	}

	// One choice: what it is on the left, the control on the right, a line
	// above it unless it is the first.
	component SettingRow: Item {
		id: row

		property string title: ""
		property string caption: ""
		property bool divider: true
		property Component leading: null
		default property alias trailing: trailingSlot.data

		width: parent?.width ?? 0
		height: Math.max(52, textColumn.implicitHeight + 20, trailingSlot.height + 20)

		Rectangle {
			visible: row.divider
			anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
			height: 1
			color: Qt.rgba(1, 1, 1, 0.12)
		}

		Loader {
			id: leadingSlot

			anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
			active: row.leading !== null
			sourceComponent: row.leading
		}

		Column {
			id: textColumn

			anchors {
				left: leadingSlot.active ? leadingSlot.right : parent.left
				leftMargin: leadingSlot.active ? 12 : 14
				right: trailingSlot.left
				rightMargin: 12
				verticalCenter: parent.verticalCenter
			}
			spacing: 3

			Text {
				width: parent.width
				elide: Text.ElideRight
				text: row.title
				visible: text !== ""
				font.pixelSize: Theme.fontTitle
				font.bold: true
				color: Theme.glassTextPrimary
			}

			Text {
				width: parent.width
				wrapMode: Text.WordWrap
				text: row.caption
				visible: text !== ""
				font.pixelSize: Theme.fontCaption
				lineHeight: 1.3
				opacity: 0.8
				color: Theme.glassTextPrimary
			}
		}

		Item {
			id: trailingSlot

			anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
			width: childrenRect.width
			height: childrenRect.height
		}
	}

	// A layout's xkb code, as the design's key-shaped badge.
	component CodeBadge: Rectangle {
		property string code: ""

		width: Math.max(36, codeLabel.implicitWidth + 14)
		height: 28
		radius: 8
		color: Qt.rgba(1, 1, 1, 0.16)
		border.width: 1
		border.color: Qt.rgba(1, 1, 1, 0.3)

		Text {
			id: codeLabel

			anchors.centerIn: parent
			text: parent.code
			font.pixelSize: Theme.fontBody
			font.bold: true
			color: Theme.glassTextPrimary
		}
	}

	// A small downward chevron, for a control that opens a menu.
	component Chevron: Shape {
		id: chevron

		property color color: Theme.glassTextPrimary

		width: 10
		height: 6
		antialiasing: true
		layer.enabled: true
		layer.samples: 4

		ShapePath {
			strokeColor: chevron.color
			strokeWidth: 1.4
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap
			joinStyle: ShapePath.RoundJoin
			startX: 1; startY: 1
			PathLine { x: 5; y: 5 }
			PathLine { x: 9; y: 1 }
		}
	}

	// A duration that opens the menu of others.
	component DurationButton: Rectangle {
		id: picker

		property string stage: ""
		property bool battery: false
		readonly property int seconds: Settings.idleAfter(picker.stage, picker.battery)
		readonly property bool opened: root.menu !== null
			&& root.menu.stage === picker.stage && root.menu.battery === picker.battery

		width: 112
		height: Theme.chipHeight
		radius: Theme.radiusPill
		color: picker.opened ? Theme.glassChipSelected
			: pickerMouse.containsMouse ? Theme.glassControlHover : Theme.glassChip
		border.width: 1
		border.color: picker.opened ? Theme.glassChipSelectedBorder : Theme.glassControlBorder

		Text {
			anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
			text: root.duration(picker.seconds)
			font.pixelSize: Theme.fontBody
			font.bold: true
			color: Theme.glassTextPrimary
		}

		Chevron {
			anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
		}

		MouseArea {
			id: pickerMouse

			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: {
				if (picker.opened) {
					root.menu = null;
					return;
				}
				const at = picker.mapToItem(body, 0, picker.height + 4);
				root.menu = { stage: picker.stage, battery: picker.battery, x: at.x, y: at.y };
			}
		}
	}

	// A picture to choose for the desktop: Groma's own drawing, or a file.
	component WallpaperTile: Rectangle {
		id: tile

		property string path: ""
		property bool chosen: false
		property string title: ""
		property string caption: ""

		signal picked

		width: 240
		height: 196
		radius: Theme.radiusRow
		color: tile.chosen ? Theme.glassChipActive
			: tileMouse.containsMouse ? Theme.glassControlHover : Theme.glassChip
		border.width: 1
		border.color: tile.chosen ? Theme.glassChipSelectedBorder : Theme.glassControlBorder

		Rectangle {
			id: thumb

			anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
			height: 136
			radius: 12
			color: Theme.desktopBase
			clip: true

			DesktopBackdrop {
				anchors.fill: parent
				visible: tile.path === ""
			}

			Image {
				anchors.fill: parent
				visible: tile.path !== ""
				source: tile.path !== "" ? "file://" + tile.path : ""
				sourceSize.width: 480
				fillMode: Image.PreserveAspectCrop
				asynchronous: true
			}
		}

		Column {
			anchors { left: parent.left; right: parent.right; top: thumb.bottom; leftMargin: 10; rightMargin: 10; topMargin: 8 }
			spacing: 2

			Text {
				width: parent.width
				elide: Text.ElideMiddle
				text: tile.title
				font.pixelSize: Theme.fontTitle
				font.bold: true
				color: Theme.glassTextPrimary
			}

			Text {
				width: parent.width
				elide: Text.ElideMiddle
				text: tile.caption
				font.pixelSize: Theme.fontCaption
				opacity: 0.8
				color: Theme.glassTextPrimary
			}
		}

		MouseArea {
			id: tileMouse

			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: tile.picked()
		}
	}

	// --- The window ------------------------------------------------------------------

	FloatingWindow {
		id: window

		visible: root.open
		title: "Settings"
		color: "transparent"

		implicitWidth: Theme.settingsWidth
		implicitHeight: Theme.settingsHeight
		minimumSize: Qt.size(640, 420)

		onVisibleChanged: if (!visible) root.open = false

		GlassPanel {
			anchors.fill: parent
			radius: Theme.radiusWindow
			shadowLayers: 0

			Item {
				id: body

				anchors.fill: parent
				focus: true

				Keys.onPressed: event => {
					const ctrl = event.modifiers & Qt.ControlModifier;
					if (HyprConfig.preview !== null) {
						if (event.key === Qt.Key_Escape)
							HyprConfig.revertDisplay();
						else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
							HyprConfig.keepDisplay();
						event.accepted = true;
						return;
					}
					if (root.menu !== null) {
						if (event.key === Qt.Key_Escape)
							root.menu = null;
						event.accepted = true;
						return;
					}
					if (root.sheet === "layouts") {
						if (event.key === Qt.Key_Escape)
							root.openSheet("");
						else if (event.key === Qt.Key_Down)
							root.layoutPicked = Math.min(root.layoutMatches.length - 1, root.layoutPicked + 1);
						else if (event.key === Qt.Key_Up)
							root.layoutPicked = Math.max(0, root.layoutPicked - 1);
						else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
							root.addLayout(root.layoutCurrent);
						else
							return;
						event.accepted = true;
						return;
					}
					if (root.sheet === "pictures") {
						if (event.key === Qt.Key_Escape)
							root.openSheet("");
						event.accepted = true;
						return;
					}
					if (event.key === Qt.Key_Escape) {
						if (searchField.text !== "") {
							searchField.clear();
							body.forceActiveFocus();
						} else {
							root.close();
						}
					} else if (event.key === Qt.Key_Down) {
						root.move(1);
					} else if (event.key === Qt.Key_Up) {
						root.move(-1);
					} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						if (root.shown.length > 0)
							root.go(root.shown[0].id);
						searchField.clear();
						body.forceActiveFocus();
					} else if (event.key === Qt.Key_Slash || (ctrl && event.key === Qt.Key_F)) {
						searchField.focusInput();
					} else if (!ctrl && event.text.length === 1 && event.text > " " && !searchField.activeFocus) {
						searchField.focusInput();
						searchField.text += event.text;
					} else {
						return;
					}
					event.accepted = true;
				}

				// Header: the window's name, the search, the close.
				Item {
					id: header

					anchors { left: parent.left; right: parent.right; top: parent.top }
					height: Theme.filesHeaderHeight

					Rectangle {
						anchors.bottom: parent.bottom
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Text {
						anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
						text: "Settings"
						font.pixelSize: Theme.fontHeading
						font.bold: true
						color: Theme.glassTextPrimary
					}

					Row {
						anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
						spacing: 10

						GlassField {
							id: searchField

							anchors.verticalCenter: parent.verticalCenter
							width: 240
							height: 38
							fontSize: Theme.fontTitle
							placeholder: "Search settings"

							leading: Lens {
								width: 26
								height: 26
								sheen: false

								FileGlyph { anchors.centerIn: parent; kind: "search" }
							}

							onAccepted: {
								if (root.shown.length > 0)
									root.go(root.shown[0].id);
								searchField.clear();
								body.forceActiveFocus();
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

				// The sections.
				Rectangle {
					id: sidebar

					anchors { left: parent.left; top: header.bottom; bottom: parent.bottom }
					width: Theme.settingsSidebarWidth
					color: Qt.rgba(1, 1, 1, 0.04)
					opacity: root.sheet !== "" || HyprConfig.preview !== null ? Theme.menuBackdropOpacity : 1

					Rectangle {
						anchors.right: parent.right
						width: 1
						height: parent.height
						color: Theme.glassControlBorder
					}

					Column {
						anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; topMargin: 12 }
						spacing: 2

						Repeater {
							model: root.shown

							Rectangle {
								id: side

								required property var modelData
								readonly property bool here: root.section === modelData.id

								width: parent.width
								height: 38
								radius: Theme.radiusPill
								color: side.here ? Theme.glassChipActive
									: sideMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: side.here ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								Row {
									anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
									spacing: 10

									Lens {
										anchors.verticalCenter: parent.verticalCenter
										width: 26
										height: 26
										sheen: false

										SettingsIcon {
											anchors.centerIn: parent
											width: 16
											height: 16
											kind: side.modelData.id
										}
									}

									Text {
										anchors.verticalCenter: parent.verticalCenter
										width: parent.width - 36
										elide: Text.ElideRight
										text: side.modelData.title
										font.pixelSize: Theme.fontTitle
										font.weight: side.here ? Font.Bold : Font.DemiBold
										color: Theme.glassTextPrimary
									}
								}

								MouseArea {
									id: sideMouse

									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: { body.forceActiveFocus(); root.go(side.modelData.id); }
								}
							}
						}

						Text {
							visible: root.shown.length === 0
							width: parent.width
							leftPadding: 10
							topPadding: 8
							wrapMode: Text.WordWrap
							text: "Nothing matches. Clear the search to see all."
							font.pixelSize: Theme.fontBody
							opacity: 0.75
							color: Theme.glassTextPrimary
						}
					}
				}

				// The section.
				Flickable {
					id: content

					anchors { left: sidebar.right; right: parent.right; top: header.bottom; bottom: parent.bottom }
					contentHeight: page.height + 44
					boundsBehavior: Flickable.StopAtBounds
					clip: true
					opacity: root.sheet !== "" || HyprConfig.preview !== null ? Theme.menuBackdropOpacity : 1

					Behavior on opacity { NumberAnimation { duration: 120 } }

					Column {
						id: page

						x: 26
						y: 22
						width: content.width - 52
						spacing: 6

						Text {
							text: root.sections.find(entry => entry.id === root.section)?.title ?? ""
							font.pixelSize: Theme.fontDisplay
							font.bold: true
							color: Theme.glassTextPrimary
						}

						Text {
							bottomPadding: 6
							visible: root.section !== "about"
							text: "Changes apply as you make them."
							font.pixelSize: Theme.fontBody
							opacity: 0.82
							color: Theme.glassTextPrimary
						}

						// --- Keyboard & Touchpad ---

						Column {
							width: parent.width
							spacing: 6
							visible: root.section === "keyboard"

							Heading { text: "LAYOUTS" }

							Group {
								Repeater {
									model: root.layouts

									SettingRow {
										id: layoutRow

										required property var modelData
										required property int index

										divider: index > 0
										title: root.layoutName(modelData)
										caption: index === 0 ? "Every session starts in this one" : ""
										leading: Component { CodeBadge { code: layoutRow.modelData.layout } }

										Row {
											spacing: 8
											visible: root.layouts.length > 1

											DialogButton {
												visible: layoutRow.index > 0
												text: "Make first"
												onClicked: root.makeFirst(layoutRow.index)
											}

											DialogButton {
												text: "Remove"
												onClicked: root.removeLayout(layoutRow.index)
											}
										}
									}
								}

								SettingRow {
									caption: root.layouts.length > 1
										? "SUPER+SPACE switches between them."
										: "Add a second to switch with SUPER+SPACE."

									DialogButton {
										text: "Add Layout…"
										onClicked: root.openSheet("layouts")
									}
								}
							}

							Heading { text: "KEYS" }

							Group {
								// Four answers; they wrap under the label in a
								// window tiled to half the screen.
								Item {
									width: parent.width
									height: capsColumn.implicitHeight + 24

									Column {
										id: capsColumn

										x: 14
										y: 12
										width: parent.width - 28
										spacing: 10

										Column {
											width: parent.width
											spacing: 3

											Text {
												text: "Caps Lock key"
												font.pixelSize: Theme.fontTitle
												font.bold: true
												color: Theme.glassTextPrimary
											}

											Text {
												width: parent.width
												wrapMode: Text.WordWrap
												text: "What it does when pressed"
												font.pixelSize: Theme.fontCaption
												opacity: 0.8
												color: Theme.glassTextPrimary
											}
										}

										Flow {
											width: parent.width
											spacing: 4

											Repeater {
												model: [["", "Caps Lock"], ["escape", "Escape"], ["ctrl", "Ctrl"], ["none", "Nothing"]]

												Chip {
													required property var modelData

													width: 84
													text: modelData[1]
													active: Settings.capsLock === modelData[0]
													onClicked: Settings.setCapsLock(modelData[0])
												}
											}
										}
									}
								}

								SettingRow {
									title: "Delay before repeating"
									caption: "How long a held key waits"

									// 150 to 1000 ms.
									WordSlider {
										trackWidth: root.trackWidth
										low: "Short"
										high: "Long"
										value: ((Settings.repeatDelay ?? HyprConfig.input.repeat_delay ?? 600) - 150) / 850
										onMoved: v => Settings.setRepeatDelay(150 + Math.round(v * 850 / 25) * 25)
									}
								}

								SettingRow {
									title: "Repeat speed"
									caption: "Then how fast it repeats"

									// 10 to 60 a second.
									WordSlider {
										trackWidth: root.trackWidth
										low: "Slow"
										high: "Fast"
										value: ((Settings.repeatRate ?? HyprConfig.input.repeat_rate ?? 25) - 10) / 50
										onMoved: v => Settings.setRepeatRate(10 + Math.round(v * 50))
									}
								}

								SettingRow {
									title: "Try it"

									GlassField {
										width: root.trackWidth + 90
										height: 34
										fontSize: Theme.fontBody
										placeholder: "Hold a key down here"
									}
								}
							}

							Heading { text: "TOUCHPAD" }

							Group {
								SettingRow {
									divider: false
									title: "Natural scrolling"
									caption: "The page follows your fingers, as on a phone"

									Switch {
										checked: Settings.naturalScroll ?? HyprConfig.input.natural_scroll ?? false
										onToggled: Settings.setNaturalScroll(!checked)
									}
								}

								SettingRow {
									title: "Tap to click"
									caption: "A light tap clicks; two fingers right-click"

									Switch {
										checked: Settings.tapToClick ?? HyprConfig.input.tap_to_click ?? true
										onToggled: Settings.setTapToClick(!checked)
									}
								}

								SettingRow {
									title: "Ignore while typing"
									caption: "So a palm on the touchpad does not move the pointer"

									Switch {
										checked: Settings.disableWhileTyping ?? HyprConfig.input.disable_while_typing ?? true
										onToggled: Settings.setDisableWhileTyping(!checked)
									}
								}

								SettingRow {
									title: "Swipe between workspaces"
									caption: "Three fingers across the touchpad"

									Switch {
										checked: Settings.workspaceSwipe ?? true
										onToggled: Settings.setWorkspaceSwipe(!checked)
									}
								}

								SettingRow {
									title: "Scroll speed"

									// 0.2 to 2, with 1 - Hyprland's own - in the middle.
									WordSlider {
										trackWidth: root.trackWidth
										low: "Slower"
										high: "Faster"
										value: {
											const f = Settings.scrollFactor ?? HyprConfig.input.scroll_factor ?? 1;
											return f <= 1 ? (f - 0.2) / 1.6 : 0.5 + (f - 1) / 2;
										}
										onMoved: v => Settings.setScrollFactor(Math.round(
											(v <= 0.5 ? 0.2 + v * 1.6 : 1 + (v - 0.5) * 2) * 20) / 20)
									}
								}
							}

							Heading { text: "POINTER" }

							Group {
								SettingRow {
									divider: false
									title: "Pointer speed"
									caption: "Mouse and touchpad"

									WordSlider {
										trackWidth: root.trackWidth
										low: "Slower"
										high: "Faster"
										value: ((Settings.pointerSpeed ?? HyprConfig.input.sensitivity ?? 0) + 1) / 2
										onMoved: v => Settings.setPointerSpeed(Math.round((v * 2 - 1) * 20) / 20)
									}
								}
							}
						}

						// --- Display ---

						Column {
							width: parent.width
							spacing: 6
							visible: root.section === "display"

							Repeater {
								model: HyprConfig.monitors

								Column {
									id: display

									required property var modelData
									// A rule in machine.lua has the last word on
									// this display, so offering a choice here
									// would only be undone at the next reload.
									readonly property bool handWritten: HyprConfig.machineSets(display.modelData)

									width: parent.width
									spacing: 6

									Heading {
										text: display.modelData.name.startsWith("eDP") ? "BUILT-IN DISPLAY" : `DISPLAY ${display.modelData.name}`
									}

									Group {
										SettingRow {
											divider: false
											title: display.modelData.description
											caption: `${display.modelData.name} · ${display.modelData.width} × ${display.modelData.height}`
											leading: Component {
												SettingsIcon { width: 22; height: 22; kind: "display"; color: Theme.glassTextPrimary }
											}
										}

										// The chips under their label rather than beside
										// it: nine of them do not fit beside it in a
										// window tiled to half the screen, and wrap.
										Item {
											visible: !display.handWritten
											width: parent.width
											height: scaleColumn.implicitHeight + 24

											Rectangle {
												anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
												height: 1
												color: Qt.rgba(1, 1, 1, 0.12)
											}

											Column {
												id: scaleColumn

												x: 14
												y: 12
												width: parent.width - 28
												spacing: 10

												Column {
													width: parent.width
													spacing: 3

													Text {
														text: "Scale"
														font.pixelSize: Theme.fontTitle
														font.bold: true
														color: Theme.glassTextPrimary
													}

													Text {
														text: `Looks like ${Math.round(display.modelData.width / display.modelData.scale)} × ${Math.round(display.modelData.height / display.modelData.scale)}`
														font.pixelSize: Theme.fontCaption
														opacity: 0.8
														color: Theme.glassTextPrimary
													}
												}

												Flow {
													width: parent.width
													spacing: 4

													Repeater {
														model: [null].concat(root.niceScales(display.modelData))

														Chip {
															required property var modelData

															width: 48
															text: root.scaleLabel(modelData)
															active: root.scaleLabel(modelData) === root.scaleLabel(root.chosenScale(display.modelData))
															onClicked: root.tryScale(display.modelData, modelData)
														}
													}
												}
											}
										}

										// Only where there is a choice: most external
										// displays offer one rate at their full size.
										SettingRow {
											visible: !display.handWritten && (display.modelData.rates ?? []).length > 1
											title: "Refresh rate"
											caption: "Lower lasts longer on battery"

											Row {
												spacing: 4

												Repeater {
													model: display.modelData.rates ?? []

													Chip {
														required property var modelData

														width: 64
														text: `${Math.round(modelData.rate)} Hz`
														active: Math.round(modelData.rate) === root.chosenRate(display.modelData)
														onClicked: root.tryRate(display.modelData, modelData)
													}
												}
											}
										}

										SettingRow {
											visible: display.handWritten
											title: "Set in machine.lua"
											caption: "Its scale and refresh rate come from ~/.config/hypr/machine.lua, which has the last word. Change them there."
										}
									}
								}
							}

							Text {
								width: parent.width
								leftPadding: 4
								topPadding: 4
								wrapMode: Text.WordWrap
								text: "Only the scales each display can show sharply. A new scale or rate is tried before it is kept."
								font.pixelSize: Theme.fontCaption
								opacity: 0.8
								color: Theme.glassTextPrimary
							}
						}

						// --- Idle & Sleep ---

						Column {
							width: parent.width
							spacing: 6
							visible: root.section === "idle"

							Item {
								width: parent.width
								height: 24

								Heading {
									anchors.right: parent.right
									anchors.rightMargin: 14
									width: 112
									text: "ON BATTERY"
								}

								Heading {
									anchors.right: parent.right
									anchors.rightMargin: 14 + 112 + 10
									width: 112
									text: "PLUGGED IN"
								}
							}

							Group {
								Repeater {
									model: root.stages

									SettingRow {
										id: stageRow

										required property var modelData
										required property int index

										divider: index > 0
										title: modelData.title

										Row {
											spacing: 10

											DurationButton { stage: stageRow.modelData.id; battery: false }
											DurationButton { stage: stageRow.modelData.id; battery: true }
										}
									}
								}
							}

							Text {
								width: parent.width
								leftPadding: 4
								topPadding: 4
								wrapMode: Text.WordWrap
								text: "Each step comes after the one above it. An app playing video keeps the screen awake."
								font.pixelSize: Theme.fontCaption
								opacity: 0.8
								color: Theme.glassTextPrimary
							}

							DialogButton {
								visible: root.idleCustomised()
								text: "Use Groma's times"
								onClicked: root.resetIdle()
							}
						}

						// --- Date & Time ---

						Column {
							width: parent.width
							spacing: 6
							visible: root.section === "datetime"

							Heading { text: "CLOCK" }

							Group {
								SettingRow {
									divider: false
									title: "24-hour clock"
									caption: Settings.clock24 ? "15:30" : "3:30 PM"

									Switch {
										checked: Settings.clock24
										onToggled: Settings.setClock24(!checked)
									}
								}

								SettingRow {
									title: "Date in the bar"
									caption: "Before the time, as in Wed 28 Oct"

									Switch {
										checked: Settings.clockDate
										onToggled: Settings.setClockDate(!checked)
									}
								}
							}

							Heading { text: "CALENDAR" }

							Group {
								SettingRow {
									divider: false
									title: "Week starts on"
									caption: Settings.weekStart === null ? "As the language has it" : "In the clock's calendar"

									Row {
										spacing: 6

										Repeater {
											model: [[1, "Monday"], [0, "Sunday"]]

											Chip {
												required property var modelData

												text: modelData[1]
												active: (Settings.weekStart ?? Qt.locale().firstDayOfWeek % 7) === modelData[0]
												onClicked: Settings.setWeekStart(modelData[0])
											}
										}
									}
								}
							}

							Heading { text: "TIME ZONE" }

							Group {
								SettingRow {
									divider: false
									title: root.timeZone || "Not set"
									caption: "Set with timedatectl set-timezone, which asks for your password"
								}
							}
						}

						// --- Wallpaper ---

						Column {
							width: parent.width
							spacing: 12
							visible: root.section === "wallpaper"

							Flow {
								width: parent.width
								spacing: 12

								WallpaperTile {
									chosen: Settings.wallpaper === ""
									title: "Groma's own"
									caption: "Drawn, so the glass has colour to take"
									onPicked: Settings.setWallpaper("")
								}

								WallpaperTile {
									visible: Settings.wallpaper !== ""
									path: Settings.wallpaper
									chosen: true
									title: root.fileName(Settings.wallpaper)
									caption: Settings.wallpaper.slice(0, Settings.wallpaper.lastIndexOf("/"))
								}
							}

							Text {
								width: parent.width
								leftPadding: 4
								wrapMode: Text.WordWrap
								text: "A picture fills the screen and is cropped to fit. If it is moved or deleted, Groma's own comes back."
								font.pixelSize: Theme.fontCaption
								opacity: 0.8
								color: Theme.glassTextPrimary
							}

							DialogButton {
								text: "Choose Picture…"
								variant: "primary"
								onClicked: root.openSheet("pictures")
							}
						}

						// --- Earbuds ---

						Column {
							width: parent.width
							spacing: 6
							visible: root.section === "earbuds"

							Heading { text: "PLAYBACK" }

							Group {
								SettingRow {
									divider: false
									title: "Pause when a bud comes out"
									caption: "And when one goes in, since the buds do not say which"

									Switch {
										checked: Settings.pauseOnBudRemoved
										onToggled: Settings.setPauseOnBudRemoved(!checked)
									}
								}

								SettingRow {
									title: "Play again when it goes back"
									caption: "Only what Groma paused, and only within two minutes"

									Switch {
										checked: Settings.resumeOnBudReplaced
										onToggled: Settings.setResumeOnBudReplaced(!checked)
									}
								}
							}

							Text {
								width: parent.width
								leftPadding: 4
								topPadding: 4
								text: `For ${root.buds?.name ?? "the earbuds"}, read over their own protocol.`
								font.pixelSize: Theme.fontCaption
								opacity: 0.8
								color: Theme.glassTextPrimary
							}
						}

						// --- Privacy ---

						Column {
							width: parent.width
							spacing: 6
							visible: root.section === "privacy"

							Heading { text: "NETWORK" }

							Group {
								SettingRow {
									divider: false
									title: "Public address"
									caption: "Ask a web service for this network's public address, shown in the Wi-Fi card. Off until you turn it on."

									Switch {
										checked: Settings.publicAddressLookup
										onToggled: Settings.setPublicAddressLookup(!checked)
									}
								}
							}
						}

						// --- About ---

						Column {
							width: parent.width
							spacing: 6
							visible: root.section === "about"

							Heading { text: "VERSIONS" }

							Group {
								Repeater {
									model: root.versions

									SettingRow {
										id: versionRow

										required property var modelData
										required property int index

										divider: index > 0
										title: modelData.title

										Text {
											text: versionRow.modelData.value
											font.family: "monospace"
											font.pixelSize: Theme.fontBody
											opacity: 0.85
											color: Theme.glassTextPrimary
										}
									}
								}
							}
						}
					}
				}

				// A click anywhere else closes the duration menu.
				MouseArea {
					anchors.fill: parent
					visible: root.menu !== null
					onClicked: root.menu = null
				}

				// The durations for one stage, at the button that opened it.
				Rectangle {
					id: menuCard

					visible: root.menu !== null
					x: Math.min(root.menu?.x ?? 0, body.width - width - 8)
					y: Math.min(root.menu?.y ?? 0, body.height - height - 8)
					width: 140
					height: menuColumn.implicitHeight + 12
					radius: 14
					color: Theme.menuSurface
					border.width: 1
					border.color: Theme.glassControlBorder

					Column {
						id: menuColumn

						anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
						spacing: 1

						Repeater {
							model: {
								if (root.menu === null)
									return [];
								const now = Settings.idleAfter(root.menu.stage, root.menu.battery);
								const list = root.durations.includes(now) ? root.durations
									: root.durations.concat([now]).sort((a, b) => (a || Infinity) - (b || Infinity));
								return list;
							}

							Rectangle {
								id: option

								required property int modelData
								readonly property bool current: root.menu !== null
									&& Settings.idleAfter(root.menu.stage, root.menu.battery) === modelData
								readonly property bool allowed: root.menu !== null
									&& root.fits(root.menu.stage, root.menu.battery, modelData)

								width: parent.width
								height: 30
								radius: 8
								color: option.current ? Qt.rgba(1, 1, 1, 0.16)
									: optionMouse.containsMouse && option.allowed ? Theme.glassControlHover : "transparent"

								Text {
									anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
									text: root.duration(option.modelData)
									font.pixelSize: Theme.fontBody
									font.bold: true
									opacity: option.allowed ? 1 : 0.4
									color: Theme.glassTextPrimary
								}

								MouseArea {
									id: optionMouse

									anchors.fill: parent
									hoverEnabled: true
									enabled: option.allowed
									cursorShape: Qt.PointingHandCursor
									onClicked: root.chooseDuration(option.modelData)
								}
							}
						}
					}
				}

				// Add Layout: the design's A3, dense over the window.
				GlassDialog {
					id: layoutSheet

					anchors.fill: parent
					dense: true
					open: root.sheet === "layouts"
					visible: open || sheet.opacity > 0.01
					sheetWidth: Math.min(Theme.dialogWidthWide, parent.width - 40)

					Item {
						width: parent.width
						height: 36

						Text {
							anchors { left: parent.left; verticalCenter: parent.verticalCenter }
							text: "Add Layout"
							font.pixelSize: Theme.fontHeading
							font.bold: true
							color: Theme.glassTextPrimary
						}

						DiscButton {
							anchors { right: parent.right; verticalCenter: parent.verticalCenter }
							onClicked: root.openSheet("")
						}
					}

					GlassField {
						id: layoutSearch

						width: parent.width
						height: 38
						fontSize: Theme.fontTitle
						placeholder: "Search layouts"

						leading: Lens {
							width: 26
							height: 26
							sheen: false

							FileGlyph { anchors.centerIn: parent; kind: "search" }
						}

						onAccepted: root.addLayout(root.layoutCurrent)
					}

					ListView {
						id: layoutList

						width: parent.width
						height: Theme.dialogListHeight
						clip: true
						spacing: 2
						boundsBehavior: Flickable.StopAtBounds
						model: root.layoutMatches
						currentIndex: root.layoutPicked
						highlightFollowsCurrentItem: false
						onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

						delegate: Rectangle {
							id: choice

							required property var modelData
							required property int index
							readonly property bool picked: index === root.layoutPicked

							width: layoutList.width
							height: Theme.launcherRowHeight
							radius: Theme.radiusRow
							color: choice.picked ? Theme.glassChipActive
								: choiceMouse.containsMouse ? Theme.glassControlHover : "transparent"
							border.width: choice.picked ? 1 : 0
							border.color: Theme.glassChipSelectedBorder

							CodeBadge {
								id: choiceCode

								anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
								code: choice.modelData.layout
							}

							Text {
								anchors { left: choiceCode.right; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
								elide: Text.ElideRight
								text: choice.modelData.name
								font.pixelSize: Theme.fontTitle
								font.bold: true
								color: Theme.glassTextPrimary
							}

							MouseArea {
								id: choiceMouse

								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.layoutPicked = choice.index
								onDoubleClicked: root.addLayout(choice.modelData)
							}
						}

						Text {
							anchors.centerIn: parent
							visible: root.layoutMatches.length === 0
							text: "No layout matches. Clear the search to see all."
							font.pixelSize: Theme.fontBody
							opacity: 0.75
							color: Theme.glassTextPrimary
						}
					}

					Item {
						width: parent.width
						height: Theme.chipHeight

						DialogButton {
							anchors.right: parent.right
							width: Math.min(implicitWidth, parent.width)
							variant: "primary"
							text: root.layoutCurrent ? `Add ${root.layoutCurrent.name}` : "Add"
							opacity: root.layoutCurrent ? 1 : 0.5
							onClicked: root.addLayout(root.layoutCurrent)
						}
					}
				}

				// Choose Picture: the pictures folder, newest first.
				GlassDialog {
					id: pictureSheet

					anchors.fill: parent
					dense: true
					open: root.sheet === "pictures"
					visible: open || sheet.opacity > 0.01
					sheetWidth: Math.min(620, parent.width - 40)

					Item {
						width: parent.width
						height: 36

						Column {
							anchors { left: parent.left; verticalCenter: parent.verticalCenter }
							spacing: 2

							Text {
								text: "Choose Picture"
								font.pixelSize: Theme.fontHeading
								font.bold: true
								color: Theme.glassTextPrimary
							}

							Text {
								text: root.picturesDir.replace(Quickshell.env("HOME"), "~")
								font.pixelSize: Theme.fontCaption
								opacity: 0.75
								color: Theme.glassTextPrimary
							}
						}

						DiscButton {
							anchors { right: parent.right; verticalCenter: parent.verticalCenter }
							onClicked: root.openSheet("")
						}
					}

					GridView {
						id: pictureGrid

						width: parent.width
						height: Theme.dialogListHeight
						clip: true
						cellWidth: Math.floor(width / 4)
						cellHeight: Math.round(cellWidth * 0.72)
						boundsBehavior: Flickable.StopAtBounds
						model: root.pictures

						delegate: Item {
							id: cell

							required property string modelData
							required property int index
							readonly property bool picked: index === root.picturePicked

							width: pictureGrid.cellWidth
							height: pictureGrid.cellHeight

							Rectangle {
								anchors.fill: parent
								anchors.margins: 4
								radius: 12
								color: cell.picked ? Theme.glassChipActive
									: cellMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: cell.picked ? 1 : 0
								border.color: Theme.glassChipSelectedBorder

								Rectangle {
									anchors.fill: parent
									anchors.margins: 4
									radius: 9
									color: Qt.rgba(0, 0, 0, 0.2)
									clip: true

									Image {
										anchors.fill: parent
										source: "file://" + cell.modelData
										sourceSize.width: 320
										fillMode: Image.PreserveAspectCrop
										asynchronous: true
									}
								}
							}

							MouseArea {
								id: cellMouse

								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.picturePicked = cell.index
								onDoubleClicked: { Settings.setWallpaper(cell.modelData); root.openSheet(""); }
							}
						}

						Text {
							anchors.centerIn: parent
							width: parent.width - 40
							horizontalAlignment: Text.AlignHCenter
							wrapMode: Text.WordWrap
							visible: root.picturesLoaded && root.pictures.length === 0
							text: "No pictures here yet. JPEG, PNG and WebP files in this folder show up here."
							font.pixelSize: Theme.fontBody
							opacity: 0.75
							color: Theme.glassTextPrimary
						}
					}

					Item {
						width: parent.width
						height: Theme.chipHeight

						DialogButton {
							readonly property string path: root.pictures[root.picturePicked] ?? ""

							anchors.right: parent.right
							width: Math.min(implicitWidth, parent.width)
							variant: "primary"
							text: path !== "" ? `Use ${root.fileName(path)}` : "Use"
							opacity: path !== "" ? 1 : 0.5
							onClicked: {
								if (path === "")
									return;
								Settings.setWallpaper(path);
								root.openSheet("");
							}
						}
					}
				}

				// Keep This Scale, or Refresh Rate: a question, so no header
				// mark, and the footer answers it. Escape is Cancel and Enter
				// is Keep.
				GlassDialog {
					anchors.fill: parent
					dense: true
					open: HyprConfig.preview !== null
					visible: open || sheet.opacity > 0.01
					sheetWidth: Theme.dialogWidthPrompt
					readonly property var trying: HyprConfig.preview
					readonly property bool rate: trying?.kind === "mode"

					title: rate ? "Keep This Refresh Rate?" : "Keep This Scale?"
					body: HyprConfig.preview === null ? ""
						: `Going back to ${rate ? root.rateLabel(trying.previous.mode, trying.previous.rate) : root.scaleLabel(trying.previous.scale)} in ${HyprConfig.previewLeft} seconds.`

					Rectangle {
						width: parent.width
						height: 6
						radius: 3
						color: Theme.glassTrack

						Rectangle {
							width: parent.width * HyprConfig.previewLeft / HyprConfig.previewSeconds
							height: parent.height
							radius: 3
							color: Theme.glassTrackFill

							Behavior on width { NumberAnimation { duration: 1000 } }
						}
					}

					Row {
						anchors.right: parent.right
						spacing: Theme.spacingS

						DialogButton {
							text: "Cancel"
							onClicked: HyprConfig.revertDisplay()
						}

						DialogButton {
							variant: "primary"
							text: HyprConfig.preview === null ? "Keep"
								: `Keep ${HyprConfig.preview.kind === "mode" ? root.rateLabel(HyprConfig.preview.mode) : root.scaleLabel(HyprConfig.preview.scale)}`
							onClicked: HyprConfig.keepDisplay()
						}
					}
				}
			}
		}
	}
}
