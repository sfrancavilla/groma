import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Shapes

// The bar's volume readout, and the control-center tile it opens.
//
// Layout follows the "Refractive lens knob" design: a 44px track the knob sits
// inside rather than on, and a lens that reads as a sphere catching light.
Item {
	id: root

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property bool ready: root.sink?.ready && root.sink?.audio
	readonly property bool muted: root.ready && root.sink.audio.muted
	readonly property real volume: root.ready ? root.sink.audio.volume : 0

	// Output devices, so the chips at the bottom of the tile are real.
	readonly property var sinks: Pipewire.nodes.values.filter(
		node => node.isSink && !node.isStream)

	property bool open: false

	implicitWidth: label.implicitWidth
	implicitHeight: label.implicitHeight

	// Descriptions are only populated for tracked nodes.
	PwObjectTracker {
		objects: root.sinks
	}

	Text {
		id: label

		anchors.centerIn: parent
		color: root.muted ? Theme.glassTextMuted : Theme.glassTextPrimary
		style: Theme.glass ? Text.Raised : Text.Normal
		styleColor: Theme.glassTextShadow

		text: !root.ready ? "Vol --"
			: root.muted ? "Muted"
			: "Vol " + Math.round(root.volume * 100) + "%"

		opacity: trigger.containsMouse || root.open ? 1.0 : 0.85

		Behavior on opacity {
			NumberAnimation { duration: 120 }
		}
	}

	MouseArea {
		id: trigger

		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton

		onClicked: mouse => {
			if (mouse.button === Qt.MiddleButton)
				root.sink.audio.muted = !root.sink.audio.muted;
			else
				root.open = !root.open;
		}

		onWheel: wheel => {
			if (!root.ready)
				return;

			const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
			root.sink.audio.volume = Math.max(0, Math.min(1, root.volume + step));
		}
	}

	// A client only receives input on its own surfaces, so "click outside" has
	// to be a surface. This one exists purely to catch that click.
	PanelWindow {
		visible: root.open

		anchors {
			top: true
			bottom: true
			left: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Top
		WlrLayershell.namespace: "groma:volume-catcher"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		MouseArea {
			anchors.fill: parent
			onClicked: root.open = false
		}
	}

	PanelWindow {
		id: panel

		// Stays mapped until the closing animation has finished.
		visible: root.open || card.opacity > 0.01

		anchors {
			top: true
			right: true
		}

		exclusionMode: ExclusionMode.Ignore
		margins {
			top: 40
			right: 8
		}

		readonly property int pad: Theme.glass ? Theme.glassShadowPadding : 0

		implicitWidth: 300 + panel.pad * 2
		implicitHeight: content.implicitHeight + 28 + panel.pad * 2
		color: "transparent"

		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.namespace: "groma:volume"
		WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

		BackgroundEffect.blurRegion: Region {
			item: card
			radius: Theme.radiusPanel
		}

		GlassPanel {
			id: card

			anchors.fill: parent
			anchors.margins: panel.pad
			radius: Theme.radiusPanel

			// Opacity, scale and y on different curves, so it reads as one
			// movement settling rather than three separate effects.
			opacity: root.open ? 1 : 0
			scale: root.open ? 1 : 0.96
			y: root.open ? 0 : -6

			Behavior on opacity {
				NumberAnimation { duration: 180; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1]; easing.type: Easing.Bezier }
			}
			Behavior on scale {
				NumberAnimation { duration: 180; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1]; easing.type: Easing.Bezier }
			}
			Behavior on y {
				NumberAnimation { duration: 180; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1]; easing.type: Easing.Bezier }
			}

			Column {
				id: content

				anchors {
					left: parent.left
					right: parent.right
					top: parent.top
					leftMargin: 14
					rightMargin: 14
					topMargin: 14
				}

				spacing: 12

				// Header: what this is, and what it is coming out of.
				Item {
					width: parent.width
					height: title.implicitHeight

					Text {
						id: title

						anchors.left: parent.left
						text: "Sound"
						font.pixelSize: 12
						font.bold: true
						color: Theme.glassTextPrimary
					}

					Text {
						anchors.right: parent.right
						width: parent.width - title.width - 12
						horizontalAlignment: Text.AlignRight
						elide: Text.ElideRight
						text: root.sink?.description ?? root.sink?.nickname ?? ""
						font.pixelSize: 12
						font.weight: Font.DemiBold
						opacity: 0.8
						color: Theme.glassTextPrimary
					}
				}

				// The track. The knob sits inside it, not on top of it, which
				// is what makes this read as a control rather than a meter.
				Rectangle {
					id: track

					// The knob travels between the insets rather than across
					// the full width, so it never overhangs either end. The
					// fill then runs to the knob's centre, not to the raw
					// percentage - otherwise the track's edge cuts through the
					// middle of the lens at full volume.
					readonly property int knobSize: 40
					readonly property int inset: 2
					readonly property real travel:
						width - track.knobSize - track.inset * 2

					width: parent.width
					height: 44
					radius: height / 2
					color: Theme.glassTrack
					border.width: 1
					border.color: Theme.glassTrackBorder
					clip: true

					Rectangle {
						id: fill

						anchors {
							left: parent.left
							top: parent.top
							bottom: parent.bottom
						}

						width: knob.x + knob.width / 2
						radius: track.radius
						color: Theme.glassTrackFill

						Behavior on width {
							enabled: !drag.pressed
							NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
						}
					}

					SpeakerIcon {
						anchors {
							left: parent.left
							leftMargin: 16
							verticalCenter: parent.verticalCenter
						}

						color: Theme.glassTextPrimary
						waves: root.muted ? 0 : root.volume > 0.5 ? 2 : 1
					}

					Text {
						anchors {
							right: parent.right
							rightMargin: 16
							verticalCenter: parent.verticalCenter
						}

						text: root.muted ? "Muted" : Math.round(root.volume * 100)
						font.pixelSize: 12
						font.bold: true
						color: Theme.glassTextPrimary
					}

					// The lens.
					Item {
						id: knob

						property real sheenPos: 0.5

						width: track.knobSize
						height: track.knobSize
						x: track.inset + root.volume * track.travel
						anchors.verticalCenter: parent.verticalCenter

						Behavior on x {
							enabled: !drag.pressed
							NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
						}

						scale: drag.pressed ? 1.06 : drag.containsMouse ? 1.03 : 1.0

						Behavior on scale {
							NumberAnimation { duration: 120; easing.type: Easing.OutBack }
						}

						// A sphere, not a disc: the highlight is off-centre and
						// the falloff is radial, so it catches light on one side.
						Shape {
							anchors.fill: parent
							preferredRendererType: Shape.CurveRenderer

							ShapePath {
								strokeColor: Theme.glassKnobEdge
								strokeWidth: 1

								fillGradient: RadialGradient {
									centerX: 14; centerY: 12; centerRadius: 32
									focalX: 14; focalY: 12

									GradientStop { position: 0.0; color: Theme.glassKnobCore }
									GradientStop { position: 0.45; color: Theme.glassKnobMid }
									GradientStop { position: 1.0; color: Theme.glassKnobRim }
								}

								PathAngleArc {
									centerX: 20; centerY: 20
									radiusX: 19; radiusY: 19
									startAngle: 0; sweepAngle: 360
								}
							}
						}

						// The sheen. A rotated circle clips the sweeping band to
						// the lens for free - rotating a circle leaves a circle,
						// so no mask is needed.
						Rectangle {
							anchors.fill: parent
							radius: width / 2
							rotation: 115
							opacity: 0.9

							gradient: Gradient {
								orientation: Gradient.Horizontal

								GradientStop {
									position: Math.max(0, knob.sheenPos - 0.22)
									color: "#00ffffff"
								}
								GradientStop {
									position: knob.sheenPos
									color: Theme.glassSheen
								}
								GradientStop {
									position: Math.min(1, knob.sheenPos + 0.22)
									color: "#00ffffff"
								}
							}
						}

						SequentialAnimation {
							running: panel.visible
							loops: Animation.Infinite

							NumberAnimation {
								target: knob; property: "sheenPos"
								from: 0.18; to: 0.82
								duration: 2000; easing.type: Easing.InOutSine
							}
							NumberAnimation {
								target: knob; property: "sheenPos"
								from: 0.82; to: 0.18
								duration: 2000; easing.type: Easing.InOutSine
							}
						}
					}

					MouseArea {
						id: drag

						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor

						// The pointer grabs the centre of the lens, so undo the
						// same inset the knob's position applies.
						function setFromX(x) {
							if (!root.ready || track.travel <= 0)
								return;

							const v = (x - track.inset - track.knobSize / 2)
								/ track.travel;

							root.sink.audio.volume = Math.max(0, Math.min(1, v));
						}

						onPressed: mouse => drag.setFromX(mouse.x)
						onPositionChanged: mouse => {
							if (drag.pressed)
								drag.setFromX(mouse.x);
						}
					}
				}

				// Output devices. One chip each; the active one is brighter.
				Row {
					width: parent.width
					spacing: 8
					visible: root.sinks.length > 0

					Repeater {
						model: root.sinks

						Rectangle {
							id: chip

							required property var modelData
							readonly property bool active:
								chip.modelData === Pipewire.defaultAudioSink

							width: (content.width - (root.sinks.length - 1) * 8)
								/ Math.max(1, root.sinks.length)
							height: 29
							radius: Theme.radiusPill

							color: chip.active ? Theme.glassChipActive
								: chipMouse.containsMouse ? Theme.glassControlHover
								: Theme.glassChip

							Behavior on color {
								ColorAnimation { duration: 120 }
							}

							Text {
								anchors {
									fill: parent
									leftMargin: 8
									rightMargin: 8
								}

								horizontalAlignment: Text.AlignHCenter
								verticalAlignment: Text.AlignVCenter
								elide: Text.ElideRight
								text: chip.modelData.description
									?? chip.modelData.nickname ?? "Output"
								font.pixelSize: 11
								font.bold: chip.active
								opacity: chip.active ? 1.0 : 0.8
								color: Theme.glassTextPrimary
							}

							MouseArea {
								id: chipMouse

								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: Pipewire.preferredDefaultAudioSink = chip.modelData
							}
						}
					}
				}
			}
		}
	}

	IpcHandler {
		target: "volume"

		function toggle(): void {
			root.open = !root.open;
		}

		// Not named show/hide: `show` collides with the `qs ipc show`
		// subcommand, and the call silently lists the functions instead.
		function opened(): void {
			root.open = true;
		}

		function closed(): void {
			root.open = false;
		}

		function set(percent: string): void {
			if (!root.ready)
				return;

			root.sink.audio.volume =
				Math.max(0, Math.min(1, parseFloat(percent) / 100));
		}
	}
}
