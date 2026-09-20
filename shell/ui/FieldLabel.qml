import QtQuick
import ".."

// The small heading over a field on the design's join form. Indented to line
// up with the text inside the rounded track below it rather than with its
// edge, which is where the eye reads the column from.
Text {
	leftPadding: 6

	font.pixelSize: Theme.fontBody
	font.bold: true
	opacity: 0.75
	color: Theme.glassTextPrimary
}
