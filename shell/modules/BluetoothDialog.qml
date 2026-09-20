import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import QtQuick
import ".."
import "../icons"
import "../ui"

// Every device in range, and what to do with it.
//
// A browse surface by the guidelines: an X in the header, one affirmative in
// the footer, and a secondary action on the left for the destructive one.
//
// Pairing goes through bluetoothctl rather than BluetoothDevice.pair(). Bluez
// will not pair without an agent to answer for the passkey, Quickshell's
// Bluetooth module exposes no agent type, and nothing else on the machine
// registers one - so calling pair() from QML fails on anything that is not
// "just works". bluetoothctl registers an agent for the length of the command.
Scope {
	id: root

	property var controller: null
	property bool open: false

	// Held by address rather than by object: discovery replaces the objects.
	property string picked: ""
	property string error: ""

	function show() {
		root.picked = "";
		root.error = "";
		root.open = true;
		list.contentY = 0;
	}

	function close() {
		root.open = false;
		root.picked = "";
		root.error = "";
	}

	readonly property var adapter: Bluetooth.defaultAdapter ?? null
	readonly property bool enabled: root.adapter?.enabled ?? false
	readonly property var devices: Bluetooth.devices?.values ?? []

	// Discovery only while someone is looking. It costs power, and it keeps
	// the radio busy enough to interfere with what is already connected.
	Binding {
		target: root.adapter
		property: "discovering"
		value: root.open && root.enabled
		when: root.adapter !== null
	}

	function label(device) {
		return device.name !== "" ? device.name : device.address;
	}

	// Bluez names a device it has no name for after its own address, so an
	// empty-name check finds nothing. Every passing phone, watch and tag
	// advertises, and a list of bare addresses is not a list anyone can choose
	// from - nine rows here were five neighbours' beacons.
	function named(device) {
		const bare = text => text.replace(/[-:]/g, "").toUpperCase();

		return device.name !== "" && bare(device.name) !== bare(device.address);
	}

	// Paired first: those are the ones with a history, and the ones whose row
	// offers to forget them.
	readonly property var pairedDevices: root.devices
		.filter(device => device.paired || device.bonded)
		.sort((a, b) => root.label(a).localeCompare(root.label(b)))

	// Anything else that has announced itself by name.
	readonly property var nearbyDevices: root.devices
		.filter(device => !(device.paired || device.bonded)
			&& root.named(device))
		.sort((a, b) => root.label(a).localeCompare(root.label(b)))

	readonly property var groups: {
		const out = [];

		if (root.pairedDevices.length > 0)
			out.push({ heading: "PAIRED", devices: root.pairedDevices });

		if (root.nearbyDevices.length > 0)
			out.push({ heading: "NEARBY", devices: root.nearbyDevices });

		return out;
	}

	readonly property var ordered: root.groups.reduce(
		(all, group) => all.concat(group.devices), [])

	readonly property var pickedDevice:
		root.ordered.find(device => device.address === root.picked) ?? null

	readonly property bool pickedKnown:
		(root.pickedDevice?.paired ?? false)
			|| (root.pickedDevice?.bonded ?? false)

	readonly property bool busy:
		(root.pickedDevice?.pairing ?? false)
			|| root.pickedDevice?.state === BluetoothDeviceState.Connecting
			|| pair.running

	// What the affirmative does depends on what is picked: a known device is
	// connected to, an unknown one is paired with first.
	readonly property string affirmative: {
		if (root.pickedDevice === null)
			return "Connect";
		if (pair.running)
			return "Pairing…";
		if (!root.pickedKnown)
			return "Pair";

		return root.pickedDevice.connected ? "Disconnect" : "Connect";
	}

	function commit() {
		const device = root.pickedDevice;
		if (device === null || root.busy)
			return;

		root.error = "";

		if (!root.pickedKnown) {
			pair.running = true;
			return;
		}

		device.connected = !device.connected;
	}

	Process {
		id: pair

		command: ["bluetoothctl", "--agent", "NoInputNoOutput",
			"pair", root.picked]

		stdout: StdioCollector {}

		stderr: StdioCollector {
			onStreamFinished: {
				if (text.trim() !== "")
					root.error = text.trim();
			}
		}

		onExited: code => {
			if (code === 0) {
				// Pairing does not connect. Doing both is what clicking a pair
				// of headphones is understood to mean.
				if (root.pickedDevice)
					root.pickedDevice.connected = true;

				return;
			}

			if (root.error === "")
				root.error = "Could not pair. The device may need a code, "
					+ "which Groma cannot ask for yet.";
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
		WlrLayershell.namespace: "groma:bluetooth"
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
			Keys.onReturnPressed: root.commit()
			Keys.onEnterPressed: root.commit()
			Keys.onDownPressed: root.move(1)
			Keys.onUpPressed: root.move(-1)

			Item {
				width: parent.width
				height: 44

				Column {
					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					spacing: Theme.spacingXs

					Text {
						text: "Bluetooth Devices"
						font.pixelSize: Theme.fontDisplay
						font.bold: true
						font.letterSpacing: -0.2
						color: Theme.glassTextPrimary
					}

					Row {
						spacing: Theme.spacingS

						Spinner {
							anchors.verticalCenter: parent.verticalCenter
							visible: root.adapter?.discovering ?? false
							spinning: root.adapter?.discovering ?? false
							color: Theme.glassTextPrimary
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter

							text: {
								if (!root.enabled)
									return "Bluetooth is off";

								const found =
									`${root.nearbyDevices.length} nearby`;

								return (root.adapter?.discovering ?? false)
									? `Scanning · ${found}` : found;
							}

							font.pixelSize: Theme.fontTitle
							font.weight: Font.DemiBold
							opacity: 0.75
							color: Theme.glassTextPrimary
						}
					}
				}

				DiscButton {
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					glyph: "close"
					onClicked: root.close()
				}
			}

			Item {
				width: parent.width
				height: Math.min(Theme.dialogListHeight, list.contentHeight)
				visible: root.ordered.length > 0

				Flickable {
					id: list

					anchors.fill: parent
					clip: true
					contentHeight: rows.implicitHeight
					boundsBehavior: Flickable.StopAtBounds

					Column {
						id: rows

						// Room for a selected row's ring, which is drawn
						// outside the row and would be clipped away.
						x: 3
						width: list.width - 6
						spacing: Theme.spacingS

						Repeater {
							model: root.groups

							Column {
								required property var modelData

								width: rows.width
								spacing: Theme.spacingS

								Text {
									leftPadding: 6
									text: modelData.heading
									font.pixelSize: Theme.fontCaption
									font.bold: true
									font.letterSpacing: 0.66
									opacity: 0.6
									color: Theme.glassTextPrimary
								}

								Repeater {
									model: modelData.devices

									BluetoothRow {
										required property var modelData

										width: rows.width
										compact: false
										device: modelData
										selected: root.picked
											=== modelData.address

										onChosen:
											root.picked = modelData.address
										onActivated: {
											root.picked = modelData.address;
											root.commit();
										}
									}
								}
							}
						}
					}
				}

				Text {
					anchors {
						right: parent.right
						rightMargin: 6
						bottom: parent.bottom
					}

					visible: list.contentHeight > list.height
						&& list.contentY + list.height
							< list.contentHeight - 4

					text: "scroll for more"
					font.pixelSize: 10
					opacity: 0.5
					color: Theme.glassTextPrimary
				}
			}

			Column {
				width: parent.width
				visible: root.ordered.length === 0
				topPadding: 28
				bottomPadding: 20
				spacing: Theme.spacingXs + 2

				Text {
					width: parent.width
					horizontalAlignment: Text.AlignHCenter
					text: !root.enabled ? "Bluetooth is off"
						: "Looking for devices…"
					font.pixelSize: Theme.fontTitle
					font.weight: Font.DemiBold
					opacity: 0.6
					color: Theme.glassTextPrimary
				}

				Text {
					width: parent.width
					horizontalAlignment: Text.AlignHCenter
					visible: root.enabled
					text: "Put the device into pairing mode to find it."
					font.pixelSize: Theme.fontTitle
					opacity: 0.6
					color: Theme.glassTextPrimary
				}
			}

			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				wrapMode: Text.WordWrap
				visible: root.error !== ""
				text: root.error
				font.pixelSize: Theme.fontCaption
				opacity: 0.9
				color: Theme.warning
			}

			Rectangle {
				width: parent.width
				height: 1
				color: Theme.glassControlBorder
			}

			Item {
				width: parent.width
				height: forgetButton.height

				DialogButton {
					id: forgetButton

					anchors.left: parent.left
					text: "Forget"
					variant: "destructive"
					visible: root.pickedKnown
					enabled: !root.busy

					onClicked: {
						root.pickedDevice?.forget();
						root.picked = "";
					}
				}

				DialogButton {
					anchors.right: parent.right

					text: root.pickedDevice !== null
						? `${root.affirmative} ${root.pickedShort}`
						: root.affirmative

					enabled: root.pickedDevice !== null && !root.busy
					variant: root.pickedDevice !== null
						? "primary" : "secondary"

					onClicked: root.commit()
				}
			}
		}
	}

	readonly property string pickedShort: {
		const name = root.pickedDevice !== null
			? root.label(root.pickedDevice) : "";

		return name.length > 14 ? name.slice(0, 13) + "…" : name;
	}

	function move(step) {
		const entries = root.ordered;
		if (entries.length === 0)
			return;

		const at = entries.findIndex(
			device => device.address === root.picked);

		const next = at < 0
			? (step > 0 ? 0 : entries.length - 1)
			: Math.max(0, Math.min(entries.length - 1, at + step));

		root.picked = entries[next].address;
	}
}
