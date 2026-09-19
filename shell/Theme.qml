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

	// Corner radii, by element size.
	readonly property int radiusSmall: 6
	readonly property int radiusMedium: 10
	readonly property int radiusLarge: 12
}
