import QtQuick
import QtQuick.Shapes

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

	default property alias content: overlay.data

	implicitWidth: Theme.sliderKnobSize
	implicitHeight: Theme.sliderKnobSize

	property real sheenPos: 0.5

	Shape {
		anchors.fill: parent
		preferredRendererType: Shape.CurveRenderer

		ShapePath {
			strokeColor: Theme.glassKnobEdge
			strokeWidth: 1

			// Proportional, so the highlight stays in the same place whatever
			// size the lens is drawn at.
			fillGradient: RadialGradient {
				centerX: lens.width * 0.35
				centerY: lens.height * 0.30
				centerRadius: lens.width * 0.8
				focalX: lens.width * 0.35
				focalY: lens.height * 0.30

				GradientStop { position: 0.0; color: Theme.glassKnobCore }
				GradientStop { position: 0.45; color: Theme.glassKnobMid }
				GradientStop { position: 1.0; color: Theme.glassKnobRim }
			}

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

	// A rotated circle clips the sweeping band to the lens for free - a
	// rotated circle is still a circle, so no mask is needed.
	Rectangle {
		anchors.fill: parent
		radius: width / 2
		rotation: 115
		opacity: 0.9
		visible: lens.sheen

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
		running: lens.sheen && lens.visible
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
