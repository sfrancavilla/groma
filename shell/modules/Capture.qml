import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import ".."
import "../ui"

// Screenshots and screen recordings.
//
// Print freezes every screen - grim takes a frame of each before anything is
// drawn - and lays the overlay over the frozen frames: drag out an area, point
// at a window, or click a screen. A picture is cut from the frozen frame, not
// taken again, so what is captured is what was chosen, even if a tooltip or a
// clock has moved since. A recording is of the live screen, so in Video the
// frozen frame steps aside and the dim lies over the real one.
//
// Either way the result is saved - Pictures/Screenshots, Videos/Screen
// Recordings - and a picture is copied as well. A card in the corner holds it
// for a few seconds: click to annotate it in Satty (or play a recording),
// drag it into another window, right-click for its folder.
//
// The recorder runs outside the shell, in capture-record.sh, so a reload does
// not end a recording; the shell reads the state it leaves behind.
Scope {
	id: root

	// Where Files can be asked to show a capture's folder.
	property var files: null

	// --- the overlay -----------------------------------------------------------

	property bool open: false
	// grim is taking the frames; the overlay comes up when it is done.
	property bool freezing: false
	// "area" | "window" | "screen"
	property string mode: "area"
	property bool video: false

	// Each output's frozen frame, by output name.
	property var frozen: ({})
	// What was on the screens when they froze, topmost first, in global
	// logical coordinates: { x, y, width, height, title }.
	property var windows: []

	// The area being drawn or drawn: { screen, x, y, width, height }, local to
	// that screen, logical. In Video it stays after the drag to be adjusted.
	property var area: null
	// The window pointed at, or picked with Tab: an element of `windows`.
	property var picked: null
	// The screen the pointer is on, by name - Screen mode's choice - and
	// where on the whole layout it is.
	property string pointerScreen: ""
	property point cursor: Qt.point(0, 0)

	// Each grim run gets its own file names: Image caches by URL.
	property string stamp: ""

	property string picturesDir: ""
	property string videosDir: ""
	readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") + "/groma-capture"
	readonly property string stateFile: root.runDir + "/recording"

	readonly property bool hasTarget: root.mode === "screen"
		|| (root.mode === "window" && root.picked !== null)
		|| (root.mode === "area" && root.area !== null && root.area.width >= 4 && root.area.height >= 4)

	function show(asVideo) {
		// Print again while recording is the way to stop.
		if (root.recording !== null) {
			root.stop();
			return;
		}
		if (root.open || root.freezing)
			return;

		root.video = asVideo;
		root.mode = root.mode === "window" ? "window" : (asVideo ? "screen" : "area");
		root.picked = null;
		root.stamp = String(Date.now());
		root.freezing = true;
		freezer.command = ["sh", "-c", freezer.script, "sh", root.runDir, root.stamp,
			...Quickshell.screens.map(s => s.name)];
		freezer.running = true;
	}

	function close() {
		// The frames are the screen's full size in memory-backed /run;
		// whatever was cut from them has been cut by now.
		if (root.open)
			Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/frozen-*.ppm', "sh", root.runDir]);
		root.open = false;
		root.freezing = false;
		root.picked = null;
		// An area drawn for a recording is remembered, for the next take.
		if (!root.video)
			root.area = null;
	}

	function setMode(mode) {
		root.mode = mode;
		root.picked = mode === "window" ? root.windowAt(root.cursor.x, root.cursor.y) : null;
	}

	// The window under a global point: the first in stacking order that
	// holds it.
	function windowAt(gx, gy) {
		return root.windows.find(w => gx >= w.x && gx < w.x + w.width
			&& gy >= w.y && gy < w.y + w.height) ?? null;
	}

	// Tab and Shift+Tab walk the windows on a screen.
	function cycle(screen, step) {
		const here = root.windows.filter(w => root.onScreen(w, screen));
		if (here.length === 0)
			return;
		root.setMode("window");
		const at = here.indexOf(root.picked);
		root.picked = here[((at < 0 ? (step > 0 ? -1 : 0) : at) + step + here.length) % here.length];
	}

	function onScreen(w, screen) {
		const cx = w.x + w.width / 2;
		const cy = w.y + w.height / 2;
		return cx >= screen.x && cx < screen.x + screen.width
			&& cy >= screen.y && cy < screen.y + screen.height;
	}

	// What a capture of a given screen covers, local and logical, or null.
	function targetOn(screen) {
		if (root.mode === "screen")
			return root.pointerScreen === screen.name ? Qt.rect(0, 0, screen.width, screen.height) : null;
		if (root.mode === "window" && root.picked !== null && root.onScreen(root.picked, screen)) {
			const p = root.picked;
			const x = Math.max(p.x, screen.x);
			const y = Math.max(p.y, screen.y);
			const right = Math.min(p.x + p.width, screen.x + screen.width);
			const bottom = Math.min(p.y + p.height, screen.y + screen.height);
			return Qt.rect(x - screen.x, y - screen.y, right - x, bottom - y);
		}
		if (root.mode === "area" && root.area !== null && root.area.screen === screen.name)
			return Qt.rect(root.area.x, root.area.y, root.area.width, root.area.height);
		return null;
	}

	// Enter, the toolbar's button, a click: capture whatever is chosen, on
	// whichever screen it is.
	function take() {
		for (const overlay of overlays.instances) {
			const rect = root.targetOn(overlay.modelData);
			if (rect !== null && rect.width >= 1 && rect.height >= 1) {
				overlay.capture(rect);
				return;
			}
		}
	}

	// "Screenshot 2026-10-28 at 15.04.12", as the files are named.
	function named(what) {
		return what + " " + Qt.formatDateTime(new Date(), "yyyy-MM-dd 'at' HH.mm.ss");
	}

	// Frames first, then the windows and which workspaces are showing, all in
	// one go so they describe the same moment. PPM rather than PNG: a frame
	// is read once, a moment later, and PNG's compression is most of grim's
	// time at this resolution.
	Process {
		id: freezer

		readonly property string script: 'dir=$1; stamp=$2; shift 2; mkdir -p "$dir"; '
			+ 'rm -f "$dir"/frozen-*.ppm "$dir"/poster-*.png; '
			+ 'for o; do grim -t ppm -o "$o" "$dir/frozen-$o-$stamp.ppm" & done; wait; '
			+ "hyprctl -j clients; printf '\\036'; hyprctl -j monitors; printf '\\036'; hyprctl -j cursorpos"

		stdout: StdioCollector {
			onStreamFinished: {
				if (!root.freezing)
					return;
				const parts = text.split("\x1e");
				let clients = [];
				let monitors = [];
				let cursor = { x: 0, y: 0 };
				try {
					clients = JSON.parse(parts[0]);
					monitors = JSON.parse(parts[1]);
					cursor = JSON.parse(parts[2]);
				} catch (e) {
					console.warn("capture: could not read the windows:", e);
				}

				const showing = new Set();
				for (const m of monitors) {
					showing.add(m.activeWorkspace?.id);
					if ((m.specialWorkspace?.id ?? 0) !== 0)
						showing.add(m.specialWorkspace.id);
				}

				// Hyprland draws fullscreen over floating over tiled, and
				// within each the most recently focused on top.
				root.windows = clients
					.filter(c => c.mapped && !c.hidden && showing.has(c.workspace?.id))
					.sort((a, b) => (b.fullscreen > 0) - (a.fullscreen > 0)
						|| b.floating - a.floating
						|| a.focusHistoryID - b.focusHistoryID)
					.map(c => ({ x: c.at[0], y: c.at[1], width: c.size[0], height: c.size[1],
						title: c.title !== "" ? c.title : c.class }));

				const frames = {};
				for (const s of Quickshell.screens)
					frames[s.name] = "file://" + root.runDir + "/frozen-" + s.name + "-" + root.stamp + ".ppm";
				root.frozen = frames;

				// Until the pointer moves, it has chosen what it is resting on.
				const under = Quickshell.screens.find(s => cursor.x >= s.x && cursor.x < s.x + s.width
					&& cursor.y >= s.y && cursor.y < s.y + s.height);
				root.pointerScreen = under?.name ?? Hyprland.focusedMonitor?.name ?? "";
				root.cursor = Qt.point(cursor.x, cursor.y);
				if (root.mode === "window")
					root.picked = root.windowAt(cursor.x, cursor.y);

				root.freezing = false;
				root.open = true;
			}
		}
	}

	// Pictures and Videos, from user-dirs.dirs, as Settings finds Pictures.
	Process {
		running: true
		command: ["sh", "-c",
			"f=\"${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs\"; [ -f \"$f\" ] && . \"$f\"; "
			+ "echo \"${XDG_PICTURES_DIR:-$HOME/Pictures}\"; echo \"${XDG_VIDEOS_DIR:-$HOME/Videos}\""]

		stdout: StdioCollector {
			onStreamFinished: {
				const lines = text.split("\n");
				root.picturesDir = lines[0] ?? "";
				root.videosDir = lines[1] ?? "";
			}
		}
	}

	// --- after a capture ---------------------------------------------------------

	// The card in the corner: { file, poster, video }.
	property var last: null

	function saved(file, poster, isVideo) {
		root.last = { file: file, poster: poster, video: isVideo };
		if (!isVideo)
			Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "sh", file]);
	}

	// A picture of a whole screen, straight away: Shift+Print.
	function screenNow() {
		if (root.recording !== null || root.open || root.freezing)
			return;
		const output = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
		const file = root.picturesDir + "/Screenshots/" + root.named("Screenshot") + ".png";
		direct.file = file;
		direct.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && grim -o "$1" "$2"', "sh", output, file];
		direct.running = true;
	}

	Process {
		id: direct

		property string file: ""

		onExited: code => {
			if (code === 0)
				root.saved(direct.file, direct.file, false);
		}
	}

	function edit() {
		const last = root.last;
		root.last = null;
		if (last === null)
			return;
		if (last.video) {
			Quickshell.execDetached(["xdg-open", last.file]);
			return;
		}
		// Satty saves over the original and copies the result on Enter; the
		// copy already on the clipboard is the unannotated one until then.
		Quickshell.execDetached(["sh", "-c",
			'if command -v satty >/dev/null; then '
			+ 'exec satty --filename "$1" --output-filename "$1" --copy-command wl-copy '
			+ '--actions-on-enter save-to-clipboard,save-to-file --early-exit; '
			+ 'else exec xdg-open "$1"; fi', "sh", last.file]);
	}

	function reveal() {
		const last = root.last;
		root.last = null;
		if (last !== null && root.files !== null)
			root.files.show(last.file.substring(0, last.file.lastIndexOf("/")));
	}

	// --- recording ---------------------------------------------------------------

	// { pid, started, file, poster } while the recorder runs.
	property var recording: null
	// Asked to start, and the recorder has not said yet.
	property bool starting: false
	// Asked to stop: SIGINT sent, the file being finished.
	property bool stopping: false
	property real now: Date.now()

	readonly property string elapsed: {
		if (root.recording === null)
			return "";
		const s = Math.max(0, Math.floor(root.now / 1000 - root.recording.started));
		const m = Math.floor(s / 60);
		return m + ":" + String(s % 60).padStart(2, "0");
	}

	function startRecording(output, region, poster) {
		const file = root.videosDir + "/Screen Recordings/" + root.named("Screen Recording") + ".mp4";
		const args = ["-f", "60", "-c", "mp4", "-cursor", "yes"];
		if (region === null)
			args.unshift("-w", output);
		else
			args.unshift("-w", "region", "-region", region);
		const sources = [];
		if (Settings.recordSound)
			sources.push("default_output");
		if (Settings.recordMicrophone)
			sources.push("default_input");
		if (sources.length > 0)
			args.push("-a", sources.join("|"));

		root.starting = true;
		Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$2")" && exec setsid "$0" "$@"',
			Quickshell.shellDir + "/modules/capture-record.sh", root.stateFile, file, poster, ...args]);
	}

	function stop() {
		if (root.recording === null || root.stopping)
			return;
		root.stopping = true;
		Quickshell.execDetached(["kill", "-INT", String(root.recording.pid)]);
	}

	// Once a second while anything is recording, and once at start, in case
	// the shell was reloaded in the middle of one.
	Timer {
		interval: 1000
		repeat: true
		triggeredOnStart: true
		running: root.starting || root.stopping || root.recording !== null
		onTriggered: {
			root.now = Date.now();
			if (!watcher.running)
				watcher.running = true;
		}
	}

	Component.onCompleted: watcher.running = true

	Process {
		id: watcher

		command: ["sh", "-c",
			's=$1; cat "$s" 2>/dev/null; printf "\\036"; '
			+ 'if [ -f "$s.done" ]; then cat "$s.done"; printf "\\036"; tail -c 600 "$s.log" 2>/dev/null; rm -f "$s.done"; fi',
			"sh", root.stateFile]

		stdout: StdioCollector {
			onStreamFinished: {
				const parts = text.split("\x1e");
				const state = (parts[0] ?? "").split("\n");
				const done = (parts[1] ?? "").split("\n");

				if (state.length >= 3 && state[0] !== "") {
					root.recording = { pid: Number(state[0]), started: Number(state[1]),
						file: state[2], poster: state[3] ?? "" };
					root.starting = false;
				} else if (root.recording !== null || done[0] !== "") {
					root.recording = null;
				}

				if (done.length >= 2 && done[0] !== "") {
					root.starting = false;
					root.stopping = false;
					// 0 for a clean stop; the recorder's own SIGINT path
					// exits with it as well.
					if (done[0] === "0" || done[0] === "130")
						root.saved(done[1], done[2] ?? "", true);
					else
						Quickshell.execDetached(["notify-send", "--app-name=Groma", "--urgency=critical",
							"The recording could not start",
							(parts[2] ?? "").trim().split("\n").slice(-3).join("\n")]);
				}
			}
		}
	}

	// --- the overlay, one per screen --------------------------------------------

	Variants {
		id: overlays

		model: Quickshell.screens

		PanelWindow {
			id: overlay

			required property var modelData
			readonly property string name: overlay.modelData.name
			readonly property bool focused: (Hyprland.focusedMonitor?.name ?? "") === overlay.name
			readonly property rect target: root.targetOn(overlay.modelData) ?? Qt.rect(0, 0, 0, 0)
			readonly property bool hasTarget: root.targetOn(overlay.modelData) !== null
			// Physical pixels to a logical one: the frame is the panel's own size.
			readonly property real ratio: shot.implicitWidth > 0 ? shot.implicitWidth / overlay.width : 1

			screen: overlay.modelData
			visible: root.open

			anchors {
				top: true
				left: true
				right: true
				bottom: true
			}

			exclusionMode: ExclusionMode.Ignore
			color: "transparent"

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "groma:capture"
			WlrLayershell.keyboardFocus: overlay.focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

			// Cut the chosen rectangle from the frozen frame and save it; or,
			// in Video, keep the cut as the recording's poster and start.
			function capture(rect) {
				const r = Qt.rect(Math.round(rect.x * overlay.ratio), Math.round(rect.y * overlay.ratio),
					Math.round(rect.width * overlay.ratio), Math.round(rect.height * overlay.ratio));
				cutter.sourceClipRect = r;
				cutter.width = rect.width;
				cutter.height = rect.height;
				const isVideo = root.video;
				const file = isVideo
					? root.runDir + "/poster-" + root.stamp + ".png"
					: root.picturesDir + "/Screenshots/" + root.named("Screenshot") + ".png";
				// For the recorder: the region in the compositor's layout, in
				// logical units, as slurp would print it. The whole screen is
				// the output by name.
				const whole = rect.width >= overlay.width && rect.height >= overlay.height;
				const region = whole ? null
					: Math.round(rect.width) + "x" + Math.round(rect.height)
						+ "+" + Math.round(overlay.modelData.x + rect.x) + "+" + Math.round(overlay.modelData.y + rect.y);

				// The size asked for is in logical units: the grab is made at
				// the window's pixel ratio, which is the frame's own.
				cutter.grabToImage(result => {
					root.close();
					mkdir.after = () => {
						if (!result.saveToFile(file)) {
							console.warn("capture: could not save", file);
							return;
						}
						if (isVideo)
							root.startRecording(overlay.name, region, file);
						else
							root.saved(file, file, false);
					};
					mkdir.command = ["mkdir", "-p", file.substring(0, file.lastIndexOf("/"))];
					mkdir.running = true;
				}, Qt.size(rect.width, rect.height));
			}

			Process {
				id: mkdir

				property var after: null

				onExited: code => {
					if (code === 0 && mkdir.after !== null)
						mkdir.after();
					mkdir.after = null;
				}
			}

			// The cut, laid out beyond the screen's edge so it is never seen;
			// grabToImage renders it all the same.
			Image {
				id: cutter

				x: overlay.width + 16
				source: root.frozen[overlay.name] ?? ""
				cache: false
				smooth: false
			}

			// The frozen frame. In Video it steps aside for the live screen.
			Image {
				id: shot

				anchors.fill: parent
				source: root.frozen[overlay.name] ?? ""
				cache: false
				visible: !root.video
				smooth: true
			}

			// The dim, in four pieces round whatever is chosen.
			Item {
				anchors.fill: parent

				readonly property rect t: overlay.target
				readonly property bool cut: overlay.hasTarget

				Rectangle {
					x: 0; y: 0
					width: parent.width
					height: parent.cut ? parent.t.y : parent.height
					color: Theme.captureScrim
				}
				Rectangle {
					visible: parent.cut
					x: 0; y: parent.t.y + parent.t.height
					width: parent.width
					height: parent.height - y
					color: Theme.captureScrim
				}
				Rectangle {
					visible: parent.cut
					x: 0; y: parent.t.y
					width: parent.t.x
					height: parent.t.height
					color: Theme.captureScrim
				}
				Rectangle {
					visible: parent.cut
					x: parent.t.x + parent.t.width; y: parent.t.y
					width: parent.width - x
					height: parent.t.height
					color: Theme.captureScrim
				}
			}

			MouseArea {
				id: pointer

				anchors.fill: parent
				hoverEnabled: true
				cursorShape: root.mode === "area" ? Qt.CrossCursor : Qt.PointingHandCursor

				// "draw" | "move" | "resize", and where it began.
				property string action: ""
				property point from
				property var startArea: null
				// Which edges a resize moves: { l, t, r, b }.
				property var edges: null

				function updateHover(mx, my) {
					root.pointerScreen = overlay.name;
					root.cursor = Qt.point(overlay.modelData.x + mx, overlay.modelData.y + my);
					if (root.mode === "window")
						root.picked = root.windowAt(root.cursor.x, root.cursor.y);
				}

				function edgesAt(mx, my) {
					const a = root.area;
					if (a === null || a.screen !== overlay.name || !root.video)
						return null;
					const grip = Theme.captureHandle;
					const near = (v, edge) => Math.abs(v - edge) <= grip;
					const inX = mx >= a.x - grip && mx <= a.x + a.width + grip;
					const inY = my >= a.y - grip && my <= a.y + a.height + grip;
					const e = { l: inY && near(mx, a.x), r: inY && near(mx, a.x + a.width),
						t: inX && near(my, a.y), b: inX && near(my, a.y + a.height) };
					return (e.l || e.r || e.t || e.b) ? e : null;
				}

				onEntered: pointer.updateHover(pointer.mouseX, pointer.mouseY)
				onPositionChanged: mouse => {
					pointer.updateHover(mouse.x, mouse.y);
					if (pointer.action === "")
						return;
					const dx = mouse.x - pointer.from.x;
					const dy = mouse.y - pointer.from.y;
					const s = pointer.startArea;
					const w = overlay.width;
					const h = overlay.height;
					if (pointer.action === "draw") {
						const x = Math.max(0, Math.min(pointer.from.x, mouse.x));
						const y = Math.max(0, Math.min(pointer.from.y, mouse.y));
						root.area = { screen: overlay.name, x: x, y: y,
							width: Math.min(w, Math.max(pointer.from.x, mouse.x)) - x,
							height: Math.min(h, Math.max(pointer.from.y, mouse.y)) - y };
					} else if (pointer.action === "move") {
						root.area = Object.assign({}, s, {
							x: Math.max(0, Math.min(w - s.width, s.x + dx)),
							y: Math.max(0, Math.min(h - s.height, s.y + dy)) });
					} else {
						const e = pointer.edges;
						let l = s.x, t = s.y, r = s.x + s.width, b = s.y + s.height;
						if (e.l) l = Math.max(0, Math.min(r - 4, l + dx));
						if (e.r) r = Math.min(w, Math.max(l + 4, r + dx));
						if (e.t) t = Math.max(0, Math.min(b - 4, t + dy));
						if (e.b) b = Math.min(h, Math.max(t + 4, b + dy));
						root.area = Object.assign({}, s, { x: l, y: t, width: r - l, height: b - t });
					}
				}

				onPressed: mouse => {
					if (mouse.button !== Qt.LeftButton || root.mode !== "area")
						return;
					pointer.from = Qt.point(mouse.x, mouse.y);
					pointer.startArea = root.area;
					const a = root.area;
					pointer.edges = pointer.edgesAt(mouse.x, mouse.y);
					if (pointer.edges !== null)
						pointer.action = "resize";
					else if (root.video && a !== null && a.screen === overlay.name
							&& mouse.x > a.x && mouse.x < a.x + a.width
							&& mouse.y > a.y && mouse.y < a.y + a.height)
						pointer.action = "move";
					else {
						pointer.action = "draw";
						root.area = null;
					}
				}

				onReleased: mouse => {
					const action = pointer.action;
					pointer.action = "";
					if (mouse.button !== Qt.LeftButton)
						return;
					if (root.mode === "area") {
						// A click is not an area: let it go.
						if (root.area !== null && (root.area.width < 4 || root.area.height < 4))
							root.area = null;
						// A picture is taken the moment the area is let go; a
						// recording waits to be adjusted and started.
						if (action === "draw" && !root.video && root.area !== null)
							root.take();
					} else {
						root.take();
					}
				}

				onDoubleClicked: {
					if (root.mode === "area" && root.area !== null)
						root.take();
				}
			}

			// The chosen rectangle's edge, and what it measures.
			Rectangle {
				visible: overlay.hasTarget && root.mode !== "screen"
				x: overlay.target.x - 1
				y: overlay.target.y - 1
				width: overlay.target.width + 2
				height: overlay.target.height + 2
				color: "transparent"
				border.width: 1
				border.color: Theme.captureRing
			}

			// Grips, while a recording's area can still be adjusted.
			Repeater {
				model: root.video && root.mode === "area" && overlay.hasTarget
					? [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]] : []

				Rectangle {
					required property var modelData

					x: overlay.target.x + overlay.target.width * modelData[0] - width / 2
					y: overlay.target.y + overlay.target.height * modelData[1] - height / 2
					width: Theme.captureHandle
					height: Theme.captureHandle
					radius: width / 2
					color: Theme.captureRing
				}
			}

			// "1280 × 720" under an area, the title on a window: in physical
			// pixels, which is what the file will measure.
			Rectangle {
				readonly property bool below: overlay.target.y + overlay.target.height + height + 12 < overlay.height
				visible: overlay.hasTarget && root.mode !== "screen" && measure.text !== ""
				x: Math.max(8, Math.min(overlay.width - width - 8,
					overlay.target.x + (overlay.target.width - width) / 2))
				// A window's name sits in its middle; an area's size under it.
				y: root.mode === "window" ? overlay.target.y + (overlay.target.height - height) / 2
					: below ? overlay.target.y + overlay.target.height + 8 : overlay.target.y + 8
				width: Math.min(360, measure.implicitWidth + 16)
				height: measure.implicitHeight + 8
				radius: height / 2
				color: Theme.menuSurface

				Text {
					id: measure

					anchors.fill: parent
					anchors.leftMargin: 8
					anchors.rightMargin: 8
					verticalAlignment: Text.AlignVCenter
					horizontalAlignment: Text.AlignHCenter
					elide: Text.ElideRight
					font.pixelSize: Theme.fontCaption
					color: Theme.glassTextPrimary
					text: root.mode === "window" && root.picked !== null
						? root.picked.title
						: Math.round(overlay.target.width * overlay.ratio) + " × "
							+ Math.round(overlay.target.height * overlay.ratio)
				}
			}

			// The way out, top right, as on anything else over the whole screen.
			DiscButton {
				visible: overlay.focused
				anchors {
					top: parent.top
					right: parent.right
					margins: Theme.spacingL
				}
				glyph: "close"
				onClicked: root.close()
			}

			// What to capture, and how.
			GlassPanel {
				id: toolbar

				visible: overlay.focused
				anchors {
					horizontalCenter: parent.horizontalCenter
					bottom: parent.bottom
					bottomMargin: 48
				}
				width: tools.implicitWidth + Theme.spacingS * 2
				height: Theme.chipHeight + Theme.spacingS * 2
				radius: height / 2
				color: Theme.tabCardSurface

				// The toolbar is not part of the screen being chosen from.
				MouseArea {
					anchors.fill: parent
					hoverEnabled: true
				}

				Row {
					id: tools

					anchors.centerIn: parent
					spacing: Theme.spacingXs

					Repeater {
						model: [["area", "Area"], ["window", "Window"], ["screen", "Screen"]]

						Chip {
							required property var modelData

							text: modelData[1]
							active: root.mode === modelData[0]
							onClicked: root.setMode(modelData[0])
						}
					}

					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						width: 1
						height: Theme.chipHeight - 10
						color: Theme.glassControlBorder
					}

					Chip {
						text: "Picture"
						active: !root.video
						onClicked: root.video = false
					}

					Chip {
						text: "Video"
						active: root.video
						onClicked: root.video = true
					}

					Rectangle {
						visible: root.video
						anchors.verticalCenter: parent.verticalCenter
						width: 1
						height: Theme.chipHeight - 10
						color: Theme.glassControlBorder
					}

					Chip {
						visible: root.video
						text: "Sound"
						active: Settings.recordSound
						onClicked: Settings.setRecordSound(!Settings.recordSound)
					}

					Chip {
						visible: root.video
						text: "Microphone"
						active: Settings.recordMicrophone
						onClicked: Settings.setRecordMicrophone(!Settings.recordMicrophone)
					}

					Item {
						width: Theme.spacingXs
						height: 1
					}

					DialogButton {
						anchors.verticalCenter: parent.verticalCenter
						variant: "primary"
						enabled: root.hasTarget
						text: root.video ? "Record" : "Capture"
						onClicked: {
							// The button sits on the screen it would capture.
							if (root.mode === "screen")
								root.pointerScreen = overlay.name;
							root.take();
						}
					}
				}
			}

			// Escape out; Enter captures; Ctrl+Enter the whole screen; Tab
			// walks the windows; A, W, S pick the mode and V the kind.
			Item {
				anchors.fill: parent
				focus: overlay.focused

				Keys.onPressed: event => {
					const key = event.key;
					if (key === Qt.Key_Escape) {
						if (pointer.action !== "") {
							pointer.action = "";
							root.area = pointer.startArea;
						} else {
							root.close();
						}
					} else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
						if (event.modifiers & Qt.ControlModifier) {
							root.setMode("screen");
							root.pointerScreen = overlay.name;
						}
						root.take();
					} else if (key === Qt.Key_Tab) {
						root.cycle(overlay.modelData, 1);
					} else if (key === Qt.Key_Backtab) {
						root.cycle(overlay.modelData, -1);
					} else if (key === Qt.Key_A) {
						root.setMode("area");
					} else if (key === Qt.Key_W) {
						root.setMode("window");
					} else if (key === Qt.Key_S) {
						root.setMode("screen");
						root.pointerScreen = overlay.name;
					} else if (key === Qt.Key_V) {
						root.video = !root.video;
					} else {
						return;
					}
					event.accepted = true;
				}
			}
		}
	}

	// --- the card ----------------------------------------------------------------

	PanelWindow {
		id: cardWindow

		readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0
		property var shown: null

		visible: card.opacity > 0.01

		anchors {
			bottom: true
			right: true
		}
		margins {
			bottom: Theme.captureMargin - cardWindow.pad
			right: Theme.captureMargin - cardWindow.pad
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"
		implicitWidth: card.width + cardWindow.pad * 2
		implicitHeight: card.height + cardWindow.pad * 2

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:capture-card"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: card.opacity > 0.01 ? blur : null

		Region {
			id: blur

			item: card
			radius: Theme.radiusLarge
		}

		// Keep what was shown while the card goes, rather than emptying it.
		Connections {
			target: root
			function onLastChanged() {
				if (root.last !== null) {
					cardWindow.shown = root.last;
					dwell.restart();
				}
			}
		}

		Timer {
			id: dwell

			interval: 6000
			running: root.last !== null && !hover.containsMouse && !dragProxy.Drag.active
			onTriggered: root.last = null
		}

		GlassPanel {
			id: card

			readonly property real aspect: thumb.implicitHeight > 0 ? thumb.implicitWidth / thumb.implicitHeight : 1.5

			x: cardWindow.pad + (root.last !== null ? 0 : 40)
			y: cardWindow.pad
			width: Math.round(Math.min(Theme.captureThumbWidth, Theme.captureThumbHeight * card.aspect)) + 12
			height: Math.round(Math.min(Theme.captureThumbHeight, Theme.captureThumbWidth / card.aspect)) + 12
			radius: Theme.radiusLarge
			color: Theme.tabCardSurface
			opacity: root.last !== null ? 1 : 0

			Behavior on x {
				NumberAnimation {
					duration: Theme.motionSpatialDuration
					easing.type: Easing.BezierSpline
					easing.bezierCurve: Theme.motionSpatial
				}
			}
			Behavior on opacity {
				NumberAnimation {
					duration: Theme.motionEffectsDuration
					easing.type: Easing.BezierSpline
					easing.bezierCurve: Theme.motionEffects
				}
			}

			Image {
				id: thumb

				anchors.fill: parent
				anchors.margins: 6
				visible: false
				source: (cardWindow.shown?.poster ?? "") !== "" ? "file://" + cardWindow.shown.poster : ""
				cache: false
				asynchronous: true
				fillMode: Image.PreserveAspectCrop
				sourceSize: Qt.size(Theme.captureThumbWidth * 2, Theme.captureThumbHeight * 2)
			}

			Item {
				id: thumbMask

				anchors.fill: thumb
				visible: false
				layer.enabled: true

				Rectangle {
					anchors.fill: parent
					radius: Theme.radiusLarge - 6
				}
			}

			MultiEffect {
				id: picture

				anchors.fill: thumb
				source: thumb
				maskEnabled: true
				maskSource: thumbMask
			}

			// A recording is marked as one: a play mark on a disc.
			Rectangle {
				visible: cardWindow.shown?.video ?? false
				anchors.centerIn: thumb
				width: 40
				height: 40
				radius: 20
				color: Theme.menuSurface

				Shape {
					anchors.fill: parent
					preferredRendererType: Shape.CurveRenderer

					ShapePath {
						strokeWidth: 0
						fillColor: Theme.glassTextPrimary
						startX: 16; startY: 12
						PathLine { x: 29; y: 20 }
						PathLine { x: 16; y: 28 }
						PathLine { x: 16; y: 12 }
					}
				}
			}

			// Out to another window: the file, as a file.
			Item {
				id: dragProxy

				Drag.dragType: Drag.Automatic
				Drag.supportedActions: Qt.CopyAction
				Drag.proposedAction: Qt.CopyAction
				Drag.onDragFinished: action => {
					if (action !== Qt.IgnoreAction)
						root.last = null;
				}
			}

			MouseArea {
				id: hover

				property point from
				property bool dragging: false

				anchors.fill: parent
				hoverEnabled: true
				acceptedButtons: Qt.LeftButton | Qt.RightButton
				cursorShape: Qt.PointingHandCursor

				onPressed: mouse => {
					hover.from = Qt.point(mouse.x, mouse.y);
					hover.dragging = false;
				}
				onPositionChanged: mouse => {
					if (!hover.pressed || hover.dragging || cardWindow.shown === null)
						return;
					if (Math.abs(mouse.x - hover.from.x) + Math.abs(mouse.y - hover.from.y) < 6)
						return;
					hover.dragging = true;
					dragProxy.Drag.mimeData = {
						"text/uri-list": "file://" + encodeURI(cardWindow.shown.file) + "\r\n"
					};
					picture.grabToImage(result => {
						dragProxy.Drag.imageSource = result.url;
						dragProxy.Drag.active = true;
					}, Qt.size(picture.width / 2, picture.height / 2));
				}
				onClicked: mouse => {
					if (hover.dragging)
						return;
					if (mouse.button === Qt.RightButton)
						root.reveal();
					else
						root.edit();
				}
			}

			DiscButton {
				visible: hover.containsMouse || closeHover.hovered
				anchors {
					top: parent.top
					right: parent.right
					margins: 10
				}
				width: 22
				height: 22
				glyph: "close"
				onClicked: root.last = null

				HoverHandler {
					id: closeHover
				}
			}
		}
	}

	// --- IPC ---------------------------------------------------------------------

	IpcHandler {
		target: "capture"

		// The overlay, for a picture. While recording, it stops instead.
		function open(): void {
			root.show(false);
		}

		// The overlay, for a recording.
		function record(): void {
			root.show(true);
		}

		// A picture of the focused screen, without the overlay.
		function screen(): void {
			root.screenNow();
		}

		function stop(): void {
			root.stop();
		}

		function close(): void {
			root.close();
		}

		// "area" | "window" | "screen", for scripts and for testing.
		function mode(mode: string): void {
			root.setMode(mode);
		}

		// Drawn as if dragged, for testing: x y width height on the focused screen.
		function area(x: real, y: real, width: real, height: real): void {
			root.mode = "area";
			root.area = { screen: Hyprland.focusedMonitor?.name ?? "", x: x, y: y, width: width, height: height };
		}

		function take(): void {
			root.take();
		}

		function state(): string {
			return JSON.stringify({ open: root.open, mode: root.mode, video: root.video,
				area: root.area, picked: root.picked, windows: root.windows.length,
				recording: root.recording, last: root.last });
		}
	}
}
