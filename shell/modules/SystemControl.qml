import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's load readout, and the tile it opens: processor, graphics,
// memory and disk, each as how much is in use.
//
// The figures come from system-worker.py, kept alive for as long as the
// shell runs, because the glyph in the bar shows them too. It reads every
// three seconds, and every second while the tile is open.
BarPopup {
	id: root

	// Past these, a figure is worth a colour. The processor is judged by its
	// temperature, not its load: a build pinning every core is the machine
	// doing its job, a die near its limit is not.
	readonly property real memoryHigh: 0.90
	readonly property real diskHigh: 0.90
	readonly property real hotCelsius: 90

	// The last reading, or null until the first one arrives.
	property var reading: null
	readonly property bool ready: root.reading !== null

	readonly property real cpu: root.reading?.cpu ?? 0
	readonly property real memory: root.ready && root.reading.memTotal > 0
		? root.reading.memUsed / root.reading.memTotal : 0
	readonly property var disks: (root.reading?.disks ?? []).map(d => Object.assign({
		used: d.size > 0 ? 1 - d.free / d.size : 0
	}, d))
	// The fullest disk speaks for all of them in the bar.
	readonly property real disk: Math.max(0, ...root.disks.map(d => d.used))

	readonly property bool hot: (root.reading?.temperature ?? 0) >= root.hotCelsius
	readonly property bool memoryFull: root.memory >= root.memoryHigh
	readonly property bool diskFull: root.disk >= root.diskHigh

	// A number of gigabytes, without the unit: a pair of them shares one,
	// "8.8 of 30.6 GB", which keeps a detail short enough not to elide.
	function gb(bytes) {
		const gb = bytes / 1024 / 1024 / 1024;
		return gb >= 100 ? String(Math.round(gb)) : gb.toFixed(1);
	}

	function celsius(value) {
		return value === null || value === undefined ? "" : Math.round(value) + " °C";
	}

	readonly property var rows: {
		if (!root.ready)
			return [];

		const r = root.reading;
		const rows = [{
			label: "Processor",
			icon: "cpu",
			detail: [root.celsius(r.temperature), r.threads + " threads"]
				.filter(s => s !== "").join(" · "),
			value: root.cpu,
			alert: root.hot
		}];

		// amdgpu says how busy it is; Intel and nouveau do not, and a row
		// that always reads 0% would be a lie.
		if (r.gpu !== null)
			rows.push({
				label: "Graphics",
				icon: "gpu",
				detail: root.celsius(r.gpuTemperature),
				value: r.gpu,
				alert: false
			});

		rows.push({
			label: "Memory",
			icon: "memory",
			detail: root.gb(r.memUsed) + " of " + root.gb(r.memTotal) + " GB",
			value: root.memory,
			alert: root.memoryFull
		});

		if (r.swapTotal > 0)
			rows.push({
				label: "Swap",
				icon: "swap",
				detail: root.gb(r.swapUsed) + " of " + root.gb(r.swapTotal) + " GB",
				value: r.swapUsed / r.swapTotal,
				alert: false
			});

		// One disk is "Disk". Only a /home of its own makes two, and then
		// each needs saying which.
		for (const d of root.disks)
			rows.push({
				label: root.disks.length === 1 ? "Disk"
					: d.mount === "/" ? "System disk" : "Home disk",
				icon: "disk",
				detail: root.gb(d.free) + " of " + root.gb(d.size) + " GB free",
				value: d.used,
				alert: d.used >= root.diskHigh
			});

		return rows;
	}

	name: "system"
	title: "System"
	cardWidth: Theme.tileWidthWide

	// What is wrong, if anything is; otherwise how busy the last minute was.
	trailing: !root.ready ? ""
		: root.hot ? "Running hot"
		: root.memoryFull ? "Memory nearly full"
		: root.diskFull ? "Disk nearly full"
		: "Load " + root.reading.load[0].toFixed(2)
	trailingColor: root.hot || root.memoryFull || root.diskFull
		? Theme.warning : Theme.glassTextPrimary

	trigger: LoadIcon {
		height: Theme.barIconSize
		width: height * aspect

		values: [root.cpu, root.memory, root.disk]
		alerts: [root.hot, root.memoryFull, root.diskFull]
		color: root.ready ? Theme.glassTextPrimary : Theme.glassTextMuted

		opacity: root.active ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}
	}

	// Looked at, it reads faster; the next reading comes at once.
	onOpenChanged: if (worker.running) worker.write((root.open ? "1" : "3") + "\n")

	Process {
		id: worker

		command: ["python3", `${Quickshell.shellDir}/modules/system-worker.py`]
		stdinEnabled: true

		// Started here rather than bound: a binding on `running` is broken
		// the first time the process exits on its own, and then it never
		// comes back.
		Component.onCompleted: worker.running = true
		onExited: reviveWorker.start()

		stdout: SplitParser {
			onRead: line => {
				try {
					root.reading = JSON.parse(line);
				} catch (e) {
					console.warn("System worker:", line);
				}
			}
		}

		stderr: SplitParser {
			onRead: line => console.warn("System worker:", line)
		}
	}

	Timer {
		id: reviveWorker

		interval: 2000
		onTriggered: if (!worker.running) worker.running = true
	}

	IpcHandler {
		target: "system"

		function toggle(): void {
			root.open = !root.open;
		}

		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}
	}

	Column {
		width: parent.width
		spacing: 0

		Text {
			width: parent.width
			visible: !root.ready
			text: "Reading…"
			font.pixelSize: Theme.fontCaption
			opacity: 0.75
			color: Theme.glassTextPrimary
		}

		Repeater {
			model: root.rows

			Item {
				id: row

				required property var modelData
				required property int index

				// A rule above every part but the first, drawn as the power
				// card draws the one between its two groups.
				readonly property real ruleSpace: row.index > 0 ? 9 : 0
				readonly property real rowHeight: 48

				width: parent.width
				height: row.rowHeight + row.ruleSpace

				// Dashed: it separates readings rather than groups, and a
				// solid rule under every row read as a table's grid.
				Row {
					visible: row.index > 0
					y: 4
					x: 8
					width: parent.width - 16
					spacing: 3

					Repeater {
						model: Math.floor((parent.width + 3) / 7)

						Rectangle {
							width: 4
							height: 1
							color: Theme.glassControlBorder
						}
					}
				}

				// The part, drawn straight on the card: a disc round each one
				// was four buttons that did nothing.
				Item {
					id: mark

					// The mark starts 3 units into its 24, so this puts its
					// left edge where the rules start.
					x: 5
					y: row.ruleSpace + (row.rowHeight - height) / 2
					width: 24
					height: 24

					HardwareIcon {
						anchors.fill: parent
						kind: row.modelData.icon
						color: Theme.glassTextPrimary
						opacity: 0.4
					}
				}

				Column {
					anchors {
						left: mark.right
						leftMargin: Theme.spacingM
						right: meter.left
						rightMargin: Theme.spacingS
						verticalCenter: mark.verticalCenter
					}

					spacing: 2

					Text {
						text: row.modelData.label
						font.pixelSize: Theme.fontTitle
						font.weight: Font.DemiBold
						color: Theme.glassTextPrimary
					}

					Text {
						width: parent.width
						visible: text !== ""
						elide: Text.ElideRight
						text: row.modelData.detail
						font.pixelSize: Theme.fontBody
						opacity: 0.75
						color: Theme.glassTextPrimary
					}
				}

				Row {
					id: meter

					anchors {
						right: parent.right
						rightMargin: 4
						verticalCenter: mark.verticalCenter
					}

					spacing: Theme.spacingS

					// Wide enough for "100%", so the tracks line up whatever
					// the figures beside them.
					Text {
						anchors.verticalCenter: parent.verticalCenter
						width: 40
						horizontalAlignment: Text.AlignRight
						text: Math.round(row.modelData.value * 100) + "%"
						font.pixelSize: Theme.fontTitle
						font.features: { "tnum": 1 }
						color: row.modelData.alert ? Theme.warning : Theme.glassTextPrimary
					}

					LevelPill {
						anchors.verticalCenter: parent.verticalCenter
						width: 104
						value: row.modelData.value
						fillColor: row.modelData.alert
							? Theme.glassFillWarning : Theme.glassTrackFill
					}
				}
			}
		}
	}
}
