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

	// The dim behind a modal dialog. With the desktop blurred behind it, far
	// less dimming is needed; without glass, it has to carry the job alone.
	readonly property color scrim: glass ? Qt.rgba(0, 0, 0, 0.28) : "#99000000"

	// Borders.
	readonly property color border: "#cccccc"
	readonly property color borderSubtle: "#dddddd"
	readonly property color borderFocus: "#444444"

	// Text. `onStrong` is for text sitting on a strong surface.
	readonly property color textPrimary: "#000000"
	readonly property color textSecondary: "#333333"
	readonly property color textMuted: "#888888"
	readonly property color textOnStrong: "#ffffff"

	// Status. One of each, used everywhere that state occurs.
	readonly property color danger: "#cc3333"
	readonly property color warning: "#f5b942"
	readonly property color success: "#4ade80"

	// --- Desktop ---
	//
	// The backdrop the glass is tinted by. Approximations of the design's
	// oklch mesh: a dark blue base with a green wash top-left and a violet one
	// bottom-right.
	// Converted from the design's oklch rather than matched by eye. The base
	// is a deep teal, not a mid grey-blue: oklch(0.3 0.05 230) is much darker
	// than it looks written down, and everything sitting on it was lifted
	// because of it.
	readonly property color desktopBase: "#0d3242"          // oklch(0.30 0.05 230)
	readonly property color desktopWashA: "#9cc86c"         // oklch(0.78 0.13 130)
	readonly property color desktopWashB: "#886de9"         // oklch(0.62 0.18 290)

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
	// White, as in the design. This only works with something behind it - see
	// Wallpaper.qml. White glass over an empty dark desktop is grey.
	readonly property color glassTint: "#ffffff"
	readonly property real glassOpacityTop: 0.14
	readonly property real glassOpacityBottom: 0.10

	// Flat, as in the design. An earlier version graded this from lighter at
	// the top to darker at the bottom, which is what made panels read as
	// "white at the top, grey underneath" rather than as one surface.
	readonly property color glassSurface: Qt.rgba(
		glassTint.r, glassTint.g, glassTint.b, glassOpacityTop)

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
	// A uniform edge, as in the design: `1px solid rgba(255,255,255,.32)`.
	// Grading it top-to-bottom seemed more like real glass, and was in fact
	// the second half of the "white at the top, grey underneath" problem.
	readonly property color glassEdge: Qt.rgba(1, 1, 1, 0.32)
	readonly property color glassEdgeDanger:
		Qt.rgba(danger.r, danger.g, danger.b, 0.70)

	// The design floats its panels on `0 16px 40px rgba(0,0,0,.30)`: a wide,
	// offset, blurred shadow. This approximates it with concentric rings whose
	// opacity falls off on a curve - enough of them, over enough distance, to
	// read as a gradient rather than as an outline.
	//
	// A real gaussian would mean MultiEffect, which renders the panel to an
	// offscreen texture every frame. Rings are plain rectangles.
	readonly property int glassShadowLayers: 18
	readonly property real glassShadowAlpha: 0.11
	// How sharply the rings fade. Higher concentrates them near the edge.
	readonly property real glassShadowFalloff: 1.8
	// Shadows fall downward, so the rings drift as they widen.
	readonly property real glassShadowDrift: 0.38
	// Room the window must leave around a panel for the shadow to bleed into.
	readonly property int glassShadowPadding: 22

	readonly property color glassTextPrimary: "#ffffff"
	readonly property color glassTextSecondary: "#d9ffffff"
	readonly property color glassTextMuted: "#8cffffff"

	// Values taken from the "Refractive lens knob" design: a track the knob
	// sits inside rather than on, a fill brighter than the track, and a lens
	// that is a sphere catching light rather than a flat dot.
	readonly property color glassTrack: Qt.rgba(1, 1, 1, 0.14)
	readonly property color glassTrackBorder: Qt.rgba(1, 1, 1, 0.25)
	readonly property color glassTrackBorderFocus: Qt.rgba(1, 1, 1, 0.55)
	readonly property color glassTrackFill: Qt.rgba(1, 1, 1, 0.40)

	readonly property color glassKnobCore: Qt.rgba(1, 1, 1, 0.95)
	readonly property color glassKnobMid: Qt.rgba(1, 1, 1, 0.55)
	readonly property color glassKnobRim: Qt.rgba(1, 1, 1, 0.25)
	readonly property color glassKnobEdge: Qt.rgba(1, 1, 1, 0.70)
	readonly property color glassSheen: Qt.rgba(1, 1, 1, 0.80)

	// A slider fill carries state through its tint: charging green, low amber.
	readonly property color glassFillCharging:
		Qt.rgba(success.r, success.g, success.b, 0.60)
	readonly property color glassFillWarning:
		Qt.rgba(warning.r, warning.g, warning.b, 0.70)
	// The lens is nearly white, so anything drawn on it has to be dark.
	readonly property color glassOnLens: "#1d6b3f"
	readonly property color glassTextOnLens: "#16161c"

	// Depth cues the design carries as inset box-shadows. Without them a panel
	// is a flat translucent rectangle and the lens is a pale disc.
	readonly property color glassInnerHighlight: Qt.rgba(1, 1, 1, 0.45)
	readonly property color glassLensShade: Qt.rgba(0, 0, 0, 0.16)
	readonly property color glassLensGlow: Qt.rgba(1, 1, 1, 0.80)

	readonly property color glassChip: Qt.rgba(1, 1, 1, 0.10)
	readonly property color glassChipActive: Qt.rgba(1, 1, 1, 0.28)

	// Dialog buttons are the tiles' chips. The primary one is bright enough
	// that its label has to go dark.
	readonly property color chipPrimary: Qt.rgba(1, 1, 1, 0.50)
	readonly property color chipPrimaryHover: Qt.rgba(1, 1, 1, 0.62)
	readonly property color chipPrimaryBorder: Qt.rgba(1, 1, 1, 0.70)
	readonly property color chipDestructive:
		Qt.rgba(warning.r, warning.g, warning.b, 0.45)
	readonly property color chipDestructiveHover:
		Qt.rgba(warning.r, warning.g, warning.b, 0.58)
	readonly property color chipDestructiveBorder:
		Qt.rgba(warning.r, warning.g, warning.b, 0.60)

	// A ring rather than a thicker border, so focus does not move anything.
	readonly property color focusRing: Qt.rgba(1, 1, 1, 0.18)

	// --- Metrics ---
	//
	// Taken from the volume tile, which is the reference for the rest of the
	// shell. Components use these rather than their own numbers, so a change
	// here moves everything together instead of leaving one widget behind.
	readonly property int tilePadding: 14
	readonly property int tileWidth: 300

	readonly property int spacingXs: 4
	readonly property int spacingS: 8
	readonly property int spacingM: 12
	readonly property int spacingL: 16

	// Sliders: the knob sits inside the track, not on it.
	readonly property int sliderHeight: 44
	readonly property int sliderKnobSize: 40
	readonly property int sliderInset: 2
	// How far past the knob centre the fill runs.
	readonly property int sliderKnobBias: 24

	readonly property int chipHeight: 29

	readonly property int dialogWidth: 320
	readonly property int dialogPadding: 20

	// --- Type scale ---
	readonly property int fontCaption: 11
	readonly property int fontBody: 12
	readonly property int fontTitle: 13
	readonly property int fontLead: 14
	readonly property int fontHeading: 16

	// Corner radii, by element size.
	readonly property int radiusSmall: 6
	readonly property int radiusMedium: 10
	readonly property int radiusLarge: 12
	readonly property int radiusPill: 12
	readonly property int radiusPanel: 24
}
