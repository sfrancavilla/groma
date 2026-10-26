import Quickshell
import QtQuick
import QtQuick.Effects
import "../ui"
import "fileicons.js" as FileIcons

// A file's or folder's icon from the icon theme - Papirus' file types and
// places - standing on its own, with a small shadow to lift it off the glass.
// A page or a folder is already a shape; set inside a round disc the two
// outlines fight, and the disc's grey dulls the colour.
//
// Where the theme has none, the drawn outline (FileGlyph) on a disc, which is
// what the outlines were drawn for.
Item {
	id: icon

	// Either the theme name directly...
	property string iconName: ""
	// ...or the file, to choose one from.
	property string fileName: ""
	property bool folder: false
	property string path: ""
	// The outline to fall back to, and its zoom.
	property string glyph: folder ? "folder" : "file"
	property real zoom: 1

	readonly property string chosen: icon.iconName !== "" ? icon.iconName
		: icon.fileName !== "" || icon.path !== "" ? FileIcons.name(icon.fileName, icon.folder, icon.path, Quickshell.env("HOME")) : ""
	readonly property string source: icon.chosen !== "" ? Quickshell.iconPath(icon.chosen, true) : ""

	Image {
		anchors.fill: parent
		visible: icon.source !== ""
		source: icon.source
		sourceSize: Qt.size(icon.width * 2, icon.height * 2)
		fillMode: Image.PreserveAspectFit
		smooth: true

		// Drawn once into a texture and kept: the icon does not change while
		// it is on screen.
		layer.enabled: visible
		layer.effect: MultiEffect {
			shadowEnabled: true
			shadowColor: "#000000"
			shadowOpacity: 0.30
			shadowBlur: 0.25
			shadowVerticalOffset: Math.max(1, icon.height / 32)
			shadowHorizontalOffset: 0
		}
	}

	Lens {
		anchors.fill: parent
		visible: icon.source === ""
		sheen: false

		FileGlyph {
			anchors.centerIn: parent
			kind: icon.glyph
			zoom: icon.zoom
		}
	}
}
