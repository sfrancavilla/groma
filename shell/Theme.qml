pragma Singleton

import Quickshell
import QtQuick

// Every colour and corner radius the shell uses, in one place.
//
// The names describe the *role* a value plays, not the colour it happens to be.
// `danger` rather than `red`, `surface` rather than `white`. That is what makes
// a second theme a matter of changing this file rather than editing every
// component - a component asking for `Theme.danger` keeps working when danger
// stops being red.
Singleton {
	// Surfaces, lightest to darkest.
	readonly property color surface: "#ffffff"
	readonly property color surfaceSunken: "#f2f2f2"
	readonly property color surfaceHover: "#dddddd"
	readonly property color surfaceStrong: "#444444"
	readonly property color surfaceStrongHover: "#222222"

	// The dim behind a modal dialog. Deliberately includes alpha.
	readonly property color scrim: "#99000000"

	// Borders.
	readonly property color border: "#cccccc"
	readonly property color borderSubtle: "#dddddd"
	readonly property color borderFocus: "#444444"

	// Text. `onStrong` is for text sitting on a strong surface.
	readonly property color textPrimary: "#000000"
	readonly property color textSecondary: "#333333"
	readonly property color textMuted: "#888888"
	readonly property color textOnStrong: "#ffffff"

	// Status. One red, used everywhere something is wrong.
	readonly property color danger: "#cc3333"

	// --- Liquid glass (experimental) ---
	//
	// The blur behind these surfaces is done by the compositor; everything
	// here is what we draw on top of it. Apple's version also refracts the
	// backdrop at the edges, which we cannot do: a Wayland client cannot read
	// the pixels behind its own surface. The gradient and the bright border
	// below are standing in for that lensing.
	readonly property bool glass: true

	// Tint and opacity are kept separate so the transparency can be tuned
	// without picking new hex values. This matters: at 80% opacity the card was
	// a grey box, because only a fifth of the blurred backdrop came through.
	// Glass should take its colour from what is behind it, which means most of
	// what you see has to actually be what is behind it.
	//
	// The tint is near-black rather than grey. Its job is to darken whatever
	// shows through for contrast, not to add a colour of its own.
	readonly property color glassTint: "#101018"
	readonly property real glassOpacityTop: 0.46
	readonly property real glassOpacityBottom: 0.30

	// Two stops rather than one flat fill - the sheen is what stops it
	// reading as "a dark box with some transparency".
	readonly property color glassSurfaceTop: Qt.rgba(
		glassTint.r, glassTint.g, glassTint.b, glassOpacityTop)
	readonly property color glassSurfaceBottom: Qt.rgba(
		glassTint.r, glassTint.g, glassTint.b, glassOpacityBottom)

	// Controls on glass - buttons, input fields - are lighter films over the
	// pane rather than their own opaque surfaces. Opaque controls on a
	// translucent panel look pasted on.
	readonly property color glassControl: Qt.rgba(1, 1, 1, 0.10)
	readonly property color glassControlHover: Qt.rgba(1, 1, 1, 0.18)
	readonly property color glassControlStrong: Qt.rgba(1, 1, 1, 0.22)
	readonly property color glassControlStrongHover: Qt.rgba(1, 1, 1, 0.32)
	readonly property color glassControlBorder: Qt.rgba(1, 1, 1, 0.20)

	// With the fill that transparent, text needs its own contrast rather than
	// relying on the surface to provide it.
	readonly property color glassTextShadow: "#b3000000"
	// The edge is not a stroke. A uniform 1px outline is the most obviously
	// drawn thing about a glass panel; a real one catches light along one side
	// and disappears along the rest. These are the stops of that falloff.
	readonly property int glassRimWidth: 1
	readonly property color glassRimTop: "#73ffffff"
	readonly property color glassRimMid: "#26ffffff"
	readonly property color glassRimBottom: "#0affffff"

	// An ambient shadow, drawn as concentric rings of decreasing opacity
	// rather than one hard outline. Cheap approximation of a feathered edge:
	// no shader, and the falloff is what stops the silhouette looking cut out.
	readonly property int glassShadowLayers: 4
	readonly property real glassShadowAlpha: 0.13
	// Room the window must leave around a card for the shadow to bleed into.
	readonly property int glassShadowPadding: 6

	// Same idea, tinted, so an urgent card still reads as urgent.
	readonly property color glassRimDangerTop: "#e6cc3333"
	readonly property color glassRimDangerMid: "#80cc3333"
	readonly property color glassRimDangerBottom: "#33cc3333"

	readonly property color glassTextPrimary: "#ffffff"
	readonly property color glassTextSecondary: "#d9ffffff"
	readonly property color glassTextMuted: "#8cffffff"

	// Values taken from the "Refractive lens knob" design: a track the knob
	// sits inside rather than on, a fill brighter than the track, and a lens
	// that is a sphere catching light rather than a flat dot.
	readonly property color glassTrack: Qt.rgba(1, 1, 1, 0.14)
	readonly property color glassTrackBorder: Qt.rgba(1, 1, 1, 0.25)
	readonly property color glassTrackFill: Qt.rgba(1, 1, 1, 0.40)

	readonly property color glassKnobCore: Qt.rgba(1, 1, 1, 0.95)
	readonly property color glassKnobMid: Qt.rgba(1, 1, 1, 0.55)
	readonly property color glassKnobRim: Qt.rgba(1, 1, 1, 0.25)
	readonly property color glassKnobEdge: Qt.rgba(1, 1, 1, 0.70)
	readonly property color glassSheen: Qt.rgba(1, 1, 1, 0.80)

	readonly property color glassChip: Qt.rgba(1, 1, 1, 0.10)
	readonly property color glassChipActive: Qt.rgba(1, 1, 1, 0.28)

	// Corner radii, by element size.
	readonly property int radiusSmall: 6
	readonly property int radiusMedium: 10
	readonly property int radiusLarge: 12
	readonly property int radiusPill: 12
	readonly property int radiusPanel: 24
}
