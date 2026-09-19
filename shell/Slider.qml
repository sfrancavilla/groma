import QtQuick
import QtQuick.Shapes

// The shell's slider: a track the lens sits inside, not on.
//
// Extracted from the volume tile so brightness, and anything else with a 0..1
// value, gets the same control rather than a lookalike. Anything declared
// inside a Slider is laid over the track - an icon on the left, a readout on
// the right.
Rectangle {
	id: control

	// 0..1. The caller owns the value: `moved` reports a drag, and it is up to
	// the caller to write it somewhere and feed it back. That keeps the slider
	// honest about what it is showing - the real state, not a local guess.
	property real value: 0
	signal moved(real value)

	// Off dims the fill without disabling the control, for mute and the like.
	property bool active: true
	// A readout rather than a control: battery is shown, not set.
	property bool interactive: true
	// The fill carries state through its tint - charging, low, normal.
	property color fillColor: Theme.glassTrackFill
	// A band travelling along the fill, for something in progress.
	property bool shimmer: false

	// Anything to place inside the lens itself, such as a charging bolt.
	property alias knobContent: knobOverlay.data

	// Where the lens currently is, in track coordinates. Content laid over the
	// track draws above the lens, so a label the lens has reached has to know
	// to switch to a colour that reads against it.
	readonly property real knobLeft: knob.x
	readonly property real knobRight: knob.x + knob.width
	// Suppressed while a panel is opening, where the first layout would
	// otherwise animate from zero.
	property bool animateValue: true

	default property alias content: overlay.data

	readonly property int knobSize: Theme.sliderKnobSize
	readonly property int inset: Theme.sliderInset
	readonly property real travel: width - control.knobSize - control.inset * 2

	implicitHeight: Theme.sliderHeight
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

		width: Math.min(control.width,
			knob.x + knob.width / 2 + Theme.sliderKnobBias)
		radius: control.radius
		color: control.fillColor
		opacity: control.active ? 1.0 : 0.5

		Behavior on color {
			ColorAnimation { duration: 200 }
		}

		// Travels along the filled part only, so it reads as the fill
		// advancing rather than as a highlight on the whole track.
		Rectangle {
			id: shimmer

			property real pos: 0.5

			anchors.fill: parent
			radius: parent.radius
			visible: control.shimmer

			gradient: Gradient {
				orientation: Gradient.Horizontal

				GradientStop {
					position: Math.max(0, shimmer.pos - 0.3)
					color: "#00ffffff"
				}
				GradientStop {
					position: shimmer.pos
					color: Qt.rgba(1, 1, 1, 0.35)
				}
				GradientStop {
					position: Math.min(1, shimmer.pos + 0.3)
					color: "#00ffffff"
				}
			}

			SequentialAnimation {
				running: shimmer.visible
				loops: Animation.Infinite

				NumberAnimation {
					target: shimmer; property: "pos"
					from: 0.0; to: 1.0
					duration: 2400; easing.type: Easing.InOutSine
				}
			}
		}

		Behavior on width {
			enabled: control.animateValue && !drag.pressed
			NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
		}
	}

	Item {
		id: knob

		property real sheenPos: 0.5

		width: control.knobSize
		height: control.knobSize
		x: control.inset + control.value * control.travel
		anchors.verticalCenter: parent.verticalCenter

		Behavior on x {
			enabled: control.animateValue && !drag.pressed
			NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
		}

		scale: !control.interactive ? 1.0
			: drag.pressed ? 1.06
			: drag.containsMouse ? 1.03
			: 1.0

		Behavior on scale {
			NumberAnimation { duration: 120; easing.type: Easing.OutBack }
		}

		// A sphere, not a disc: the highlight is off-centre and the falloff is
		// radial, so it catches light on one side.
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

		// The sheen. A rotated circle clips the sweeping band to the lens for
		// free - a rotated circle is still a circle, so no mask is needed.
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

		// Declared after the lens so it draws on top of it.
		Item {
			id: knobOverlay

			anchors.fill: parent
		}

		SequentialAnimation {
			running: control.visible
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

	// Declared after the lens, so content laid over the track is not hidden by
	// it when the two meet.
	Item {
		id: overlay

		anchors.fill: parent
	}

	MouseArea {
		id: drag

		anchors.fill: parent
		enabled: control.interactive
		hoverEnabled: control.interactive
		cursorShape: control.interactive
			? Qt.PointingHandCursor : Qt.ArrowCursor

		// The pointer grabs the centre of the lens, so undo the same inset the
		// knob's position applies.
		function report(x) {
			if (control.travel <= 0)
				return;

			const v = (x - control.inset - control.knobSize / 2) / control.travel;
			control.moved(Math.max(0, Math.min(1, v)));
		}

		onPressed: mouse => drag.report(mouse.x)
		onPositionChanged: mouse => {
			if (drag.pressed)
				drag.report(mouse.x);
		}
	}
}
