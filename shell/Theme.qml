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
	// Shadows fall downward. The design offsets its by 16px against a 40px
	// blur, so almost nothing lands above the panel. At a low drift the
	// innermost rings sit a fraction of a pixel above the top edge - a dark
	// line immediately above the lit one, which reads as a doubled border.
	readonly property real glassShadowDrift: 0.85
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

	// The lens: pearl. White at the highlight, falling to a cool pale grey-blue
	// at the rim, and nearly opaque. The design's white at falling alpha let
	// the panel through at the rim, which on a dark panel turned it a muddy
	// grey; this keeps the sphere's shading without borrowing the background.
	readonly property color glassKnobCore: "#ffffff"
	readonly property color glassKnobMid: Qt.rgba(240 / 255, 244 / 255, 250 / 255, 0.94)
	readonly property color glassKnobRim: Qt.rgba(205 / 255, 214 / 255, 228 / 255, 0.88)
	readonly property color glassKnobEdge: Qt.rgba(1, 1, 1, 0.90)
	readonly property color glassSheen: Qt.rgba(1, 1, 1, 0.80)

	// A slider fill carries state through its tint: charging green, low amber.
	readonly property color glassFillCharging:
		Qt.rgba(success.r, success.g, success.b, 0.60)
	readonly property color glassFillWarning:
		Qt.rgba(warning.r, warning.g, warning.b, 0.70)
	// The lens is nearly white, so anything drawn on it has to be dark.
	readonly property color glassOnLens: "#1d6b3f"
	// The launcher's lens glyphs for a recognised calculation and command,
	// the design's oklch(0.5 0.14 60) and oklch(0.45 0.13 150), converted.
	readonly property color calcInk: "#8a5a10"
	readonly property color runInk: "#1f6b3a"
	// The marks drawn on a lens - file and folder outlines, the power menu,
	// search - in navy, oklch(0.36 0.076 255). The design's oklch(0.45 0.08
	// 250) was chosen for 2px lines; at the finer markLine it read faint.
	readonly property color fileInk: "#1e3d63"
	readonly property color glassTextOnLens: "#16161c"

	// Depth cues the design carries as inset box-shadows, for the lens. The
	// panel's own inset highlight is not here: on screen it read as a line
	// drawn on the top edge rather than as a surface catching light.
	readonly property color glassLensShade: Qt.rgba(0, 0, 0, 0.10)
	readonly property color glassLensGlow: Qt.rgba(1, 1, 1, 0.85)

	// A menu drawn inside a window sits on that window's own content, and
	// the compositor blurs nothing there: the same glass as a sheet would show
	// the rows through it. So a menu is denser and darker - enough backdrop
	// of its own to be read on - with the same edge as everything else.
	readonly property color menuSurface: Qt.rgba(0.07, 0.08, 0.11, 0.90)
	// And what is under it steps back, as the desktop does behind a sheet.
	readonly property real menuBackdropOpacity: 0.55

	readonly property color glassChip: Qt.rgba(1, 1, 1, 0.10)
	readonly property color glassChipActive: Qt.rgba(1, 1, 1, 0.28)

	// A picked row in the network list. Brighter than the connected card and
	// ringed, because here it means "this is what Join will act on" rather
	// than "this is the state of things".
	readonly property color glassChipSelected: Qt.rgba(1, 1, 1, 0.34)
	// A passkey digit's tile: brighter than a row, because the digits are the
	// whole point of the sheet they sit in.
	readonly property color glassChipDigit: Qt.rgba(1, 1, 1, 0.22)
	readonly property color glassChipSelectedBorder: Qt.rgba(1, 1, 1, 0.60)
	readonly property color glassRowRing: Qt.rgba(1, 1, 1, 0.14)

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

	// The Trash view's Restore chip: the design's oklch(0.85 0.2 145) at .38
	// with an oklch(0.9 0.18 145) edge at .6. Empty Trash is the destructive
	// chip, whose amber is the design's to the last digit.
	readonly property color chipRestore: Qt.rgba(0x6b / 255, 0xef / 255, 0x75 / 255, 0.38)
	readonly property color chipRestoreBorder: Qt.rgba(0x8a / 255, 0xfd / 255, 0x90 / 255, 0.60)
	// The selected stem of a name being renamed, oklch(0.7 0.12 250) at .7.
	readonly property color renameSelection: Qt.rgba(0x61 / 255, 0xa3 / 255, 0xe6 / 255, 0.70)

	// Drag and drop in the Files window, from the design's 10d: the folder a
	// drag is over is oklch(0.8 0.1 250) at .38 with a bright edge and a soft
	// ring of the same blue; the rows being dragged fade; the count badge on
	// the ghost is white with oklch(0.35 0.08 250) ink.
	readonly property color dropTarget: Qt.rgba(0x8c / 255, 0xc3 / 255, 0xfc / 255, 0.38)
	readonly property color dropTargetEdge: Qt.rgba(1, 1, 1, 0.75)
	readonly property color dropTargetRing: Qt.rgba(0x8c / 255, 0xc3 / 255, 0xfc / 255, 0.20)
	readonly property color dragSource: Qt.rgba(1, 1, 1, 0.20)
	readonly property color dragSourceEdge: Qt.rgba(1, 1, 1, 0.32)
	readonly property color dragBadgeInk: "#143c62"
	readonly property color dragCaption: Qt.rgba(0, 0, 0, 0.28)

	// Software, from the design's turn 11. The source mark: "official" is the
	// plain micro-chip, "AUR" oklch(0.82 0.1 250) at .35 with an
	// oklch(0.9 0.08 250) edge at .55; "out of date" is oklch(0.85 0.17 70) at
	// .45 with oklch(0.9 0.16 70) at .6. Update is oklch(0.85 0.2 145) at .35.
	readonly property color microChip: Qt.rgba(1, 1, 1, 0.10)
	readonly property color microChipBorder: Qt.rgba(1, 1, 1, 0.22)
	readonly property color chipAur: Qt.rgba(0x92 / 255, 0xc9 / 255, 1, 0.35)
	readonly property color chipAurBorder: Qt.rgba(0xb6 / 255, 0xe3 / 255, 1, 0.55)
	readonly property color chipOutOfDate: Qt.rgba(1, 0xb7 / 255, 0x34 / 255, 0.45)
	readonly property color chipOutOfDateBorder: Qt.rgba(1, 0xc9 / 255, 0x58 / 255, 0.60)
	readonly property color chipUpdate: Qt.rgba(0x6b / 255, 0xef / 255, 0x75 / 255, 0.35)
	readonly property color chipUpdateBorder: Qt.rgba(0x8a / 255, 0xfd / 255, 0x90 / 255, 0.60)
	// The tail of the terminal in the install card: a dark inset.
	readonly property color terminalInset: Qt.rgba(0, 0, 0, 0.22)

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

	readonly property int barHeight: 32
	// Glyphs in the bar are drawn on one 24-unit grid with a 2-unit stroke and
	// shown at this height, so they share a size and a line weight and read as
	// a set. Widths follow from each grid: square, except the battery's.
	readonly property int barIconSize: 17
	// Line weights of the shell's own glyphs, in pixels as drawn. Thin, so
	// they read as drawn rather than heavy. A glyph standing on the bar or in
	// a field takes barIconLine; a mark inside a lens disc is dark ink on
	// bright glass and carries a little more, markLine.
	readonly property real barIconLine: 1.1
	readonly property real markLine: 1.5
	// A workspace in the bar: a square-ish key with its number, or wider to
	// carry a name, capped so one long name cannot push the rest off.
	readonly property int workspacePillWidth: 26
	readonly property int workspacePillHeight: 22
	readonly property int workspaceNameMaxWidth: 140
	// The colours a workspace can be tagged with: Chrome's tab-group set as
	// it draws them on a dark toolbar, light enough to tint glass without
	// darkening the white text on it. Stored by key, never by value.
	readonly property var tagPalette: [
		{ key: "grey", color: "#dadce0" },
		{ key: "blue", color: "#8ab4f8" },
		{ key: "red", color: "#f28b82" },
		{ key: "yellow", color: "#fdd663" },
		{ key: "green", color: "#81c995" },
		{ key: "pink", color: "#ff8bcb" },
		{ key: "purple", color: "#c58af9" },
		{ key: "cyan", color: "#78d9ec" },
		{ key: "orange", color: "#fcad70" }
	]

	function tagColor(key) {
		return tagPalette.find(tag => tag.key === key)?.color ?? "transparent";
	}

	// A tagged pill is solid, as Chrome draws a group: any see-through tint
	// takes on the wallpaper, and over the green wash red came out brown.
	// Solid pastel wants dark ink. Focus is a ring outside, since the fill
	// is already as bright as it goes; an empty tagged workspace is the
	// outline alone, because fading a colour muddies it the same way.
	readonly property real tagFill: 0.80
	readonly property real tagFillHover: 0.92
	readonly property real tagEdge: 0.60
	readonly property color tagInk: "#202124"
	readonly property color tagRing: Qt.rgba(1, 1, 1, 0.75)
	readonly property int tagSwatchSize: 22
	// The card that shows a workspace from the bar. Wider than a tile, so a
	// miniature of a 3:2 screen is big enough to tell a terminal from a page.
	readonly property int workspacePreviewWidth: 360
	// A workspace's tab stands this far round its pill. A glyph's tab stands
	// wider, tabPadding: the glyph is smaller than a pill and wants the room.
	readonly property int workspaceTabLip: 3

	// --- Tab cards ---
	//
	// Every card the bar opens hangs from what opened it, like a tab, and
	// grows down out of it - the way Caelestia's popouts grow out of its bar.
	// The tab runs from this far below the screen edge to this far above the
	// bar's bottom, and meets the card in a curve this tight.
	readonly property int tabInset: 2
	readonly property int tabPadding: 8
	readonly property int tabJoin: 8
	// Card and tab in one dense glass. The tab lies on the wallpaper and the
	// card usually on a window, and see-through glass took its colour from
	// each: green above, grey below. Dense, they are one colour over anything.
	// Slate, the mid-grey Groma's clear glass most often comes out as on this
	// desktop; white text on it is 8.9:1.
	readonly property color tabCardSurface: Qt.rgba(0x3d / 255, 0x4c / 255, 0x57 / 255, 0.92)

	readonly property int dialogWidth: 320
	readonly property int dialogPadding: 20

	// A picker is not a prompt. The design gives the network list 520 where a
	// question gets 320 - it has to hold a name, a security label and a
	// strength readout on one line without any of them eliding.
	readonly property int dialogWidthWide: 520
	// The launcher, from the design's turn 9: wider than a picker, drawn with
	// its top edge a fifth of the way down rather than centred, so the
	// results grow downward and the sheet never jumps as they change.
	readonly property int launcherWidth: 680
	readonly property real launcherTop: 0.20
	readonly property int launcherPadding: 12
	readonly property int launcherRadius: 30
	readonly property int launcherTrackHeight: 60
	readonly property int launcherRowHeight: 48
	readonly property int launcherTopHitHeight: 56
	// The Files window, from the design's turn 10: an ordinary window at 1×,
	// with its own header and footer since Groma has no global menu bar.
	readonly property int filesWidth: 1040
	readonly property int filesHeight: 660
	readonly property int filesHeaderHeight: 60
	readonly property int filesFooterHeight: 44
	readonly property int filesSidebarWidth: 200
	// Between a prompt and a picker: 8d has to hold six passkey tiles.
	readonly property int dialogWidthPrompt: 440
	readonly property int dialogListHeight: 344

	// How far a page slides when a sheet steps between them. Equal to the
	// sheet's padding on purpose: a page at full travel is exactly at the
	// inside edge of the glass, so nothing has to be clipped to contain it.
	readonly property int dialogPageSlide: 24

	// --- Motion ---
	//
	// Material 3's expressive curves, as Caelestia uses them. Spatial is for
	// anything that moves or resizes, and overshoots a touch, so a panel
	// arrives rather than stops; effects is for opacity, and does not.
	readonly property var motionSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
	// Caelestia's "fast" duration with its default curve: at its own 500 a
	// card felt slow to open, and its fast curve overshoots enough to bounce.
	readonly property int motionSpatialDuration: 350
	readonly property var motionEffects: [0.34, 0.8, 0.34, 1, 1, 1]
	readonly property int motionEffectsDuration: 200
	readonly property var motionEffectsFast: [0.31, 0.94, 0.34, 1, 1, 1]
	readonly property int motionEffectsFastDuration: 150

	// --- Type scale ---
	readonly property int fontCaption: 11
	readonly property int fontBody: 12
	readonly property int fontTitle: 13
	readonly property int fontLead: 14
	readonly property int fontHeading: 16
	readonly property int fontDisplay: 20
	readonly property int fontSearch: 22

	// Corner radii, by element size.
	readonly property int radiusSmall: 6
	readonly property int radiusMedium: 10
	readonly property int radiusLarge: 12
	readonly property int radiusPill: 12
	// A row in the wide picker, which is taller than a tile's row and wants a
	// correspondingly rounder corner.
	readonly property int radiusRow: 16
	readonly property int radiusPanel: 24
	// A window's corners are cut by the compositor, and Hyprland caps its
	// rounding at 20. A pane rounder than its window shows the blur in the
	// corners, so the two are the same number, and the design's 24 is not.
	readonly property int radiusWindow: 20
}
