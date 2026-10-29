import Quickshell
import Quickshell.Io
import QtQuick
import ".."
import "../icons"
import "../ui"

// The bar's clock, and the card it opens: what has arrived, and a month to
// look across.
//
// The card hangs centred under the clock, the one thing in the middle of the
// bar. On the left, the notification centre: everything not yet dealt with,
// newest first, and Do Not Disturb. On the right, the month, which starts on
// the chosen first day of the week and always shows six weeks, so stepping
// from a month that needs five to one that needs six does not resize the
// card under the pointer.
//
// In the bar, a crescent before the time says Do Not Disturb is on, and a
// dot after it that something arrived quietly and has not been looked at.
BarPopup {
	id: root

	// The daemon (Notifications.qml): its list, its toasts, its quiet count.
	property var notifications: null
	readonly property var list: root.notifications?.list ?? []

	// For "5 min ago" to move on while the card is open.
	property real now: Date.now()

	Timer {
		interval: 30000
		repeat: true
		running: root.open
		onTriggered: root.now = Date.now()
	}

	SystemClock {
		id: clock

		precision: SystemClock.Minutes
	}

	// The month on show, as a year and a 0-based month. Opening the card goes
	// back to today's.
	property int year: clock.date.getFullYear()
	property int month: clock.date.getMonth()

	readonly property bool onToday: root.year === clock.date.getFullYear()
		&& root.month === clock.date.getMonth()

	// As chosen in Settings, or the locale's: 0 is Sunday, as getDay() counts.
	readonly property int firstDay: Settings.weekStart ?? Qt.locale().firstDayOfWeek % 7

	function step(months) {
		const d = new Date(root.year, root.month + months, 1);
		root.year = d.getFullYear();
		root.month = d.getMonth();
	}

	function today() {
		root.year = clock.date.getFullYear();
		root.month = clock.date.getMonth();
	}

	// ISO 8601: weeks start on Monday, and week 1 holds the year's first
	// Thursday.
	function isoWeek(date) {
		const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
		const day = d.getUTCDay() || 7;
		d.setUTCDate(d.getUTCDate() + 4 - day);
		const start = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
		return Math.ceil(((d - start) / 86400000 + 1) / 7);
	}

	// Six weeks from the start of the week holding the 1st. Dates are made
	// from their parts, not by adding milliseconds, so a change of clocks
	// does not shift a day.
	readonly property var days: {
		const first = new Date(root.year, root.month, 1);
		const lead = (first.getDay() - root.firstDay + 7) % 7;
		const now = clock.date;
		const out = [];
		for (let i = 0; i < 42; i++) {
			const d = new Date(root.year, root.month, 1 - lead + i);
			out.push({
				day: d.getDate(),
				inMonth: d.getMonth() === root.month,
				today: d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth()
					&& d.getDate() === now.getDate(),
				weekend: d.getDay() === 0 || d.getDay() === 6
			});
		}
		return out;
	}

	name: "clock"
	centred: true
	title: Qt.formatDateTime(clock.date, "dddd d MMMM")
	trailing: "Week " + root.isoWeek(clock.date)

	cardWidth: Theme.clockCardWidth

	onOpenChanged: {
		if (!root.open)
			return;
		root.today();
		root.now = Date.now();
		if (root.notifications !== null)
			root.notifications.missed = 0;
	}

	trigger: Row {
		spacing: 6

		PowerIcon {
			anchors.verticalCenter: parent.verticalCenter
			visible: Settings.doNotDisturb
			width: 12
			height: 12
			kind: "moon"
			color: Theme.glassTextPrimary
		}

		// As chosen in Settings: the date or not, 24 hours or 12.
		Text {
			anchors.verticalCenter: parent.verticalCenter
			text: Qt.formatDateTime(clock.date,
				(Settings.clockDate ? "ddd d MMM " : "") + (Settings.clock24 ? "HH:mm" : "h:mm AP"))
			color: Theme.glass ? Theme.glassTextPrimary : Theme.textPrimary
			style: Theme.glass ? Text.Raised : Text.Normal
			styleColor: Theme.glassTextShadow
		}

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			visible: (root.notifications?.missed ?? 0) > 0
			width: 6
			height: 6
			radius: 3
			color: Theme.glassTextPrimary
		}
	}

	IpcHandler {
		target: "clock"

		function toggle(): void {
			root.open = !root.open;
		}

		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}

		// Months forward (or back, negative) from the one on show.
		function step(months: int): void {
			root.step(months);
		}
	}

	Row {
		width: parent.width
		spacing: Theme.spacingL

		// --- what has arrived ---

		Column {
			id: centre

			width: parent.width - calendar.width - divider.width - parent.spacing * 2
			spacing: Theme.spacingS

			Flickable {
				id: scroller

				width: parent.width
				// As tall as the month at least, so the card keeps its shape
				// when there is little or nothing; taller as the list grows,
				// to a point, then it scrolls.
				height: Math.max(calendar.height - footer.height - centre.spacing,
					Math.min(stack.implicitHeight, Theme.clockListMaxHeight))
				contentHeight: stack.implicitHeight
				clip: true
				boundsBehavior: Flickable.StopAtBounds

				Column {
					id: stack

					width: scroller.width
					spacing: Theme.spacingS

					Repeater {
						model: root.list

						Rectangle {
							id: row

							required property var modelData

							width: stack.width
							height: rowContent.implicitHeight + Theme.spacingM * 2
							radius: Theme.radiusLarge
							color: rowClick.containsMouse ? Theme.glassControlHover : Theme.glassControl

							Behavior on color {
								ColorAnimation { duration: 120 }
							}

							// As on the toast: a click does what it is for, a
							// right-click puts it away.
							//
							// The card closes before the action runs: invoking
							// dismisses the notification, which takes this row
							// away mid-handler, and nothing after it would run.
							MouseArea {
								id: rowClick

								anchors.fill: parent
								hoverEnabled: true
								acceptedButtons: Qt.LeftButton | Qt.RightButton
								onClicked: mouse => {
									const open = row.modelData.actions.find(a => a.identifier === "default");
									if (mouse.button === Qt.RightButton) {
										row.modelData.dismiss();
									} else if (open) {
										root.open = false;
										open.invoke();
									}
								}
							}

							NotificationContent {
								id: rowContent

								anchors {
									left: parent.left
									right: parent.right
									verticalCenter: parent.verticalCenter
									leftMargin: Theme.spacingM
									rightMargin: Theme.spacingM
								}

								notification: row.modelData
								arrived: root.notifications?.arrived[row.modelData.id] ?? 0
								now: root.now
								onCloseClicked: row.modelData.dismiss()
							}
						}
					}
				}

				// Placed by hand: a Flickable's children are its content, which
				// has no height while there is nothing in it.
				Text {
					x: (scroller.width - width) / 2
					y: (scroller.height - height) / 2
					visible: root.list.length === 0
					text: "No notifications"
					font.pixelSize: Theme.fontBody
					color: Theme.glassTextMuted
				}
			}

			Item {
				id: footer

				width: parent.width
				height: Theme.chipHeight

				Row {
					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					spacing: Theme.spacingS

					Switch {
						anchors.verticalCenter: parent.verticalCenter
						checked: Settings.doNotDisturb
						onToggled: Settings.setDoNotDisturb(!checked)
					}

					Text {
						anchors.verticalCenter: parent.verticalCenter
						text: "Do not disturb"
						font.pixelSize: Theme.fontBody
						color: Theme.glassTextPrimary
					}
				}

				Chip {
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					visible: root.list.length > 0
					text: "Clear all"
					onClicked: root.notifications?.clear()
				}
			}
		}

		Rectangle {
			id: divider

			width: 1
			height: centre.height
			color: Theme.glassControlBorder
		}

		// --- the month ---

		Column {
			id: calendar

			readonly property real cell: width / 7

			width: Theme.clockCalendarWidth
			spacing: Theme.spacingS

			// The month, and the way to the next and the last.
			Item {
				width: parent.width
				height: 26

				Text {
					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					text: Qt.locale().standaloneMonthName(root.month, Locale.LongFormat) + " " + root.year
					font.pixelSize: Theme.fontLead
					font.weight: Font.DemiBold
					color: Theme.glassTextPrimary
				}

				Row {
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					spacing: Theme.spacingXs

					Chip {
						anchors.verticalCenter: parent.verticalCenter
						visible: !root.onToday
						height: 26
						text: "Today"
						onClicked: root.today()
					}

					DiscButton {
						width: 26
						height: 26
						glyph: "back"
						onClicked: root.step(-1)
					}

					DiscButton {
						width: 26
						height: 26
						glyph: "back"
						rotation: 180
						onClicked: root.step(1)
					}
				}
			}

			// The days of the week, by their initials.
			Row {
				Repeater {
					model: 7

					Text {
						required property int index

						width: calendar.cell
						horizontalAlignment: Text.AlignHCenter
						text: Qt.locale().dayName((root.firstDay + index) % 7, Locale.NarrowFormat)
						font.pixelSize: Theme.fontCaption
						font.weight: Font.DemiBold
						color: Theme.glassTextMuted
					}
				}
			}

			Grid {
				columns: 7

				Repeater {
					model: root.days

					Item {
						required property var modelData

						width: calendar.cell
						height: 32

						// Today is the one lit lens on the page.
						Lens {
							anchors.centerIn: parent
							width: 28
							height: 28
							sheen: false
							visible: modelData.today
						}

						Text {
							anchors.centerIn: parent
							text: modelData.day
							font.pixelSize: Theme.fontBody
							font.weight: modelData.today ? Font.Bold : Font.Normal
							font.features: { "tnum": 1 }
							color: modelData.today ? Theme.glassTextOnLens
								: modelData.weekend ? Theme.glassTextSecondary
								: Theme.glassTextPrimary
							opacity: modelData.inMonth ? 1 : 0.35
						}
					}
				}

				// A scroll over the month turns it.
				WheelHandler {
					acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
					onWheel: event => {
						wheel.travel += event.angleDelta.y;
						if (Math.abs(wheel.travel) >= 120) {
							root.step(wheel.travel > 0 ? -1 : 1);
							wheel.travel = 0;
						}
					}
				}
			}

			// What a touchpad's small scrolls add up to before they turn a page.
			QtObject {
				id: wheel

				property real travel: 0
			}
		}
	}
}
