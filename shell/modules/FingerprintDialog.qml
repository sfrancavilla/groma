import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// Fingerprint: the fingers fprintd knows, adding one, and taking one away.
//
// Three pages of one sheet: the list, which finger to add, and the touches
// that add it. Reading goes over D-Bus (fingerprint-probe.sh beside this);
// adding and removing go through fprintd's own fprintd-enroll and
// fprintd-delete, which ask polkit first - so the first change raises
// Groma's password prompt, and polkit then remembers it for a few minutes.
//
// Also says, once, that a reader exists with nothing enrolled - otherwise the
// only place anyone learns about it is the end of install.sh.
//
//   qs -c groma ipc call fingerprint opened
Scope {
	id: root

	property bool open: false

	// "list" | "pick" | "enrol"
	property string page: "list"

	// --- what fprintd knows -------------------------------------------------

	property bool loading: false
	property string device: ""
	property string deviceName: ""
	property int stages: 0
	property bool swipe: false
	property var fingers: []

	property int picked: 0

	readonly property string pickedFinger:
		root.fingers.length > 0 ? root.fingers[Math.min(root.picked, root.fingers.length - 1)] : ""

	function probe() {
		root.loading = true;
		prober.running = false;
		prober.running = true;
	}

	Process {
		id: prober

		command: ["sh", `${Quickshell.shellDir}/modules/fingerprint-probe.sh`]

		stdout: StdioCollector {
			onStreamFinished: {
				let device = "", name = "", stages = 0, type = "";
				const fingers = [];
				for (const line of text.split("\n")) {
					const space = line.indexOf(" ");
					const key = line.slice(0, space), value = line.slice(space + 1);
					if (key === "device") device = value;
					else if (key === "name") name = value;
					else if (key === "stages") stages = parseInt(value) || 0;
					else if (key === "type") type = value;
					else if (key === "finger") fingers.push(value);
				}
				root.device = device;
				root.deviceName = name;
				root.stages = stages;
				root.swipe = type.startsWith("swipe");
				root.fingers = fingers.sort((a, b) => root.order.indexOf(a) - root.order.indexOf(b));
				root.picked = Math.min(root.picked, Math.max(0, fingers.length - 1));
				root.loading = false;
				root.probed();
			}
		}
	}

	signal probed

	// --- fingers --------------------------------------------------------------

	readonly property var hands: ["left", "right"]
	readonly property var digits: [
		["thumb", "Thumb"], ["index-finger", "Index"], ["middle-finger", "Middle"],
		["ring-finger", "Ring"], ["little-finger", "Little"]
	]

	// Which finger to suggest first: the ones people reach a reader with.
	readonly property var order: [
		"right-index-finger", "left-index-finger", "right-thumb", "left-thumb",
		"right-middle-finger", "left-middle-finger", "right-ring-finger",
		"left-ring-finger", "right-little-finger", "left-little-finger"
	]

	// fprintd's names, read aloud: "right-index-finger" is "Right index finger".
	function label(name) {
		const words = name.replace(/-/g, " ");
		return words.charAt(0).toUpperCase() + words.slice(1);
	}

	// --- pages ----------------------------------------------------------------

	function show(page) {
		root.page = page === "pick" ? "pick" : "list";
		if (root.page === "pick")
			root.choose();
		root.open = true;
		root.probe();
	}

	function close() {
		root.cancel();
		root.open = false;
	}

	// The first finger not already there.
	property string choice: ""

	function choose() {
		root.choice = root.order.find(f => !root.fingers.includes(f)) ?? "";
	}

	onProbed: {
		if (root.page === "pick" && (root.choice === "" || root.fingers.includes(root.choice)))
			root.choose();
		if (root.nudging)
			root.nudgeIfUnused();
	}

	function add() {
		if (root.device === "" || root.fingers.length >= root.order.length)
			return;
		root.choose();
		root.page = "pick";
	}

	function back() {
		root.cancel();
		root.page = "list";
	}

	function move(delta) {
		if (root.fingers.length > 0)
			root.picked = Math.max(0, Math.min(root.fingers.length - 1, root.picked + delta));
	}

	// --- adding -----------------------------------------------------------------

	property string enrolFinger: ""
	property int passed: 0
	// "running" | "done" | "failed"
	property string enrolState: ""
	property string note: ""

	function startEnrol() {
		if (root.choice === "" || enroller.running)
			return;
		root.enrolFinger = root.choice;
		root.passed = 0;
		root.enrolState = "running";
		root.note = root.swipe
			? `Swipe your ${root.label(root.enrolFinger).toLowerCase()} across the reader.`
			: `Touch the reader with your ${root.label(root.enrolFinger).toLowerCase()}.`;
		root.page = "enrol";
		enroller.command = ["fprintd-enroll", "-f", root.enrolFinger];
		enroller.running = true;
	}

	// Killing fprintd-enroll is how it is stopped: it has no signal handler,
	// and fprintd ends the enrolment when its client leaves the bus.
	function cancel() {
		if (enroller.running) {
			root.enrolState = "";
			enroller.running = false;
		}
	}

	function fail(text) {
		root.enrolState = "failed";
		root.note = text;
	}

	// fprintd-enroll prints one "Enroll result:" line per touch, and a line
	// of its own for anything that stops it before the first.
	function enrolLine(line) {
		const result = line.startsWith("Enroll result: ") ? line.slice(15).trim() : "";

		if (result === "") {
			const refused = /^(EnrollStart failed|failed to claim device|Impossible to enroll|failed to connect to device): (.*)$/.exec(line);
			if (refused === null)
				return;
			const why = refused[2];
			root.fail(why.includes("PermissionDenied") || why.includes("Not Authorized")
				? "Adding a finger needs your password."
				: why.includes("AlreadyInUse") || why.includes("already")
					? "The reader is busy. Try again in a moment."
					: "The reader could not start.");
			return;
		}

		const again = root.swipe ? "Swipe again." : "Lift your finger, then touch again, shifted a little.";

		switch (result) {
		case "enroll-stage-passed":
			root.passed += 1;
			root.note = again;
			break;
		case "enroll-retry-scan":
			root.note = "That one did not register. " + (root.swipe ? "Swipe again." : "Touch again.");
			break;
		case "enroll-swipe-too-short":
			root.note = "Too short. Swipe the whole finger across.";
			break;
		case "enroll-finger-not-centered":
			root.note = "Centre your finger on the reader and try again.";
			break;
		case "enroll-remove-and-retry":
			root.note = "Lift your finger and try again.";
			break;
		case "enroll-completed":
			root.passed = Math.max(root.passed, root.stages);
			root.enrolState = "done";
			root.note = `${root.label(root.enrolFinger)} added.`;
			finished.restart();
			break;
		case "enroll-duplicate":
			root.fail("That finger is already enrolled, perhaps as another one.");
			break;
		case "enroll-data-full":
			root.fail("The reader has no room for another finger.");
			break;
		case "enroll-disconnected":
			root.fail("The reader was disconnected.");
			break;
		default:
			root.fail("The reader could not add this finger. Try again.");
		}
	}

	Process {
		id: enroller

		stdout: SplitParser {
			onRead: line => root.enrolLine(line)
		}

		onExited: {
			if (root.enrolState === "running")
				root.fail("Adding the finger stopped.");
			root.probe();
		}
	}

	// Long enough to read "added", then back to the list it is now in.
	Timer {
		id: finished

		interval: 1400
		onTriggered: {
			if (root.page === "enrol" && root.enrolState === "done") {
				root.picked = Math.max(0, root.fingers.indexOf(root.enrolFinger));
				root.page = "list";
			}
		}
	}

	// --- removing ---------------------------------------------------------------

	function remove() {
		if (root.pickedFinger === "" || remover.running)
			return;
		remover.command = ["fprintd-delete", Quickshell.env("USER"), "-f", root.pickedFinger];
		remover.running = true;
	}

	Process {
		id: remover

		onExited: root.probe()
	}

	// --- saying so, once ------------------------------------------------------

	// Late enough not to land in the middle of logging in.
	Timer {
		interval: 30000
		running: !Settings.fingerprintNudged
		onTriggered: {
			root.nudging = true;
			root.probe();
		}
	}

	property bool nudging: false

	function nudgeIfUnused() {
		root.nudging = false;

		// No reader: nothing to say, and asked again next login, so a reader
		// that arrives later still gets mentioned.
		if (root.device === "")
			return;

		Settings.setFingerprintNudged(true);
		if (root.fingers.length === 0)
			nudge.running = true;
	}

	Process {
		id: nudge

		command: ["notify-send", "--app-name=Groma", "--icon=groma-fingerprint",
			"--action=setup=Set Up Fingerprint…", "--wait",
			"This laptop has a fingerprint reader",
			"Add a finger, and the lock screen opens with a touch."]

		stdout: StdioCollector {
			onStreamFinished: {
				if (text.trim() === "setup")
					root.show("pick");
			}
		}
	}

	IpcHandler {
		target: "fingerprint"

		function opened(): void { root.show("list"); }
		function closed(): void { root.close(); }
		function toggle(): void { if (root.open) root.close(); else root.show("list"); }
		// Straight to choosing a finger, as the notification does.
		function add(): void { root.show("pick"); }
		// The once-only notification, again, for testing it.
		function nudge(): void { nudge.running = true; }
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
		WlrLayershell.namespace: "groma:fingerprint"
		WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: dialog.sheet
			radius: Theme.radiusPanel
		}

		onVisibleChanged: if (visible) dialog.forceActiveFocus()

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			sheetWidth: Theme.dialogWidthWide
			padding: 24
			spacing: Theme.spacingL

			// Escape backs out one page at a time, then closes; during the
			// touches it is Cancel.
			Keys.onEscapePressed: {
				if (root.page === "list")
					root.close();
				else
					root.back();
			}
			Keys.onReturnPressed: root.enter()
			Keys.onEnterPressed: root.enter()
			Keys.onDownPressed: if (root.page === "list") root.move(1)
			Keys.onUpPressed: if (root.page === "list") root.move(-1)

			Item {
				id: pager

				width: parent.width
				height: root.page === "list" ? listPage.implicitHeight
					: root.page === "pick" ? pickPage.implicitHeight
					: enrolPage.implicitHeight

				Behavior on height {
					enabled: root.open
					NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
				}

				// ---------------------------------------------------------------
				// Page one: the fingers there are.
				// ---------------------------------------------------------------

				FingerprintPage {
					id: listPage

					index: 0
					current: root.pageIndex

					Item {
						width: parent.width
						height: 44

						Column {
							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter
							spacing: Theme.spacingXs

							Text {
								text: "Fingerprint"
								font.pixelSize: Theme.fontDisplay
								font.bold: true
								font.letterSpacing: -0.2
								color: Theme.glassTextPrimary
							}

							Text {
								text: root.device !== "" ? root.deviceName
									: root.loading ? "Looking for a reader…" : "No reader"
								font.pixelSize: Theme.fontTitle
								font.weight: Font.DemiBold
								opacity: 0.75
								color: Theme.glassTextPrimary
							}
						}

						DiscButton {
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							onClicked: root.close()
						}
					}

					Column {
						width: parent.width
						spacing: 4

						Repeater {
							model: root.fingers

							Rectangle {
								id: row

								required property string modelData
								required property int index

								readonly property bool chosen: root.picked === index

								width: parent.width
								height: 52
								radius: Theme.radiusRow
								color: chosen ? Theme.glassChipActive : rowMouse.containsMouse ? Theme.glassControlHover : "transparent"
								border.width: chosen ? 1 : 0
								border.color: Theme.glassTrackBorderFocus

								Row {
									anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
									spacing: 12

									Lens {
										anchors.verticalCenter: parent.verticalCenter
										width: 30
										height: 30
										sheen: false
										plain: !row.chosen

										FingerprintIcon {
											anchors.centerIn: parent
											width: 15
											height: 16
											color: row.chosen ? Theme.fileInk : Theme.glassTextPrimary
										}
									}

									Text {
										anchors.verticalCenter: parent.verticalCenter
										text: root.label(row.modelData)
										font.pixelSize: Theme.fontLead
										font.weight: row.chosen ? Font.Bold : Font.DemiBold
										color: Theme.glassTextPrimary
									}
								}

								MouseArea {
									id: rowMouse

									anchors.fill: parent
									hoverEnabled: true
									onClicked: root.picked = row.index
								}
							}
						}
					}

					// Nothing to list: say why, and what a finger would do.
					Text {
						width: parent.width
						visible: root.fingers.length === 0 && !root.loading
						wrapMode: Text.WordWrap
						font.pixelSize: Theme.fontBody
						lineHeight: 1.45
						opacity: 0.82
						color: Theme.glassTextPrimary
						text: root.device === ""
							? "Groma found no fingerprint reader it can use. Readers are driven by libfprint, which supports most recent laptops; fprintd has to be installed for it."
							: "No fingers yet. Add one, and the lock screen opens with a touch of the reader."
					}

					Text {
						width: parent.width
						visible: root.fingers.length > 0
						wrapMode: Text.WordWrap
						font.pixelSize: Theme.fontBody
						lineHeight: 1.45
						opacity: 0.7
						color: Theme.glassTextPrimary
						text: "Any of these opens the lock screen. Logging in after a restart, and anything that asks for an administrator, still takes your password."
					}

					Item {
						width: parent.width
						height: Theme.chipHeight
						visible: root.device !== ""

						DialogButton {
							anchors.left: parent.left
							visible: root.fingers.length > 0
							text: "Remove"
							variant: "destructive"
							enabled: !remover.running
							onClicked: root.remove()
						}

						DialogButton {
							anchors.right: parent.right
							text: "Add Finger…"
							variant: "primary"
							enabled: root.fingers.length < root.order.length
							onClicked: root.add()
						}
					}
				}

				// ---------------------------------------------------------------
				// Page two: which finger.
				// ---------------------------------------------------------------

				FingerprintPage {
					id: pickPage

					index: 1
					current: root.pageIndex

					Row {
						width: parent.width
						height: 44
						spacing: Theme.spacingM

						DiscButton {
							anchors.verticalCenter: parent.verticalCenter
							glyph: "back"
							onClicked: root.back()
						}

						Column {
							anchors.verticalCenter: parent.verticalCenter
							spacing: Theme.spacingXs

							Text {
								text: "Add Finger"
								font.pixelSize: Theme.fontDisplay
								font.bold: true
								font.letterSpacing: -0.2
								color: Theme.glassTextPrimary
							}

							Text {
								text: "Pick the one you will touch the reader with."
								font.pixelSize: Theme.fontTitle
								font.weight: Font.DemiBold
								opacity: 0.75
								color: Theme.glassTextPrimary
							}
						}
					}

					Repeater {
						model: root.hands

						Column {
							id: hand

							required property string modelData

							width: parent.width
							spacing: Theme.spacingS

							FieldLabel {
								text: hand.modelData.toUpperCase() + " HAND"
							}

							Row {
								spacing: 6

								Repeater {
									model: root.digits

									Chip {
										required property var modelData

										readonly property string finger: `${hand.modelData}-${modelData[0]}`
										readonly property bool there: root.fingers.includes(finger)

										width: (pickPage.width - 6 * 4) / 5
										text: modelData[1]
										active: root.choice === finger
										enabled: !there
										opacity: there ? 0.35 : 1
										onClicked: root.choice = finger
									}
								}
							}
						}
					}

					Item {
						width: parent.width
						height: Theme.chipHeight

						Row {
							anchors.right: parent.right
							spacing: Theme.spacingS

							DialogButton {
								text: "Cancel"
								onClicked: root.back()
							}

							DialogButton {
								width: Math.min(implicitWidth, pickPage.width / 2)
								text: root.choice !== "" ? "Add " + root.label(root.choice).toLowerCase() : "Add"
								variant: "primary"
								enabled: root.choice !== ""
								onClicked: root.startEnrol()
							}
						}
					}
				}

				// ---------------------------------------------------------------
				// Page three: the touches.
				// ---------------------------------------------------------------

				FingerprintPage {
					id: enrolPage

					index: 2
					current: root.pageIndex

					Column {
						width: parent.width
						spacing: Theme.spacingXs

						Text {
							text: "Add Finger"
							font.pixelSize: Theme.fontDisplay
							font.bold: true
							font.letterSpacing: -0.2
							color: Theme.glassTextPrimary
						}

						Text {
							text: root.enrolFinger !== "" ? root.label(root.enrolFinger) : ""
							font.pixelSize: Theme.fontTitle
							font.weight: Font.DemiBold
							opacity: 0.75
							color: Theme.glassTextPrimary
						}
					}

					// The print fills from the bottom, a touch at a time.
					Item {
						id: printMark

						readonly property real fraction: root.stages > 0
							? Math.min(1, root.passed / root.stages) : 0
						readonly property color ink: root.enrolState === "done" ? Theme.success
							: root.enrolState === "failed" ? Theme.warning : Theme.glassTextPrimary

						anchors.horizontalCenter: parent.horizontalCenter
						width: 96
						height: 104

						FingerprintIcon {
							anchors.fill: parent
							color: printMark.ink
							opacity: 0.22
						}

						Item {
							anchors.bottom: parent.bottom
							width: parent.width
							height: parent.height * printMark.fraction
							clip: true

							Behavior on height {
								NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
							}

							FingerprintIcon {
								anchors.bottom: parent.bottom
								width: printMark.width
								height: printMark.height
								color: printMark.ink
							}
						}
					}

					Text {
						width: parent.width
						horizontalAlignment: Text.AlignHCenter
						wrapMode: Text.WordWrap
						text: root.note
						font.pixelSize: Theme.fontLead
						font.weight: Font.DemiBold
						color: root.enrolState === "failed" ? Theme.warning : Theme.glassTextPrimary
					}

					Text {
						width: parent.width
						horizontalAlignment: Text.AlignHCenter
						visible: root.stages > 0 && root.enrolState === "running"
						text: `${root.passed} of ${root.stages}`
						font.pixelSize: Theme.fontBody
						opacity: 0.6
						color: Theme.glassTextPrimary
					}

					Item {
						width: parent.width
						height: Theme.chipHeight

						Row {
							anchors.right: parent.right
							spacing: Theme.spacingS

							DialogButton {
								text: "Cancel"
								visible: root.enrolState !== "done"
								onClicked: root.back()
							}

							DialogButton {
								text: "Try again"
								variant: "primary"
								visible: root.enrolState === "failed"
								onClicked: {
									root.choice = root.enrolFinger;
									root.startEnrol();
								}
							}
						}
					}
				}
			}
		}
	}

	function enter() {
		if (root.page === "list")
			root.add();
		else if (root.page === "pick")
			root.startEnrol();
		else if (root.enrolState === "failed") {
			root.choice = root.enrolFinger;
			root.startEnrol();
		}
	}

	readonly property int pageIndex: root.page === "list" ? 0 : root.page === "pick" ? 1 : 2

	// One page of the three, sliding: forward is rightwards, back leftwards.
	// Told which page is showing rather than reading root, whose ids an
	// inline component cannot see.
	component FingerprintPage: Column {
		required property int index
		property int current: 0

		width: parent.width
		spacing: Theme.spacingL

		x: index < current ? -Theme.dialogPageSlide : index > current ? Theme.dialogPageSlide : 0
		opacity: index === current ? 1 : 0

		// All three are on screen mid-slide; only one takes clicks.
		visible: opacity > 0.01
		enabled: index === current

		Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
		Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
	}
}
