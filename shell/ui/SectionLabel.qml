import QtQuick
import ".."

// The UPPERCASE label over a group of controls in a bar card: OUTPUT,
// OTHER NETWORKS, MY DEVICES. Written in capitals by the caller rather than
// forced here: a label that carries its own casing, "5 GHz", keeps it.
Text {
	width: parent?.width ?? 0
	// Where the rules start, and the marks under it.
	leftPadding: 8
	font.pixelSize: 10
	font.bold: true
	font.letterSpacing: 0.6
	opacity: 0.6
	color: Theme.glassTextPrimary
}
