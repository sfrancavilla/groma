import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"
import "snapshots.js" as Snapshots

// Snapshots: what snapper has kept, for the system and for /home.
//
// System snapshots come in pairs around each pacman run; the list shows the
// pair as one change - "System update", "Installing gradle" - with how many
// files it touched. Undo puts those files back as they were before it, in a
// terminal, because it needs root and says what it is doing.
//
// Home snapshots are the timeline: hourly, daily, weekly. Browse opens one
// in Files, read-only, and a lost file is copied back from there - no
// password, because snapper lets this user read them (ALLOW_USERS,
// SYNC_ACL in the config).
//
// Booting a snapshot is the boot menu's job; the note at the bottom says so,
// rather than pretending the shell can do it.
Scope {
	id: root

	property bool open: false
	// "root" | "home"
	property string config: "root"

	property var snapshots: []
	property int picked: 0
	property bool loading: false

	// The changed files for the picked system pair: { key, count, sample }.
	property var changes: null

	function show(which) {
		if (which === "root" || which === "home")
			root.config = which;
		root.open = true;
		root.refresh();
	}

	function refresh() {
		root.loading = true;
		lister.command = ["snapper", "--jsonout", "-c", root.config, "list"];
		lister.running = false;
		lister.running = true;
	}

	onConfigChanged: {
		root.picked = 0;
		root.changes = null;
		if (root.open)
			root.refresh();
	}

	Process {
		id: lister

		stdout: StdioCollector {
			onStreamFinished: {
				root.loading = false;
				let list = [];
				try {
					list = JSON.parse(text)[root.config] ?? [];
				} catch (err) {
					root.snapshots = [];
					return;
				}
				root.snapshots = root.config === "root" ? root.pairs(list) : root.singles(list);
				root.picked = 0;
				root.loadChanges();
			}
		}
	}

	// pre and post as one row, newest first. A pre whose post never came
	// (a pacman run that failed) still shows, on its own.
	function pairs(list) {
		const rows = [];
		for (const s of list) {
			if (s.number === 0 || s.type === "post")
				continue;
			if (s.type === "pre") {
				const post = list.find(p => p.type === "post" && p["pre-number"] === s.number);
				const after = post ? Snapshots.phrase("post", post.description ?? "") : "";
				rows.push({ pre: s.number, post: post ? post.number : 0, date: s.date,
					title: Snapshots.title(s.description ?? ""), detail: after });
			} else {
				rows.push({ pre: s.number, post: 0, date: s.date,
					title: s.description || "Snapshot", detail: "Taken by hand" });
			}
		}
		return rows.reverse();
	}

	function singles(list) {
		return list.filter(s => s.number !== 0).map(s => ({
			pre: s.number, post: 0, date: s.date,
			title: s.description || (s.cleanup === "timeline" ? "Hourly snapshot" : "Snapshot"),
			detail: s.cleanup === "timeline" ? "Timeline" : "Taken by hand"
		})).reverse();
	}

	readonly property var current: root.snapshots.length > 0 ? root.snapshots[Math.min(root.picked, root.snapshots.length - 1)] : null

	onPickedChanged: root.loadChanges()

	function loadChanges() {
		root.changes = null;
		const c = root.current;
		if (c === null || root.config !== "root" || c.post === 0)
			return;
		statusProbe.key = `${c.pre}..${c.post}`;
		statusProbe.command = ["snapper", "-c", "root", "status", statusProbe.key];
		statusProbe.running = false;
		statusProbe.running = true;
	}

	Process {
		id: statusProbe

		property string key: ""

		stdout: StdioCollector {
			onStreamFinished: {
				const lines = text.split("\n").filter(l => l.trim() !== "");
				root.changes = { key: statusProbe.key, count: lines.length,
					sample: lines.slice(0, 3).map(l => l.slice(7)) };
			}
		}
	}

	function move(delta) {
		if (root.snapshots.length === 0)
			return;
		root.picked = Math.max(0, Math.min(root.snapshots.length - 1, root.picked + delta));
	}

	function ago(date) {
		const then = new Date(date.replace(" ", "T"));
		const minutes = Math.round((Date.now() - then.getTime()) / 60000);
		if (minutes < 1)
			return "just now";
		if (minutes < 60)
			return minutes + " min ago";
		const hours = Math.round(minutes / 60);
		if (hours < 24)
			return hours + " h ago";
		return Qt.formatDateTime(then, "d MMM, hh:mm");
	}

	// --- doing ------------------------------------------------------------------

	function act() {
		const c = root.current;
		if (c === null)
			return;
		if (root.config === "home")
			root.browse(c);
		else if (c.post !== 0)
			root.undo(c);
	}

	// Files, at this user's folder inside the snapshot.
	function browse(c) {
		root.open = false;
		const home = Quickshell.env("HOME");
		const inside = home.startsWith("/home/") ? home.slice("/home".length) : "";
		Quickshell.execDetached(["qs", "-c", "groma", "ipc", "call", "files", "open",
			`/home/.snapshots/${c.pre}/snapshot${inside}`]);
	}

	function undo(c) {
		root.open = false;
		Quickshell.execDetached(["foot", "--app-id=groma-snapshot-undo", "--title=Undo a Change", "--",
			"bash", "-c",
			'echo "Undoing \\"$1\\": every file it changed goes back to how it was before it ($2)."; '
			+ 'echo "Packages are left as pacman knows them - run a system update afterwards if this was one."; echo; '
			+ 'sudo snapper -c root status "$2"; echo; read -rp "Undo these changes? [y/N] " a; '
			+ '[ "${a,,}" = y ] && sudo snapper -c root undochange "$2"; echo; read -rp "Press Enter to close."',
			"sh", c.title, `${c.pre}..${c.post}`]);
	}

	function snapshotNow() {
		snapper.command = ["snapper", "-c", root.config, "create", "--description", "Taken from Groma", "--cleanup-algorithm", "number"];
		snapper.running = true;
	}

	Process {
		id: snapper

		onExited: root.refresh()
	}

	IpcHandler {
		target: "snapshots"

		function opened(): void { root.show(""); }
		function closed(): void { root.open = false; }
		function toggle(): void { if (root.open) root.open = false; else root.show(""); }
		// "root" or "home".
		function view(which: string): void { root.show(which); }
		function pick(index: int): void { root.picked = index; }
	}

	// --- the sheet ----------------------------------------------------------------

	PanelWindow {
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
		WlrLayershell.namespace: "groma:snapshots"
		WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: dialog.sheet
			radius: Theme.radiusPanel
		}

		onVisibleChanged: if (visible) keys.forceActiveFocus()

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			sheetWidth: Theme.dialogWidthWide + 60

			Item {
				id: keys

				width: parent.width
				height: 36
				focus: true

				Keys.onPressed: event => {
					if (event.key === Qt.Key_Escape)
						root.open = false;
					else if (event.key === Qt.Key_Down)
						root.move(1);
					else if (event.key === Qt.Key_Up)
						root.move(-1);
					else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
						root.config = root.config === "root" ? "home" : "root";
					else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
						root.act();
					else
						return;
					event.accepted = true;
				}

				Text {
					anchors.verticalCenter: parent.verticalCenter
					text: "Snapshots"
					font.pixelSize: Theme.fontHeading
					font.bold: true
					color: Theme.glassTextPrimary
				}

				Row {
					anchors.right: closeDisc.left
					anchors.rightMargin: Theme.spacingM
					anchors.verticalCenter: parent.verticalCenter
					spacing: 6

					Repeater {
						model: [["root", "System"], ["home", "Home"]]

						Chip {
							required property var modelData

							text: modelData[1]
							active: root.config === modelData[0]
							onClicked: root.config = modelData[0]
						}
					}
				}

				DiscButton {
					id: closeDisc

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					onClicked: root.open = false
				}
			}

			ListView {
				id: list

				width: parent.width
				height: Theme.dialogListHeight
				clip: true
				spacing: 4
				model: root.snapshots
				currentIndex: root.picked
				highlightFollowsCurrentItem: false
				boundsBehavior: Flickable.StopAtBounds
				onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

				delegate: Rectangle {
					id: row

					required property var modelData
					required property int index

					readonly property bool chosen: root.picked === index

					width: list.width
					height: 52
					radius: Theme.radiusRow
					color: chosen ? Theme.glassChipActive : rowMouse.containsMouse ? Theme.glassControlHover : "transparent"
					border.width: chosen ? 1 : 0
					border.color: Theme.glassTrackBorderFocus

					Row {
						anchors { left: parent.left; right: when.left; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
						spacing: 12

						Lens {
							id: disc

							anchors.verticalCenter: parent.verticalCenter
							width: 30
							height: 30
							sheen: false

							PowerIcon {
								anchors.centerIn: parent
								visible: root.config === "root"
								width: 14
								height: 14
								stroke: 1.6
								kind: "restart"
								color: Theme.fileInk
							}

							FileGlyph {
								anchors.centerIn: parent
								visible: root.config === "home"
								kind: "home"
							}
						}

						Column {
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width - disc.width - 12
							spacing: 2

							Text {
								width: parent.width
								elide: Text.ElideRight
								text: row.modelData.title
								font.pixelSize: Theme.fontLead
								font.weight: row.chosen ? Font.Bold : Font.DemiBold
								color: Theme.glassTextPrimary
							}

							Text {
								width: parent.width
								elide: Text.ElideRight
								text: `#${row.modelData.pre}` + (row.modelData.post ? ` → #${row.modelData.post}` : "")
									+ (row.modelData.detail ? " · " + row.modelData.detail : "")
								font.pixelSize: Theme.fontBody
								opacity: 0.7
								color: Theme.glassTextPrimary
							}
						}
					}

					Text {
						id: when

						anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
						text: root.ago(row.modelData.date)
						font.pixelSize: Theme.fontBody
						font.weight: Font.DemiBold
						opacity: 0.6
						color: Theme.glassTextPrimary
					}

					MouseArea {
						id: rowMouse

						anchors.fill: parent
						hoverEnabled: true
						onClicked: root.picked = row.index
						onDoubleClicked: { root.picked = row.index; root.act(); }
					}
				}

				Text {
					anchors.centerIn: parent
					visible: root.snapshots.length === 0
					text: root.loading ? "Reading snapshots…" : "No snapshots yet"
					font.pixelSize: Theme.fontTitle
					font.weight: Font.DemiBold
					opacity: 0.6
					color: Theme.glassTextPrimary
				}
			}

			// What the picked row is about: for a system change, what it
			// touched; for home, where Browse goes.
			Text {
				width: parent.width
				wrapMode: Text.WordWrap
				maximumLineCount: 3
				elide: Text.ElideRight
				font.pixelSize: Theme.fontBody
				lineHeight: 1.35
				opacity: 0.8
				color: Theme.glassTextPrimary
				text: {
					const c = root.current;
					if (c === null)
						return "";
					if (root.config === "home")
						return `Browse opens snapshot #${c.pre} in Files, read-only. Copy a file out of it to get it back.`;
					if (c.post === 0)
						return "A single snapshot, not a change: boot it from the Snapshots menu in Limine.";
					const ch = root.changes;
					if (ch === null)
						return "Counting the files this change touched…";
					return `${ch.count} ${ch.count === 1 ? "file" : "files"} changed`
						+ (ch.sample.length ? ": " + ch.sample.join(", ") + (ch.count > ch.sample.length ? " and more" : "") : "")
						+ ". To boot the system as it was, pick it in Limine’s Snapshots menu.";
				}
			}

			Item {
				width: parent.width
				height: Theme.chipHeight

				DialogButton {
					anchors.left: parent.left
					text: "Snapshot now"
					onClicked: root.snapshotNow()
				}

				DialogButton {
					anchors.right: parent.right
					readonly property bool home: root.config === "home"
					text: home ? "Browse" : "Undo…"
					variant: home ? "primary" : "destructive"
					enabled: root.current !== null && (home || root.current.post !== 0)
					onClicked: root.act()
				}
			}
		}
	}
}
