import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// Everything about picking and joining a network, in one sheet of two pages.
//
// Page one is the design's 7: "Other Networks", searchable, grouped by band.
// Page two is its 7c: the join form. They were two separate modals, which the
// design had already argued against - 7c opens with a back chevron, not a
// close - and the seam showed: joining from the list closed one window and
// opened another the same size in the same place.
//
// The connection is made with nmcli rather than through Quickshell, whose
// Network can only ask to connect with settings it has no way to build from
// QML - there is nothing to put a password into.
Scope {
	id: root

	// The network control, for its scan data. It is the controller's business,
	// and duplicating it here would let the two disagree.
	property var controller: null

	property bool open: false

	// "list" | "join"
	property string page: "list"

	// --- page one -------------------------------------------------------

	// The picked network, held by name rather than by object: a rescan
	// replaces the objects, and a selection that survives one scan but not the
	// next would be worse than none.
	property string picked: ""

	readonly property string search: searchField.text

	function showList() {
		root.page = "list";
		root.picked = "";
		searchField.clear();
		root.open = true;
		root.refocus();
	}

	// Put the caret where the missing thing is. Every way in calls this, not
	// just a change of page: asking for a hidden network while the join page
	// is already up replaces the fields without the page changing, and relying
	// on the page alone left the caret in the password box of the network that
	// had just been abandoned.
	function refocus() {
		Qt.callLater(() => {
			if (window.visible)
				window.takeFocus();
		});
	}

	// Driving the filter without a pointer, as with the rest of the network
	// IPC. Also the only way to see the search render without typing into a
	// dialog that has the keyboard.
	function setSearch(term) {
		searchField.text = term;
	}

	// --- page two -------------------------------------------------------

	property int bars: 0
	property bool secured: true
	property bool hidden: false
	property string error: ""
	property bool joining: false

	signal joined

	// From a row: the name is known, so it is filled in but still editable - a
	// typo in a list is easier to fix than to work around.
	function askJoin(name, signalBars, isSecured) {
		root.bars = signalBars ?? 0;
		root.secured = isSecured ?? true;
		root.hidden = false;
		root.openSecurity = root.secured ? "password" : "open";
		root.error = "";
		root.joining = false;
		ssid.text = name ?? "";
		password.clear();
		root.page = "join";
		root.open = true;
		root.refocus();
	}

	// From the button: nothing is known, which is the case for a network that
	// does not broadcast its name.
	function askHidden() {
		root.bars = 0;
		root.secured = true;
		root.hidden = true;
		root.openSecurity = "password";
		root.error = "";
		root.joining = false;
		ssid.text = "";
		password.clear();
		root.page = "join";
		root.open = true;
		root.refocus();
	}

	// What a hidden network is secured with. The design's 7c offers None,
	// WPA2, WPA3 and Enterprise; only two of those are distinctions this form
	// can honour. NetworkManager negotiates WPA2 against WPA3 itself once it
	// has probed for the network, so offering them as separate chips would be
	// theatre, and Enterprise needs an identity, an EAP method and a phase-2
	// method - a connection editor, not a checkbox.
	//
	// "open" | "password"
	property string openSecurity: "password"

	readonly property bool needsPassword:
		root.hidden ? root.openSecurity === "password" : root.secured

	function back() {
		root.error = "";
		root.page = "list";
		root.refocus();
	}

	function close() {
		root.open = false;
		root.page = "list";
		root.picked = "";
		root.error = "";
		password.clear();
	}

	// Join what is picked. Known networks need nothing typed, so they connect
	// where they stand; the rest go to page two.
	function commit() {
		const network = root.ordered.find(entry => entry.name === root.picked);
		if (!network || !root.supported(network.name))
			return;

		if (network.known) {
			network.requestConnect();
			root.close();
			return;
		}

		root.askJoin(network.name, root.controller?.barsFor(network.name) ?? 0,
			root.controller?.detail[network.name]?.secured ?? true);
	}

	function join() {
		if (root.joining || ssid.text === "")
			return;

		if (root.needsPassword && password.text === "")
			return;

		root.joining = true;
		root.error = "";

		// --ask makes nmcli read the secret from stdin rather than taking it
		// as an argument, which would put the password in the process list for
		// anything on the machine to read.
		connect.running = true;
	}

	Process {
		id: connect

		// `hidden yes` tells NetworkManager to probe for a network that does
		// not announce itself, which is the only reason to type a name in.
		command: {
			const base = ["nmcli"];

			if (root.needsPassword)
				base.push("--ask");

			base.push("device", "wifi", "connect", ssid.text);

			if (root.hidden)
				base.push("hidden", "yes");

			return base;
		}

		stdinEnabled: true

		onStarted: {
			if (root.needsPassword)
				connect.write(password.text + "\n");

			password.clear();
		}

		stdout: StdioCollector {}

		stderr: StdioCollector {
			onStreamFinished: {
				if (text.trim() !== "")
					root.error = text.trim().replace(/^Error:\s*/, "");
			}
		}

		onExited: code => {
			root.joining = false;

			if (code !== 0) {
				if (root.error === "")
					root.error = "Could not join the network";

				return;
			}

			// NetworkManager saves the profile and turns autoconnect on for
			// anything joined this way. Unticking the box is a request not to
			// come back to it on its own, which is what "remember" means to
			// anyone who is not editing connection files.
			if (!remember.checked)
				forget.running = true;

			root.joined();
			root.close();
		}
	}

	Process {
		id: forget

		command: ["nmcli", "connection", "modify", ssid.text,
			"connection.autoconnect", "no"]
	}

	// --- shared ---------------------------------------------------------

	readonly property var networks: root.controller?.others ?? []
	readonly property bool scanning: root.controller?.scanning ?? false

	readonly property var matching: {
		const term = root.search.trim().toLowerCase();
		if (term === "")
			return root.networks;

		return root.networks.filter(
			entry => entry.name.toLowerCase().includes(term));
	}

	// Fastest band first, which is also the order anyone reading the list
	// wants: the 5 GHz entry of a network is the one to join.
	readonly property var bandOrder: ["6 GHz", "5 GHz", "2.4 GHz"]
	readonly property string unknownBand: "Band unknown"

	readonly property var groups: {
		const buckets = {};

		for (const entry of root.matching) {
			const band = root.controller?.detail[entry.name]?.band ?? "";
			const key = band !== "" ? band : root.unknownBand;

			if (!buckets[key])
				buckets[key] = [];

			buckets[key].push(entry);
		}

		const labels = root.bandOrder.filter(band => buckets[band]);

		// Anything the scan has not described yet goes last rather than
		// claiming a band it might not be on.
		if (buckets[root.unknownBand])
			labels.push(root.unknownBand);

		return labels.map(band => ({ band: band, networks: buckets[band] }));
	}

	// Headers are worth their space once they divide something. Until the scan
	// answers, every network is of unknown band and a lone "Band unknown"
	// heading over the whole list says nothing - so the list goes ungrouped
	// until there is a grouping to show.
	readonly property bool grouped: root.groups.length > 1
		|| (root.groups.length === 1
			&& root.groups[0].band !== root.unknownBand)

	// The groups flattened, so the arrow keys walk the list in the order it is
	// drawn rather than the order the model happens to be in.
	readonly property var ordered: root.groups.reduce(
		(all, group) => all.concat(group.networks), [])

	function move(step) {
		const entries = root.ordered;
		if (entries.length === 0)
			return;

		const at = entries.findIndex(entry => entry.name === root.picked);

		// No selection yet: down starts at the top, up at the bottom.
		const next = at < 0
			? (step > 0 ? 0 : entries.length - 1)
			: Math.max(0, Math.min(entries.length - 1, at + step));

		root.picked = entries[next].name;
	}

	// nmcli's `device wifi connect` documents that it supports only open, WEP
	// and WPA-PSK where no profile exists. An 802.1X network needs an identity
	// and an EAP method - a connection editor, which this is not - so it can
	// be listed but not joined from here.
	function supported(name) {
		return (root.controller?.detail[name]?.security ?? "") !== "Enterprise";
	}

	readonly property bool pickedSupported:
		root.picked === "" || root.supported(root.picked)

	// The button says what it will join. An SSID may be 32 characters and the
	// footer has room for about half that.
	readonly property string pickedShort: root.picked.length > 16
		? root.picked.slice(0, 15) + "…" : root.picked

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
		WlrLayershell.namespace: "groma:network"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		// Put the caret where the missing thing is. The sheet holds the
		// keyboard while it is up, so typing has to land somewhere useful.
		function takeFocus() {
			if (root.page === "list")
				searchField.focusInput();
			else if (ssid.text === "")
				ssid.focusInput();
			else
				password.focusInput();
		}

		onVisibleChanged: if (window.visible) window.takeFocus()

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			// The design's picker: wider than a prompt, with correspondingly
			// larger gutters and gaps. Page two keeps the width so that moving
			// between them does not resize the sheet sideways.
			sheetWidth: Theme.dialogWidthWide
			padding: 24
			spacing: Theme.spacingL

			// Escape backs out one page at a time, then closes - the same
			// thing the back chevron does, so the two cannot disagree.
			Keys.onEscapePressed: root.page === "join" ? root.back() : root.close()
			Keys.onReturnPressed: root.page === "join" ? root.join() : root.commit()
			Keys.onEnterPressed: root.page === "join" ? root.join() : root.commit()
			Keys.onDownPressed: if (root.page === "list") root.move(1)
			Keys.onUpPressed: if (root.page === "list") root.move(-1)

			// ---------------------------------------------------------------
			// Page one: the picker.
			// ---------------------------------------------------------------

			// The two pages overlaid rather than stacked, so one can slide out while
			// the other slides in. Nothing clips them: a page travels exactly the
			// sheet's padding, so at full travel it sits against the inside edge of
			// the glass. Clipping here would cut the focus rings off the fields,
			// which are drawn outside them.
			Item {
				id: pager

				width: parent.width
				height: root.page === "list"
					? listPage.implicitHeight : joinPage.implicitHeight

				// Not while the sheet is shut, or opening it would animate the first
				// page's height up from nothing behind the fade.
				Behavior on height {
					enabled: root.open
					NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
				}

				Column {
					id: listPage

					width: parent.width
					spacing: Theme.spacingL

					// Waits off to the left while the join page has the sheet:
					// forward is rightwards, back is leftwards, as on a phone.
					x: root.page === "list" ? 0 : -Theme.dialogPageSlide
					opacity: root.page === "list" ? 1 : 0

					// Both pages are on screen mid-slide; only one takes clicks.
					visible: opacity > 0.01
					enabled: root.page === "list"

					Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
					Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }

					Item {
						width: parent.width
						height: 44

						Column {
							anchors.left: parent.left
							anchors.verticalCenter: parent.verticalCenter
							spacing: Theme.spacingXs

							Text {
								text: "Other Networks"
								font.pixelSize: Theme.fontDisplay
								font.bold: true
								font.letterSpacing: -0.2
								color: Theme.glassTextPrimary
							}

							Row {
								spacing: Theme.spacingS

								Spinner {
									anchors.verticalCenter: parent.verticalCenter
									visible: root.scanning
									spinning: root.scanning
									color: Theme.glassTextPrimary
								}

								Text {
									anchors.verticalCenter: parent.verticalCenter

									// An empty list mid-scan and an empty list
									// after one mean different things, so the
									// count is never shown without saying which
									// this is.
									text: {
										if (!(root.controller?.enabled ?? false))
											return "Wi-Fi is off";

										const found =
											`${root.networks.length} found`;

										return root.scanning
											? `Scanning · ${found}` : found;
									}

									font.pixelSize: Theme.fontTitle
									font.weight: Font.DemiBold
									opacity: 0.75
									color: Theme.glassTextPrimary
								}
							}
						}

						// A dialog that owns the keyboard needs a way out that is
						// not a keypress.
						DiscButton {
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							glyph: "close"
							onClicked: root.close()
						}
					}

					GlassField {
						id: searchField

						width: parent.width
						placeholder: "Search networks"

						leading: SearchIcon {
							width: 15
							height: 15
							color: Theme.glassTextPrimary
							opacity: 0.8
						}

						onAccepted: root.commit()
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

								// Held off the edges by the width of a selected
								// row's ring, which is drawn outside the row and
								// would otherwise be clipped away.
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
											visible: root.grouped
											text: modelData.band
											font.pixelSize: Theme.fontCaption
											font.bold: true
											font.letterSpacing: 0.66
											opacity: 0.6
											color: Theme.glassTextPrimary
										}

										Repeater {
											model: modelData.networks

											NetworkRow {
												required property var modelData

												width: rows.width
												compact: false
												network: modelData
												highlight: root.search.trim()
												selected:
													root.picked === modelData.name

												detail: root.controller?.detail[
													modelData.name] ?? null
												bars: root.controller?.barsFor(
													modelData.name) ?? 0
												unsupported: !root.supported(
													modelData.name)

												onChosen:
													root.picked = modelData.name
												onActivated: {
													root.picked = modelData.name;
													root.commit();
												}
											}
										}
									}
								}
							}
						}

						// Only worth saying when there is more below.
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

					// Nothing to show, for one of two quite different reasons.
					Column {
						width: parent.width
						visible: root.ordered.length === 0
						topPadding: 28
						bottomPadding: 20
						spacing: Theme.spacingXs + 2

						Text {
							width: parent.width
							horizontalAlignment: Text.AlignHCenter
							text: root.networks.length === 0
								? (root.scanning ? "Looking for networks…"
									: "No networks in range")
								: `Showing 0 of ${root.networks.length} networks`

							font.pixelSize: Theme.fontTitle
							font.weight: Font.DemiBold
							opacity: 0.6
							color: Theme.glassTextPrimary
						}

						Text {
							width: parent.width
							horizontalAlignment: Text.AlignHCenter
							visible: root.networks.length > 0
							text: "Clear the search to see all."
							font.pixelSize: Theme.fontTitle
							opacity: 0.6
							color: Theme.glassTextPrimary
						}
					}

					// A disabled Join with no explanation is the silent failure
					// moved rather than fixed.
					Text {
						width: parent.width
						horizontalAlignment: Text.AlignHCenter
						visible: !root.pickedSupported
						wrapMode: Text.WordWrap

						text: "Enterprise networks need an identity and a "
							+ "certificate. Groma cannot join one yet."

						font.pixelSize: Theme.fontCaption
						opacity: 0.75
						color: Theme.warning
					}

					// How much of the list the search is hiding. Without this a
					// filter left in the box looks like a network that has gone.
					Text {
						width: parent.width
						horizontalAlignment: Text.AlignHCenter
						visible: root.ordered.length > 0
							&& root.matching.length < root.networks.length

						text: `Showing ${root.matching.length} of `
							+ `${root.networks.length} networks · clear the `
							+ `search to see all.`

						font.pixelSize: Theme.fontCaption
						opacity: 0.6
						color: Theme.glassTextPrimary
					}

					Rectangle {
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Item {
						width: parent.width
						height: hiddenButton.height

						DialogButton {
							id: hiddenButton

							anchors.left: parent.left
							text: "Join Hidden Network…"
							onClicked: root.askHidden()
						}

						Row {
							anchors.right: parent.right
							spacing: Theme.spacingS + 2

							DialogButton {
								text: root.picked !== ""
									? `Join ${root.pickedShort}` : "Join"

								enabled: root.picked !== "" && root.pickedSupported

								// Dim glass with faded text until there is
								// something to join, then the bright chip - which
								// needs dark text, so the variant changes with it.
								variant: root.picked !== "" && root.pickedSupported
									? "primary" : "secondary"

								onClicked: root.commit()
							}
						}
					}
				}

				// ---------------------------------------------------------------
				// Page two: the join form.
				// ---------------------------------------------------------------

				Column {
					id: joinPage

					width: parent.width
					spacing: Theme.spacingL

					// Waits off to the right, and arrives from there.
					x: root.page === "join" ? 0 : Theme.dialogPageSlide
					opacity: root.page === "join" ? 1 : 0

					// Both pages are on screen mid-slide; only one takes clicks.
					visible: opacity > 0.01
					enabled: root.page === "join"

					Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }
					Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] } }

					Row {
						width: parent.width
						spacing: Theme.spacingL - 2

						DiscButton {
							anchors.verticalCenter: parent.verticalCenter
							glyph: "back"
							onClicked: root.back()
						}

						Column {
							anchors.verticalCenter: parent.verticalCenter
							spacing: Theme.spacingXs

							Text {
								text: root.hidden
									? "Join Hidden Network" : "Join Network"
								font.pixelSize: Theme.fontDisplay
								font.bold: true
								font.letterSpacing: -0.2
								color: Theme.glassTextPrimary
							}

							Text {
								text: root.hidden
									? "Enter the network name and security details."
									: root.secured
										? "This network is secured. Enter its "
											+ "password to connect."
										: "This network is open. No password is "
											+ "needed."

								font.pixelSize: Theme.fontTitle
								font.weight: Font.DemiBold
								opacity: 0.75
								color: Theme.glassTextPrimary
							}
						}
					}

					Column {
						width: parent.width
						spacing: Theme.spacingM

						Column {
							width: parent.width
							spacing: Theme.spacingXs + 2

							FieldLabel { text: "NETWORK NAME" }

							GlassField {
								id: ssid

								width: parent.width
								placeholder: "Network name"
								enabled: !root.joining

								onAccepted: root.needsPassword
									? password.focusInput() : root.join()
							}
						}

						// Only asked for when nothing was scanned to answer it.
						Column {
							width: parent.width
							visible: root.hidden
							spacing: Theme.spacingXs + 2

							FieldLabel { text: "SECURITY" }

							Row {
								width: parent.width
								spacing: Theme.spacingS

								Repeater {
									model: [
										{ key: "open", label: "Open" },
										{ key: "password", label: "Password" }
									]

									DialogButton {
										required property var modelData

										width: (parent.width - Theme.spacingS) / 2
										text: modelData.label
										enabled: !root.joining

										variant: root.openSecurity === modelData.key
											? "primary" : "secondary"

										onClicked:
											root.openSecurity = modelData.key
									}
								}
							}
						}

						Column {
							width: parent.width
							visible: root.needsPassword
							spacing: Theme.spacingXs + 2

							FieldLabel { text: "PASSWORD" }

							GlassField {
								id: password

								width: parent.width
								placeholder: "Required"
								echoMode: TextInput.Password
								revealable: true
								enabled: !root.joining

								onAccepted: root.join()
							}
						}
					}

					Checkbox {
						id: remember

						text: "Remember this network"
						checked: true
						onToggled: remember.checked = !remember.checked
					}

					Text {
						width: parent.width
						wrapMode: Text.WordWrap
						visible: root.error !== ""
						text: root.error
						font.pixelSize: Theme.fontCaption
						lineHeight: 1.4
						color: Theme.warning
					}

					Rectangle {
						width: parent.width
						height: 1
						color: Theme.glassControlBorder
					}

					Row {
						anchors.right: parent.right
						spacing: Theme.spacingS + 2

						DialogButton {
							text: "Cancel"
							enabled: !root.joining
							onClicked: root.close()
						}

						DialogButton {
							text: root.joining ? "Joining…" : "Join"
							variant: "primary"
							enabled: !root.joining && ssid.text !== ""
								&& (!root.needsPassword || password.text !== "")
							onClicked: root.join()
						}
					}
				}
			}
		}
	}
}
