import Quickshell
import Quickshell.Wayland
import QtQuick
import ".."
import "../icons"
import "../ui"

// Every network in range: the design's "Other Networks" picker.
//
// The tile shows four, because a tile that grows with the airwaves is not a
// tile. This is where the rest live - searchable, grouped by band, and joined
// deliberately rather than on the first click, because a list that scrolls is
// a list you can join the wrong thing from.
Scope {
	id: root

	// The network control, for its scan data and for what joining means. Both
	// are its business, and duplicating either here would let them disagree.
	property var controller: null

	property bool open: false

	// The picked network, held by name rather than by object: a rescan
	// replaces the objects, and a selection that survives one scan but not the
	// next would be worse than none.
	property string picked: ""

	readonly property string search: searchField.text

	function show() {
		root.picked = "";
		searchField.clear();
		root.open = true;
	}

	function close() {
		root.open = false;
		root.picked = "";
	}

	// Join what is picked, then close. In that order: this runs from a click on
	// this window's own surface, and closing first tears that surface down
	// underneath the handler.
	function commit() {
		const network = root.ordered.find(entry => entry.name === root.picked);
		if (!network)
			return;

		root.controller?.activate(network);
		root.close();
	}

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

	readonly property var networks: root.controller?.others ?? []
	readonly property bool scanning: root.controller?.scanning ?? false

	readonly property var matching: {
		const term = root.search.trim().toLowerCase();
		if (term === "")
			return root.networks;

		return root.networks.filter(
			entry => entry.name.toLowerCase().includes(term));
	}

	// Fastest band first, which is also the order anyone scanning the list
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
		WlrLayershell.namespace: "groma:network-list"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

		BackgroundEffect.blurRegion: Region {
			item: dialog
		}

		// Put the caret in the search box on open. The dialog holds the
		// keyboard while it is up, so typing has to land somewhere useful.
		onVisibleChanged: if (window.visible) searchField.focusInput()

		GlassDialog {
			id: dialog

			anchors.fill: parent
			open: root.open
			focus: true

			// The design's picker: wider than a prompt, with correspondingly
			// larger gutters and gaps.
			sheetWidth: Theme.dialogWidthWide
			padding: 24
			spacing: Theme.spacingL

			// The header is a title, a live scan state and a close button, so
			// it is built below rather than left to title/body.
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

							// An empty list mid-scan and an empty list after
							// one mean different things, so the count is never
							// shown without saying which this is.
							text: {
								if (!(root.controller?.enabled ?? false))
									return "Wi-Fi is off";

								const found = `${root.networks.length} found`;

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

				// Close. A dialog that owns the keyboard needs a way out that
				// is not a keypress.
				Rectangle {
					id: closeButton

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter

					width: 36
					height: 36
					radius: 18

					color: closeMouse.containsMouse
						? Theme.glassControlHover : Theme.glassControl
					border.width: 1
					border.color: Theme.glassControlBorder

					Behavior on color {
						ColorAnimation { duration: 120 }
					}

					Item {
						anchors.centerIn: parent
						width: 12
						height: 12

						Repeater {
							model: [45, -45]

							Rectangle {
								required property int modelData

								anchors.centerIn: parent
								width: 2
								height: 12
								radius: 1
								color: Theme.glassTextPrimary
								rotation: modelData
							}
						}
					}

					MouseArea {
						id: closeMouse

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: root.close()
					}
				}
			}

			GlassField {
				id: searchField

				width: parent.width
				placeholder: "Search networks"

				leading: SearchIcon {
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

						// Held off the edges by the width of a selected row's
						// ring, which is drawn outside the row and would
						// otherwise be clipped away on the left and right.
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
										selected: root.picked === modelData.name

										detail: root.controller?.detail[
											modelData.name] ?? null
										bars: root.controller?.barsFor(
											modelData.name) ?? 0

										onChosen: root.picked = modelData.name
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

			// How much of the list the search is hiding. Without this a filter
			// left in the box looks like a network that has gone away.
			Text {
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				visible: root.ordered.length > 0
					&& root.matching.length < root.networks.length

				text: `Showing ${root.matching.length} of `
					+ `${root.networks.length} networks · clear the search `
					+ `to see all.`

				font.pixelSize: Theme.fontCaption
				opacity: 0.6
				color: Theme.glassTextPrimary
			}

			// A separator above the buttons, as the design has it: the list
			// scrolls, and without a rule the last row and the footer run
			// together.
			Rectangle {
				width: parent.width
				height: 1
				color: Theme.glassControlBorder
			}

			Item {
				width: parent.width
				height: hidden.height

				DialogButton {
					id: hidden

					anchors.left: parent.left
					text: "Join Hidden Network…"

					// Opens before this closes, for the same reason commit
					// joins before closing.
					onClicked: {
						root.controller?.joinDialog?.askManual();
						root.close();
					}
				}

				Row {
					anchors.right: parent.right
					spacing: Theme.spacingS + 2

					DialogButton {
						text: "Cancel"
						onClicked: root.close()
					}

					DialogButton {
						text: root.picked !== ""
							? `Join ${root.pickedShort}` : "Join"

						enabled: root.picked !== ""

						// Dim glass with faded text until there is something to
						// join, then the bright chip - which needs dark text,
						// so the variant changes with it.
						variant: root.picked !== "" ? "primary" : "secondary"

						onClicked: root.commit()
					}
				}
			}
		}
	}
}
