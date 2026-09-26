import QtQuick
import QtQuick.Shapes
import ".."

// A sphere of glass catching light: off-centre highlight, radial falloff, and
// a sheen that sweeps across it.
//
// The slider's knob and the dialogs' icon disc are the same object at
// different sizes, so it lives here rather than in either of them.
Item {
	id: lens

	// The sweep is right on a control you are dragging, and a distraction on a
	// static icon.
	property bool sheen: true

	// Flat glass instead of a sphere. The design's device list uses the lit
	// lens for the picked row and this for the rest, so the disc carries the
	// selection as much as the row's fill does - which only works if both are
	// the same disc.
	property bool plain: false

	// A coloured sphere instead of a white one. The launcher tints each
	// application's disc from its name, so any icon theme - or none - reads
	// as one set.
	property color tint: "transparent"
	readonly property bool tinted: tint.a > 0

	default property alias content: overlay.data

	implicitWidth: Theme.sliderKnobSize
	implicitHeight: Theme.sliderKnobSize

	property real sheenPos: 0.5

	RadialGradient {
		id: sphere

		centerX: lens.width * 0.35
		centerY: lens.height * 0.30
		centerRadius: lens.width * 0.8
		focalX: lens.width * 0.35
		focalY: lens.height * 0.30

		GradientStop { position: 0.0; color: lens.tinted ? "#ffffff" : Theme.glassKnobCore }
		GradientStop { position: lens.tinted ? 0.5 : 0.45; color: lens.tinted ? Qt.lighter(lens.tint, 1.3) : Theme.glassKnobMid }
		GradientStop { position: 1.0; color: lens.tinted ? lens.tint : Theme.glassKnobRim }
	}

	Shape {
		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer

		ShapePath {
			strokeColor: lens.plain
				? Theme.glassTrackBorder : Theme.glassKnobEdge
			strokeWidth: 1

			fillColor: lens.plain ? Theme.glassTrack : "transparent"

			// Proportional, so the highlight stays in the same place whatever
			// size the lens is drawn at.
			fillGradient: lens.plain ? null : sphere
			PathAngleArc {
				centerX: lens.width / 2
				centerY: lens.height / 2
				radiusX: lens.width / 2 - 1
				radiusY: lens.height / 2 - 1
				startAngle: 0
				sweepAngle: 360
			}
		}
	}

	// `inset -3px -4px 8px rgba(0,0,0,.12)` and `inset 2px 3px 6px
	// rgba(255,255,255,.8)`: shading on the inside of the sphere, dark where
	// it turns away from the light and bright where it faces it. Without these
	// the radial fill alone reads as a pale disc.
	//
	// Both are radial gradients offset from centre, clipped to the lens by
	// being circles themselves.
	Rectangle {
		anchors.fill: parent
		radius: width / 2
		rotation: 315
		visible: !lens.plain

		gradient: Gradient {
			orientation: Gradient.Horizontal

			GradientStop { position: 0.0; color: "#00000000" }
			GradientStop { position: 0.62; color: "#00000000" }
			GradientStop { position: 1.0; color: Theme.glassLensShade }
		}
	}

	Rectangle {
		anchors.fill: parent
		radius: width / 2
		rotation: 315
		visible: !lens.plain

		gradient: Gradient {
			orientation: Gradient.Horizontal

			GradientStop { position: 0.0; color: Theme.glassLensGlow }
			GradientStop { position: 0.28; color: "#00ffffff" }
			GradientStop { position: 1.0; color: "#00ffffff" }
		}
	}

	// A rotated circle clips the sweeping band to the lens for free - a
	// rotated circle is still a circle, so no mask is needed.
	Rectangle {
		anchors.fill: parent
		radius: width / 2
		rotation: 115
		opacity: 0.9
		visible: lens.sheen && !lens.plain

		gradient: Gradient {
			orientation: Gradient.Horizontal

			GradientStop {
				position: Math.max(0, lens.sheenPos - 0.22)
				color: "#00ffffff"
			}
			GradientStop {
				position: lens.sheenPos
				color: Theme.glassSheen
			}
			GradientStop {
				position: Math.min(1, lens.sheenPos + 0.22)
				color: "#00ffffff"
			}
		}
	}

	SequentialAnimation {
		running: lens.sheen && !lens.plain && lens.visible
		loops: Animation.Infinite

		NumberAnimation {
			target: lens; property: "sheenPos"
			from: 0.18; to: 0.82
			duration: 2000; easing.type: Easing.InOutSine
		}
		NumberAnimation {
			target: lens; property: "sheenPos"
			from: 0.82; to: 0.18
			duration: 2000; easing.type: Easing.InOutSine
		}
	}

	// Declared last, so a glyph sits on top of the glass.
	Item {
		id: overlay

		anchors.fill: parent
	}
}
